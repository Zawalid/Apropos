import AppKit
import SwiftUI

/// Colors and metrics shared by every Cue surface. The palette follows Lopper's: a green-tinted grey, mint on dark
/// and deep emerald on light for anything that has to read as an accent.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let panelRadius: CGFloat = 18
    static let rowRadius: CGFloat = 9
    static let controlRadius: CGFloat = 8

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }

    /// The accent as text or an icon.
    static let accentText = adaptive(
        light: NSColor(srgbRed: 0.04, green: 0.42, blue: 0.31, alpha: 1),
        dark: NSColor(srgbRed: 0.50, green: 0.90, blue: 0.74, alpha: 1))

    /// The brand's bright mint, for fills that carry dark text.
    static let mint = Color(red: 0.55, green: 0.95, blue: 0.80)
    static let ink = Color(red: 0.043, green: 0.063, blue: 0.057)

    /// Supporting text. The tertiary label is too faint on light backgrounds, so light mode uses the secondary one.
    static let metaText = adaptive(light: .secondaryLabelColor, dark: .tertiaryLabelColor)

    static let cautionText = adaptive(
        light: NSColor(srgbRed: 0.63, green: 0.29, blue: 0.03, alpha: 1), dark: .systemOrange)

    /// The tint laid over the panel's blur so it reads as Cue's green-grey rather than whatever is behind it.
    static let panelTint = adaptive(
        light: NSColor(srgbRed: 0.97, green: 0.98, blue: 0.975, alpha: 0.55),
        dark: NSColor(srgbRed: 0.075, green: 0.09, blue: 0.085, alpha: 0.55))

    static let hairline = Color.primary.opacity(0.08)
    static let selection = adaptive(
        light: NSColor(srgbRed: 0.04, green: 0.42, blue: 0.31, alpha: 0.12),
        dark: NSColor(srgbRed: 0.50, green: 0.90, blue: 0.74, alpha: 0.16))
}

extension Font {
    /// Shortcuts and counts are set in a monospaced face.
    static func data(_ style: Font.TextStyle = .caption, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}
