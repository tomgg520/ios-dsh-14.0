import SwiftUI

struct ConnectionBanner: View {
    let text: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.danger)
            } else {
                ProgressView()
                    .scaleEffect(0.65)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(isError ? Theme.danger : .secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isError ? Theme.danger.opacity(0.10) : Theme.accent.opacity(0.08))
    }
}

struct SessionRow: View {
    let session: SessionSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if session.isLive {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 5, height: 5)
                    }
                    Text(session.cwd.isEmpty ? "未知目录" : session.cwd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            Text(TimeFormat.relative(session.updatedAt))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.7))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

struct StatusDot: View {
    let state: String

    private var color: Color {
        switch state {
        case "ready": return Theme.success
        case "starting", "restarting": return Theme.warning
        case "stopped": return Theme.warning
        case "failed", "unreachable": return Theme.danger
        default: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
