//  BashExecutor.swift
/*
 Copyright (c) 2024 swift
 */

import Dispatch
import Foundation

/// Executes shell commands concurrently or singly.
/// Uses `Pipe` for output, sync wait.
///
/// This class is deliberately `public` so it can be reused across the
/// codebase (e.g., in the TUI, tool execution, tests).
public final class BashExecutor: @unchecked Sendable {
    // MARK: - Constants

    /// Maximum allowed length for a command string.
    public static let maxCommandLength = 1000

    /// Shared singleton instance for reuse across the application.
    public static let shared = BashExecutor()

    // MARK: - Private Properties

    /// Serial queue used for audit logging to avoid race conditions.
    private let auditQueue = DispatchQueue(label: "BashExecutor.auditQueue")

    // MARK: - Initialization

    /// Private initializer to enforce singleton usage.
    private init() {}

    // MARK: - Validation

    /// Validates a bash command string.
    ///
    /// Checks for:
    ///   • Non‑empty
    ///   • Length ≤ `maxCommandLength`
    ///   • Allowed first command word (allowlist)
    ///   • Absence of suspicious operators (`&&`, `||`, `;`, `|`, `&`, `` ` ``, `$(`)
    ///   • No control characters (including newlines, tabs, etc.)
    ///
    /// - Parameter command: The command to validate.
    /// - Throws: `BashError.invalidCommand` with a descriptive reason.
    private func validate(_ command: String) throws {
        guard !command.isEmpty else {
            throw BashError.invalidCommand("Empty command")
        }
        guard command.count <= BashExecutor.maxCommandLength else {
            throw BashError.invalidCommand("Too long (\(command.count) > \(BashExecutor.maxCommandLength))")
        }

        // Use the new Security actor for robust validation
        // Note: Since validate is called in a non-isolated context, we use the static method.
        let validation = Security.validateCommand(command)
        if !validation.allowed {
            throw BashError.invalidCommand(validation.reason)
        }

        // Disallow control characters (including newlines, tabs, etc.)
        if command.rangeOfCharacter(from: .controlCharacters) != nil {
            throw BashError.invalidCommand("Contains control characters")
        }
    }

    // MARK: - Audit Logging

    /// Appends an audit entry for the executed command to `~/.swiftgroq/audit.log`.
    ///
    /// The entry format is:
    /// `[YYYY-MM-DD HH:mm:ss] <command>`
    ///
    /// This method is thread‑safe via a serial `auditQueue`.
    private func logCommand(_ command: String) {
        self.auditQueue.async {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let dir = home.appendingPathComponent(".swiftgroq", isDirectory: true)
            // Ensure the directory exists.
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            let logURL = dir.appendingPathComponent("audit.log")

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let timestamp = formatter.string(from: Date())
            let line = "[\(timestamp)] \(command)\n"

            // Append the line atomically.
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    // Append to existing file.
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        defer { try? handle.close() }
                        do {
                            try handle.seekToEnd()
                            try handle.write(contentsOf: data)
                        } catch {
                            // Silently ignore logging failures – they must not affect command execution.
                        }
                    }
                } else {
                    // Create a new file with the line.
                    try? data.write(to: logURL, options: [.atomic])
                }
            }
        }
    }

    // MARK: - Public API

    /// Executes a single bash command asynchronously.
    ///
    /// - Parameters:
    ///   - command: Validated command string.
    ///   - timeoutSeconds: Maximum time to allow the command to run before it is terminated. Default is 30 seconds.
    ///   - skipValidation: If true, skips the security validation (internal use only).
    /// - Returns: The trimmed stdout+stderr output.
    /// - Throws: `BashError` (`invalidCommand`, `decodeFailed`, `executionFailed`, `executionTimeout`).
    public nonisolated func execute(_ command: String, timeoutSeconds: TimeInterval = 30.0, skipValidation: Bool = false) async throws -> String {
        // Input validation
        if !skipValidation {
            try self.validate(command)
        }

        // Record the command in the audit log before execution.
        self.logCommand(command)

        return try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .background) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-c", command]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()

                    // Read data in background to avoid pipe deadlock
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()

                    let timeoutDate = Date(timeIntervalSinceNow: timeoutSeconds)
                    while process.isRunning && Date() < timeoutDate {
                        try await Task.sleep(nanoseconds: 100_000_000) // 100 ms
                    }

                    if process.isRunning {
                        process.terminate()
                        continuation.resume(throwing: BashError.executionTimeout)
                        return
                    }

                    process.waitUntilExit()

                    // Guard against excessively large output (1 MiB limit)
                    guard data.count <= 1_048_576 else {
                        continuation.resume(throwing: BashError.invalidCommand("Output too large (>1 MB)"))
                        return
                    }

                    guard let output = String(data: data, encoding: .utf8) else {
                        continuation.resume(throwing: BashError.decodeFailed)
                        return
                    }

                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: BashError.executionFailed(output: output, status: process.terminationStatus))
                        return
                    }

                    continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Executes an array of commands concurrently, returning ordered results.
    ///
    /// Uses a `TaskGroup` for parallelism while preserving the original order
    /// of the input array.
    ///
    /// - Throws: `BashError` if any command fails validation or execution.
    ///
    /// ## Usage Example
    /// ```swift
    /// let cmds = ["ls", "pwd"]
    /// let outputs = try await BashExecutor.shared.executeAsync(cmds)
    /// ```
    public nonisolated func executeAsync(_ commands: [String]) async throws -> [String] {
        // Validate each command before launching tasks
        for cmd in commands {
            try self.validate(cmd)
        }

        // Run multiple commands concurrently and collect their outputs in the original order
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, cmd) in commands.enumerated() {
                group.addTask {
                    // Each individual execution will log its command via `execute(_:)`.
                    try (index, await self.execute(cmd))
                }
            }

            var ordered: [String] = Array(repeating: "", count: commands.count)
            for try await (index, result) in group {
                ordered[index] = result
            }
            return ordered
        }
    }
}
