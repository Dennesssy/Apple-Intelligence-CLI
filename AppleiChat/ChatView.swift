import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                HStack {
                    Text("AI Chat")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                Divider()
            }
            .padding()

            // Messages
            if viewModel.messages.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue.opacity(0.3))
                    Text("Start a conversation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12, pinnedViews: []) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation(.easeOut) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 12) {
                TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(viewModel.inputText.isEmpty ? .gray : .blue)
                }
                .disabled(viewModel.inputText.isEmpty || viewModel.isGenerating)
            }
            .padding()
        }
    }

    private func sendMessage() {
        Task {
            await viewModel.sendMessage()
        }
    }
}

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if message.role == .assistant {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    Text(message.role == .user ? "You" : "AI")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(message.role == .user ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    }
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

#Preview {
    ChatView()
}
