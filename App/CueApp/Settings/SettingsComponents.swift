import SwiftUI

/// A rounded card holding grouped rows, with hairline dividers between them.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .padding(.leading, 6)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardEdge, lineWidth: 1))
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row of a card: title and optional detail at the left, a control at the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var leading: AnyView?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let leading { leading }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 46)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A hairline between rows of one card.
struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Theme.cardEdge).frame(height: 1).padding(.leading, 14)
    }
}

/// A switch row.
struct ToggleRow: View {
    let title: String
    var detail: String?
    let isOn: Binding<Bool>

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            CueToggle(title: title, isOn: isOn)
        }
    }
}

/// A switch that reads the same whether or not its window is key: accent track when on, quiet track when off.
struct CueToggle: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.selection) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.keyEdge)
                .frame(width: 40, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Theme.accentInk : Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(3)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable()
        .cueFocusRing(Capsule())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A segmented control in Cue's style: a quiet track with a sliding highlight.
struct CueSegmented<Value: Hashable & Identifiable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let selected = option == selection
                Button {
                    withAnimation(reduceMotion ? nil : Motion.selection) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.highlight)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable()
                .cueFocusRing(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))
    }
}

/// A quiet rounded button for the settings pages.
struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(destructive ? Theme.cautionText : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.chip))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.chipEdge, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.05 : 0)
            .contentShape(Rectangle())
            .cueFocusRing(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}
