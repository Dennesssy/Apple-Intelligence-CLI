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

// MARK: - Tool Definitions

struct FetchWebContent: Tool {
    let name = "fetch_web_content"
    let description = "Fetch and analyze web content from a URL"
    let parameters = FetchWebContentParameters()

    @Generable
    struct Arguments {
        @Guide(description: "The URL to fetch content from")
        let url: String
    }

    func call(arguments: Arguments) async throws -> String {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let dir = executableURL.deletingLastPathComponent()
        let swiftfejsPath = dir.appendingPathComponent("swiftfejs").path

        guard FileManager.default.fileExists(atPath: swiftfejsPath) else {
            return "Error: SwiftFejs not found at \(swiftfejsPath)"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftfejsPath)
        process.arguments = [arguments.url, "--mode", "text", "--timeout", "15"]

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
            return "Error fetching URL: \(error.localizedDescription)"
        }

        return "Error: Failed to fetch content"
    }
}

struct ListProcesses: Tool {
    let name = "list_processes"
    let description = "List currently running processes on the system, optionally filtered."
    let parameters = ListProcessesParameters()
    
    @Generable
    struct Arguments {
    }
    
    func call(arguments: Arguments) async throws -> String {
        return try await BashExecutor.shared.execute("ps aux | head -20")
    }
}

struct ListProcessesParameters: Encodable {
    // Schema inferred
}


    let name = "bash_execute"
    let description = "Execute a safe, validated bash command and return stdout/stderr output. Supports timeout and security checks."
    let parameters = BashExecuteParameters()
    
    @Generable
    struct Arguments {
        @Guide(description: "The bash command to execute (e.g. 'ls -la', 'pwd'). Must pass security validation.")
        let command: String
    }
    
    func call(arguments: Arguments) async throws -> String {
        try await BashExecutor.shared.execute(arguments.command, timeoutSeconds: 10.0)
    }
}

struct HomebrewAutorun: Tool {
    let name = "homebrew_autorun"
    let description = "Run Homebrew maintenance: update, upgrade all, cleanup/prune caches."
    let parameters = HomebrewAutorunParameters()
    
    @Generable
    struct Arguments {}
    
    func call(arguments: Arguments) async throws -> String {
        try await BashExecutor.shared.execute("brew update && brew upgrade && brew cleanup 0 --prune=all", timeoutSeconds: 60.0)
    }
}

struct HomebrewAutorunParameters: Encodable {}



struct FetchWebContentParameters: Encodable {
    // Empty parameters struct - schema is inferred from Arguments
}

// MARK: - Configuration

struct CLIConfig {
    var modelUseCase: ModelUseCase = .general
    var temperature: Double = 0.3
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

    init(config: CLIConfig) {
        self.config = config
        self.model = config.modelUseCase.systemModel
        self.initializeSession()
    }

    private func initializeSession() {
        let availability = model.availability

        switch availability {
        case .available:
            let fetchTool = FetchWebContent()
            let processTool = ListProcesses()
            let bashTool = BashExecute()
            let brewTool = HomebrewAutorun()
            session = LanguageModelSession(
                model: model,
                tools: [fetchTool, processTool, bashTool, brewTool],
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

        do {
            let options = GenerationOptions(temperature: config.temperature)
            // streamResponse automatically maintains conversation history in the session
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

        } catch let error as LanguageModelSession.GenerationError {
            handleGenerationError(error)
        } catch {
            printError("Error: \(error.localizedDescription)")
        }
    }

    // Interactive mode
    func interactive() async {
        printInfo("Applei CLI - Interactive Mode")
        printInfo("Press Ctrl+C to exit or type 'exit'/'quit'\n")

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

            // Check for exit command
            let command = input.lowercased()
            if command == "exit" || command == "quit" {
                printInfo("Goodbye!")
                return
            }

            await query(input)
        }
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

    // MARK: - Web Content Fetching

    func fetchWebContent(_ urlString: String) -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let dir = executableURL.deletingLastPathComponent()
        let swiftfejsPath = dir.appendingPathComponent("swiftfejs").path

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
