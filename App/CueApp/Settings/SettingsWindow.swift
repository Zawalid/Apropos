import Cue
import AppKit
import SwiftUI

/// Things the settings search should find that are actions, not stored settings.
struct SettingsAction: Identifiable {
    let title: String
    let keywords: String
    let page: SettingPage
    var id: String { title }

    static let all = [
        SettingsAction(title: "Reset learned ranking", keywords: "usage frecency suggestions", page: .privacyAndData),
        SettingsAction(title: "Clear history", keywords: "recent commands", page: .privacyAndData),
        SettingsAction(title: "Hidden commands", keywords: "unhide show again", page: .privacyAndData),
        SettingsAction(title: "Export settings", keywords: "backup json", page: .privacyAndData),
        SettingsAction(title: "Import settings", keywords: "restore json", page: .privacyAndData),
        SettingsAction(title: "Accessibility access", keywords: "permission", page: .privacyAndData),
        SettingsAction(title: "Version", keywords: "about build", page: .about),
    ]
}

@MainActor
@Observable
final class SettingsNavigation {
    var page = SettingPage.general
}

/// Owns the Settings window: one 860 x 600 window with a sidebar and grouped cards.
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
        if let page { navigation.page = page }
        let window = window ?? makeWindow()
        self.window = window
        if !AgentMode.isOn { NSApp.activate() }
        window.makeKeyAndOrderFront(nil)
        AgentMode.conceal(window)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Cue Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.contentView = NSHostingView(
            rootView: SettingsRoot(controller: controller, settings: controller.settings, navigation: navigation))
        window.center()
        return window
    }
}

private struct SettingsRoot: View {
    let controller: AppController
    let settings: SettingsModel
    let navigation: SettingsNavigation

    @State private var query = ""
    @Environment(\.cueReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)
                .background(Theme.sidebarBackground)
            Rectangle().fill(Theme.cardEdge).frame(width: 1)
            detail
        }
        .frame(minWidth: 860, minHeight: 600)
        .background(Theme.windowBackground)
        .tint(Theme.accentText)
        .ignoresSafeArea()
        .providesReduceMotion(settings.reduceMotion)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.text3)
                TextField("Search settings", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .accessibilityLabel("Search settings")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.chipEdge, lineWidth: 1))
            .padding(.top, 44)

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(SettingPage.allCases, id: \.self) { page in pageButton(page) }
            } else {
                searchResults
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func pageButton(_ page: SettingPage) -> some View {
        let selected = navigation.page == page
        return Button {
            navigation.page = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected ? Theme.accentText : Theme.tileInk)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(
                            selected ? Theme.accentSoft : Theme.tile))
                Text(page.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Theme.highlight : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .cueFocusRing(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var searchResults: some View {
        let hits: [(title: String, page: SettingPage)] =
            SettingsRegistry.search(query).map { ($0.title, $0.page) }
            + SettingsAction.all.filter {
                let haystack = ($0.title + " " + $0.keywords).lowercased()
                return query.lowercased().split(separator: " ").allSatisfy { haystack.contains($0) }
            }.map { ($0.title, $0.page) }
        return VStack(alignment: .leading, spacing: 2) {
            if hits.isEmpty {
                Text("No settings match")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
                    .padding(8)
            }
            ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                Button {
                    navigation.page = hit.page
                    query = ""
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(hit.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                        Text(hit.page.title).font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                page
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 36)
            .padding(.top, 52)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(navigation.page)
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : Motion.easeOut(0.12), value: navigation.page)
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.page {
        case .general: GeneralPage(controller: controller, settings: settings)
        case .appearance: AppearancePage(settings: settings)
        case .context: ContextPage(settings: settings)
        case .privacyAndData: PrivacyPage(controller: controller, settings: settings)
        case .updates: UpdatesPage(settings: settings)
        case .about: AboutPage()
        }
    }
}
