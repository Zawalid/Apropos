import AppKit

/// A plain AppKit entry point. The app has no SwiftUI scene on purpose: an empty `Settings` scene made macOS open a blank
/// "Apropos Settings" window on Command-comma next to the real one. The status item, the panel, the Settings window and
/// the welcome guide are all owned by `AppController`, and `MainMenu` gives the app the few menu items it needs.
@main
enum AproposMain {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install(
            openSettings: { [weak self] in self?.controller.showSettings() },
            openAbout: { [weak self] in self?.controller.showSettings(page: .about) })
        controller.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        controller.handleExternal(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.flush()
    }
}
