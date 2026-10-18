import Cue
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
    @Environment(\.cueReduceMotion) private var reduceMotion
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

/// A titled group of rows in a rounded card.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .padding(.leading, 12)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardEdge, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3)
                    .padding(.horizontal, 12)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row: a title with an optional second line, any leading icon, and a trailing control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var leading: AnyView?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let leading { leading }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.cardEdge).frame(height: 1).padding(.leading, 12)
        }
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
            detail: title == nil ? definition.map(\.detail).flatMap { $0.isEmpty ? nil : $0 } : nil
        ) {
            CueToggle(title: title ?? definition?.title ?? id.rawValue, isOn: $isOn)
        }
        .settingsAnchor(id.rawValue)
    }
}

/// A switch that reads the same whether or not its window is key: accent track when on, quiet track when off.
struct CueToggle: View {
    let title: String
    @Binding var isOn: Bool

    @Environment(\.cueReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.selection) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? Theme.accent : Theme.keyEdge)
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Theme.accentInk : Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                        .padding(2.5)
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

/// A menu that shows its current value and a chevron, right-aligned like a pop-up button.
struct ValueMenu<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button(option.title) { selection = option.value }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.value == selection }?.title ?? "")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.chip))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.chipEdge, lineWidth: 1))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A quiet rounded button for the settings panes.
struct SecondaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(destructive ? Theme.cautionText : Theme.text)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.chip))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.chipEdge, lineWidth: 1))
            .brightness(configuration.isPressed ? -0.05 : 0)
            .contentShape(Rectangle())
            .cueFocusRing(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// The sidebar tile of a page: a flat neutral square with the page's symbol.
struct PageTile: View {
    let page: SettingPage
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(Theme.tileInk)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.tile))
            .accessibilityHidden(true)
    }
}
