import SwiftUI

struct PermissionCard: View {
    let request: PermissionRequest
    let onSelect: (String?) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.warning)
                Text("需要你的授权")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }

            Text(request.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(request.options) { option in
                    Button(action: { onSelect(option.id) }) {
                        Text(option.name)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundColor(option.isReject ? Theme.danger : .white)
                            .background(option.isReject ? Theme.surfaceAlt(scheme) : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }

                Button(action: { onSelect(nil) }) {
                    Text("取消本次操作")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(14)
        .background(Theme.surface(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.warning.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }
}
