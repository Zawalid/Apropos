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

private func title(_ id: SettingID) -> String { SettingsRegistry.definition(for: id)?.title ?? id.rawValue }

private func detail(_ id: SettingID) -> String? {
    SettingsRegistry.definition(for: id).map(\.detail).flatMap { $0.isEmpty ? nil : $0 }
}

// MARK: General

struct GeneralPage: View {
    let controller: AppController
    let settings: SettingsModel

    private static let presets: [(value: Int, title: String)] = [
        (0, "Immediately"), (15, "After 15 seconds"), (60, "After 1 minute"), (300, "After 5 minutes"),
        (3600, "After 1 hour"),
    ]

    var body: some View {
        @Bindable var settings = settings
        SettingsSection {
            SettingToggleRow(
                id: .openAtLogin,
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            SettingToggleRow(id: .showInMenuBar, isOn: $settings.showInMenuBar)
            SettingsRow(
                title: title(.openHotKey), detail: "Cue runs alongside your launcher. Pick a shortcut it does not use."
            ) {
                ShortcutRecorder(
                    combo: controller.combo, onRecordingChange: { controller.setRecording($0) },
                    onChange: { controller.setCombo($0) })
            }
            .settingsAnchor(SettingID.openHotKey.rawValue)
        }
        if !controller.isHotKeyRegistered {
            Label(
                "macOS did not accept this shortcut. Another app may be using it.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.cautionText)
            .padding(.horizontal, 16)
        }
        SettingsSection(title: "Panel") {
            SettingToggleRow(id: .closeOnFocusLoss, isOn: $settings.closeOnFocusLoss)
            SettingsRow(
                title: title(.resetQueryAfterSeconds),
                detail: "Keep what you typed if you reopen the panel within this time."
            ) {
                ValueMenu(options: options, selection: $settings.resetQuerySeconds)
            }
            .settingsAnchor(SettingID.resetQueryAfterSeconds.rawValue)
            SettingToggleRow(id: .showAlternateCommands, isOn: $settings.showAlternates)
        }
    }

    /// The presets, plus the stored value when someone edited the file to something else.
    private var options: [(value: Int, title: String)] {
        let current = settings.resetQuerySeconds
        if Self.presets.contains(where: { $0.value == current }) { return Self.presets }
        return (Self.presets + [(current, "After \(current) seconds")]).sorted { $0.value < $1.value }
    }
}

// MARK: Appearance

struct AppearancePage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        SettingsSection {
            SettingsRow(title: title(.theme)) {
                ValueMenu(
                    options: AppearanceMode.allCases.map { ($0, $0.title) }, selection: $settings.appearance)
            }
            .settingsAnchor(SettingID.theme.rawValue)
            SettingsRow(title: title(.interfaceSize), detail: detail(.interfaceSize)) {
                SizePicker(selection: $settings.interfaceSize)
            }
            .settingsAnchor(SettingID.interfaceSize.rawValue)
            SettingsRow(title: title(.rowIcons), detail: detail(.rowIcons)) {
                ValueMenu(
                    options: RowIconStyle.allCases.map { ($0, $0.title) }, selection: $settings.rowIcons)
            }
            .settingsAnchor(SettingID.rowIcons.rawValue)
            SettingToggleRow(id: .reduceMotion, isOn: $settings.reduceMotion)
        }
    }
}

/// Three "Aa" choices of growing size.
private struct SizePicker: View {
    @Binding var selection: InterfaceSize

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InterfaceSize.allCases) { size in
                let selected = size == selection
                Button {
                    selection = size
                } label: {
                    Text("Aa")
                        .font(.system(size: size == .compact ? 11 : size == .standard ? 13 : 16, weight: .medium))
                        .foregroundStyle(selected ? Theme.text : Theme.text3)
                        .frame(width: 36, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(
                                selected ? Theme.highlight : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(size.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: Context

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
        SettingsSection(footer: "Everything Cue reads stays on this Mac.") {
            SettingToggleRow(id: .contextSensing, isOn: $settings.contextSensing)
        }
        SettingsSection(title: title(.contextChips), footer: detail(.contextChips)) {
            ForEach(SettingsRegistry.contextChipOptions, id: \.value) { option in
                if let kind = ContextKind(rawValue: option.value) {
                    SettingsRow(title: option.title) {
                        CueToggle(
                            title: option.title,
                            isOn: Binding(
                                get: { settings.isChipShown(kind) }, set: { settings.setChip(kind, shown: $0) }))
                    }
                }
            }
        }
        .settingsAnchor(SettingID.contextChips.rawValue)
        .opacity(settings.contextSensing ? 1 : 0.5)
        .disabled(!settings.contextSensing)
        SettingsSection(title: "Apps", footer: "Turn an app off and Cue reads nothing from it beyond the menu.") {
            if apps.isEmpty {
                SettingsRow(title: "No apps to list") { EmptyView() }
            }
            ForEach(apps) { app in
                SettingsRow(title: app.name, leading: AnyView(AppIconImage(icon: app.icon, size: 20))) {
                    CueToggle(
                        title: app.name,
                        isOn: Binding(
                            get: { settings.isSensingEnabled(for: app.bundleID) },
                            set: { settings.setSensing($0, for: app.bundleID) }))
                }
            }
        }
        .settingsAnchor(SettingID.contextDisabledApps.rawValue)
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

// MARK: Privacy and data

struct PrivacyPage: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var confirming: Confirmation?

    enum Confirmation: Identifiable {
        case ranking, history
        var id: Self { self }
    }

    var body: some View {
        SettingsSection(title: "Access") {
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
            .settingsAnchor("accessibility")
        }
        SettingsSection(title: title(.contextIgnoreList), footer: detail(.contextIgnoreList)) {
            ForEach(settings.ignoreList, id: \.self) { id in
                let name = appDisplayName(id)
                SettingsRow(title: name, detail: name == id ? nil : id) {
                    Button("Remove") { settings.ignoreList.removeAll { $0 == id } }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            SettingsRow(title: "Add an app", detail: "Choose from the apps that are open.") {
                Menu("Choose") {
                    ForEach(candidates, id: \.bundleID) { app in
                        Button(app.name) { settings.ignoreList.append(app.bundleID) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(SecondaryButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .settingsAnchor(SettingID.contextIgnoreList.rawValue)
        SettingsSection(title: "Learned data") {
            SettingsRow(title: "Reset learned ranking", detail: "Which commands you use most in each app.") {
                Button("Reset") { confirming = .ranking }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
            .settingsAnchor("ranking")
            SettingsRow(title: "Clear history", detail: "The recent commands in the menu bar menu.") {
                Button("Clear") { confirming = .history }.buttonStyle(SecondaryButtonStyle(destructive: true))
            }
            .settingsAnchor("history")
            hiddenCommands
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

    private var candidates: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .filter { !settings.ignoreList.contains($0.0) && $0.0 != Bundle.main.bundleIdentifier }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

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

// MARK: Updates and About

struct UpdatesPage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        SettingsSection(footer: "Cue only contacts the update server when you ask it to or turn this on.") {
            SettingToggleRow(id: .checkForUpdates, isOn: $settings.checkForUpdates)
            SettingsRow(title: "Check now", detail: "Version \(AboutPage.version)") {
                Button("Check for Updates") { settings.checkForUpdatesNow() }.buttonStyle(SecondaryButtonStyle())
            }
            .settingsAnchor("checknow")
        }
    }
}

struct AboutPage: View {
    let controller: AppController
    let settings: SettingsModel

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text("Cue").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
            Text("Version \(Self.version)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .settingsAnchor("version")
            Text("What you can do right now, in this app, with this selection.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        SettingsSection(title: "Diagnostics") {
            diagnostic(
                "Accessibility access", ok: controller.permission.isTrusted, okText: "Allowed", badText: "Not allowed")
            diagnostic("Context sensing", ok: settings.contextSensing, okText: "On", badText: "Off")
            diagnostic(
                "Settings file", ok: settings.store.lastSaveError == nil, okText: "Saved",
                badText: settings.store.lastSaveError ?? "Not saved")
        }
    }

    private func diagnostic(_ name: String, ok: Bool, okText: String, badText: String) -> some View {
        SettingsRow(
            title: name,
            leading: AnyView(
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(ok ? Theme.accentText : Theme.cautionText))
        ) {
            Text(ok ? okText : badText).font(.system(size: 12)).foregroundStyle(Theme.text2)
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
