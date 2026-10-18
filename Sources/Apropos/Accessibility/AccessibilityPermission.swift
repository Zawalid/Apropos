import AppKit
import ApplicationServices
import Observation

/// Whether Apropos may use the Accessibility API, kept live. macOS has no callback for this, so the model listens for the
/// system's distributed notification and also polls while access is missing, which makes the UI recover the moment
/// the person flips the switch in System Settings.
@MainActor
@Observable
public final class AccessibilityPermission {
    public private(set) var isTrusted: Bool

    private let probe: @Sendable () -> Bool
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")

    public init(probe: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.probe = probe
        self.isTrusted = probe()
    }

    /// Starts watching. Safe to call more than once.
    public func startMonitoring() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The flag flips shortly after the notification, so check now and again once it has settled.
            Task { @MainActor in
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(300))
                self?.refresh()
            }
        }
        updatePolling()
    }

    public func refresh() {
        let now = probe()
        guard now != isTrusted else { return }
        isTrusted = now
        AproposLog.accessibility.info("accessibility trusted: \(now)")
        updatePolling()
    }

    /// Asks macOS to show its own "would like to control this computer" prompt, which also adds Apropos to the list.
    public func requestPrompt() {
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    public func openSystemSettings() {
        guard let url = Self.settingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func updatePolling() {
        timer?.invalidate()
        timer = nil
        guard !isTrusted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
