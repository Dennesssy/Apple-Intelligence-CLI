import Foundation
import FoundationModels

// MARK: - Custom Types

enum ModelUseCase: String, CaseIterable, Identifiable {
    case chat
    case code
    case analysis

    var id: String { self.rawValue }
}

enum ModelAvailability {
    case available
    case unavailable(UnavailableReason)

    enum UnavailableReason {
        case appleIntelligenceNotEnabled
        case modelNotAvailable
        case networkError(String)
        case offline
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp: Date
    var isStreaming: Bool = false

    enum MessageRole {
        case user
        case assistant
        case system
    }
}

// Extension to convert MessageRole to string for JSON encoding/decoding
extension ChatMessage.MessageRole: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .user: try container.encode("user")
        case .assistant: try container.encode("assistant")
        case .system: try container.encode("system")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "user": self = .user
        case "assistant": self = .assistant
        case "system": self = .system
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid role: \(value)")
        }
    }
}

// Protocol for LocalModel (will be used for mock or production implementation)
// This follows the style defined in FoundationModels framework
protocol LocalModel {
    func createSession() -> LanguageModelSession
}

// Concrete implementation for LocalModel
class FoundationLocalModel: LocalModel {
    func createSession() -> LanguageModelSession {
        return LanguageModelSession()
    }
}

extension ChatMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case role, content, timestamp, isStreaming
    }
}

// Adding convenience initializers to match existing usage patterns
extension ChatMessage {
    init(role: MessageRole, content: String, timestamp: Date) {
        self.init(role: role, content: content, timestamp: timestamp, isStreaming: false)
    }

    init(role: MessageRole, content: String, isStreaming: Bool) {
        self.init(role: role, content: content, timestamp: Date(), isStreaming: isStreaming)
    }
}

// Protocol for Error handling that matches expected interface
enum LanguageModelSessionError: LocalizedError {
    case networkError(String)
    case invalidResponse(String)
    case exceededContextWindow
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let desc): return "Network error: \(desc)"
        case .invalidResponse(let desc): return "Invalid response: \(desc)"
        case .exceededContextWindow: return "Context window size exceeded"
        case .unknown(let error): return "Unknown error: \(error.localizedDescription)"
        }
    }
}

extension Error {
    var isExceededContextWindowSize: Bool {
        if let modelError = self as? LanguageModelSessionError {
            return modelError == .exceededContextWindow
        }
        return false
    }
}

// Mock implementation for XcodeContext if needed elsewhere
// This can be made available globally for convenience
class XcodeContextManager {
    static let shared = XcodeContextManager()

    var contextUpdateObserver: NSObjectProtocol?
    let appGroupIdentifier = "group.com.yourcompany.appleicode"
}

// Adding context 열 for SourceEditorCommand types
enum XcodeAction: String, Codable {
    case sendToChat
    case refactor
    case explain
    case fix
}

// Making context available at app level if needed for general usage
extension Notification.Name {
    static let twoWayCommunicationConfirmation = Notification.Name("TwoWayCommunicationConfirmed")
}
