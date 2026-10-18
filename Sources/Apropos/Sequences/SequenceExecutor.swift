import Foundation

/// What the action engine hands over to run a `sequence` backend.
public struct SequenceExecution: Sendable {
    public var actionID: ActionID
    public var values: ContextValues
    public var target: TargetApp?
    /// The engine only runs commands that passed their own confirmation; this says whether the person gave it.
    public var confirmed: Bool
    /// The command's timeout: the whole run must end inside it.
    public var timeout: TimeInterval
    /// Answers to the sequence's questions, by question id. Empty for runs with no one to ask (a shortcut key, a link).
    public var answers: [String: String]

    public init(
        actionID: ActionID, values: ContextValues, target: TargetApp?, confirmed: Bool, timeout: TimeInterval,
        answers: [String: String] = [:]
    ) {
        self.actionID = actionID
        self.values = values
        self.target = target
        self.confirmed = confirmed
        self.timeout = timeout
        self.answers = answers
    }
}

/// How the action engine runs a `sequence` backend. A value of closures, like `ActionServices` itself, so engine tests
/// can substitute a fake and never touch an app.
public struct SequenceExecutor: Sendable {
    public var run: @Sendable (SequenceBackend, SequenceExecution) async -> SequenceReport

    public init(run: @escaping @Sendable (SequenceBackend, SequenceExecution) async -> SequenceReport) {
        self.run = run
    }

    /// The default: no sequencer is connected, so a sequence command reports it cannot run.
    public static let unavailable = SequenceExecutor { _, _ in
        SequenceReport(outcome: .refused(.notConnected), results: [])
    }

    /// Runs sequences through the real engines.
    ///
    /// - Parameters:
    ///   - catalogue: The actions, commands and destinations in effect now. Asked at every run, so a pack that was
    ///     reloaded is seen.
    ///   - actions: The services the steps use. Its own `sequences` is replaced, so a sequence cannot start another.
    ///   - send: What destinations need.
    ///   - privacy: The privacy list at run time (menu steps check it again).
    public static func live(
        catalogue: @escaping @Sendable () async -> SequenceCatalogue, functions: ActionFunctionRegistry = .builtin,
        actions: ActionServices = .live, send: SendServices,
        progress: @escaping @Sendable (SequenceProgress) -> Void = { _ in },
        privacy: @escaping @Sendable () -> ContextPrivacy = { ContextPrivacy.load() }
    ) -> SequenceExecutor {
        var inner = actions
        inner.sequences = .unavailable
        let runner = EngineStepRunner(
            engine: ActionEngine(functions: functions, services: inner), destinations: DestinationRunner(services: send)
        )
        return SequenceExecutor { backend, execution in
            let plan = SequencePlanner.plan(
                backend.approved, trust: .trusted, catalogue: await catalogue(), privacy: privacy())
            // Stop a little before the engine's own timeout so the report names the step instead of just timing out.
            let invocation = SequenceInvocation(
                values: execution.values, target: execution.target, answers: execution.answers,
                confirmed: execution.confirmed, timeout: max(execution.timeout - 0.3, 0.3))
            return await Sequencer(runner: runner).run(plan, invocation: invocation, onProgress: progress)
        }
    }
}

extension SequenceBackend {
    /// The steps with their own trust cleared. A command's trust is its review state, decided by the person; the steps'
    /// marks only matter for sequences that have not become commands yet.
    var approved: SequenceBackend {
        var copy = self
        copy.steps = steps.map {
            var step = $0
            step.trust = .trusted
            return step
        }
        return copy
    }
}

/// Runs a planned step through the existing engines: context actions, commands, links, Shortcuts and menu steps through
/// `ActionEngine`, destinations through `DestinationRunner`. Values reach backends only as the engine already allows:
/// separate arguments, standard input, environment entries, script parameters or percent-encoded link parts.
public struct EngineStepRunner: SequenceStepRunner {
    public let engine: ActionEngine
    public let destinations: DestinationRunner

    public init(engine: ActionEngine, destinations: DestinationRunner) {
        self.engine = engine
        self.destinations = destinations
    }

    public func run(_ planned: PlannedStep, values: ContextValues, target: TargetApp?, capture: Bool) async
        -> StepRunResult
    {
        switch planned.target {
        case .action(var action)?:
            action.timeout = planned.step.effectiveTimeout
            // The combined confirmation covered every step, so the action's own question is not asked again.
            if capture {
                // The text is wanted back, not delivered: any output other than none makes the backend return it.
                if action.output == .none { action.output = .clipboard }
                switch await engine.produce(action, values: values, target: target, confirmed: true) {
                case .success(let text): return .done(produced: text)
                case .failure(let error): return .failed(Self.reason(error))
                }
            }
            switch await engine.run(action, values: values, target: target, confirmed: true) {
            case .success: return .done(produced: nil)
            case .failure(let error): return .failed(Self.reason(error))
            }
        case .destination(var destination)?:
            destination.timeout = min(destination.timeout, planned.step.effectiveTimeout)
            guard let payload = Self.payload(for: planned.step, values: values, target: target) else {
                let kind = planned.step.inputs.first?.kind ?? .text
                return .failed(.missingInput(kind))
            }
            switch await destinations.send(destination, payload: payload, confirmed: true) {
            case .success: return .done(produced: nil)
            case .failure(.timedOut): return .failed(.timedOut)
            case .failure(.cancelled): return .failed(.cancelled)
            case .failure(let error): return .failed(.backend(error.message))
            }
        case nil:
            return .failed(.unavailable(.unknownAction))
        }
    }

    static func reason(_ error: ActionError) -> SequenceFailureReason {
        switch error {
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        default: .backend(error.message)
        }
    }

    /// The payload a send step carries: its one payload input, as the send-to layer would build it.
    static func payload(for step: SequenceStep, values: ContextValues, target: TargetApp?) -> Payload? {
        let bundleID = target?.bundleID
        guard let kind = step.inputs.compactMap({ $0.kind.payloadKind }).first else { return nil }
        switch kind {
        case .text: return Payload.text(values.selectedText, source: values.pageURL, bundleID: bundleID)
        case .page: return Payload.page(url: values.pageURL, title: values.pageTitle, bundleID: bundleID)
        case .files: return Payload.files(values.selectedFiles, bundleID: bundleID)
        case .folder: return Payload.folder(values.folderURL, bundleID: bundleID)
        }
    }
}
