import AppKit
import ApplicationServices
import Foundation

/// The real outside world: running apps, the Accessibility API and the system clock.
public struct LiveStepEnvironment: StepEnvironment {
    /// How long one Accessibility call waits for an app before giving up. Short, so a hung app cannot hold a run.
    public var messagingTimeout: Float

    public init(messagingTimeout: Float = 0.5) { self.messagingTimeout = messagingTimeout }

    public func isTrusted() -> Bool { AXIsProcessTrusted() }

    public func application(bundleID: String, preferring pid: pid_t?) -> StepApplication? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { !$0.isTerminated }
        guard let chosen = running.first(where: { $0.processIdentifier == pid }) ?? running.first else { return nil }
        let root = LiveAXNode.application(pid: chosen.processIdentifier, timeout: messagingTimeout)
        return StepApplication(pid: chosen.processIdentifier, bundleID: bundleID, root: root)
    }

    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    public func press(_ element: any AXNode) -> StepPressResult {
        guard let live = element as? LiveAXNode else { return .staleElement }
        switch AXUIElementPerformAction(live.element, kAXPressAction as CFString) {
        case .success: return .delivered
        case .cannotComplete: return .timedOut
        case .invalidUIElement: return .staleElement
        case .apiDisabled: return .permissionLost
        case let other: return .failed(code: other.rawValue)
        }
    }

    public func activate(_ application: StepApplication) async -> Bool {
        await MainActor.run {
            NSRunningApplication(processIdentifier: application.pid)?.activate() ?? false
        }
    }

    public func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
