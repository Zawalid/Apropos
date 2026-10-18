import AppKit
import SwiftUI

/// The brand system for the surfaces around the palette: onboarding, Settings, the menu bar and empty states. It follows
/// `docs/identity/brand.md`. The palette keeps its own `Theme`; nothing here changes how it looks.
///
/// Two rules carry the identity. Mint is for what you can act on. Pearl, the tangerine bead, means "now": the current
/// step, the current page, a live recording. It is never decoration.
enum Brand {
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }

    private static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> NSColor {
        NSColor(
            srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    // MARK: Surfaces

    static let window = adaptive(light: rgb(0xF2F5F4), dark: rgb(0x0B1418))
    static let rail = adaptive(light: rgb(0xE8EEEC), dark: rgb(0x111D22))
    static let raised = adaptive(light: rgb(0xDDE6E3), dark: rgb(0x182A31))
    static let section = adaptive(light: rgb(0xFFFFFF, 0.72), dark: rgb(0x111D22))
    static let line = adaptive(light: rgb(0x0A181C, 0.10), dark: rgb(0xFFFFFF, 0.08))

    // MARK: Text

    static let text = adaptive(light: rgb(0x0E1A1D), dark: rgb(0xEAF3F1))
    static let text2 = adaptive(light: rgb(0x0E1A1D, 0.66), dark: rgb(0xEAF3F1, 0.64))
    static let text3 = adaptive(light: rgb(0x0E1A1D, 0.52), dark: rgb(0xEAF3F1, 0.46))

    // MARK: Accent

    static let mint = adaptive(light: rgb(0x0A8F70), dark: rgb(0x8CF2CC))
    static let mintInk = adaptive(light: rgb(0xF2FBF8), dark: rgb(0x062018))
    /// The moment. Only for what is current or live.
    static let pearl = adaptive(light: rgb(0xE56F2E), dark: rgb(0xFF8A4C))

    // MARK: Shape

    static let controlRadius: CGFloat = 8
    static let sectionRadius: CGFloat = 12
    static let windowRadius: CGFloat = 14

    // MARK: Images

    /// A rendered brand image. The app finds it in the asset catalog; the preview renderer, which has no app bundle,
    /// reads the same file from the repository.
    static func image(_ name: String, file: String) -> NSImage? {
        if let image = NSImage(named: name) { return image }
        #if DEBUG
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/prototype/assets/\(file)")
            return NSImage(contentsOf: url)
        #else
            return nil
        #endif
    }
}

/// The pearl: a small bead of light with a halo. It can pulse while something is live.
struct PearlView: View {
    var size: CGFloat = 7
    var pulsing = false

    @State private var bright = false
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(Brand.pearl)
            .frame(width: size, height: size)
            .shadow(color: Brand.pearl.opacity(bright ? 0.7 : 0.5), radius: bright ? size * 1.1 : size * 0.7)
            .onAppear {
                guard pulsing, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { bright = true }
            }
            .accessibilityHidden(true)
    }
}

/// The step list of a flow: a thin line through small nodes, finished steps filled in mint, and the pearl gliding to the
/// current one. This is the pearl's flow job.
struct RingStepper: View {
    let titles: [String]
    let current: Int
    var pearlPulses = false

    static let rowHeight: CGFloat = 44

    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The track and its mint progress.
            Rectangle().fill(Brand.line)
                .frame(width: 1, height: CGFloat(max(titles.count - 1, 0)) * Self.rowHeight)
                .offset(x: 5.5, y: Self.rowHeight / 2)
            Rectangle().fill(Brand.mint)
                .frame(width: 1, height: CGFloat(current) * Self.rowHeight)
                .offset(x: 5.5, y: Self.rowHeight / 2)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 16) {
                        node(done: index < current)
                        Text(title)
                            .font(.system(size: 13.5, weight: index == current ? .medium : .regular))
                            .foregroundStyle(index == current ? Brand.text : index < current ? Brand.text2 : Brand.text3)
                    }
                    .frame(height: Self.rowHeight, alignment: .leading)
                }
            }
            PearlView(size: 7, pulsing: pearlPulses)
                .offset(x: 2, y: CGFloat(current) * Self.rowHeight + Self.rowHeight / 2 - 3.5)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.42, dampingFraction: 0.64), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(titles.count): \(titles[min(current, titles.count - 1)])")
    }

    private func node(done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? Brand.mint : Brand.rail)
            Circle().strokeBorder(done ? Brand.mint : Brand.text3, lineWidth: 1)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 6.5, weight: .heavy))
                    .foregroundStyle(Brand.mintInk)
            }
        }
        .frame(width: 11, height: 11)
    }
}

/// The two buttons of a flow. One filled button per view, the rest quiet.
struct BrandButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain }
    var kind: Kind = .secondary
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: kind == .primary ? .semibold : .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .plain ? 4 : 16)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .aproposFocusRing(RoundedRectangle(cornerRadius: Brand.controlRadius, style: .continuous))
    }

    private var foreground: Color {
        switch kind {
        case .primary: Brand.mintInk
        case .secondary: Brand.text
        case .plain: hovering ? Brand.text : Brand.text2
        }
    }

    private func fill(pressed: Bool) -> Color {
        switch kind {
        case .primary: Brand.mint.opacity(pressed ? 0.85 : hovering ? 0.94 : 1)
        case .secondary: pressed || hovering ? Brand.raised : Brand.raised.opacity(0.7)
        case .plain: .clear
        }
    }
}

/// The ring and bead mark as a vector, drawn in the current foreground colour. It is the menu bar glyph's twin, used inside
/// the app wherever the asset catalog's template image is not available.
struct BrandGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width, geometry.size.height) / 18
            ZStack(alignment: .topLeading) {
                Circle()
                    .trim(from: 0, to: 304.0 / 360.0)
                    .rotation(.degrees(-12))
                    .stroke(style: StrokeStyle(lineWidth: 2.1 * unit, lineCap: .round))
                    .frame(width: 12.4 * unit, height: 12.4 * unit)
                    .offset(x: 2.8 * unit, y: 2.8 * unit)
                Circle()
                    .frame(width: 6 * unit, height: 6 * unit)
                    .offset(x: (13.749 - 3) * unit, y: (5.015 - 3) * unit)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
