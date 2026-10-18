import AppKit
import Apropos
import Observation
import ServiceManagement

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

extension InterfaceSize {
    /// The value the settings file stores.
    var stored: String { self == .standard ? "default" : rawValue }

    init(stored: String) {
        self = InterfaceSize.allCases.first { $0.stored == stored } ?? .standard
    }
}

extension Notification.Name {
    static let aproposSettingsChanged = Notification.Name("com.zawalid.apropos.settings.changed")
}

/// The settings every part of the app reads and writes, backed by `SettingsStore` (one JSON file). The store is the
/// source of truth; the typed properties below are views of it, so changes reach the UI and the rest of the app at once.
@MainActor
@Observable
final class SettingsModel {
    let store: SettingsStore
    /// False for previews: the model then never touches the app's appearance or the login item.
    private let appliesSystemState: Bool

    init(store: SettingsStore = SettingsStore(), appliesSystemState: Bool = true) {
        self.store = store
        self.appliesSystemState = appliesSystemState
        guard appliesSystemState else { return }
        migrateLegacyHotKey()
        applyAppearance()
        syncLoginItem()
    }

    // MARK: Typed access

    var showInMenuBar: Bool {
        get { store.bool(.showInMenuBar) }
        set { write(.bool(newValue), .showInMenuBar) }
    }

    var closeOnFocusLoss: Bool {
        get { store.bool(.closeOnFocusLoss) }
        set { write(.bool(newValue), .closeOnFocusLoss) }
    }

    var resetQuerySeconds: Int {
        get { store.number(.resetQueryAfterSeconds) }
        set { write(.number(newValue), .resetQueryAfterSeconds) }
    }

    var showAlternates: Bool {
        get { store.bool(.showAlternateCommands) }
        set { write(.bool(newValue), .showAlternateCommands) }
    }

    var hotKey: HotKeyCombo {
        get { store.hotkey(.openHotKey) }
        set { write(.hotkey(newValue), .openHotKey) }
    }

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: store.string(.theme)) ?? .system }
        set {
            write(.string(newValue.rawValue), .theme)
            applyAppearance()
        }
    }

    var interfaceSize: InterfaceSize {
        get { InterfaceSize(stored: store.string(.interfaceSize)) }
        set { write(.string(newValue.stored), .interfaceSize) }
    }

    var rowIcons: RowIconStyle {
        get { RowIconStyle(rawValue: store.string(.rowIcons)) ?? .glyph }
        set { write(.string(newValue.rawValue), .rowIcons) }
    }

    var reduceMotion: Bool {
        get { store.bool(.reduceMotion) }
        set { write(.bool(newValue), .reduceMotion) }
    }

    var contextSensing: Bool {
        get { store.bool(.contextSensing) }
        set { write(.bool(newValue), .contextSensing) }
    }

    var checkForUpdates: Bool {
        get { store.bool(.checkForUpdates) }
        set { write(.bool(newValue), .checkForUpdates) }
    }

    var predictNextCommand: Bool {
        get { store.bool(.predictNextCommand) }
        set { write(.bool(newValue), .predictNextCommand) }
    }

    var showPredictionReasons: Bool {
        get { store.bool(.showPredictionReasons) }
        set { write(.bool(newValue), .showPredictionReasons) }
    }

    var ignoreList: [String] {
        get { store.stringList(.contextIgnoreList) }
        set { write(.stringList(newValue), .contextIgnoreList) }
    }

    var metrics: InterfaceMetrics { .metrics(for: interfaceSize) }

    var launchAtLogin: Bool { store.bool(.openAtLogin) }

    func setLaunchAtLogin(_ enabled: Bool) {
        write(.bool(enabled), .openAtLogin)
        if appliesSystemState { syncLoginItem() }
    }

    // MARK: Context

    func isSensingEnabled(for bundleID: String) -> Bool {
        !store.stringList(.contextDisabledApps).contains(bundleID)
    }

    func setSensing(_ enabled: Bool, for bundleID: String) {
        var list = store.stringList(.contextDisabledApps).filter { $0 != bundleID }
        if !enabled { list.append(bundleID) }
        write(.stringList(list), .contextDisabledApps)
    }

    var contextDisabledApps: [String] { store.stringList(.contextDisabledApps) }

    func isChipShown(_ kind: ContextKind) -> Bool { store.stringList(.contextChips).contains(kind.rawValue) }

    func setChip(_ kind: ContextKind, shown: Bool) {
        var chosen = Set(store.stringList(.contextChips))
        if shown { chosen.insert(kind.rawValue) } else { chosen.remove(kind.rawValue) }
        write(.stringList(Array(chosen)), .contextChips)
    }

    var visibleKinds: [ContextKind] { store.visibleContextKinds() }
    var contextPrivacy: ContextPrivacy { store.contextPrivacy() }

    // MARK: Defaults

    /// True when the setting differs from its default, so its row can offer a reset.
    func isModified(_ id: SettingID) -> Bool { !store.isDefault(id) }

    func resetSetting(_ id: SettingID) {
        store.reset(id)
        if id == .theme { applyAppearance() }
        NotificationCenter.default.post(name: .aproposSettingsChanged, object: nil)
    }

    // MARK: Files

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "apropos-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.exportSettings(to: url) } catch { report("Could not export settings", error) }
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try store.importSettings(from: url)
            applyAppearance()
            NotificationCenter.default.post(name: .aproposSettingsChanged, object: nil)
        } catch {
            report("Could not import settings", error)
        }
    }

    func checkForUpdatesNow() {
        let alert = NSAlert()
        alert.messageText = "Updates are not set up yet"
        alert.informativeText = "Apropos will check for updates once the updater ships."
        alert.runModal()
    }

    func flush() { store.flush() }

    // MARK: Internals

    private func write(_ value: SettingValue, _ id: SettingID) {
        guard store.set(value, for: id) else { return }
        NotificationCenter.default.post(name: .aproposSettingsChanged, object: nil)
    }

    private func report(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = String(describing: error)
        alert.runModal()
    }

    /// Settings made before the settings file existed lived in UserDefaults; carry the hotkey over once.
    private func migrateLegacyHotKey() {
        let legacy = HotKeyStore().load()
        if store.isDefault(.openHotKey), legacy != .default { _ = store.set(.hotkey(legacy), for: .openHotKey) }
    }

    private func syncLoginItem() {
        let wanted = store.bool(.openAtLogin)
        let enabled = SMAppService.mainApp.status == .enabled
        guard wanted != enabled else { return }
        do {
            if wanted { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            AproposLog.app.error("login item failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applyAppearance() {
        guard appliesSystemState else { return }
        #if DEBUG
            if AgentMode.isOn, ProcessInfo.processInfo.environment["APROPOS_APPEARANCE"] != nil { return }
        #endif
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        }
    }
}
