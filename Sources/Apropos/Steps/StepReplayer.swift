import Foundation

/// Apps the engine has already driven in this run of Apropos. The first step in an app that has not been driven yet is
/// given extra time to be ready: the spike saw identical steps time out on a cold start and succeed a moment later.
public final class WarmApps: @unchecked Sendable {
    public static let shared = WarmApps()

    private let lock = NSLock()
    private var pids = Set<pid_t>()

    public init() {}

    func isWarm(_ pid: pid_t) -> Bool { lock.withLock { pids.contains(pid) } }
    func markWarm(_ pid: pid_t) { lock.withLock { _ = pids.insert(pid) } }
}

/// What happened at one step.
public struct StepReport: Equatable, Sendable {
    /// Counted from 1.
    public let step: Int
    public let stepID: String
    /// The kind of locator that found the element.
    public let matchedKind: LocatorKind?
    /// A weaker locator than the step's strongest one was needed.
    public let isDegraded: Bool
    /// Presses repeated after a transient failure.
    public let retries: Int
    public let milliseconds: Int
}

public struct StepRunReport: Equatable, Sendable {
    public let steps: [StepReport]
    /// Nil when every step was done.
    public let failure: StepFailure?
    public let milliseconds: Int

    public var succeeded: Bool { failure == nil }
}

/// Runs steps with Accessibility actions. It never moves the pointer and never brings an app to the front unless a
/// step asks for that. It stops at the first step that fails: skipping a step would turn a mispress into a different
/// command.
///
/// Nothing here runs on the main actor: waiting is `Task.sleep`, and the Accessibility calls block only the task that
/// makes them. Cancel the task to cancel the run; no step is started after that, and a cancelled wait ends at once.
public struct StepReplayer: Sendable {
    public struct Configuration: Sendable {
        /// The whole run, from the first step to the last.
        public var totalTimeout: TimeInterval = 60
        /// Added to the readiness wait of the first step in an app that has not been driven yet.
        public var coldStartExtra: TimeInterval = 3
        public var pollInitial: TimeInterval = 0.05
        public var pollMax: TimeInterval = 0.4
        public var pollGrowth: Double = 1.6
        /// Extra attempts at a press after a transient failure.
        public var pressRetries = 2
        public var retryDelay: TimeInterval = 0.15

        public init() {}
    }

    public var configuration: Configuration
    public let environment: any StepEnvironment
    /// Read at the start of every run, so a change of the privacy list applies to the next run.
    public let privacy: @Sendable () -> ContextPrivacy
    public let warm: WarmApps
    public let log: StepLog

    public init(
        environment: any StepEnvironment, configuration: Configuration = Configuration(),
        privacy: @escaping @Sendable () -> ContextPrivacy = { ContextPrivacy() }, warm: WarmApps = .shared,
        log: StepLog = .standard
    ) {
        self.environment = environment
        self.configuration = configuration
        self.privacy = privacy
        self.warm = warm
        self.log = log
    }

    /// - Parameters:
    ///   - actionID: Only for the log line.
    ///   - target: The app that was in front when the command was started. Its process is used for steps in that app.
    ///   - timeout: Replaces `Configuration.totalTimeout` when given: the action's own timeout.
    public func run(
        _ backend: UIStepsBackend, actionID: String, target: TargetApp?, timeout: TimeInterval? = nil
    ) async -> StepRunReport {
        let started = environment.now()
        let total = timeout ?? configuration.totalTimeout
        let deadline = started + total
        log.started(actionID, steps: backend.steps.count)

        func finish(_ reports: [StepReport], _ failure: StepFailure?) -> StepRunReport {
            let milliseconds = Self.milliseconds(environment.now() - started)
            if let failure {
                log.failed(actionID, failure)
            } else {
                log.completed(actionID, milliseconds: milliseconds)
            }
            return StepRunReport(steps: reports, failure: failure, milliseconds: milliseconds)
        }

        if let issue = UIStepsValidator.issues(in: backend, privacy: privacy()).first {
            return finish([], StepFailure(step: issue.step ?? 1, reason: .notAllowed))
        }
        guard environment.isTrusted() else {
            return finish([], StepFailure(step: 1, reason: .permissionMissing))
        }

        var reports: [StepReport] = []
        for (offset, step) in backend.steps.enumerated() {
            let number = offset + 1
            let stepStarted = environment.now()
            switch await perform(step, number: number, target: target, deadline: deadline) {
            case .success(let outcome):
                let report = StepReport(
                    step: number, stepID: step.id, matchedKind: outcome.kind, isDegraded: outcome.degraded,
                    retries: outcome.retries, milliseconds: Self.milliseconds(environment.now() - stepStarted))
                reports.append(report)
                log.matched(
                    actionID, step: number, kind: outcome.kind, degraded: outcome.degraded,
                    milliseconds: report.milliseconds, retries: outcome.retries)
            case .failure(let failure):
                return finish(reports, failure)
            }
        }
        return finish(reports, nil)
    }

    // MARK: One step

    private struct Outcome {
        let kind: LocatorKind
        let degraded: Bool
        let retries: Int
    }

    private func perform(
        _ step: UIStep, number: Int, target: TargetApp?, deadline: TimeInterval
    ) async -> Result<Outcome, StepFailure> {
        func fail(_ reason: StepFailureReason) -> Result<Outcome, StepFailure> {
            .failure(StepFailure(step: number, reason: reason))
        }
        if Task.isCancelled { return fail(.cancelled) }
        let preferred = target?.bundleID == step.app ? target?.pid : nil
        guard let application = environment.application(bundleID: step.app, preferring: preferred) else {
            return fail(.appNotRunning)
        }
        if step.activates {
            _ = await environment.activate(application)
        }

        let cold = !warm.isWarm(application.pid)
        let readyBy = min(
            environment.now() + step.waitTimeout + (cold ? configuration.coldStartExtra : 0), deadline)
        var retries = 0
        var delay = configuration.pollInitial

        while true {
            if Task.isCancelled { return fail(.cancelled) }
            let ready = resolveReady(step, preferredPID: application.pid, until: readyBy, hardDeadline: deadline)
            switch ready {
            case .failure(let reason):
                return fail(reason)
            case .waiting(let reason):
                if environment.now() >= readyBy {
                    return fail(environment.now() >= deadline ? .timedOut : reason)
                }
                do {
                    try await environment.sleep(min(delay, max(readyBy - environment.now(), 0.01)))
                } catch {
                    return fail(.cancelled)
                }
                delay = min(delay * configuration.pollGrowth, configuration.pollMax)
            case .ready(let resolution, let live):
                guard let element = resolution.element, let kind = resolution.matchedKind else {
                    return fail(.notFound)
                }
                if Task.isCancelled { return fail(.cancelled) }
                switch environment.press(element) {
                case .delivered, .timedOut:
                    // A menu item that opens a sheet keeps the app busy past the messaging timeout although the
                    // action was delivered: both count as done.
                    break
                case .permissionLost:
                    return fail(.permissionMissing)
                case .staleElement:
                    // The element keeps vanishing between finding it and pressing it.
                    if retries >= configuration.pressRetries { return fail(.notFound) }
                    retries += 1
                    if await !pause(configuration.retryDelay) { return fail(.cancelled) }
                    continue
                case .failed(let code):
                    if retries >= configuration.pressRetries { return fail(.actionFailed(code: code)) }
                    retries += 1
                    if await !pause(configuration.retryDelay) { return fail(.cancelled) }
                    continue
                }
                if let expectation = step.expect {
                    if let reason = await check(expectation, in: live, deadline: deadline) { return fail(reason) }
                }
                warm.markWarm(application.pid)
                return .success(Outcome(kind: kind, degraded: resolution.isDegraded, retries: retries))
            }
        }
    }

    private enum Readiness {
        case ready(StepResolution, StepApplication)
        /// Not yet; look again until the wait ends.
        case waiting(StepFailureReason)
        case failure(StepFailureReason)
    }

    private func resolveReady(
        _ step: UIStep, preferredPID: pid_t, until readyBy: TimeInterval, hardDeadline: TimeInterval
    ) -> Readiness {
        guard let application = environment.application(bundleID: step.app, preferring: preferredPID) else {
            return .failure(.appNotRunning)
        }
        let limit = min(readyBy, hardDeadline)
        let environment = environment
        let resolver = StepResolver(budget: ResolveBudget(isExpired: { environment.now() > limit }))
        let resolution = resolver.resolve(step, in: application.root)
        if let failure = resolution.failure {
            switch failure {
            case .ambiguous, .secureField: return .failure(StepFailureReason(failure))
            case .notFound, .noMenuBar, .budgetExceeded: return .waiting(StepFailureReason(failure))
            }
        }
        guard resolution.element != nil else { return .waiting(.notFound) }
        // Found but disabled: the app may enable it a moment later, for example after the previous step.
        if !resolution.isEnabled { return .waiting(.disabled) }
        return .ready(resolution, application)
    }

    private func pause(_ seconds: TimeInterval) async -> Bool {
        do {
            try await environment.sleep(seconds)
            return true
        } catch {
            return false
        }
    }

    /// Nil when the expectation holds in time, else why not.
    private func check(
        _ expectation: StepExpectation, in application: StepApplication, deadline: TimeInterval
    ) async -> StepFailureReason? {
        let limit = min(environment.now() + (expectation.timeout ?? StepWait.defaultTimeout), deadline)
        var delay = configuration.pollInitial
        let environment = environment
        let resolver = StepResolver(budget: ResolveBudget(isExpired: { environment.now() > limit }))
        while true {
            if Task.isCancelled { return .cancelled }
            let live = environment.application(bundleID: application.bundleID, preferring: application.pid)
            guard let live else { return .appNotRunning }
            let found = resolver.find(expectation.locator, inWindowsOf: live.root)
            if found.failure == .secureField { return .secureField }
            switch expectation.condition {
            case .appears where found.isMatch: return nil
            case .gone where !found.isMatch && found.failure != .budgetExceeded: return nil
            default: break
            }
            if environment.now() >= limit { return environment.now() >= deadline ? .timedOut : .expectationNotMet }
            if await !pause(min(delay, max(limit - environment.now(), 0.01))) { return .cancelled }
            delay = min(delay * configuration.pollGrowth, configuration.pollMax)
        }
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Int { max(Int((seconds * 1000).rounded()), 0) }
}
