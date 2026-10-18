import AppKit
import Cue
import SwiftUI

/// The name of an installed app, or the bundle identifier itself when it is not installed here.
func appDisplayName(_ bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    return bundleID
}

/// The registry's definition of a setting, so titles and details are written once.
private func definition(_ id: SettingID) -> SettingDefinition {
    SettingsRegistry.definition(for: id)
        ?? SettingDefinition(id: id, title: id.rawValue, page: .general, type: .bool, defaultValue: .bool(false))
}

private func toggle(_ id: SettingID, _ binding: Binding<Bool>) -> ToggleRow {
    let def = definition(id)
    return ToggleRow(title: def.title, detail: def.detail.isEmpty ? nil : def.detail, isOn: binding)
}

struct GeneralPage: View {
    let controller: AppController
    let settings: SettingsModel

    private static let presets: [(seconds: Int, title: String)] = [
        (0, "Immediately"), (15, "After 15 seconds"), (60, "After 1 minute"), (300, "After 5 minutes"),
        (3600, "After 1 hour"),
    ]

    var body: some View {
        @Bindable var settings = settings
        PageHeader(title: "General", subtitle: "How Cue starts and when the panel opens and closes.")
        SettingsCard {
            toggle(
                .openAtLogin,
                Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            SettingsDivider()
            toggle(.showInMenuBar, $settings.showInMenuBar)
        }
        SettingsCard(
            title: "Panel",
            footer: controller.isHotKeyRegistered
                ? nil : "macOS did not accept this shortcut. Another app may be using it. Choose a different one."
        ) {
            SettingsRow(
                title: definition(.openHotKey).title,
                detail: "Cue runs alongside your launcher. Pick a shortcut it does not use."
            ) {
                ShortcutRecorder(
                    combo: controller.combo, onRecordingChange: { controller.setRecording($0) },
                    onChange: { controller.setCombo($0) })
            }
            SettingsDivider()
            toggle(.closeOnFocusLoss, $settings.closeOnFocusLoss)
            SettingsDivider()
            SettingsRow(
                title: definition(.resetQueryAfterSeconds).title,
                detail: "Keep what you typed if you reopen the panel within this time."
            ) {
                Picker("Reset search after", selection: $settings.resetQuerySeconds) {
                    ForEach(options, id: \.seconds) { Text($0.title).tag($0.seconds) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            SettingsDivider()
            toggle(.showAlternateCommands, $settings.showAlternates)
        }
    }

    /// The presets, plus the stored value when someone edited the file to something else.
    private var options: [(seconds: Int, title: String)] {
        let current = settings.resetQuerySeconds
        if Self.presets.contains(where: { $0.seconds == current }) { return Self.presets }
        return (Self.presets + [(current, "After \(current) seconds")]).sorted { $0.seconds < $1.seconds }
    }
}

struct AppearancePage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        PageHeader(title: "Appearance", subtitle: "Theme and how dense the command list is.")
        SettingsCard {
            SettingsRow(title: definition(.theme).title) {
                CueSegmented(options: AppearanceMode.allCases, title: \.title, selection: $settings.appearance)
            }
            SettingsDivider()
            SettingsRow(title: definition(.interfaceSize).title, detail: definition(.interfaceSize).detail) {
                CueSegmented(options: InterfaceSize.allCases, title: \.title, selection: $settings.interfaceSize)
            }
            SettingsDivider()
            SettingsRow(title: definition(.rowIcons).title) {
                CueSegmented(options: RowIconStyle.allCases, title: \.title, selection: $settings.rowIcons)
            }
            SettingsDivider()
            toggle(.reduceMotion, $settings.reduceMotion)
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
            if settings.rowIcons != .none {
                Image(systemName: settings.rowIcons == .glyph ? "plus" : "app.fill")
                    .font(.system(size: metrics.symbol, weight: .medium))
                    .foregroundStyle(Theme.tileInk)
                    .frame(width: metrics.tile, height: metrics.tile)
                    .background(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).fill(Theme.tile))
            }
            Text("New Session").font(.system(size: metrics.title, weight: .medium)).foregroundStyle(Theme.text)
            Spacer()
            KeyCap(text: "\u{2318}")
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
            toggle(.contextSensing, $settings.contextSensing)
        }
        SettingsCard(title: definition(.contextChips).title, footer: definition(.contextChips).detail) {
            ForEach(Array(SettingsRegistry.contextChipOptions.enumerated()), id: \.element.value) { index, option in
                if index > 0 { SettingsDivider() }
                if let kind = ContextKind(rawValue: option.value) {
                    ToggleRow(
                        title: option.title,
                        isOn: Binding(get: { settings.isChipShown(kind) }, set: { settings.setChip(kind, shown: $0) }))
                }
            }
        }
        .opacity(settings.contextSensing ? 1 : 0.5)
        .disabled(!settings.contextSensing)
        SettingsCard(
            title: "Apps", footer: "Turn an app off and Cue reads nothing from it beyond the menu."
        ) {
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
        .opacity(settings.contextSensing ? 1 : 0.5)
        .disabled(!settings.contextSensing)
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
            list.append(AppEntry(bundleID: id, name: appDisplayName(id), icon: nil))
        }
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Apps Cue never reads, password managers by default.
private struct IgnoreListCard: View {
    let settings: SettingsModel

    var body: some View {
        let def = definition(.contextIgnoreList)
        SettingsCard(title: def.title, footer: def.detail) {
            ForEach(Array(settings.ignoreList.enumerated()), id: \.element) { index, id in
                if index > 0 { SettingsDivider() }
                SettingsRow(title: Self.name(for: id), detail: Self.name(for: id) == id ? nil : id) {
                    Button("Remove") { settings.ignoreList.removeAll { $0 == id } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            if !settings.ignoreList.isEmpty { SettingsDivider() }
            SettingsRow(title: "Add an app", detail: "Choose from the apps that are open.") {
                Menu("Choose") {
                    ForEach(candidates, id: \.bundleID) { app in
                        Button(app.name) { settings.ignoreList.append(app.bundleID) }
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
            .filter { !settings.ignoreList.contains($0.0) && $0.0 != Bundle.main.bundleIdentifier }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private static func name(for bundleID: String) -> String { appDisplayName(bundleID) }
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
        IgnoreListCard(settings: settings)
        SettingsCard(title: "Learned data") {
            SettingsRow(title: "Learned ranking", detail: "Which commands you use most in each app.") {
                Button("Reset") { confirming = .ranking }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
            SettingsDivider()
            SettingsRow(title: "History", detail: "The recent commands in the menu bar menu.") {
                Button("Clear") { confirming = .history }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
            SettingsDivider()
            HiddenCommandsRow(controller: controller)
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
                if confirming == .ranking {
                    controller.usage.resetLearnedRanking()
                } else {
                    controller.usage.clearHistory()
                }
            }
        } message: {
            Text("This cannot be undone. Pins and hidden commands are kept.")
        }
    }
}

/// Brings back commands hidden from the palette, for the app that was in front when Settings opened.
private struct HiddenCommandsRow: View {
    let controller: AppController

    var body: some View {
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
    }
}

struct UpdatesPage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        PageHeader(title: "Updates")
        SettingsCard(footer: "Cue only contacts the update server when you ask it to or turn this on.") {
            toggle(.checkForUpdates, $settings.checkForUpdates)
            SettingsDivider()
            SettingsRow(title: "Check now") {
                Button("Check for Updates") { settings.checkForUpdatesNow() }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

struct AboutPage: View {
    var body: some View {
        PageHeader(title: "About")
        SettingsCard {
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
