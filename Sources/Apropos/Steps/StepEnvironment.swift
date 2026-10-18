import Foundation

/// An app the steps can be resolved in.
public struct StepApplication: Sendable {
    public let pid: pid_t
    public let bundleID: String
    /// The application element.
    public let root: any AXNode

    public init(pid: pid_t, bundleID: String, root: any AXNode) {
        self.pid = pid
        self.bundleID = bundleID
        self.root = root
    }
}

/// The read-only half of the outside world. Resolving and dry runs need nothing more, so they cannot press anything.
public protocol StepObserving: Sendable {
    /// Whether Apropos may use the Accessibility API.
    func isTrusted() -> Bool
    /// The running app with this bundle identifier. `preferring` wins when several instances run.
    func application(bundleID: String, preferring pid: pid_t?) -> StepApplication?
    /// A monotonic clock, in seconds.
    func now() -> TimeInterval
}

/// How an Accessibility press ended.
public enum StepPressResult: Equatable, Sendable {
    case delivered
    /// The element is gone or stale; resolving again may find it.
    case staleElement
    /// The app did not answer in time. Not an error for a menu item: one that opens a sheet keeps the app busy.
    case timedOut
    /// The Accessibility grant is gone.
    case permissionLost
    case failed(code: Int32)
}

/// Everything a run does to the outside world, replaceable so tests need no app, no clock and no Accessibility.
public protocol StepEnvironment: StepObserving {
    func press(_ element: any AXNode) -> StepPressResult
    /// Brings the app to the front. Only called for a step that asks for it.
    func activate(_ application: StepApplication) async -> Bool
    func sleep(_ seconds: TimeInterval) async throws
}
