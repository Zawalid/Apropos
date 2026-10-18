import Apropos
import SwiftUI

/// Where the settings window is, with history for the back and forward buttons, and what the search just revealed.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var page = SettingPage.general
    private var backStack: [SettingPage] = []
    private var forwardStack: [SettingPage] = []

    /// The anchor the pane should scroll to; `scrollToken` makes picking the same result twice scroll again.
    var scrollTarget: String?
    var scrollToken = 0
    /// The anchor whose label is pulsing right now.
    var flashing: String?

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func select(_ page: SettingPage) {
        guard page != self.page else { return }
        backStack.append(self.page)
        forwardStack = []
        self.page = page
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(page)
        page = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(page)
        page = next
    }

    func reveal(page: SettingPage, anchor: String?) {
        select(page)
        guard let anchor else { return }
        scrollTarget = anchor
        scrollToken += 1
    }
}

// MARK: Search anchors

/// Marks a row as a place the search can jump to, and pulses it when it is the one that was found.
private struct SettingsAnchorModifier: ViewModifier {
    let anchor: String
    @Environment(SettingsNavigation.self) private var navigation

    func body(content: Content) -> some View {
        content
            .id(anchor)
            .background {
                if navigation.flashing == anchor { Theme.accentSoft.transition(.opacity) }
            }
    }
}

extension View {
    func settingsAnchor(_ anchor: String) -> some View {
        modifier(SettingsAnchorModifier(anchor: anchor))
    }
}

/// Scrolls a pane to the search result and pulses it once.
struct SettingsRevealer<Content: View>: View {
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.aproposReduceMotion) private var reduceMotion
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            content
                .task(id: navigation.scrollToken) {
                    guard let target = navigation.scrollTarget else { return }
                    try? await Task.sleep(for: .milliseconds(80))
                    proxy.scrollTo(target, anchor: .center)
                    withAnimation(reduceMotion ? nil : Motion.easeOut(0.2)) { navigation.flashing = target }
                    try? await Task.sleep(for: .milliseconds(1100))
                    withAnimation(reduceMotion ? nil : Motion.easeOut(0.3)) { navigation.flashing = nil }
                    navigation.scrollTarget = nil
                }
        }
    }
}

// MARK: Cards and rows

/// A titled group of rows in a rounded card. The last row's divider is pushed out of the card and clipped.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.leading, 14)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .padding(.bottom, -1)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.Settings.card))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.Settings.cardEdge, lineWidth: 1))
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row: a title with an optional second line, any leading icon, and a trailing control. A row given a setting id
/// shows a small dot when that setting differs from its default, and a reset button while the pointer is over it.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var leading: AnyView?
    var settingID: SettingID?
    @ViewBuilder var trailing: Trailing

    @Environment(SettingsModel.self) private var settings
    @State private var hovering = false

    var body: some View {
        let modified = settingID.map(settings.isModified) ?? false
        HStack(spacing: 12) {
            if let leading { leading }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            if modified, let settingID {
                Button {
                    settings.resetSetting(settingID)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.text3)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(hovering ? Theme.Settings.chip : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel("Reset \(title) to its default")
            }
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 46)
        .overlay(alignment: .leading) {
            if modified { Circle().fill(Theme.accent).frame(width: 4, height: 4).padding(.leading, 5) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Settings.rule).frame(height: 1)
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// A switch row whose texts come from the settings registry.
struct SettingToggleRow: View {
    let id: SettingID
    var title: String?
    @Binding var isOn: Bool

    var body: some View {
        let definition = SettingsRegistry.definition(for: id)
        SettingsRow(
            title: title ?? definition?.title ?? id.rawValue,
            detail: title == nil ? definition.map(\.detail).flatMap { $0.isEmpty ? nil : $0 } : nil, settingID: id
        ) {
            AproposToggle(title: title ?? definition?.title ?? id.rawValue, isOn: $isOn)
        }
        .settingsAnchor(id.rawValue)
    }
}

/// A switch that reads the same whether or not its window is key: accent track when on, quiet track when off.
struct AproposToggle: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.selection) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.Settings.switchOff)
                .frame(width: 38, height: 22)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Theme.accentInk : Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .padding(2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable()
        .aproposFocusRing(Capsule())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A menu that shows its current value and a chevron, right-aligned like a pop-up button. It has no box until hovered.
struct ValueMenu<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(hovering ? Theme.text : Theme.text2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.Settings.chip : .clear)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, -8)
        .onHover { hovering = $0 }
    }
}

/// A filled pill button for the settings panes: no border, a slightly brighter fill on hover.
struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false

    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(destructive ? Theme.cautionText : Theme.text)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering || configuration.isPressed ? Theme.Settings.chipHover : Theme.Settings.chip)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .aproposFocusRing(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Lays children out left to right and wraps them onto new lines, for the context chip toggles.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (subview, point) in zip(subviews, result.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}

/// The sidebar tile of a page: a flat light square with the page's symbol.
struct PageTile: View {
    let page: SettingPage
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.Settings.tileInk)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.Settings.tile))
            .accessibilityHidden(true)
    }
}
