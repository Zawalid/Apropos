import AppKit

/// Agent mode keeps automated checks (screenshots, scripted runs) away from the person's own session. Set
/// `APROPOS_AGENT=1` on a Debug build and the app runs without a status item, a global hotkey, the welcome window or
/// activation, its windows are fully transparent and ignore the mouse, and the debug remote control is only live here.
/// A normal run never listens to the remote control, so a script can no longer open the panel on the person's screen.
enum AgentMode {
    #if DEBUG
        static let isOn = ProcessInfo.processInfo.environment["APROPOS_AGENT"] == "1"
    #else
        static let isOn = false
    #endif

    /// Makes `window` invisible and untouchable while it still draws, so it can be snapshotted from its views.
    @MainActor
    static func conceal(_ window: NSWindow) {
        guard isOn else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }
}
