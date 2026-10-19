import AppKit
import Apropos
import CoreGraphics
import SwiftUI

/// What Apropos can reach, what it keeps on this Mac, and how to see it, take a copy of it, or forget it.
struct PrivacyPage: View {
    let controller: AppController
    let settings: SettingsModel

    @Environment(SettingsNavigation.self) private var navigation
    @State private var tick = 0
    @State private var forgetting: DataKind?
    @State private var forgettingAll = false

    /// The kinds of data Apropos keeps that can be forgotten without losing your commands or settings.
    enum DataKind: String, Identifiable, CaseIterable {
        case ranking, habits, recents, outside, folders
        var id: String { rawValue }

        var title: String {
            switch self {
            case .ranking: "Usage and ranking"
            case .habits: "Learned habits"
            case .recents: "Recent commands"
            case .outside: "Outside requests"
            case .folders: "Saved folders"
            }
        }

        var detail: String {
            switch self {
            case .ranking: "Which commands you use most in each app. Pins and hidden commands are kept."
            case .habits: "What you usually run after what, for Usually next."
            case .recents: "The recent list in the menu bar."
            case .outside: "The list of links and Shortcuts that asked Apropos to do something."
            case .folders: "Folders remembered for Copy to and Move to."
            }
        }
    }

    var body: some View {
        let _ = tick
        PrivacyIntro()
        networkSection
        permissions
        keeps
        SettingsSection(title: "Apps it never reads") {
            SettingsRow(
                title: "Password managers, banks and anything else you choose",
                detail: "Managed on the Context page, in one list with the per-app choices."
            ) {
                Button("Open Context") { navigation.select(.context) }.buttonStyle(SecondaryButtonStyle())
            }
            .settingsAnchor(SettingID.contextIgnoreList.rawValue)
            hiddenCommands
        }
        SettingsSection(title: "Your data") {
            SettingsRow(title: "Export all my data", detail: "Copies every file Apropos keeps into a folder you choose.") {
                Button("Export") { exportAll() }.buttonStyle(SecondaryButtonStyle())
            }
            SettingsRow(
                title: "Forget everything it learned",
                detail: "Clears habits, ranking, recent commands, outside requests and saved folders. Your commands and settings stay."
            ) {
                Button("Forget") { forgettingAll = true }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
        }
        SettingsSection(title: "Settings file") {
            SettingsRow(title: "Export settings", detail: "Save your settings as a JSON file.") {
                Button("Export") { settings.exportSettings() }.buttonStyle(SecondaryButtonStyle())
            }
            .settingsAnchor("export")
            SettingsRow(title: "Import settings", detail: "Replace your settings with a saved file.") {
                Button("Import") { settings.importSettings() }.buttonStyle(SecondaryButtonStyle())
            }
            .settingsAnchor("import")
        }
        Color.clear.frame(height: 0)
            .confirmationDialog(
                forgetting.map { "Forget \($0.title.lowercased())?" } ?? "", isPresented: Binding(
                    get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    if let forgetting { forget(forgetting) }
                    forgetting = nil
                }
            } message: {
                Text("This cannot be undone.")
            }
            .confirmationDialog(
                "Forget everything it learned?", isPresented: $forgettingAll, titleVisibility: .visible
            ) {
                Button("Forget everything", role: .destructive) {
                    DataKind.allCases.forEach(forget)
                }
            } message: {
                Text("Habits, ranking, recent commands, outside requests and saved folders are cleared. Your commands and settings stay. This cannot be undone.")
            }
    }

    // MARK: Network

    private var networkSection: some View {
        SettingsSection(title: "Network") {
            SettingsRow(
                title: settings.checkForUpdates ? "Connects only to check for updates" : "Makes no network connections",
                detail: settings.checkForUpdates
                    ? "The update check is on. Nothing else leaves this Mac."
                    : "The update check is off, so nothing at all leaves this Mac."
            ) {
                Button("Updates") { navigation.select(.updates) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        SettingsSection(
            title: "What macOS lets it do",
            footer: "Apropos asks only for what a feature needs, and tells you why."
        ) {
            permissionRow(
                "Accessibility", "Reads menus and presses items in the app in front. Needed for the panel.",
                state: controller.permission.isTrusted ? .allowed : .needed, anchor: "accessibility"
            ) {
                controller.permission.requestPrompt()
                controller.permission.openSystemSettings()
            }
            permissionRow(
                "Input Monitoring", "Needed only to record a command by watching what you do. Not used yet.",
                state: CGPreflightListenEventAccess() ? .allowed : .notNeeded, anchor: nil
            ) { openPane("Privacy_ListenEvent") }
            permissionRow(
                "Automation", "macOS asks the first time one of your commands controls another app with AppleScript.",
                state: .onDemand, anchor: nil
            ) { openPane("Privacy_Automation") }
        }
    }

    private enum PermissionState { case allowed, needed, notNeeded, onDemand }

    private func permissionRow(
        _ title: String, _ detail: String, state: PermissionState, anchor: String?, action: @escaping () -> Void
    ) -> some View {
        let row = SettingsRow(title: title, detail: detail) {
            HStack(spacing: 8) {
                switch state {
                case .allowed:
                    Badge(text: "Allowed", tone: .mint)
                case .needed:
                    Badge(text: "Needed", tone: .warning)
                    Button("Allow", action: action).buttonStyle(SecondaryButtonStyle())
                case .notNeeded:
                    Badge(text: "Not needed yet")
                    Button("Open", action: action).buttonStyle(SecondaryButtonStyle())
                case .onDemand:
                    Badge(text: "Asked when needed")
                    Button("Open", action: action).buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        return Group {
            if let anchor { row.settingsAnchor(anchor) } else { row }
        }
    }

    private func openPane(_ name: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(name)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: What it keeps

    private struct Kept: Identifiable {
        let id: String
        let title: String
        let detail: String
        let urls: [URL]
        let kind: DataKind?
    }

    private var items: [Kept] {
        let engine = controller.usage.prediction
        return [
            Kept(
                id: "settings", title: "Settings", detail: "Your choices on these pages.",
                urls: [settings.store.url, settings.store.url.deletingLastPathComponent().appendingPathComponent("history")],
                kind: nil),
            Kept(
                id: "commands", title: "Your commands", detail: "Commands and sequences, and the last versions of each.",
                urls: [controller.userCommands.directory], kind: nil),
            Kept(id: DataKind.ranking.id, title: DataKind.ranking.title, detail: DataKind.ranking.detail, urls: [controller.usage.store.url], kind: .ranking),
            Kept(id: DataKind.habits.id, title: DataKind.habits.title, detail: DataKind.habits.detail, urls: [engine.log.url], kind: .habits),
            Kept(
                id: DataKind.recents.id, title: DataKind.recents.title,
                detail: "\(controller.usage.recents.count) in the menu bar.", urls: [], kind: .recents),
            Kept(id: DataKind.outside.id, title: DataKind.outside.title, detail: DataKind.outside.detail, urls: [controller.externalLog.url], kind: .outside),
            Kept(
                id: DataKind.folders.id, title: DataKind.folders.title, detail: DataKind.folders.detail,
                urls: [controller.destinationToggles.url.deletingLastPathComponent().appendingPathComponent("send-folders.json")],
                kind: .folders),
        ]
    }

    private var keeps: some View {
        SettingsSection(
            title: "What Apropos keeps",
            footer: "All of it is on this Mac, in your Library. None of it holds what you type, select or copy."
        ) {
            ForEach(items) { item in
                let footprint = DataFootprint.of(item.urls)
                SettingsRow(title: item.title, detail: item.detail + sizeText(footprint)) {
                    HStack(spacing: 8) {
                        if let first = item.urls.first, footprint.exists {
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if let kind = item.kind {
                            Button("Forget") { forgetting = kind }
                                .buttonStyle(SecondaryButtonStyle(destructive: true))
                        }
                    }
                }
                .settingsAnchor(item.kind == .ranking ? "ranking" : item.kind == .recents ? "history" : item.id)
            }
        }
    }

    private func sizeText(_ footprint: DataFootprint) -> String {
        guard footprint.exists else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(footprint.bytes), countStyle: .file)
        let when = footprint.modified.map { ", changed " + $0.formatted(.relative(presentation: .named)) } ?? ""
        return " " + size + when + "."
    }

    private func forget(_ kind: DataKind) {
        switch kind {
        case .ranking: controller.usage.resetLearnedRanking()
        case .habits: controller.usage.prediction.reset()
        case .recents: controller.usage.clearHistory()
        case .outside: controller.externalLog.clear()
        case .folders: controller.send.savedFolders.forEach { controller.send.forgetFolder($0) }
        }
        tick += 1
    }

    private func exportAll() {
        controller.usage.flush()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose where to put the folder of Apropos data."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let folder = chosen.appendingPathComponent("Apropos data", isDirectory: true)
        let urls = items.flatMap(\.urls)
        _ = try? DataExport.copy(urls, into: folder)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    // MARK: Hidden commands

    /// Brings back commands hidden from the palette, for the app that was in front when Settings opened.
    @ViewBuilder
    private var hiddenCommands: some View {
        let app = controller.tracker.app
        let hidden = app?.bundleID.map { controller.usage.hiddenIDs(forBundleID: $0) } ?? []
        SettingsRow(
            title: "Hidden commands",
            detail: hidden.isEmpty
                ? "Nothing is hidden in \(app?.name ?? "the last app you used")."
                : "\(hidden.count) hidden in \(app?.name ?? "this app")."
        ) {
            if !hidden.isEmpty {
                Button("Show again") { hidden.forEach { controller.usage.unhide($0) } }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .settingsAnchor("hidden")
    }
}

/// The promise, and what it covers.
private struct PrivacyIntro: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("Everything stays on this Mac")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.text)
            Text(
                "Apropos has no account and no server. It reads the app in front only when you open the panel, keeps a few small files in your Library, and never records what you type, select or copy."
            )
            .font(.system(size: 12.5))
            .lineSpacing(2)
            .foregroundStyle(Brand.text2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
    }
}
