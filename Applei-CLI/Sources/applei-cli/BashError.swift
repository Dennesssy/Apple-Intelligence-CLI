import Foundation

/// Errors that can be thrown by ``BashExecutor``.
///
/// Conforms to ``LocalizedError`` to provide user‑friendly descriptions and
/// recovery suggestions.
public enum BashError: Error, LocalizedError {
    /// The command failed validation.
    case invalidCommand(String)

    /// The command's output could not be decoded as UTF‑8.
    case decodeFailed

    /// The command terminated with a non‑zero exit status.
    case executionFailed(output: String, status: Int32)

    /// The command did not finish within the allowed time.
    case executionTimeout

    public var errorDescription: String? {
        switch self {
        case let .invalidCommand(reason):
            return "Invalid command: \(reason)"
        case .decodeFailed:
            return "Failed to decode command output as UTF‑8"
        case let .executionFailed(output, status):
            return "Command failed (status \(status)): \(output)"
        case .executionTimeout:
            return "Command timed out. Recovery: Use shorter commands or increase timeout."
        }
    }
}
