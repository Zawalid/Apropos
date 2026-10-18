import AppKit
import Apropos
import SwiftUI

/// One result of the settings search: a page, a setting, or an action.
struct SettingsHit: Identifiable, Hashable {
    let id: String
    let title: String
    let page: SettingPage
    let section: String?
    let anchor: String?
    let isPage: Bool
}

/// What the search knows about. Registry settings come from `SettingsRegistry`; actions that are not stored settings
/// are listed here with the section they live in.
enum SettingsCatalog {
    private static let sections: [SettingID: String] = [
        .openAtLogin: "Startup", .showInMenuBar: "Startup", .openHotKey: "Panel", .closeOnFocusLoss: "Panel",
        .resetQueryAfterSeconds: "Panel", .showAlternateCommands: "Panel", .theme: "Look", .interfaceSize: "Look",
        .rowIcons: "Look", .reduceMotion: "Look", .contextSensing: "Context", .contextChips: "Chips",
        .contextDisabledApps: "Apps", .contextIgnoreList: "Never read these apps", .checkForUpdates: "Updates",
    ]

    private struct Action {
        let title: String
        let keywords: String
        let page: SettingPage
        let section: String
        let anchor: String
    }

    private static let actions = [
        Action(
            title: "Accessibility", keywords: "permission access", page: .privacyAndData, section: "Access",
            anchor: "accessibility"),
        Action(
            title: "Reset learned ranking", keywords: "usage frecency suggestions", page: .privacyAndData,
            section: "Learned data", anchor: "ranking"),
        Action(
            title: "Clear history", keywords: "recent commands", page: .privacyAndData, section: "Learned data",
            anchor: "history"),
        Action(
            title: "Hidden commands", keywords: "unhide show again", page: .privacyAndData, section: "Learned data",
            anchor: "hidden"),
        Action(
            title: "Export settings", keywords: "backup json", page: .privacyAndData, section: "Settings file",
            anchor: "export"),
        Action(
            title: "Import settings", keywords: "restore json", page: .privacyAndData, section: "Settings file",
            anchor: "import"),
        Action(
            title: "Check for updates now", keywords: "version upgrade", page: .updates, section: "Updates",
            anchor: "checknow"),
        Action(title: "Version", keywords: "about build", page: .about, section: "Apropos", anchor: "version"),
    ]

    static func search(_ query: String) -> [SettingsHit] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        var hits: [SettingsHit] = []
        for page in SettingPage.allCases where words.allSatisfy({ page.title.lowercased().contains($0) }) {
            hits.append(
                SettingsHit(
                    id: "page-\(page.rawValue)", title: page.title, page: page, section: nil, anchor: nil, isPage: true)
            )
        }
        for definition in SettingsRegistry.search(query) {
            hits.append(
                SettingsHit(
                    id: definition.id.rawValue, title: definition.title, page: definition.page,
                    section: sections[definition.id], anchor: definition.id.rawValue, isPage: false))
        }
        for action in actions {
            let haystack = (action.title + " " + action.keywords).lowercased()
            if words.allSatisfy({ haystack.contains($0) }) {
                hits.append(
                    SettingsHit(
                        id: action.anchor, title: action.title, page: action.page, section: action.section,
                        anchor: action.anchor, isPage: false))
            }
        }
        return hits
    }
}

/// Owns the Settings window: a dark window with a floating sidebar panel, like the launcher it sits beside.
@MainActor
final class SettingsWindowController {
    private let controller: AppController
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(controller: AppController) {
        self.controller = controller
    }

    var currentWindow: NSWindow? { window }

    func show(page: SettingPage? = nil) {
        if let page { navigation.select(page) }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = NSHostingView(
            rootView: SettingsRoot(controller: controller, settings: controller.settings, navigation: navigation))
        window.center()
        return window
    }
}

struct SettingsRoot: View {
    let controller: AppController
    let settings: SettingsModel
    let navigation: SettingsNavigation

    @State private var query: String
    @State private var highlightedHit = 0
    @FocusState private var searchFocused: Bool
    @Namespace private var selection
    @Environment(\.aproposReduceMotion) private var reduceMotion

    init(controller: AppController, settings: SettingsModel, navigation: SettingsNavigation, initialQuery: String = "")
    {
        self.controller = controller
        self.settings = settings
        self.navigation = navigation
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 212)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.Settings.sidebar))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.Settings.sidebarEdge, lineWidth: 1)
                )
                .padding(8)
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Theme.Settings.window)
        .tint(Theme.accent)
        .environment(navigation)
        .environment(settings)
        .environment(\.interfaceMetrics, settings.metrics)
        .providesReduceMotion(settings.reduceMotion)
        .ignoresSafeArea()
    }

    // MARK: Sidebar

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
                .padding(.top, 44)
                .padding(.horizontal, 2)
                .padding(.bottom, 10)
            if trimmedQuery.isEmpty {
                pageList
            } else {
                searchResults
            }
            Spacer(minLength: 0)
            sidebarFooter
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text3)
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
                .onSubmit { openHit(at: highlightedHit) }
                .onKeyPress(.downArrow) { moveHit(1) }
                .onKeyPress(.upArrow) { moveHit(-1) }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
                .onChange(of: query) { highlightedHit = 0 }
                .accessibilityLabel("Search settings")
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.Settings.chip))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? Theme.text3 : .clear, lineWidth: 1)
        )
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach([SettingPage.general, .appearance, .context, .privacyAndData], id: \.self) { pageRow($0) }
            Rectangle().fill(Theme.Settings.rule).frame(height: 1).padding(.vertical, 6).padding(.horizontal, 8)
            ForEach([SettingPage.updates, .about], id: \.self) { pageRow($0) }
        }
    }

    private func pageRow(_ page: SettingPage) -> some View {
        SidebarRow(page: page, isSelected: navigation.page == page, namespace: selection) {
            withAnimation(reduceMotion ? nil : Motion.selection) { navigation.select(page) }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(controller.permission.isTrusted ? Theme.accent : Theme.cautionText)
                .frame(width: 6, height: 6)
            Text(controller.permission.isTrusted ? "Ready" : "Needs access")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                ForEach(Array(controller.combo.caps.enumerated()), id: \.offset) {
                    KeyCap(text: $0.element, small: true)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var hits: [SettingsHit] { SettingsCatalog.search(trimmedQuery) }

    private var searchResults: some View {
        let hits = self.hits
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if hits.isEmpty {
                    Text("No settings match")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    Button {
                        openHit(at: index)
                    } label: {
                        HStack(spacing: 10) {
                            PageTile(page: hit.page)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.title).font(.system(size: 13.5)).foregroundStyle(Theme.text)
                                Text(
                                    hit.isPage
                                        ? "Page"
                                        : [hit.page.title, hit.section].compactMap { $0 }.joined(
                                            separator: " \u{203A} ")
                                )
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.text3)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(index == highlightedHit ? Theme.Settings.highlight : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func moveHit(_ delta: Int) -> KeyPress.Result {
        let count = hits.count
        guard count > 0, !trimmedQuery.isEmpty else { return .ignored }
        highlightedHit = min(max(highlightedHit + delta, 0), count - 1)
        return .handled
    }

    private func openHit(at index: Int) {
        let hits = self.hits
        guard hits.indices.contains(index) else { return }
        navigation.reveal(page: hits[index].page, anchor: hits[index].anchor)
    }

    // MARK: Detail

    private var detail: some View {
        ZStack(alignment: .top) {
            SettingsRevealer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        page
                    }
                    .frame(maxWidth: 580, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 62)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity)
                    .id(navigation.page)
                }
                .scrollIndicators(.never)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: 0.075),
                            .init(color: .black, location: 0.965), .init(color: .clear, location: 1),
                        ], startPoint: .top, endPoint: .bottom))
            }
            topBar
        }
    }

    /// Back and forward through the panes visited.
    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                historyButton("chevron.left", label: "Back", enabled: navigation.canGoBack) { navigation.goBack() }
                Rectangle().fill(Theme.Settings.rule).frame(width: 1, height: 14)
                historyButton("chevron.right", label: "Forward", enabled: navigation.canGoForward) {
                    navigation.goForward()
                }
            }
            .background(Capsule().fill(Theme.Settings.chip))
            .overlay(Capsule().strokeBorder(Theme.Settings.cardEdge, lineWidth: 1))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text : Theme.text3.opacity(0.5))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.page {
        case .general: GeneralPage(controller: controller, settings: settings)
        case .appearance: AppearancePage(settings: settings)
        case .context: ContextPage(settings: settings)
        case .privacyAndData: PrivacyPage(controller: controller, settings: settings)
        case .updates: UpdatesPage(settings: settings)
        case .about: AboutPage(controller: controller, settings: settings)
        }
    }
}

/// One row of the sidebar. The highlight is shared between rows, so it slides from the old page to the new one.
private struct SidebarRow: View {
    let page: SettingPage
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PageTile(page: page)
                Text(page.title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.Settings.highlight)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.Settings.hover)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
