import AppKit
import Cue
import SwiftUI

struct GeneralPage: View {
    let controller: AppController
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        PageHeader(title: "General", subtitle: "How Cue starts and when the panel opens and closes.")
        SettingsCard {
            ToggleRow(
                title: "Open at login",
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            SettingsDivider()
            ToggleRow(
                title: "Show in menu bar",
                detail: "Cue stays reachable from its hotkey if you hide the icon.",
                isOn: $settings.values.showInMenuBar)
        }
        SettingsCard(
            title: "Panel",
            footer: controller.isHotKeyRegistered
                ? nil : "macOS did not accept this shortcut. Another app may be using it. Choose a different one."
        ) {
            SettingsRow(
                title: "Open hotkey", detail: "Cue runs alongside your launcher. Pick a shortcut it does not use."
            ) {
                ShortcutRecorder(
                    combo: controller.combo, onRecordingChange: { controller.setRecording($0) },
                    onChange: { controller.setCombo($0) })
            }
            SettingsDivider()
            ToggleRow(
                title: "Close on focus loss", detail: "Hide the panel when you click another window.",
                isOn: $settings.values.closeOnFocusLoss)
            SettingsDivider()
            SettingsRow(title: "Reset query", detail: "Keep what you typed if you reopen the panel soon after.") {
                Picker("Reset query", selection: $settings.values.resetQuery) {
                    ForEach(ResetQueryDelay.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
        }
    }
}

struct AppearancePage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        PageHeader(title: "Appearance", subtitle: "Theme and how dense the command list is.")
        SettingsCard {
            SettingsRow(title: "Theme") {
                CueSegmented(
                    options: AppearanceMode.allCases, title: \.title, selection: $settings.values.appearance)
            }
            SettingsDivider()
            SettingsRow(title: "Interface size", detail: "Row height, icon tile and text size in the panel.") {
                CueSegmented(
                    options: InterfaceSize.allCases, title: \.title, selection: $settings.values.interfaceSize)
            }
            SettingsDivider()
            SettingsRow(title: "Row icons") {
                CueSegmented(options: RowIconStyle.allCases, title: \.title, selection: $settings.values.rowIcons)
            }
        }
        SettingsCard(title: "Preview") {
            PreviewRow(settings: settings)
        }
    }
}

/// A sample row that follows the chosen size and icon style.
private struct PreviewRow: View {
    let settings: SettingsModel

    var body: some View {
        let metrics = settings.metrics
        HStack(spacing: 12) {
            if settings.values.rowIcons != .none {
                Image(systemName: settings.values.rowIcons == .glyph ? "plus" : "app.fill")
                    .font(.system(size: metrics.symbol, weight: .medium))
                    .foregroundStyle(Theme.tileInk)
                    .frame(width: metrics.tile, height: metrics.tile)
                    .background(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).fill(Theme.tile))
            }
            Text("New Session").font(.system(size: metrics.title, weight: .medium)).foregroundStyle(Theme.text)
            Spacer()
            KeyCap(text: "⌘")
            KeyCap(text: "N")
        }
        .padding(.horizontal, 14)
        .frame(height: metrics.rowHeight + 12)
        .accessibilityElement(children: .combine)
    }
}

struct ContextPage: View {
    let settings: SettingsModel

    @State private var apps: [AppEntry] = []

    struct AppEntry: Identifiable {
        let bundleID: String
        let name: String
        let icon: NSImage?
        var id: String { bundleID }
    }

    var body: some View {
        @Bindable var settings = settings
        PageHeader(
            title: "Context",
            subtitle: "What Cue reads to build the chips under the search field. All of it stays on this Mac.")
        SettingsCard {
            ToggleRow(
                title: "Sense context", detail: "Off shows only the app chip.", isOn: $settings.values.contextEnabled)
        }
        SettingsCard(title: "Chips") {
            ForEach(Array(ContextKind.allCases.enumerated()), id: \.element) { index, kind in
                if index > 0 { SettingsDivider() }
                ToggleRow(
                    title: Self.title(for: kind),
                    isOn: Binding(get: { settings.isChipShown(kind) }, set: { settings.setChip(kind, shown: $0) }))
            }
        }
        .opacity(settings.values.contextEnabled ? 1 : 0.5)
        .disabled(!settings.values.contextEnabled)
        SettingsCard(title: "Apps", footer: "Turn an app off and Cue reads nothing from it beyond its name.") {
            if apps.isEmpty {
                SettingsRow(title: "No apps to list") { EmptyView() }
            }
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                if index > 0 { SettingsDivider() }
                SettingsRow(title: app.name, leading: AnyView(AppIconImage(icon: app.icon, size: 24))) {
                    CueToggle(
                        title: app.name,
                        isOn: Binding(
                            get: { settings.isSensingEnabled(for: app.bundleID) },
                            set: { settings.setSensing($0, for: app.bundleID) }))
                }
            }
        }
        .opacity(settings.values.contextEnabled ? 1 : 0.5)
        .disabled(!settings.values.contextEnabled)
        IgnoredAppsCard(settings: settings)
        Color.clear.frame(height: 0).onAppear { apps = loadApps() }
    }

    private func loadApps() -> [AppEntry] {
        var seen = Set<String>()
        var list: [AppEntry] = []
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        for app in running {
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { continue }
            list.append(AppEntry(bundleID: id, name: app.localizedName ?? id, icon: app.icon))
        }
        for id in settings.contextDisabledApps where seen.insert(id).inserted {
            list.append(AppEntry(bundleID: id, name: id, icon: nil))
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func title(for kind: ContextKind) -> String {
        switch kind {
        case .document: "Document"
        case .url: "Web address"
        case .folder: "Folder"
        case .branch: "Git branch"
        case .selection: "Selected text"
        case .selectionCount: "Selected items"
        }
    }
}

/// Apps where the panel never opens.
private struct IgnoredAppsCard: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        SettingsCard(title: "Ignored apps", footer: "The Cue hotkey does nothing while one of these is in front.") {
            ForEach(Array(settings.values.ignoredApps.enumerated()), id: \.element) { index, id in
                if index > 0 { SettingsDivider() }
                SettingsRow(title: Self.name(for: id), detail: id) {
                    Button("Remove") { settings.values.ignoredApps.removeAll { $0 == id } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            if !settings.values.ignoredApps.isEmpty { SettingsDivider() }
            SettingsRow(title: "Add an app", detail: "Choose from the apps that are open.") {
                Menu("Choose") {
                    ForEach(candidates, id: \.bundleID) { app in
                        Button(app.name) { settings.values.ignoredApps.append(app.bundleID) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    private var candidates: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .filter { !settings.values.ignoredApps.contains($0.0) && $0.0 != Bundle.main.bundleIdentifier }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private static func name(for bundleID: String) -> String {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName ?? bundleID
    }
}

struct AppIconImage: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "app").font(.system(size: size * 0.7)).foregroundStyle(Theme.text3).frame(
                width: size, height: size)
        }
    }
}

struct PrivacyPage: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var confirming: Confirmation?

    enum Confirmation: Identifiable {
        case ranking, history
        var id: Self { self }
    }

    var body: some View {
        PageHeader(
            title: "Privacy and data",
            subtitle: "Cue is local first. Nothing about your screen or selection leaves this Mac.")
        SettingsCard(title: "Access") {
            SettingsRow(title: "Accessibility", detail: "Lets Cue read and press menu items.") {
                if controller.permission.isTrusted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.accentText)
                } else {
                    Button("Allow in System Settings") {
                        controller.permission.requestPrompt()
                        controller.permission.openSystemSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        SettingsCard(title: "Learned data") {
            SettingsRow(title: "Learned ranking", detail: "Which commands you use most in each app.") {
                Button("Reset") { confirming = .ranking }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
            SettingsDivider()
            SettingsRow(title: "History", detail: "The list of recent commands.") {
                Button("Clear") { confirming = .history }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
        }
        SettingsCard(title: "Settings file") {
            SettingsRow(title: "Export settings", detail: "Save your settings as a JSON file.") {
                Button("Export") { settings.exportSettings() }.buttonStyle(SecondaryButtonStyle())
            }
            SettingsDivider()
            SettingsRow(title: "Import settings", detail: "Replace your settings with a saved file.") {
                Button("Import") { settings.importSettings() }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .confirmationDialog(
            confirming == .ranking ? "Reset learned ranking?" : "Clear history?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(confirming == .ranking ? "Reset" : "Clear", role: .destructive) {
                if confirming == .ranking { settings.resetLearnedRanking() } else { settings.clearHistory() }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct AboutPage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        PageHeader(title: "Updates and About")
        SettingsCard(
            title: "Updates", footer: "Cue only contacts the update server when you ask it to or turn this on."
        ) {
            ToggleRow(title: "Check for updates automatically", isOn: $settings.values.checkForUpdates)
            SettingsDivider()
            SettingsRow(title: "Check now") {
                Button("Check for Updates") { settings.checkForUpdatesNow() }.buttonStyle(SecondaryButtonStyle())
            }
        }
        SettingsCard(title: "About") {
            SettingsRow(title: "Cue") {
                Text("Version \(Self.version)").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
            }
            SettingsDivider()
            SettingsRow(
                title: "Context companion",
                detail: "Cue shows what you can do right now, in this app, with this selection."
            ) {
                EmptyView()
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
