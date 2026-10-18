import SwiftUI

/// A row of picture choices: each option is a small drawing of what it does, with its name below. The chosen one wears a
/// mint ring. Used where seeing the result beats reading a menu.
struct ChoiceCards<Value: Hashable, Preview: View>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    @ViewBuilder var preview: (Value) -> Preview

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    VStack(spacing: 8) {
                        preview(option.value)
                            .frame(height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selected ? Brand.mint : Brand.line, lineWidth: selected ? 2 : 1)
                            )
                        Text(option.title)
                            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Brand.text : Brand.text2)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(16)
    }
}

/// A tiny drawing of the panel: a search field and three rows, in light or dark, optionally with leading marks.
struct MiniPanel: View {
    enum Scheme { case light, dark }
    enum Leading { case none, glyph, logos }

    let scheme: Scheme
    var leading: Leading = .glyph

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color.white : Color.black
        VStack(alignment: .leading, spacing: 7) {
            Capsule().fill(ink.opacity(0.16)).frame(width: 54, height: 7)
                .padding(.bottom, 3)
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 6) {
                    mark(index: index, ink: ink)
                    Capsule().fill(ink.opacity(index == 0 ? 0.55 : 0.28)).frame(width: [58, 44, 66][index], height: 6)
                }
                .padding(.horizontal, 5)
                .frame(height: 14)
                .background(Capsule().fill(index == 0 ? ink.opacity(0.1) : .clear))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.96, green: 0.96, blue: 0.97))
    }

    @ViewBuilder
    private func mark(index: Int, ink: Color) -> some View {
        switch leading {
        case .none:
            EmptyView()
        case .glyph:
            RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(ink.opacity(0.4), lineWidth: 1)
                .frame(width: 7, height: 7)
        case .logos:
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill([Color.blue, Color.orange, Color.green][index])
                .frame(width: 8, height: 8)
        }
    }
}

/// The system option: the dark panel on one half and the light on the other.
struct SplitMiniPanel: View {
    var body: some View {
        ZStack {
            MiniPanel(scheme: .light)
            MiniPanel(scheme: .dark)
                .mask(
                    GeometryReader { geometry in
                        Path { path in
                            path.move(to: CGPoint(x: geometry.size.width, y: 0))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: geometry.size.width * 0.35, y: geometry.size.height))
                            path.addLine(to: CGPoint(x: geometry.size.width * 0.65, y: 0))
                            path.closeSubpath()
                        }
                        .fill(.black)
                    })
        }
    }
}
