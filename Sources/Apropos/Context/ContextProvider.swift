import Foundation

/// What a provider is given: who the app is and, when Accessibility is available, its application element.
public struct ContextTarget: Sendable {
    public let appName: String
    public let bundleID: String?
    public let pid: pid_t
    public let root: (any AXNode)?

    public init(appName: String, bundleID: String?, pid: pid_t, root: (any AXNode)?) {
        self.appName = appName
        self.bundleID = bundleID
        self.pid = pid
        self.root = root
    }
}

/// Reads context for one kind of app. `read` is synchronous and may block on the app, so the service runs it off the
/// main thread with a hard timeout. A provider returns whatever it could read; it never throws.
public protocol ContextProvider: Sendable {
    /// Bundle ids this provider serves. Empty for the generic fallback.
    var bundleIDs: Set<String> { get }
    /// Longest the service waits for this provider.
    var timeout: TimeInterval { get }
    func read(_ target: ContextTarget) -> ContextFields
    /// Longest the service waits for `readSelectedFiles`.
    var filesTimeout: TimeInterval { get }
    /// Absolute paths of the files selected in the app, read only when `selectedCount` says there are some. Runs
    /// after `read`, in parallel with the git lookup, so a slow answer never delays the chips.
    func readSelectedFiles(_ target: ContextTarget, selectedCount: Int?) -> [String]
}

extension ContextProvider {
    public var filesTimeout: TimeInterval { 0 }
    public func readSelectedFiles(_ target: ContextTarget, selectedCount: Int?) -> [String] { [] }
}

/// Picks a provider by bundle id.
public struct ContextProviderRegistry: Sendable {
    public let fallback: any ContextProvider
    private let byBundleID: [String: any ContextProvider]

    public init(
        providers: [any ContextProvider] = ContextProviderRegistry.defaultProviders,
        fallback: any ContextProvider = GenericAccessibilityProvider()
    ) {
        self.fallback = fallback
        var map: [String: any ContextProvider] = [:]
        for provider in providers {
            for id in provider.bundleIDs { map[id] = provider }
        }
        byBundleID = map
    }

    public static var defaultProviders: [any ContextProvider] {
        [FinderProvider(), BrowserProvider(), XcodeProvider()]
    }

    /// The app-specific provider, or nil when only the generic one applies.
    public func specific(for bundleID: String?) -> (any ContextProvider)? {
        bundleID.flatMap { byBundleID[$0] }
    }
}
