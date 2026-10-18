import ApplicationServices
import Foundation

/// Builds a `ContextSnapshot` for the frontmost app. Call `snapshot(for:)` when the panel opens: it runs off the
/// main thread, every provider has a hard timeout, and a slow or failing provider yields a partial snapshot, never
/// an error. Nothing is logged except counts and timings; selection text and URLs never reach a log.
public struct ContextService: Sendable {
    public let registry: ContextProviderRegistry
    public var privacy: ContextPrivacy
    private let git: any GitBranchLookup
    private let isTrusted: @Sendable () -> Bool
    private let makeRoot: @Sendable (pid_t) -> (any AXNode)?
    private let gitTimeout: TimeInterval

    public init(
        registry: ContextProviderRegistry = ContextProviderRegistry(),
        privacy: ContextPrivacy = ContextPrivacy(),
        git: any GitBranchLookup = GitBranchReader(),
        gitTimeout: TimeInterval = 0.12,
        isTrusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        makeRoot: @escaping @Sendable (pid_t) -> (any AXNode)? = { LiveAXNode.application(pid: $0) }
    ) {
        self.registry = registry
        self.privacy = privacy
        self.git = git
        self.gitTimeout = gitTimeout
        self.isTrusted = isTrusted
        self.makeRoot = makeRoot
    }

    public func snapshot(for app: TargetApp) async -> ContextSnapshot {
        let started = Date()
        var snapshot = ContextSnapshot(
            appName: app.name, bundleID: app.bundleID, pid: app.pid, capturedAt: started)

        if privacy.isDisabled(app.bundleID) {
            snapshot.gaps = [.disabledForApp]
            return snapshot
        }
        guard isTrusted(), let root = makeRoot(app.pid) else {
            snapshot.gaps = [.notTrusted]
            return snapshot
        }
        let target = ContextTarget(appName: app.name, bundleID: app.bundleID, pid: app.pid, root: root)

        // The generic read and the app-specific read run side by side, so the slower one sets the wait.
        let generic = registry.fallback
        let specific = registry.specific(for: app.bundleID)
        async let genericFields = TimedWork.run(timeout: generic.timeout) { generic.read(target) }
        async let specificFields = TimedWork.run(timeout: specific?.timeout ?? 0) {
            specific?.read(target) ?? ContextFields()
        }
        let genericResult = await genericFields
        let specificResult = specific == nil ? ContextFields() : await specificFields
        if genericResult == nil || (specific != nil && specificResult == nil) { snapshot.gaps.append(.timedOut) }

        var fields = (specificResult ?? ContextFields()).merging(fallback: genericResult ?? ContextFields())
        if privacy.blocksSelection(app.bundleID) {
            fields.selectedText = nil
            fields.fullSelection = nil
        }
        fields.selectedText = ContextText.truncatedSelection(fields.selectedText)

        // Git and the selected files are read side by side; each has its own deadline.
        let gitPath = fields.folderPath ?? fields.documentPath
        let lookup = git
        let timeout = gitTimeout
        async let gitResult = TimedWork.run(timeout: timeout * 2 + 0.03) { () -> (String?, String?) in
            guard let gitPath else { return (nil, nil) }
            return (
                lookup.branch(forFolder: gitPath, timeout: timeout),
                lookup.repoRoot(forFolder: gitPath, timeout: timeout)
            )
        }
        let selectedCount = fields.selectedItemCount
        async let filesResult = TimedWork.run(timeout: specific?.filesTimeout ?? 0) {
            specific?.readSelectedFiles(target, selectedCount: selectedCount) ?? []
        }
        if let (branch, root) = await gitResult {
            fields.gitBranch = branch
            fields.repoRoot = root
        }
        if let files = await filesResult, !files.isEmpty { fields.selectedFilePaths = files }

        snapshot.fields = fields
        snapshot.values = ContextValues(fields: fields)
        snapshot.items = ContextItemBuilder.items(from: fields)
        snapshot.capturedAt = Date()
        let elapsed = Int(Date().timeIntervalSince(started) * 1000)
        AproposLog.app.debug("context: \(snapshot.items.count) items in \(elapsed) ms")
        return snapshot
    }
}
