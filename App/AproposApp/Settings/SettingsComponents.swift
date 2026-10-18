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
                if navigation.flashing == anchor { Brand.mint.opacity(0.14).transition(.opacity) }
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.text3)
                    .padding(.leading, 2)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .padding(.bottom, -1)
                .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
                .clipShape(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text3)
                    .padding(.horizontal, 2)
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
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Brand.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.text2)
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
                        .foregroundStyle(Brand.text3)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(hovering ? Brand.raised : .clear))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .accessibilityLabel("Reset \(title) to its default")
            }
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .overlay(alignment: .leading) {
            if modified { Circle().fill(Brand.mint).frame(width: 4, height: 4).padding(.leading, 5) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Brand.line).frame(height: 1).padding(.leading, 16)
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

/// The system switch, tinted with the accent. Native, so it behaves and looks like every other Mac switch.
struct AproposToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Brand.mint)
            .accessibilityLabel(title)
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
                    .foregroundStyle(Brand.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Brand.text3)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .frame(height: 28)
            .background(
                Capsule().fill(hovering ? Brand.raised : Brand.raised.opacity(0.8))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
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
            .foregroundStyle(destructive ? Brand.danger : Brand.text)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(
                Capsule().fill(hovering || configuration.isPressed ? Brand.raised : Brand.raised.opacity(0.8))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .aproposFocusRing(Capsule())
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

/// The glyph of a page: a plain symbol in the text colour, brand mint when its page is current. No tile, no colour coding.
struct PageTile: View {
    let page: SettingPage
    var size: CGFloat = 22
    var active = false

    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: 14.5, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(active ? Brand.mint : Brand.text2)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
