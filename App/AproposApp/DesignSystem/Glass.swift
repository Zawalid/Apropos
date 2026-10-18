import AppKit
import SwiftUI

/// The glass look. On macOS 26 it is the system's Liquid Glass; before that, a behind-window blur with the same tint
/// and hairline, so the two read as one design.
extension View {
    /// A glass surface in `shape`: material, Apropos's tint, a hairline whose top edge catches light, and no fill
    /// outside the shape.
    func aproposGlass<S: InsettableShape>(in shape: S, tinted: Bool = true) -> some View {
        modifier(AproposGlass(shape: shape, tinted: tinted))
    }
}

private struct AproposGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tinted: Bool

    func body(content: Content) -> some View {
        content
            .background { backing }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Theme.glassEdgeTop, Theme.glassEdge, Theme.glassEdge],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
    }

    @ViewBuilder
    private var backing: some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(
                tinted ? .regular.tint(Theme.glassTint) : .regular, in: shape)
        } else {
            ZStack {
                VisualEffectBlur()
                if tinted { Theme.glassTint }
            }
        }
    }
}

/// A behind-window blur: the fallback below macOS 26.
private struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A keyboard focus ring in the accent, drawn only while the view has focus.
private struct AproposFocusRing<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content.overlay {
            if isFocused { shape.stroke(Theme.accentText, lineWidth: 2).padding(-2) }
        }
    }
}

extension View {
    func aproposFocusRing<S: Shape>(_ shape: S) -> some View {
        modifier(AproposFocusRing(shape: shape))
    }
}
