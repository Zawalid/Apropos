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

    func application(_ application: NSApplication, open urls: [URL]) {
        controller.handleExternal(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.flush()
    }
}
