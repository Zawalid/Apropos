import AppKit
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, context, privacy, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .context: "Context"
        case .privacy: "Privacy and data"
        case .about: "Updates and About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .context: "scope"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

/// One searchable setting, for the sidebar's search field.
struct SettingsEntry: Identifiable {
    let title: String
    let page: SettingsPage
    var id: String { title }

    static let all: [SettingsEntry] = [
        SettingsEntry(title: "Open at login", page: .general),
        SettingsEntry(title: "Show in menu bar", page: .general),
        SettingsEntry(title: "Open hotkey", page: .general),
        SettingsEntry(title: "Close on focus loss", page: .general),
        SettingsEntry(title: "Reset query", page: .general),
        SettingsEntry(title: "Theme", page: .appearance),
        SettingsEntry(title: "Interface size", page: .appearance),
        SettingsEntry(title: "Row icons", page: .appearance),
        SettingsEntry(title: "Sense context", page: .context),
        SettingsEntry(title: "Context chips", page: .context),
        SettingsEntry(title: "Apps that Cue senses", page: .context),
        SettingsEntry(title: "Ignored apps", page: .context),
        SettingsEntry(title: "Accessibility", page: .privacy),
        SettingsEntry(title: "Reset learned ranking", page: .privacy),
        SettingsEntry(title: "Clear history", page: .privacy),
        SettingsEntry(title: "Export settings", page: .privacy),
        SettingsEntry(title: "Import settings", page: .privacy),
        SettingsEntry(title: "Check for updates", page: .about),
        SettingsEntry(title: "Version", page: .about),
    ]
}

@MainActor
@Observable
final class SettingsNavigation {
    var page = SettingsPage.general
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

    func show(page: SettingsPage? = nil) {
        if let page { navigation.page = page }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                ForEach(SettingsPage.allCases) { page in pageButton(page) }
            } else {
                searchResults
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func pageButton(_ page: SettingsPage) -> some View {
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
        let needle = query.lowercased()
        let hits = SettingsEntry.all.filter { $0.title.lowercased().contains(needle) }
        return VStack(alignment: .leading, spacing: 2) {
            if hits.isEmpty {
                Text("No settings match")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
                    .padding(8)
            }
            ForEach(hits) { hit in
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
        case .privacy: PrivacyPage(controller: controller, settings: settings)
        case .about: AboutPage(settings: settings)
        }
    }
}
