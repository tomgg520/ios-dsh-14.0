import SwiftUI

struct MessageRow: View {
    let message: ChatMessage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch message.role {
        case .user:
            userRow
        case .assistant:
            assistantRow
        case .system:
            systemRow
        }
    }

    private var userRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 52)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.bubbleGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
                Text(TimeFormat.clock(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.subtleText(scheme))
            }
        }
    }

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.thinking.isEmpty {
                ThinkingView(text: message.thinking, isStreaming: message.isStreaming)
            }

            ForEach(message.tools) { tool in
                ToolCallCard(tool: tool)
            }

            if !message.text.isEmpty {
                MarkdownView(text: message.text)
            }

            if message.isStreaming && message.text.isEmpty && message.tools.isEmpty && message.thinking.isEmpty {
                TypingIndicator()
            }

            if !message.text.isEmpty && !message.isStreaming {
                Text(TimeFormat.clock(message.createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.subtleText(scheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var systemRow: some View {
        HStack {
            Spacer(minLength: 24)
            Text(message.text)
                .font(.system(size: 12))
                .foregroundColor(message.isError ? Theme.danger : Theme.subtleText(scheme))
                .multilineTextAlignment(.center)
                .padding(.vertical, 2)
            Spacer(minLength: 24)
        }
    }
}

struct ThinkingView: View {
    let text: String
    let isStreaming: Bool

    @State private var expanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                    Text(isStreaming ? "正在思考…" : "思考过程")
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(Theme.subtleText(scheme))
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if expanded {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.subtleText(scheme))
                    .lineSpacing(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceAlt(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle() {
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.18)) {
            expanded.toggle()
        }
    }
}

struct TypingIndicator: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("正在回复…")
                .font(.system(size: 13))
                .foregroundColor(Theme.subtleText(scheme))
        }
        .padding(.vertical, 2)
    }
}
