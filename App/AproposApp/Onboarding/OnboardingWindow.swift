import AppKit
import SwiftUI

/// Owns the onboarding window: one small window, shown on the first launch and from the menu bar menu.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private var model: OnboardingModel?

    var currentWindow: NSWindow? { window }

    func show(model: OnboardingModel, reduceMotion: Bool) {
        self.model?.stopObserving()
        self.model = model
        let hosting = NSHostingView(rootView: OnboardingView(model: model, reduceMotionSetting: reduceMotion))
        let window = window ?? makeWindow()
        window.contentView = hosting
        self.window = window
        if !AgentMode.isOn { NSApp.activate() }
        window.makeKeyAndOrderFront(nil)
        AgentMode.conceal(window)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingView.size.width, height: OnboardingView.size.height),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Welcome to Apropos"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()
        return window
    }
}
