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
        .resetQueryAfterSeconds: "Panel", .showAlternateCommands: "Include in the panel",
        .includeContextActions: "Include in the panel", .includeUserCommands: "Include in the panel",
        .includeSendTo: "Include in the panel", .theme: "Look", .interfaceSize: "Look",
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
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 720, height: 480)
        window.contentView = NSHostingView(
            rootView: SettingsRoot(controller: controller, settings: controller.settings, navigation: navigation))
        window.center()
        return window
    }
}

/// The Settings window. Its traffic lights are moved in and down so they sit inside the floating sidebar panel.
final class SettingsWindow: NSWindow {
    private var restingOrigins: [NSWindow.ButtonType: NSPoint] = [:]

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(type) else { continue }
            let origin = restingOrigins[type] ?? button.frame.origin
            restingOrigins[type] = origin
            button.setFrameOrigin(NSPoint(x: origin.x + 11, y: origin.y - 13))
        }
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
                .frame(width: 224)
                .frame(maxHeight: .infinity)
                .brandGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.leading, 10)
                .padding(.vertical, 10)
            detail
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(WindowBackdrop().ignoresSafeArea())
        .tint(Brand.mint)
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
                .padding(.top, 50)
                .padding(.bottom, 12)
            if trimmedQuery.isEmpty {
                pageList
            } else {
                searchResults
            }
            Spacer(minLength: 0)
            sidebarFooter
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.text3)
            TextField("Search settings", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Brand.text)
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
        .background(Capsule().fill(Brand.raised))
        .overlay(Capsule().strokeBorder(searchFocused ? Brand.mint.opacity(0.7) : .clear, lineWidth: 1.5))
    }

    /// The pages in three groups, like the prototype: how it behaves, what it knows, and the rest.
    private var pageList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([SettingPage.general, .appearance], id: \.self) { pageRow($0) }
            Color.clear.frame(height: 14)
            ForEach([SettingPage.commands, .destinations], id: \.self) { pageRow($0) }
            Color.clear.frame(height: 14)
            ForEach([SettingPage.context, .prediction, .integrations, .privacyAndData], id: \.self) { pageRow($0) }
            Color.clear.frame(height: 14)
            ForEach([SettingPage.updates, .about], id: \.self) { pageRow($0) }
        }
    }

    private func pageRow(_ page: SettingPage) -> some View {
        SidebarRow(page: page, isSelected: navigation.page == page, namespace: selection) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.42, dampingFraction: 0.66)) {
                navigation.select(page)
            }
        }
    }

    /// Whether Apropos works, always in view: ready with its shortcut, or what is missing with one click to fix it.
    private var sidebarFooter: some View {
        let trusted = controller.permission.isTrusted
        return Button {
            navigation.reveal(page: .privacyAndData, anchor: trusted ? nil : "accessibility")
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(trusted ? Brand.mint.opacity(0.16) : Brand.danger.opacity(0.16))
                    if trusted {
                        BrandGlyph().foregroundStyle(Brand.mint).frame(width: 15, height: 15)
                    } else {
                        Image(systemName: "exclamationmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.danger)
                    }
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(trusted ? "Ready" : "Allow access")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                    Text(trusted ? "\(controller.combo.display) opens it" : "Accessibility is off")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.text3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.text3)
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Brand.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trusted ? "Apropos is ready" : "Apropos needs Accessibility")
    }

    private var hits: [SettingsHit] { SettingsCatalog.search(trimmedQuery) }

    private var searchResults: some View {
        let hits = self.hits
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if hits.isEmpty {
                    Text("No settings match")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.text3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }
                ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                    Button {
                        openHit(at: index)
                    } label: {
                        HStack(spacing: 10) {
                            PageTile(page: hit.page, active: index == highlightedHit)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.title).font(.system(size: 13.5)).foregroundStyle(Brand.text)
                                Text(
                                    hit.isPage
                                        ? "Page"
                                        : [hit.page.title, hit.section].compactMap { $0 }.joined(
                                            separator: " \u{203A} ")
                                )
                                .font(.system(size: 11.5))
                                .foregroundStyle(Brand.text3)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(index == highlightedHit ? Brand.raised : .clear)
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
                    VStack(alignment: .leading, spacing: 26) {
                        header
                        page
                    }
                    .frame(maxWidth: 580, alignment: .leading)
                    .padding(.horizontal, 30)
                    .padding(.top, 50)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity)
                    .id(navigation.page)
                }
                .scrollIndicators(.never)
            }
            // Content fades out as it slides under the floating back and forward buttons, like a glass header.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 54)
                    Rectangle()
                }
            )
            topBar
        }
    }

    /// The page title with a quiet live status on the right, so every page tells you where things stand.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(navigation.page.title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(Brand.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let status = status(for: navigation.page) {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.text3)
            }
        }
    }

    private func status(for page: SettingPage) -> String? {
        switch page {
        case .general: "Opens with \(controller.combo.caps.joined(separator: " "))"
        case .appearance: settings.appearance.title
        case .commands:
            controller.userCommands.commands.isEmpty
                ? "None yet" : "\(controller.userCommands.commands.count) of your own"
        case .destinations: "\(controller.send.library.runnable.count) available"
        case .prediction: settings.predictNextCommand ? "Learning on this Mac" : "Off"
        case .integrations: "apropos:// links"
        case .context: settings.contextSensing ? "Sensing is on" : "Sensing is off"
        case .privacyAndData: controller.permission.isTrusted ? "Accessibility allowed" : "Needs Accessibility"
        case .updates: "Early access"
        case .about:
            (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "Version \($0)" }
        }
    }

    /// Back and forward through the panes visited.
    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                historyButton("chevron.left", label: "Back", enabled: navigation.canGoBack) { navigation.goBack() }
                Rectangle().fill(Brand.line).frame(width: 1, height: 14)
                historyButton("chevron.right", label: "Forward", enabled: navigation.canGoForward) {
                    navigation.goForward()
                }
            }
            .brandGlass(in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 30)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? Brand.text : Brand.text3.opacity(0.5))
                .frame(width: 34, height: 28)
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
        case .commands: CommandsPage(controller: controller)
        case .destinations: DestinationsPage(controller: controller)
        case .prediction: PredictionPage(controller: controller, settings: settings)
        case .integrations: IntegrationsPage(controller: controller, settings: settings)
        case .context: ContextPage(controller: controller, settings: settings)
        case .privacyAndData: PrivacyPage(controller: controller, settings: settings)
        case .updates: UpdatesPage(settings: settings)
        case .about: AboutPage(controller: controller, settings: settings)
        }
    }
}

/// One row of the sidebar. The selection and the pearl are shared between rows, so they glide from the old page to the new.
private struct SidebarRow: View {
    let page: SettingPage
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PageTile(page: page, active: isSelected)
                Text(page.title)
                    .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Brand.text : Brand.text2)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .frame(height: 36)
            .background {
                if isSelected {
                    Capsule().fill(Brand.raised)
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hovering {
                    Capsule().fill(Brand.raised.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
