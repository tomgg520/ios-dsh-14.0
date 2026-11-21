import SwiftUI

struct ToolCallCard: View {
    let tool: ToolCallModel

    @State private var expanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                header
            }
            .buttonStyle(PlainButtonStyle())

            if expanded && !tool.detail.isEmpty {
                Divider().opacity(0.4)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(tool.detail)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(Theme.subtleText(scheme))
                        .padding(12)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .background(Theme.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.border(scheme), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            statusIcon
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(statusText)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.subtleText(scheme))
            }

            Spacer(minLength: 4)

            if !tool.detail.isEmpty {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.subtleText(scheme))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch tool.status {
        case "completed":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.success)
        case "failed":
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.danger)
        case "in_progress":
            ProgressView()
                .scaleEffect(0.6)
        default:
            Image(systemName: iconForKind)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.accent)
        }
    }

    private var iconForKind: String {
        switch tool.kind {
        case "read": return "doc.text"
        case "edit", "delete": return "pencil"
        case "move": return "arrow.left.arrow.right"
        case "search": return "magnifyingglass"
        case "execute": return "terminal"
        case "fetch": return "globe"
        case "think": return "brain.head.profile"
        default: return "wrench.and.screwdriver"
        }
    }

    private var statusText: String {
        switch tool.status {
        case "pending": return "等待执行"
        case "in_progress": return "正在执行"
        case "completed": return "已完成"
        case "failed": return "执行失败"
        default: return tool.status
        }
    }

    private func toggle() {
        guard !tool.detail.isEmpty else { return }
        Haptics.light()
        withAnimation(.easeInOut(duration: 0.18)) {
            expanded.toggle()
        }
    }
}
