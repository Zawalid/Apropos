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
    private(set) var combo: HotKeyCombo
    private(set) var isHotKeyRegistered = true

    @ObservationIgnored private let store = HotKeyStore()
    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var panel: PanelController?
    @ObservationIgnored private var settingsWindow: NSWindow?
    @ObservationIgnored private var onboardingWindow: NSWindow?

    init() {
        let menus = AppMenuModel(tracker: tracker, permission: permission)
        self.menus = menus
        self.palette = PaletteModel(menus: menus, tracker: tracker)
        self.combo = store.load()
    }

    func start() {
        permission.startMonitoring()
        tracker.start()
        let panel = PanelController(model: palette, tracker: tracker, permission: permission)
        self.panel = panel
        let hotKey = GlobalHotKey { [weak panel] in panel?.toggle() }
        self.hotKey = hotKey
        isHotKeyRegistered = hotKey.register(combo)
        if !permission.isTrusted { showOnboarding() }
    }

    func togglePanel() { panel?.toggle() }

    func setCombo(_ new: HotKeyCombo) {
        combo = new
        store.save(new)
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

    func showSettings() {
        let window = settingsWindow ?? makeWindow(title: "Cue Settings", content: SettingsView(controller: self))
        settingsWindow = window
        present(window)
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
