import AppKit
import Cue
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
        Action(title: "Version", keywords: "about build", page: .about, section: "Cue", anchor: "version"),
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
        window.title = "Cue Settings"
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
                .frame(width: 214)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.sidebarBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardEdge, lineWidth: 1)
                )
                .padding(6)
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Theme.windowBackground)
        .tint(Theme.accent)
        .environment(navigation)
        .environment(\.interfaceMetrics, settings.metrics)
        .providesReduceMotion(settings.reduceMotion)
        .ignoresSafeArea()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
                .padding(.top, 38)
            if trimmedQuery.isEmpty {
                pageList
            } else {
                searchResults
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var searchField: some View {
        HStack(spacing: 8) {
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
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.chip))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.chipEdge, lineWidth: 1))
    }

    private var pageList: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach([SettingPage.general, .appearance, .context, .privacyAndData], id: \.self) { pageRow($0) }
            Divider().overlay(Theme.cardEdge).padding(.vertical, 6).padding(.horizontal, 6)
            ForEach([SettingPage.updates, .about], id: \.self) { pageRow($0) }
        }
    }

    private func pageRow(_ page: SettingPage) -> some View {
        let selected = navigation.page == page
        return Button {
            navigation.select(page)
        } label: {
            HStack(spacing: 9) {
                PageTile(page: page)
                Text(page.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.highlight : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
                        .padding(10)
                }
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    Button {
                        openHit(at: index)
                    } label: {
                        HStack(spacing: 10) {
                            PageTile(page: hit.page)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.title).font(.system(size: 13)).foregroundStyle(Theme.text)
                                Text(
                                    hit.isPage
                                        ? "Page"
                                        : [hit.page.title, hit.section].compactMap { $0 }.joined(
                                            separator: " \u{203A} ")
                                )
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.text3)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(index == highlightedHit ? Theme.highlight : .clear)
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
        VStack(spacing: 0) {
            topBar
            SettingsRevealer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        page
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                    .id(navigation.page)
                }
                .scrollIndicators(.never)
            }
        }
    }

    /// Back and forward through the panes visited, and the title of the current one.
    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                historyButton("chevron.left", label: "Back", enabled: navigation.canGoBack) { navigation.goBack() }
                Rectangle().fill(Theme.cardEdge).frame(width: 1, height: 12)
                historyButton("chevron.right", label: "Forward", enabled: navigation.canGoForward) {
                    navigation.goForward()
                }
            }
            .background(Capsule().fill(Theme.chip))
            .overlay(Capsule().strokeBorder(Theme.chipEdge, lineWidth: 1))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(height: 44, alignment: .center)
    }

    private func historyButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Theme.text : Theme.text3.opacity(0.5))
                .frame(width: 30, height: 26)
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
