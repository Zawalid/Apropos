import AppKit
import SwiftUI

@main
struct AproposApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item is an NSStatusItem owned by the controller; SwiftUI needs a scene, and this one is empty.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        routeSettingsShortcut()
    }

    @objc private func openSettings() { controller.showSettings() }

    /// The empty Settings scene puts its own Settings item, with Command-comma, in the app menu. Point that item at the
    /// window the controller owns. SwiftUI rebuilds the menu, so this runs whenever the app becomes active.
    private func routeSettingsShortcut() {
        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        for item in appMenu.items where item.keyEquivalent == "," {
            item.target = self
            item.action = #selector(openSettings)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        controller.handleExternal(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.flush()
    }
}
