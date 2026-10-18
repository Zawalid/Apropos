import AppKit
import SwiftUI

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Cue", systemImage: "command.square") {
            MenuBarContent(controller: appDelegate.controller)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}

private struct MenuBarContent: View {
    let controller: AppController

    var body: some View {
        Button("Open Cue (\(controller.combo.display))") { controller.togglePanel() }
        if !controller.permission.isTrusted {
            Button("Allow Accessibility Access…") { controller.showOnboarding() }
        }
        Divider()
        Button("Settings…") { controller.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Cue") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
