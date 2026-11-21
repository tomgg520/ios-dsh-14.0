import SwiftUI

enum Theme {
    static let accent = Color(red: 0.30, green: 0.42, blue: 1.00)
    static let accentDark = Color(red: 0.22, green: 0.32, blue: 0.95)
    static let danger = Color(red: 0.94, green: 0.36, blue: 0.36)
    static let success = Color(red: 0.24, green: 0.78, blue: 0.52)
    static let warning = Color(red: 0.97, green: 0.67, blue: 0.24)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.035, green: 0.04, blue: 0.055)
            : Color(red: 0.965, green: 0.968, blue: 0.978)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.085, green: 0.095, blue: 0.125)
            : Color.white
    }

    static func surfaceAlt(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.145, blue: 0.18)
            : Color(red: 0.925, green: 0.93, blue: 0.945)
    }

    static func codeBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.065, blue: 0.09)
            : Color(red: 0.945, green: 0.95, blue: 0.965)
    }

    static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.08)
    }

    static func subtleText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5)
    }

    static let bubbleGradient = LinearGradient(
        gradient: Gradient(colors: [Color(red: 0.33, green: 0.45, blue: 1.0), Color(red: 0.24, green: 0.34, blue: 0.95)]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 通用小控件

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(enabled ? Theme.accent : Theme.accent.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
