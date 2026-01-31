//
//  applei-cli.swift
//  Applei-CLI
//
//  CLI tool for Apple Intelligence using FoundationModels framework
//
//  Usage:
//    ./applei-cli "Your prompt here"           # Single query mode
//    ./applei-cli --interactive                # Interactive mode
//    ./applei-cli --model general "Prompt"     # Specify model
//    ./applei-cli --temperature 0.8 "Prompt"   # Set temperature
//
//  Build instructions:
//    swiftc -o applei-cli applei-cli.swift -framework FoundationModels -framework Foundation
//    chmod +x applei-cli
//

import Foundation
import FoundationModels

// MARK: - Configuration

struct CLIConfig {
    var modelUseCase: ModelUseCase = .general
    var temperature: Double = 0.7
    var maxTokens: Int? = nil
    var interactive: Bool = false
    var fetchUrl: String? = nil
    var systemInstructions: String = """
    You are a helpful AI assistant running in a CLI environment. Provide clear, concise answers.
    Keep responses focused and practical. Be accurate and acknowledge uncertainty when appropriate.
    """

    enum ModelUseCase: String {
        case general
        case contentTagging

        var systemModel: SystemLanguageModel {
            switch self {
            case .general:
                return SystemLanguageModel(useCase: .general)
            case .contentTagging:
                return SystemLanguageModel(useCase: .contentTagging)
            }
        }
    }
}

// MARK: - CLI Manager

class AppleiCLI {
    private var session: LanguageModelSession?
    private var model: SystemLanguageModel
    private var config: CLIConfig
    private var messageCount: Int = 0
    private var recentMessages: [(role: String, content: String)] = []  // Keep last 10 messages

    init(config: CLIConfig) {
        self.config = config
        self.model = config.modelUseCase.systemModel
        self.initializeSession()
    }

    private func initializeSession() {
        let availability = model.availability

        switch availability {
        case .available:
            session = LanguageModelSession(
                model: model,
                tools: [],
                instructions: config.systemInstructions
            )
            // Prewarm session to reduce latency
            Task {
                await prewarmSession()
            }
        case .unavailable(.deviceNotEligible):
            printError("Device not eligible for Apple Intelligence")
            exit(1)
        case .unavailable(.appleIntelligenceNotEnabled):
            printError("Apple Intelligence not enabled. Enable in Settings > Apple Intelligence & Siri")
            exit(1)
        case .unavailable(.modelNotReady):
            printError("Model not ready. Please wait for download to complete")
            exit(1)
        case .unavailable:
            printError("Model unavailable. Check your settings")
            exit(1)
        }
    }

    private func prewarmSession() async {
        guard let session = session else { return }
        session.prewarm(promptPrefix: nil)
    }

    // Single prompt mode
    func query(_ prompt: String) async {
        guard let session = session else {
            printError("Session not initialized")
            return
        }

        // Store user message in memory
        storeMessage(role: "user", content: prompt)

        do {
            let options = GenerationOptions(temperature: config.temperature)
            let stream = session.streamResponse(to: prompt, options: options)

            var fullResponse = ""

            for try await partial in stream {
                // Print incrementally for streaming effect
                if fullResponse.isEmpty {
                    print("\n", terminator: "")
                }

                let newContent = String(partial.content.dropFirst(fullResponse.count))
                print(newContent, terminator: "")
                fflush(stdout)

                fullResponse += newContent  // Accumulate properly
            }

            print("\n")
            messageCount += 2 // User + Assistant

            // Store assistant response in memory
            storeMessage(role: "assistant", content: fullResponse)

        } catch let error as LanguageModelSession.GenerationError {
            handleGenerationError(error)
        } catch {
            printError("Error: \(error.localizedDescription)")
        }
    }

    // Store messages in memory (keep last 10 for context)
    private func storeMessage(role: String, content: String) {
        recentMessages.append((role: role, content: content))
        // Keep only last 10 messages
        if recentMessages.count > 10 {
            recentMessages.removeFirst()
        }
    }

    // Get conversation context (last 5 exchanges)
    func getRecentContext() -> String {
        guard !recentMessages.isEmpty else { return "" }
        let last5 = Array(recentMessages.suffix(10))
        return last5.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
    }

    // Print current context for debugging
    func printContext() {
        printInfo("Recent conversation context (\(recentMessages.count) messages):")
        for (index, msg) in recentMessages.enumerated() {
            print("  \(index + 1). \(msg.role): \(msg.content.prefix(50))...")
        }
    }

    // Interactive mode
    func interactive() async {
        printInfo("Applei CLI - Interactive Mode")
        printInfo("Press Ctrl+C to exit or type 'exit'/'quit'")
        printInfo("Type 'clear' to reset conversation")
        printInfo("Type 'help' for commands\n")

        // Handle Ctrl+C gracefully
        signal(SIGINT) { _ in
            print("\n")
            print("\u{001B}[36m[INFO]\u{001B}[0m Goodbye!")
            exit(0)
        }

        while true {
            print("\n> ", terminator: "")
            fflush(stdout)

            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                continue
            }

            if input.isEmpty {
                continue
            }

            // Handle commands
            let parts = input.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let command = parts.first.map(String.init).map { $0.lowercased() } ?? ""
            let argument = parts.count > 1 ? String(parts[1]) : ""

            switch command {
            case "exit", "quit":
                printInfo("Goodbye!")
                return
            case "clear":
                clearSession()
                printInfo("Conversation cleared")
                continue
            case "help":
                printHelp()
                continue
            case "status":
                printStatus()
                continue
            case "context":
                printContext()
                continue
            case "fetch":
                if argument.isEmpty {
                    printWarning("Usage: fetch <url>")
                    continue
                }
                printInfo("Fetching \(argument)...")
                if let content = fetchWebContent(argument) {
                    let preview = String(content.prefix(200))
                    printInfo("Fetched \(content.count) characters")
                    let analysisPrompt = "Please analyze this web content and provide a summary:\n\n\(content)"
                    await query(analysisPrompt)
                }
                continue
            default:
                break
            }

            await query(input)
        }
    }

    private func clearSession() {
        messageCount = 0
        initializeSession()
    }

    private func printStatus() {
        printInfo("Model: \(config.modelUseCase)")
        printInfo("Temperature: \(config.temperature)")
        printInfo("Message count: \(messageCount)")
        printInfo("Session active: \(session != nil)")
    }

    private func printHelp() {
        print("""

        Available Commands:
          help              - Show this help message
          status            - Show current session status
          clear             - Clear conversation history
          fetch <url>       - Fetch and analyze web content
          exit/quit         - Exit interactive mode

        """)
    }

    // MARK: - Web Content Fetching (SwiftFejs Integration)

    func fetchWebContent(_ urlString: String) -> String? {
        let swiftfejsPath = "/Users/denn/ML/Projecti/SwiftFejs/swiftfejs"

        guard FileManager.default.fileExists(atPath: swiftfejsPath) else {
            printWarning("SwiftFejs not found at \(swiftfejsPath)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftfejsPath)
        process.arguments = [urlString, "--mode", "text", "--timeout", "15"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let content = String(data: data, encoding: .utf8) {
                return content
            }
        } catch {
            printError("Failed to fetch URL: \(error.localizedDescription)")
        }

        return nil
    }


    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) {
        switch error {
        case .exceededContextWindowSize:
            printWarning("Context window exceeded. Creating new session with recent context...")

            if let originalSession = session {
                session = newContextualSession(from: originalSession)
                Task {
                    await prewarmSession()
                }
            }

            messageCount = 0

        case .refusal(_, _):
            printWarning("Model refused to generate response")

        case .assetsUnavailable:
            printError("Required assets are unavailable")

        case .guardrailViolation:
            printWarning("Response violated safety guardrails")

        case .unsupportedGuide:
            printError("Unsupported generation guide specified")

        case .unsupportedLanguageOrLocale:
            printError("Unsupported language or locale")

        case .decodingFailure:
            printError("Failed to decode model response")

        case .rateLimited:
            printWarning("API rate limit exceeded. Please retry later")

        case .concurrentRequests:
            printWarning("Too many concurrent requests. Please wait")

        @unknown default:
            printError("Unexpected generation error occurred")
        }
    }

    private func newContextualSession(from originalSession: LanguageModelSession) -> LanguageModelSession {
        let allEntries = originalSession.transcript
        var condensedEntries: [Transcript.Entry] = []

        if let first = allEntries.first {
            condensedEntries.append(first)
        }

        let recentEntries = allEntries.suffix(6)
        condensedEntries.append(contentsOf: recentEntries)

        let condensedTranscript = Transcript(entries: condensedEntries)
        return LanguageModelSession(transcript: condensedTranscript)
    }

    // MARK: - Utility Functions

    private func printError(_ message: String) {
        fputs("\u{001B}[31m[ERROR]\u{001B}[0m \(message)\n", stderr)
    }

    private func printWarning(_ message: String) {
        fputs("\u{001B}[33m[WARNING]\u{001B}[0m \(message)\n", stderr)
    }

    private func printInfo(_ message: String) {
        print("\u{001B}[36m[INFO]\u{001B}[0m \(message)")
    }
}

// MARK: - Argument Parser

struct ArgumentParser {
    static func parse() -> (config: CLIConfig, prompt: String?) {
        var config = CLIConfig()
        var prompt: String? = nil
        var args = CommandLine.arguments
        args.removeFirst() // Remove program name

        var i = 0
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "--interactive", "-i":
                config.interactive = true
                i += 1

            case "--model", "-m":
                if i + 1 < args.count {
                    let modelStr = args[i + 1]
                    if let modelCase = CLIConfig.ModelUseCase(rawValue: modelStr) {
                        config.modelUseCase = modelCase
                    } else {
                        fputs("Unknown model: \(modelStr). Using default (general)\n", stderr)
                    }
                    i += 2
                } else {
                    fputs("--model requires a value\n", stderr)
                    i += 1
                }

            case "--temperature", "-t":
                if i + 1 < args.count {
                    if let temp = Double(args[i + 1]) {
                        config.temperature = max(0.0, min(1.0, temp))
                    }
                    i += 2
                } else {
                    fputs("--temperature requires a value\n", stderr)
                    i += 1
                }

            case "--system", "-s":
                if i + 1 < args.count {
                    config.systemInstructions = args[i + 1]
                    i += 2
                } else {
                    fputs("--system requires a value\n", stderr)
                    i += 1
                }

            case "--fetch-url":
                if i + 1 < args.count {
                    config.fetchUrl = args[i + 1]
                    i += 2
                } else {
                    fputs("--fetch-url requires a URL\n", stderr)
                    i += 1
                }

            case "--help", "-h":
                printUsage()
                exit(0)

            default:
                // Treat as prompt
                if prompt == nil {
                    prompt = arg
                } else {
                    prompt! += " " + arg
                }
                i += 1
            }
        }

        return (config, prompt)
    }

    static func printUsage() {
        print("""

        Applei CLI - Apple Intelligence Command Line Interface

        Usage:
          applei-cli [options] "prompt"           Single query mode
          applei-cli --interactive                Interactive mode
          applei-cli --fetch-url <url> "analyze"  Fetch and analyze web content
          applei-cli --ask-gemini "question"      Ask Gemini a question

        Options:
          -i, --interactive              Start interactive mode
          -m, --model <model>            Select model (general, contentTagging)
          -t, --temperature <value>      Set temperature (0.0-1.0, default: 0.7)
          -s, --system <instructions>    Custom system instructions
          --fetch-url <url>              Fetch web content via SwiftFejs
          -h, --help                     Show this help message

        Examples:
          applei-cli "What is Swift?"
          applei-cli --fetch-url "https://example.com" "summarize this"
          applei-cli --interactive

        Interactive Mode Commands:
          fetch <url>                    Fetch and analyze web content
          context                        Show recent conversation context
          clear                          Reset conversation
          status                         Show session info
          help                           Show available commands
          exit/quit                      Exit

        Integration Features:
          - SwiftFejs: Fetch and analyze web content (via --fetch-url or fetch command)
          - FoundationModels: Apple Intelligence on-device LLM

        Note: Requires macOS 15.1+ and Apple Intelligence enabled

        """)
    }
}

// MARK: - Main Entry Point

@main
struct Main {
    static func main() async {
        let (config, prompt) = ArgumentParser.parse()

        let cli = AppleiCLI(config: config)

        if config.interactive {
            await cli.interactive()
        } else if let url = config.fetchUrl {
            // Fetch URL mode
            if let content = cli.fetchWebContent(url) {
                let analysisPrompt = prompt ?? "Please analyze and summarize this web content."
                let fullPrompt = "Web Content:\n\n\(content)\n\nAnalysis Request: \(analysisPrompt)"
                await cli.query(fullPrompt)
            }
        } else if let prompt = prompt {
            await cli.query(prompt)
        } else {
            ArgumentParser.printUsage()
            exit(1)
        }
    }
}
