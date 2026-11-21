import SwiftUI
import UIKit

struct Composer: View {
    @Binding var text: String
    let isStreaming: Bool
    let isCancelling: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @Environment(\.colorScheme) private var scheme

    private var canSend: Bool {
        !text.trimmed.isEmpty
    }

    private var fieldHeight: CGFloat {
        let lines = min(max(text.components(separatedBy: "\n").count, 1), 5)
        return CGFloat(lines) * 21
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("发消息给 DSH…")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.subtleText(scheme))
                        .padding(.top, 2)
                        .padding(.leading, 1)
                        .allowsHitTesting(false)
                }

                GrowingTextView(text: $text, onSend: {
                    if canSend { onSend() }
                })
                .frame(height: max(21, fieldHeight))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.border(scheme), lineWidth: 1)
            )

            Button(action: primaryAction) {
                ZStack {
                    Circle()
                        .fill(buttonBackground)
                    Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: isStreaming ? 14 : 16, weight: .bold))
                        .foregroundColor(isStreaming ? .white : (canSend ? .white : Theme.subtleText(scheme)))
                }
                .frame(width: 42, height: 42)
                .opacity(isCancelling ? 0.55 : 1)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isStreaming && !canSend)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.background(scheme))
    }

    private var buttonBackground: Color {
        if isStreaming { return Theme.danger }
        return canSend ? Theme.accent : Theme.surfaceAlt(scheme)
    }

    private func primaryAction() {
        if isStreaming {
            onStop()
        } else if canSend {
            onSend()
        }
    }
}

/// 自动换行、回车即发送的输入框。
struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFont.systemFont(ofSize: 16)
        view.backgroundColor = .clear
        view.textColor = UIColor.label
        view.tintColor = UIColor(red: 0.30, green: 0.42, blue: 1.0, alpha: 1.0)
        view.textContainerInset = UIEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.keyboardDismissMode = .interactive
        view.returnKeyType = .send
        view.autocorrectionType = .yes
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.textContainer.maximumNumberOfLines = 0
        view.textContainer.lineBreakMode = .byWordWrapping
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onSend()
                return false
            }
            return true
        }
    }
}
