import SwiftUI

/// A keycap pill: one key of a shortcut.
struct KeyCap: View {
    let text: String
    var onAccent = false
    var small = false

    var body: some View {
        Text(text)
            .font(.system(size: small ? 10.5 : 11.5, weight: .medium))
            .foregroundStyle(onAccent ? Theme.accentInk.opacity(0.8) : Theme.text2)
            .frame(minWidth: small ? 17 : 20, minHeight: small ? 17 : 20)
            .padding(.horizontal, text.count > 1 ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(onAccent ? Theme.accentInk.opacity(0.1) : Theme.keyFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(onAccent ? Theme.accentInk.opacity(0.2) : Theme.keyEdge, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// A button inside a glass capsule: quiet until hovered, shrinks a touch while pressed.
struct CapsuleButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .frame(height: Theme.footerHeight - 6)
            .background(Capsule().fill(hovering || configuration.isPressed ? Theme.highlight : .clear))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.easeOut(0.12), value: configuration.isPressed)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .cueFocusRing(Capsule())
    }
}

/// The round glass button at the bottom left.
struct RoundGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: Theme.footerHeight, height: Theme.footerHeight)
            .background(Theme.floatFill, in: Circle())
            .cueGlass(in: Circle(), tinted: false)
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Motion.easeOut(0.12), value: configuration.isPressed)
            .contentShape(Circle())
            .cueFocusRing(Circle())
    }
}

/// The accent-filled call to action, used once per screen.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(Theme.accent))
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.easeOut(0.12), value: configuration.isPressed)
            .contentShape(Capsule())
            .cueFocusRing(Capsule())
    }
}
