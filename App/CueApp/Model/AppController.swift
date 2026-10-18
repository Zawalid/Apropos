import AppKit
import Cue
import Observation
import SwiftUI

/// Wires the pieces together: permission, app tracking, menu loading, the palette panel and the global shortcut. It is
/// the only place that knows about all of them.
@MainActor
@Observable
final class AppController {
    let permission = AccessibilityPermission()
    let tracker = FrontmostAppTracker()
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

    init() {
        var settingsURL = SettingsStore.defaultURL
        var usageURL = UsageStore.defaultURL
        #if DEBUG
            // Snapshots and experiments keep their data out of the real files.
            if let dir = ProcessInfo.processInfo.environment["CUE_DATA_DIR"] {
                settingsURL = URL(fileURLWithPath: dir).appendingPathComponent("settings.json")
                usageURL = URL(fileURLWithPath: dir).appendingPathComponent("usage.json")
            }
        #endif
        let settings = SettingsModel(store: SettingsStore(url: settingsURL))
        self.settings = settings
        let menus = AppMenuModel(tracker: tracker, permission: permission)
        menus.showAlternates = settings.showAlternates
        self.menus = menus
        let usageStore = UsageStore(url: usageURL)
        let palette = PaletteModel(
            menus: menus, tracker: tracker, ranker: CommandRanker(signal: usageStore.rankingSignal()))
        self.palette = palette
        self.usage = UsageController(store: usageStore, palette: palette)
        self.combo = settings.hotKey
        self.context = ContextModel(settings: settings)
    }

    func start() {
        permission.startMonitoring()
        tracker.start()
        let panel = PanelController(
            model: palette, tracker: tracker, permission: permission, settings: settings, context: context,
            usage: usage, openSettings: { [weak self] in self?.showSettings() })
        statusItem = StatusItemController(controller: self)
        self.panel = panel
        #if DEBUG
            if let name = ProcessInfo.processInfo.environment["CUE_FIXTURE_COMMANDS"] {
                let fixtures = DebugFixtures.commands(named: name)
                menus.seed(fixtures)
                if ProcessInfo.processInfo.environment["CUE_FIXTURE_USAGE"] != nil {
                    DebugFixtures.seedUsage(usage, commands: fixtures)
                }
            }
            DebugSnapshot.installRemoteControl(panel: panel, model: palette)
            DebugSnapshot.installSettingsControl(controller: self)
            if let name = ProcessInfo.processInfo.environment["CUE_APPEARANCE"] {
                NSApp.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
            }
        #endif
        let hotKey = GlobalHotKey { [weak panel] in panel?.toggle() }
        self.hotKey = hotKey
        isHotKeyRegistered = hotKey.register(combo)
        if !permission.isTrusted { showOnboarding() }
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
