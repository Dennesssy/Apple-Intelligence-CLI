# Applei-CLI

On-device AI assistant using Apple's FoundationModels framework with conversation context management.

## Features

- **Apple Intelligence** - On-device LLM (FoundationModels framework)
- **Persistent Context** - Remembers last 10 messages during interactive session
- **Web Analysis** - Fetch and analyze web content via SwiftFejs
- **Interactive Mode** - Multi-turn conversations with full context recall
- **Temperature Control** - Adjust creativity (0.0-1.0)
- **Privacy-First** - 100% on-device processing

## Requirements

- macOS 15.1+ with Apple Intelligence enabled
- Apple Silicon (M1+)
- Optional: SwiftFejs binary for web fetching

## Build & Install

```bash
swiftc -parse-as-library -o applei-cli applei-cli.swift \
    -framework FoundationModels -framework Foundation -O
chmod +x applei-cli
```

Quick alias:
```bash
alias applei='/Users/denn/Desktop/Xcode/AppleiChat/Applei-CLI/applei-cli --interactive'
```

## Usage

### Interactive Mode (Recommended)
```bash
./applei-cli --interactive
```

Interactive Commands:
- `fetch <url>` - Fetch and analyze web content
- `context` - Show recent conversation history (last 10 messages)
- `clear` - Reset conversation
- `status` - Show session info
- `help` - Show available commands
- `exit` / `quit` - Exit

### Single Query Mode
```bash
./applei-cli "What is Swift?"
./applei-cli --temperature 0.8 "Write a creative story"
./applei-cli --fetch-url "https://example.com" "summarize this"
```

## Options

```
-i, --interactive              Start interactive mode
-m, --model <model>            Select model (general, contentTagging)
-t, --temperature <value>      Set temperature (0.0-1.0, default: 0.7)
-s, --system <instructions>    Custom system instructions
--fetch-url <url>              Fetch and analyze web content
-h, --help                     Show help
```

## Example Interactive Session

```
Applei> What is Swift?
[Apple Intelligence responds...]

Applei> Tell me more about it
[Response uses previous context from LanguageModelSession]

Applei> context
Recent conversation context (4 messages):
  1. user: What is Swift?
  2. assistant: Swift is a modern programming language...
  3. user: Tell me more about it
  4. assistant: Swift has many advantages...

Applei> fetch https://swift.org/blog
[Analyzes web content]

Applei> exit
```

## Architecture

```
AppleiCLI
├── LanguageModelSession (stateful conversation)
├── Message History (last 10 in memory)
├── SwiftFejs Integration (web fetching)
└── FoundationModels (Apple Intelligence)
```

## Key Features

- **Stateful Sessions** - LanguageModelSession maintains conversation context automatically
- **Recent Context** - Keep last 10 messages in memory for reference
- **Streaming Responses** - Real-time output during generation
- **Interactive Context Display** - `context` command shows conversation history
- **Error Recovery** - Graceful handling of edge cases
- **Clean Exit** - Ctrl+C for safe shutdown

## Conversation Management

### How It Works

1. **Per-Session Persistence**: LanguageModelSession automatically maintains conversation history
2. **Memory Cache**: CLI keeps last 10 messages for quick context display
3. **Interactive Recall**: Use `context` command to view recent exchanges

### Example

```bash
$ ./applei-cli --interactive
> What is React?
[Response about React]
> How does it differ from Vue?
[Uses context from previous message automatically]
> context
[Shows last 10 messages from session]
```

## SwiftUI App

Companion macOS app with:
- ✅ Conversation persistence (auto-saves to ~/Documents/AppleiChat/)
- ✅ Auto-load previous conversations on startup
- ✅ Same FoundationModels backend
- ✅ Split-view UI (sidebar + chat)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Apple Intelligence not enabled" | Enable in Settings > Apple Intelligence & Siri |
| "Device not eligible" | Requires Apple Silicon M1+ |
| "Session not initialized" | Apple Intelligence may be downloading |
| Missing web content | SwiftFejs is optional; app continues |

## Files

- `applei-cli.swift` - Single-file CLI implementation
- `README.md` - This file

## Status

✅ **Production-Ready**
- Full FoundationModels integration
- Conversation context management
- Interactive and single-query modes
- Web content analysis

---

**Built with**: FoundationModels, SwiftUI (companion app), on-device Apple Intelligence
