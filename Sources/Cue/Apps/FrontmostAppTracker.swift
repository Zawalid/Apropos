import AppKit
import Observation

/// The app the person is working in.
public struct TargetApp: Identifiable, Equatable, Sendable {
    public let pid: pid_t
    public let bundleID: String?
    public let name: String

    public var id: pid_t { pid }
}

/// Follows the frontmost app. NSWorkspace says which app is in front; an AXObserver on that app says when its window
/// or document changes, which is when its menus can change. Cue's own windows never count as the target, so the
/// palette keeps showing the app the person came from.
@MainActor
@Observable
public final class FrontmostAppTracker {
    public private(set) var app: TargetApp?
    /// Bumped whenever the target's menus may have changed. Observers refresh when it moves.
    public private(set) var menuChangeCount = 0

    @ObservationIgnored private var changeObserver: AXChangeObserver?
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private let ownBundleID: String?
    @ObservationIgnored private var observedPID: pid_t?
    @ObservationIgnored private var debounce: Task<Void, Never>?

    public init(ownBundleID: String? = Bundle.main.bundleIdentifier) {
        self.ownBundleID = ownBundleID
    }

    public func start() {
        guard tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.activated(running) }
            })
        tokens.append(
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.terminated(running) }
            })
        activated(NSWorkspace.shared.frontmostApplication)
    }

    /// Re-attaches the AX observer, for when access was granted after the app became the target.
    public func reattach() {
        observedPID = nil
        if let pid = app?.pid { attachObserver(pid: pid) }
    }

    private func activated(_ running: NSRunningApplication?) {
        guard let running, running.activationPolicy != .prohibited else { return }
        if let own = ownBundleID, running.bundleIdentifier == own { return }
        let target = TargetApp(
            pid: running.processIdentifier, bundleID: running.bundleIdentifier,
            name: running.localizedName ?? running.bundleIdentifier ?? "App")
        guard target != app else { return }
        app = target
        attachObserver(pid: target.pid)
        menuChangeCount += 1
    }

    private func terminated(_ running: NSRunningApplication?) {
        guard let running, running.processIdentifier == app?.pid else { return }
        changeObserver?.stop()
        changeObserver = nil
        observedPID = nil
    }

    private func attachObserver(pid: pid_t) {
        guard observedPID != pid else { return }
        changeObserver?.stop()
        changeObserver = nil
        observedPID = pid
        guard AXIsProcessTrusted() else { return }
        changeObserver = AXChangeObserver(pid: pid) { [weak self] in self?.menusMayHaveChanged() }
    }

    private func menusMayHaveChanged() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.menuChangeCount += 1
        }
    }
}
