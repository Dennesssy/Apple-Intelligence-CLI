import SwiftUI
import Foundation
import FoundationModels

@Observable
class ChatViewModel {
    var messages: [Message] = []
    var isGenerating = false
    var inputText = ""

    private var languageSession: LanguageModelSession?
    private let conversationsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AppleiChat")

    init() {
        createConversationsDirectory()
        initializeSession()
        loadLastConversation()
    }

    private func initializeSession() {
        let model = SystemLanguageModel(useCase: .general)
        languageSession = LanguageModelSession(
            model: model,
            tools: [],
            instructions: "You are a helpful AI assistant. Provide clear, concise responses."
        )
    }

    func sendMessage() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add user message
        let userMessage = Message(role: .user, content: trimmed)
        messages.append(userMessage)
        inputText = ""

        isGenerating = true

        // Generate response
        await generateResponse(to: trimmed)

        isGenerating = false

        // Save after each message
        saveConversation()
    }

    private func generateResponse(to prompt: String) async {
        guard let session = languageSession else {
            let error = Message(role: .assistant, content: "Error: Session not initialized")
            messages.append(error)
            return
        }

        do {
            let options = GenerationOptions(temperature: 0.7)
            let stream = session.streamResponse(to: prompt, options: options)

            var fullResponse = ""

            for try await partial in stream {
                fullResponse = partial.content
            }

            let assistantMessage = Message(role: .assistant, content: fullResponse)
            messages.append(assistantMessage)

        } catch {
            let errorMessage = Message(role: .assistant, content: "Error: \(error.localizedDescription)")
            messages.append(errorMessage)
        }
    }

    // MARK: - Persistence

    private func createConversationsDirectory() {
        try? FileManager.default.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
    }

    func saveConversation(name: String = "current") {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        if let encoded = try? encoder.encode(messages) {
            let fileURL = conversationsDirectory.appendingPathComponent("\(name).json")
            try? encoded.write(to: fileURL)
        }
    }

    func loadLastConversation(name: String = "current") {
        let fileURL = conversationsDirectory.appendingPathComponent("\(name).json")

        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode([Message].self, from: data) {
            messages = decoded
        }
    }

    func listSavedConversations() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: conversationsDirectory.path) else {
            return []
        }
        return contents.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
    }

    func newConversation() {
        messages = []
        inputText = ""
        initializeSession()
    }
}
