import AppKit
import Cue
import Observation
import SwiftUI

/// Wires the pieces together: permission, app tracking, menu loading, the palette panel and the global shortcut. It is
/// the only place that knows about all of them.
@MainActor
@Observable
final class AppController {
    let permission: AccessibilityPermission
    let tracker: FrontmostAppTracker
    let menus: AppMenuModel
    let palette: PaletteModel
    let settings: SettingsModel
    let context: ContextModel
    let usage: UsageController
    private(set) var combo: HotKeyCombo
    private(set) var isHotKeyRegistered = true

    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var panel: PanelController?
    @ObservationIgnored private var settingsController: SettingsWindowController?
    @ObservationIgnored private var statusItem: StatusItemController?
    @ObservationIgnored private var onboardingWindow: NSWindow?

    convenience init() {
        Self.runLegacyMigration()
        var settingsURL = SettingsStore.defaultURL
        var usageURL = UsageStore.defaultURL
        #if DEBUG
            // Snapshots and experiments keep their data out of the real files.
            if let dir = ProcessInfo.processInfo.environment["CUE_DATA_DIR"] {
                settingsURL = URL(fileURLWithPath: dir).appendingPathComponent("settings.json")
                usageURL = URL(fileURLWithPath: dir).appendingPathComponent("usage.json")
            }
        #endif
        self.init(
            settings: SettingsModel(store: SettingsStore(url: settingsURL)), usageStore: UsageStore(url: usageURL),
            permission: AccessibilityPermission(), tracker: FrontmostAppTracker(), defaults: .standard)
    }

    /// Brings data from the former name over before any store opens. Debug runs that redirect their data skip it, so
    /// experiments never read or write the real folders.
    private static func runLegacyMigration() {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CUE_DATA_DIR"] != nil || AgentMode.isOn { return }
        #endif
        guard let domain = Bundle.main.bundleIdentifier else { return }
        let outcome = LegacyMigration(
            supportDirectory: SettingsStore.supportDirectory, folderName: SettingsStore.folderName,
            defaults: .standard, domain: domain
        ).run()
        CueLog.app.info("\(outcome.summary, privacy: .public)")
    }

    /// The pieces are passed in so previews can build a controller over in-memory stores and a fixed permission.
    init(
        settings: SettingsModel, usageStore: UsageStore, permission: AccessibilityPermission,
        tracker: FrontmostAppTracker, defaults: UserDefaults
    ) {
        self.permission = permission
        self.tracker = tracker
        self.settings = settings
        let menus = AppMenuModel(tracker: tracker, permission: permission)
        menus.showAlternates = settings.showAlternates
        self.menus = menus
        let palette = PaletteModel(
            menus: menus, tracker: tracker, ranker: CommandRanker(signal: usageStore.rankingSignal()))
        self.palette = palette
        self.usage = UsageController(store: usageStore, palette: palette, defaults: defaults)
        self.combo = settings.hotKey
        self.context = ContextModel(settings: settings)
    }

    func start() {
        permission.startMonitoring()
        if !(AgentMode.isOn && ProcessInfo.processInfo.environment["CUE_FIXTURE_COMMANDS"] != nil) { tracker.start() }
        let panel = PanelController(
            model: palette, tracker: tracker, permission: permission, settings: settings, context: context,
            usage: usage, openSettings: { [weak self] in self?.showSettings() })
        if AgentMode.isOn {
            // Automated runs stay invisible: no dock icon, status item, hotkey or welcome window.
            NSApp.setActivationPolicy(.accessory)
        } else {
            statusItem = StatusItemController(controller: self)
        }
        self.panel = panel
        #if DEBUG
            if let name = ProcessInfo.processInfo.environment["CUE_FIXTURE_COMMANDS"] {
                let fixtures = DebugFixtures.commands(named: name)
                menus.seed(fixtures)
                if AgentMode.isOn { tracker.pin(DebugFixtures.targetApp(named: name)) }
                if ProcessInfo.processInfo.environment["CUE_FIXTURE_USAGE"] != nil {
                    DebugFixtures.seedUsage(usage, commands: fixtures)
                }
            }
            if AgentMode.isOn {
                DebugSnapshot.installRemoteControl(panel: panel, model: palette)
                DebugSnapshot.installSettingsControl(controller: self)
                if let name = ProcessInfo.processInfo.environment["CUE_APPEARANCE"] {
                    NSApp.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
                }
            }
        #endif
        if !AgentMode.isOn {
            let hotKey = GlobalHotKey { [weak panel] in panel?.toggle() }
            self.hotKey = hotKey
            isHotKeyRegistered = hotKey.register(combo)
            showWelcomeOnce()
        }
        NotificationCenter.default.addObserver(
            forName: .cueSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    /// Applies the settings that live outside the views: the hotkey and the alternate-command rows.
    private func settingsChanged() {
        if menus.showAlternates != settings.showAlternates { menus.showAlternates = settings.showAlternates }
        if settings.hotKey != combo {
            combo = settings.hotKey
            isHotKeyRegistered = hotKey?.register(combo) ?? false
        }
    }

    func flush() {
        settings.flush()
        usage.flush()
    }

    func togglePanel() { panel?.toggle() }

    func setCombo(_ new: HotKeyCombo) {
        combo = new
        settings.hotKey = new
        isHotKeyRegistered = hotKey?.register(new) ?? false
    }

    /// While the person is choosing a new shortcut, the current one must not fire.
    func setRecording(_ recording: Bool) {
        if recording {
            hotKey?.unregister()
        } else {
            isHotKeyRegistered = hotKey?.register(combo) ?? false
        }
    }

    func showSettings(page: SettingPage? = nil) {
        let controller = settingsController ?? SettingsWindowController(controller: self)
        settingsController = controller
        controller.show(page: page)
    }

    var settingsWindow: NSWindow? { settingsController?.currentWindow }

    /// The welcome window is for the first launch only. After that, missing access shows in the panel and the menu bar
    /// item instead of reopening a window on every start.
    private func showWelcomeOnce() {
        let key = "hasSeenWelcome"
        guard !permission.isTrusted, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showOnboarding()
    }

    func showOnboarding() {
        let content = PermissionView(permission: permission, style: .full)
            .frame(width: 520, height: 420)
        let window = onboardingWindow ?? makeWindow(title: "Welcome to Cue", content: content)
        onboardingWindow = window
        present(window)
    }

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        if !AgentMode.isOn { NSApp.activate() }
        window.makeKeyAndOrderFront(nil)
        AgentMode.conceal(window)
    }
}
