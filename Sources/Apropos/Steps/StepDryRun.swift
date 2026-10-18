import Foundation

/// What a dry resolve found for one step.
public struct StepDryResult: Equatable, Sendable {
    /// Counted from 1.
    public let step: Int
    public let stepID: String
    /// The kind of locator that matched, nil when nothing did.
    public let matchedKind: LocatorKind?
    /// True when a weaker locator than the step's strongest one matched.
    public let isDegraded: Bool
    public let isEnabled: Bool
    public let failure: StepFailureReason?
    public let attempts: [LocatorAttempt]
}

/// Whether a command still finds its way around.
public enum StepHealth: Equatable, Sendable {
    /// Every step matched with its strongest locator.
    case healthy
    /// Everything resolves, but some step needed a weaker locator: it will break next.
    case degraded
    /// Some step no longer resolves.
    case broken
    /// Could not be checked: no Accessibility access, or the app is not running.
    case unknown

    /// True when the person should look at the command.
    public var needsAttention: Bool { self == .degraded || self == .broken }
}

public struct StepDryRunReport: Equatable, Sendable {
    public let results: [StepDryResult]
    public let health: StepHealth
    /// Set when nothing could be checked at all.
    public let blocked: StepFailureReason?
}

/// Finds every step's element without performing anything. It takes only the read-only half of the environment, so it
/// cannot press, and it never waits: it looks once. Safe to run in the background.
///
/// Menu steps do not depend on one another, so each is resolved against the app as it is now. Steps that would act on
/// something an earlier step opens cannot be checked this way.
public struct StepDryRun: Sendable {
    public var perStepBudget: TimeInterval
    public var privacy: ContextPrivacy

    public init(perStepBudget: TimeInterval = 2, privacy: ContextPrivacy = ContextPrivacy()) {
        self.perStepBudget = perStepBudget
        self.privacy = privacy
    }

    public func run(_ backend: UIStepsBackend, environment: any StepObserving) -> StepDryRunReport {
        if !UIStepsValidator.issues(in: backend, privacy: privacy).isEmpty {
            return StepDryRunReport(
                results: backend.steps.indices.map { failedResult(backend.steps[$0], index: $0 + 1, .notAllowed) },
                health: .broken, blocked: nil)
        }
        guard environment.isTrusted() else {
            return StepDryRunReport(results: [], health: .unknown, blocked: .permissionMissing)
        }
        var results: [StepDryResult] = []
        var unknownApp = false
        for (offset, step) in backend.steps.enumerated() {
            guard let application = environment.application(bundleID: step.app, preferring: nil) else {
                unknownApp = true
                results.append(failedResult(step, index: offset + 1, .appNotRunning))
                continue
            }
            let deadline = environment.now() + perStepBudget
            let resolver = StepResolver(budget: ResolveBudget(isExpired: { environment.now() > deadline }))
            let resolution = resolver.resolve(step, in: application.root)
            results.append(
                StepDryResult(
                    step: offset + 1, stepID: step.id, matchedKind: resolution.matchedKind,
                    isDegraded: resolution.isDegraded, isEnabled: resolution.isEnabled,
                    failure: resolution.failure.map(StepFailureReason.init), attempts: resolution.attempts))
        }
        let health: StepHealth
        if results.contains(where: { $0.failure != nil && $0.failure != .appNotRunning }) {
            health = .broken
        } else if unknownApp {
            health = .unknown
        } else if results.contains(where: \.isDegraded) {
            health = .degraded
        } else {
            health = .healthy
        }
        return StepDryRunReport(results: results, health: health, blocked: nil)
    }

    private func failedResult(_ step: UIStep, index: Int, _ reason: StepFailureReason) -> StepDryResult {
        StepDryResult(
            step: index, stepID: step.id, matchedKind: nil, isDegraded: false, isEnabled: false, failure: reason,
            attempts: [])
    }
}
