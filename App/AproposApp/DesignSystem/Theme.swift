import AppKit
import SwiftUI

/// Colors and metrics shared by every Apropos surface. They follow the interactive prototype in `docs/prototype`: a
/// green-tinted glass, neutral selection and one mint accent (deep emerald in light mode) used sparingly.
enum Theme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let panelRadius: CGFloat = 22
    static let rowRadius: CGFloat = 12
    static let tileRadius: CGFloat = 8
    static let tileSize: CGFloat = 24
    static let controlRadius: CGFloat = 8
    static let rowHeight: CGFloat = 38
    static let sectionHeight: CGFloat = 30
    /// The list stops this far above the panel's bottom edge so the floating footer has its own strip.
    static let footerInset: CGFloat = 54
    static let listFade: CGFloat = 24
    static let footerHeight: CGFloat = 34

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }

    private static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> NSColor {
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
    }

    // MARK: Text

    static let text = adaptive(light: rgba(18, 28, 24, 1), dark: rgba(242, 245, 243, 1))
    static let text2 = adaptive(light: rgba(18, 28, 24, 0.66), dark: rgba(242, 245, 243, 0.64))
    static let text3 = adaptive(light: rgba(18, 28, 24, 0.5), dark: rgba(242, 245, 243, 0.44))

    // MARK: Accent

    /// The accent as text or an icon.
    static let accentText = adaptive(light: rgba(10, 107, 80, 1), dark: rgba(140, 242, 204, 1))
    /// The fill of the primary button, carrying `accentInk`.
    static let accent = adaptive(light: rgba(10, 107, 80, 1), dark: rgba(140, 242, 204, 1))
    static let accentInk = adaptive(light: rgba(244, 251, 248, 1), dark: rgba(11, 16, 15, 1))
    static let accentSoft = adaptive(light: rgba(10, 107, 80, 0.13), dark: rgba(140, 242, 204, 0.16))

    /// The brand's bright mint, for fills that carry dark text.
    static let mint = Color(red: 0.549, green: 0.949, blue: 0.8)
    static let ink = Color(red: 0.043, green: 0.063, blue: 0.057)

    static let cautionText = adaptive(light: rgba(160, 74, 8, 1), dark: NSColor.systemOrange)

    // MARK: Surfaces

    static let glassTint = adaptive(light: rgba(247, 249, 248, 0.66), dark: rgba(26, 29, 28, 0.62))
    /// A whisper of fill for the small glass controls floating over the list, so they read as glass and not as pills.
    static let floatFill = adaptive(light: rgba(255, 255, 255, 0.18), dark: rgba(255, 255, 255, 0.04))
    static let glassEdge = adaptive(light: rgba(0, 0, 0, 0.09), dark: rgba(255, 255, 255, 0.13))
    static let glassEdgeTop = adaptive(light: rgba(255, 255, 255, 0.9), dark: rgba(255, 255, 255, 0.22))
    static let highlight = adaptive(light: rgba(0, 0, 0, 0.06), dark: rgba(255, 255, 255, 0.09))
    static let chip = adaptive(light: rgba(0, 0, 0, 0.05), dark: rgba(255, 255, 255, 0.07))
    static let chipEdge = adaptive(light: rgba(0, 0, 0, 0.06), dark: rgba(255, 255, 255, 0.08))
    static let tile = adaptive(light: rgba(0, 0, 0, 0.06), dark: rgba(255, 255, 255, 0.08))
    static let tileInk = adaptive(light: rgba(18, 28, 24, 0.82), dark: rgba(255, 255, 255, 0.9))
    static let keyFill = adaptive(light: rgba(0, 0, 0, 0.04), dark: rgba(255, 255, 255, 0.07))
    static let keyEdge = adaptive(light: rgba(0, 0, 0, 0.14), dark: rgba(255, 255, 255, 0.15))
    static let windowBackground = adaptive(light: rgba(242, 245, 243, 1), dark: rgba(22, 25, 24, 1))
    static let sidebarBackground = adaptive(light: rgba(234, 238, 236, 1), dark: rgba(27, 31, 30, 1))
    static let card = adaptive(light: rgba(255, 255, 255, 0.8), dark: rgba(255, 255, 255, 0.045))
    static let cardEdge = adaptive(light: rgba(0, 0, 0, 0.07), dark: rgba(255, 255, 255, 0.07))
    static let divider = adaptive(light: rgba(0, 0, 0, 0.07), dark: rgba(255, 255, 255, 0.07))
}

extension Font {
    /// Shortcuts and counts are set in a monospaced face.
    static func data(_ style: Font.TextStyle = .caption, weight: Font.Weight = .medium) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

/// Tokens for the Settings window, taken from `docs/prototype/settings.html`.
extension Theme {
    enum Settings {
        static let window = adaptive(light: rgba(242, 244, 243, 1), dark: rgba(14, 17, 16, 1))
        static let sidebar = adaptive(light: rgba(0, 0, 0, 0.035), dark: rgba(255, 255, 255, 0.04))
        static let sidebarEdge = adaptive(light: rgba(0, 0, 0, 0.07), dark: rgba(255, 255, 255, 0.07))
        static let card = adaptive(light: rgba(255, 255, 255, 1), dark: rgba(23, 26, 25, 1))
        static let cardEdge = adaptive(light: rgba(0, 0, 0, 0.07), dark: rgba(255, 255, 255, 0.06))
        static let rule = adaptive(light: rgba(0, 0, 0, 0.07), dark: rgba(255, 255, 255, 0.06))
        static let highlight = adaptive(light: rgba(0, 0, 0, 0.07), dark: rgba(255, 255, 255, 0.075))
        static let hover = adaptive(light: rgba(0, 0, 0, 0.04), dark: rgba(255, 255, 255, 0.05))
        static let chip = adaptive(light: rgba(0, 0, 0, 0.055), dark: rgba(255, 255, 255, 0.075))
        static let chipHover = adaptive(light: rgba(0, 0, 0, 0.09), dark: rgba(255, 255, 255, 0.12))
        static let tile = adaptive(light: rgba(58, 64, 62, 1), dark: rgba(221, 225, 223, 1))
        static let tileInk = adaptive(light: rgba(244, 246, 245, 1), dark: rgba(27, 31, 30, 1))
        static let switchOff = adaptive(light: rgba(0, 0, 0, 0.18), dark: rgba(255, 255, 255, 0.2))
    }
}
