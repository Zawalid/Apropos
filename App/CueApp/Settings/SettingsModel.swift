import AppKit
import Cue
import Observation
import ServiceManagement

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

/// How long a typed query survives closing the panel.
enum ResetQueryDelay: String, CaseIterable, Codable, Identifiable {
    case immediately, fiveSeconds, fifteenSeconds, oneMinute, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .fiveSeconds: "After 5 seconds"
        case .fifteenSeconds: "After 15 seconds"
        case .oneMinute: "After 1 minute"
        case .never: "Never"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .immediately: 0
        case .fiveSeconds: 5
        case .fifteenSeconds: 15
        case .oneMinute: 60
        case .never: .infinity
        }
    }
}

extension Notification.Name {
    static let cueSettingsChanged = Notification.Name("com.zawalid.cue.settings.changed")
}

/// The adapter every settings view and consumer goes through. For now it keeps a local JSON blob in UserDefaults; when
/// `SettingsStore` lands in `Sources/Cue/Settings`, only this file changes.
@MainActor
@Observable
final class SettingsModel {
    struct Stored: Codable, Equatable {
        var showInMenuBar = true
        var closeOnFocusLoss = true
        var resetQuery = ResetQueryDelay.immediately
        var appearance = AppearanceMode.system
        var interfaceSize = InterfaceSize.standard
        var rowIcons = RowIconStyle.glyph
        var contextEnabled = true
        var hiddenChips: Set<String> = []
        var ignoredApps: [String] = []
        var checkForUpdates = false
    }

    private static let defaultsKey = "cueSettingsPlaceholder"

    var values: Stored { didSet { if values != oldValue { changed() } } }

    /// Apps where Cue senses nothing beyond the name. Shared with the context layer through `ContextPrivacy`.
    var contextDisabledApps: Set<String> {
        didSet { ContextPrivacy(disabledBundleIDs: contextDisabledApps).save() }
    }

    private(set) var launchAtLogin: Bool

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        {
            values = stored
        } else {
            values = Stored()
        }
        contextDisabledApps = ContextPrivacy.load().disabledBundleIDs
        launchAtLogin = SMAppService.mainApp.status == .enabled
        applyAppearance()
    }

    var metrics: InterfaceMetrics { .metrics(for: values.interfaceSize) }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            CueLog.app.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func isSensingEnabled(for bundleID: String) -> Bool { !contextDisabledApps.contains(bundleID) }

    func setSensing(_ enabled: Bool, for bundleID: String) {
        if enabled { contextDisabledApps.remove(bundleID) } else { contextDisabledApps.insert(bundleID) }
    }

    func isChipShown(_ kind: ContextKind) -> Bool { !values.hiddenChips.contains(kind.rawValue) }

    func setChip(_ kind: ContextKind, shown: Bool) {
        if shown { values.hiddenChips.remove(kind.rawValue) } else { values.hiddenChips.insert(kind.rawValue) }
    }

    func isIgnored(_ bundleID: String?) -> Bool {
        bundleID.map(values.ignoredApps.contains) ?? false
    }

    // MARK: Placeholders until the usage store and updater land

    /// Wired to the usage store when it exists.
    func resetLearnedRanking() {}

    /// Wired to the usage store when it exists.
    func clearHistory() {}

    func checkForUpdatesNow() {
        let alert = NSAlert()
        alert.messageText = "Updates are not set up yet"
        alert.informativeText = "Cue will check for updates once the updater ships."
        alert.runModal()
    }

    // MARK: Export and import

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "cue-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(values) { try? data.write(to: url) }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
            let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return }
        values = stored
    }

    // MARK: Persistence

    private func changed() {
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
        applyAppearance()
        NotificationCenter.default.post(name: .cueSettingsChanged, object: nil)
    }

    private func applyAppearance() {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CUE_APPEARANCE"] != nil { return }
        #endif
        switch values.appearance {
        case .system: NSApp?.appearance = nil
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        }
    }
}
