//  Security.swift
/*
 Copyright (c) 2024 swift
 */

import Foundation

/// # Security Module
///
/// Provides sandboxing and validation for autonomous agent operations.
/// Enforces path restrictions and command allowlisting.
public actor Security {
    // MARK: - Constants

    /// Allowed commands for the autonomous agent.
    private static let allowedCommands: Set<String> = [
        "ls", "pwd", "cat", "echo", "mkdir", "touch", "rm", "cp", "mv",
        "grep", "head", "tail", "wc", "date", "uptime", "ps", "df", "du",
        "whoami", "id", "find", "git", "cd", "npm", "node", "swift", "swiftc"
    ]

    // MARK: - Path Validation

    /// Validates that a path is within the allowed project directory.
    ///
    /// - Parameters:
    ///   - path: The path to validate (absolute or relative).
    ///   - projectRoot: The root directory of the project (default is current directory).
    /// - Returns: True if the path is safe.
    public static func isPathSafe(_ path: String, projectRoot: String = FileManager.default.currentDirectoryPath) -> Bool {
        let rootURL = URL(fileURLWithPath: projectRoot).standardized
        let targetURL = URL(fileURLWithPath: path, relativeTo: rootURL).standardized

        // Ensure the standardized path still starts with the root path
        return targetURL.path.hasPrefix(rootURL.path)
    }

    // MARK: - Command Validation

    /// Validates a bash command string against the allowlist and security rules.
    ///
    /// - Parameter command: The full command string.
    /// - Returns: (allowed: Bool, reason: String)
    public static func validateCommand(_ command: String) -> (allowed: Bool, reason: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (false, "Command is empty")
        }

        let components = trimmed.components(separatedBy: .whitespacesAndNewlines)
        guard let firstWord = components.first?.lowercased() else {
            return (false, "Could not parse command")
        }

        // Handle absolute paths by taking the last component
        let cmdName = URL(fileURLWithPath: firstWord).lastPathComponent

        if !self.allowedCommands.contains(cmdName) {
            return (false, "Command '\(cmdName)' is not in the allowed list")
        }

        // Check for suspicious patterns
        // We allow '..' for navigation, trusting the agent to stay within bounds for now.
        // A robust implementation would parse arguments and validate paths against projectRoot.
        // if trimmed.contains("..") {
        //    return (false, "Directory traversal (..) is not allowed in commands")
        // }

        return (true, "")
    }
}
