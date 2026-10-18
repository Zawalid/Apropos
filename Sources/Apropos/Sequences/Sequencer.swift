import Foundation

/// Why a step failed. Fixed vocabulary: sentences and codes carry no value, so they can be shown and logged anywhere.
public enum SequenceFailureReason: Equatable, Sendable {
    /// The context does not hold what an input asked for.
    case missingInput(SequenceValueKind)
    case missingAnswer
    /// What an earlier step gave could not be passed on as the kind of value this step reads.
    case invalidValue(SequenceValueProblem)
    /// The plan found a problem with this step (a missing app, an unknown command).
    case unavailable(PlanProblem)
    case timedOut
    case cancelled
    /// The engine, a destination or the menu steps reported a failure; the sentence is theirs and names no value.
    case backend(String)

    public var message: String {
        switch self {
        case .missingInput(let kind): "there is no \(kind.noun) to use"
        case .missingAnswer: "you did not answer its question"
        case .invalidValue(let problem): problem.message
        case .unavailable(let problem): problem.message
        case .timedOut: "it took too long"
        case .cancelled: "it was cancelled"
        case .backend(let sentence): sentence.isEmpty ? "it failed" : Self.lowercased(sentence)
        }
    }

    /// A short stable word for logs.
    public var code: String {
        switch self {
        case .missingInput: "missingInput"
        case .missingAnswer: "missingAnswer"
        case .invalidValue: "invalidValue"
        case .unavailable: "unavailable"
        case .timedOut: "timedOut"
        case .cancelled: "cancelled"
        case .backend: "backend"
        }
    }

    private static func lowercased(_ sentence: String) -> String {
        var text = sentence
        if text.hasSuffix(".") { text.removeLast() }
        guard let first = text.first, first.isUppercase, text.dropFirst().first?.isUppercase != true else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }
}

public enum SequenceSkipReason: Equatable, Sendable {
    /// An earlier step failed and the run stopped.
    case afterFailure
    /// The run was cancelled before this step started.
    case cancelled
    /// The whole run ran out of time before this step started.
    case timedOut
    /// A step it reads failed and went on (continue on failure), so there is nothing to read.
    case inputUnavailable
}

public enum SequenceStepStatus: Equatable, Sendable {
    case ok
    case failed(SequenceFailureReason)
    case skipped(SequenceSkipReason)
}

/// What happened to one step.
public struct SequenceStepResult: Equatable, Sendable, Identifiable {
    public var id: String { stepID }
    public let index: Int
    public let stepID: String
    /// The catalogue name of the step, for messages.
    public let title: String
    public let status: SequenceStepStatus
    public let duration: TimeInterval
}

/// How a run ended.
public enum SequenceOutcome: Equatable, Sendable {
    /// Every step ran and worked.
    case completed
    /// Every step was tried; some failed and were allowed to.
    case completedWithFailures
    /// A step failed and the run stopped there (index from 0).
    case stopped(atStep: Int)
    case cancelled
    case timedOut
    /// Nothing ran: the plan is not allowed to.
    case refused(PlanRefusal)
    /// Nothing ran: the combined confirmation has not been given.
    case needsConfirmation
    /// Nothing ran: some questions are unanswered.
    case needsAnswers([String])
}

/// The structured result of a run, one entry per step.
public struct SequenceReport: Equatable, Sendable {
    public let outcome: SequenceOutcome
    public let results: [SequenceStepResult]

    public var succeeded: Bool { outcome == .completed }

    /// The first step that failed, if any.
    public var firstFailure: (step: SequenceStepResult, reason: SequenceFailureReason)? {
        for result in results {
            if case .failed(let reason) = result.status { return (result, reason) }
        }
        return nil
    }

    /// One sentence for the person, or nil when everything worked. Names the step, never a value.
    public var message: String? {
        switch outcome {
        case .completed:
            return nil
        case .completedWithFailures:
            let failed = results.filter { if case .failed = $0.status { true } else { false } }
            return "\(failed.count) step\(failed.count == 1 ? "" : "s") failed and the run went on."
        case .stopped, .cancelled, .timedOut:
            guard let failure = firstFailure else {
                return outcome == .timedOut
                    ? "The sequence took too long and was stopped." : "The sequence was cancelled."
            }
            let step = failure.step
            return "Step \(step.index + 1) (\(step.title)) stopped the sequence: \(failure.reason.message)."
        case .refused(let refusal):
            return refusal.message
        case .needsConfirmation:
            return "That sequence needs your confirmation."
        case .needsAnswers:
            return "That sequence has a question to answer first."
        }
    }
}

/// What the interface hears while a run goes on.
public enum SequenceProgress: Equatable, Sendable {
    case started(index: Int, title: String)
    case finished(SequenceStepResult)
    case ended(SequenceOutcome)
}

/// What a runner reports for one step.
public enum StepRunResult: Equatable, Sendable {
    /// Done. The text is what the step produced, if the backend produced any.
    case done(produced: String?)
    case failed(SequenceFailureReason)
}

/// Runs one planned step on the values it was given. The live one goes through the existing engines; tests substitute a
/// fake and never touch an app.
public protocol SequenceStepRunner: Sendable {
    /// - Parameters:
    ///   - values: Exactly the inputs the step declared, nothing else.
    ///   - capture: True when the step names an output: return its text instead of delivering it.
    func run(_ step: PlannedStep, values: ContextValues, target: TargetApp?, capture: Bool) async -> StepRunResult
}

/// What a run is started with.
public struct SequenceInvocation: Sendable {
    /// The sensed context, taken once when the run starts.
    public var values: ContextValues
    public var target: TargetApp?
    /// Answers to the plan's questions, by question id.
    public var answers: [String: String]
    /// The person gave the combined confirmation.
    public var confirmed: Bool
    /// The whole run may take this long.
    public var timeout: TimeInterval

    public init(
        values: ContextValues, target: TargetApp? = nil, answers: [String: String] = [:], confirmed: Bool = false,
        timeout: TimeInterval = SequenceLimits.maxTotalTimeout
    ) {
        self.values = values
        self.target = target
        self.answers = answers
        self.confirmed = confirmed
        self.timeout = timeout
    }
}

/// Runs a plan one step at a time, off the main thread, passing values from step to step.
///
/// - A step sees only the inputs it declared. Context inputs come from the snapshot taken at the start; the others from
///   earlier outputs and the person's answers, each passed through `SequenceCoercion` on the way.
/// - It stops at the first failure unless the step says to go on. Later steps that read what a failed step should have
///   given are skipped.
/// - Each step has its own time limit and the run has a total one. Cancelling the task stops it: no step starts after
///   that and the step in flight is cancelled.
/// - It logs step numbers and fixed words only, never a value, a title or an answer.
public struct Sequencer: Sendable {
    public let runner: any SequenceStepRunner
    private let fileExists: @Sendable (String) -> Bool

    public init(
        runner: any SequenceStepRunner,
        fileExists: @escaping @Sendable (String) -> Bool = SequenceCoercion.defaultFileExists
    ) {
        self.runner = runner
        self.fileExists = fileExists
    }

    public func run(
        _ plan: SequencePlan, invocation: SequenceInvocation,
        onProgress: @escaping @Sendable (SequenceProgress) -> Void = { _ in }
    ) async -> SequenceReport {
        if let refusal = plan.refusal { return finish(.refused(refusal), [], onProgress) }
        if plan.requiresConfirmation, !invocation.confirmed { return finish(.needsConfirmation, [], onProgress) }
        let unanswered = plan.questions.map(\.id).filter { invocation.answers[$0] == nil }
        if !unanswered.isEmpty { return finish(.needsAnswers(unanswered), [], onProgress) }

        let state = RunState()
        enum Race: Sendable {
            case finished
            case timer
            /// The timer was cancelled, which says nothing about time.
            case stopped
        }
        await withTaskGroup(of: Race.self) { group in
            group.addTask {
                await loop(plan, invocation, state, onProgress)
                return .finished
            }
            group.addTask {
                do { try await Task.sleep(for: .seconds(max(invocation.timeout, 0.1))) } catch { return .stopped }
                return .timer
            }
            while let race = await group.next() {
                if race == .timer { state.end(by: .timedOut) }
                if race != .stopped { break }
            }
            group.cancelAll()
        }
        return finish(state.outcome(), state.results(), onProgress)
    }

    private func finish(
        _ outcome: SequenceOutcome, _ results: [SequenceStepResult], _ onProgress: @Sendable (SequenceProgress) -> Void
    ) -> SequenceReport {
        AproposLog.app.info("sequence ended: \(Self.word(for: outcome), privacy: .public)")
        onProgress(.ended(outcome))
        return SequenceReport(outcome: outcome, results: results)
    }

    private static func word(for outcome: SequenceOutcome) -> String {
        switch outcome {
        case .completed: "completed"
        case .completedWithFailures: "completedWithFailures"
        case .stopped(let step): "stopped at step \(step + 1)"
        case .cancelled: "cancelled"
        case .timedOut: "timedOut"
        case .refused: "refused"
        case .needsConfirmation: "needsConfirmation"
        case .needsAnswers: "needsAnswers"
        }
    }

    // MARK: The loop

    private func loop(
        _ plan: SequencePlan, _ invocation: SequenceInvocation, _ state: RunState,
        _ onProgress: @escaping @Sendable (SequenceProgress) -> Void
    ) async {
        var outputs: [String: SequenceValue] = [:]
        var failedOutputs = Set<String>()
        let clock = ContinuousClock()
        var stoppedAt: Int?

        for planned in plan.steps {
            let index = planned.index
            if Task.isCancelled || state.cause != nil {
                state.record(planned, .skipped(state.cause == .timedOut ? .timedOut : .cancelled), 0)
                onProgress(.finished(state.last()))
                continue
            }
            if stoppedAt != nil {
                state.record(planned, .skipped(.afterFailure), 0)
                onProgress(.finished(state.last()))
                continue
            }

            onProgress(.started(index: index, title: planned.title))
            let started = clock.now
            var status: SequenceStepStatus
            var produced: SequenceValue?

            switch gather(planned, invocation, plan, outputs, failedOutputs) {
            case .skip:
                status = .skipped(.inputUnavailable)
            case .fail(let reason):
                status = .failed(reason)
            case .values(let values):
                if let problem = planned.problems.first {
                    status = .failed(.unavailable(problem))
                } else {
                    let result = await runStep(planned, values: values, target: invocation.target)
                    switch result {
                    case .failed(let reason):
                        status = .failed(Self.settle(reason, cause: state.cause))
                    case .done where state.cause != nil:
                        // Cut off by the run's own deadline or a cancel: what it did cannot be counted on.
                        status = .failed(Self.settle(.cancelled, cause: state.cause))
                    case .done(let text):
                        status = .ok
                        if let output = planned.step.output {
                            switch text.map({
                                SequenceCoercion.value(fromText: $0, as: output.kind, fileExists: fileExists)
                            })
                                ?? .failure(.empty)
                            {
                            case .success(let value): produced = value
                            case .failure(let problem): status = .failed(.invalidValue(problem))
                            }
                        }
                    }
                }
            }

            if let output = planned.step.output {
                if let produced, status == .ok {
                    outputs[output.name] = produced
                } else {
                    failedOutputs.insert(output.name)
                }
            }
            let elapsed = clock.now - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            state.record(planned, status, seconds)
            AproposLog.app.info(
                "sequence step \(index + 1, privacy: .public) \(Self.word(for: status), privacy: .public)")
            onProgress(.finished(state.last()))

            if case .failed = status, !planned.step.continueOnFailure { stoppedAt = index }
        }
        if let stop = stoppedAt, !Task.isCancelled, state.cause == nil { state.setOutcome(.stopped(atStep: stop)) }
    }

    private static func word(for status: SequenceStepStatus) -> String {
        switch status {
        case .ok: "ok"
        case .failed(let reason): "failed(\(reason.code))"
        case .skipped: "skipped"
        }
    }

    /// A failure that the run itself caused is reported as what caused it.
    private static func settle(_ reason: SequenceFailureReason, cause: RunState.Cause?) -> SequenceFailureReason {
        switch cause {
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case nil: reason
        }
    }

    private func runStep(_ planned: PlannedStep, values: ContextValues, target: TargetApp?) async -> StepRunResult {
        let limit = planned.step.effectiveTimeout
        let capture = planned.step.output != nil
        enum Race: Sendable {
            case result(StepRunResult)
            case timer
            case stopped
        }
        return await withTaskGroup(of: Race.self) { group in
            group.addTask { .result(await runner.run(planned, values: values, target: target, capture: capture)) }
            group.addTask {
                do { try await Task.sleep(for: .seconds(limit)) } catch { return .stopped }
                return .timer
            }
            var answer = StepRunResult.failed(.cancelled)
            while let race = await group.next() {
                switch race {
                case .result(let result): answer = result
                case .timer: answer = .failed(.timedOut)
                case .stopped: continue
                }
                break
            }
            group.cancelAll()
            return answer
        }
    }

    // MARK: Inputs

    private enum Gathered {
        case values(ContextValues)
        case fail(SequenceFailureReason)
        case skip
    }

    private func gather(
        _ planned: PlannedStep, _ invocation: SequenceInvocation, _ plan: SequencePlan,
        _ outputs: [String: SequenceValue], _ failedOutputs: Set<String>
    ) -> Gathered {
        var values = ContextValues()
        for input in planned.step.inputs {
            switch input.source {
            case .context:
                guard let value = SequenceValue.from(context: invocation.values, kind: input.kind) else {
                    return .fail(.missingInput(input.kind))
                }
                value.apply(to: &values)
            case .output(let name):
                if failedOutputs.contains(name) { return .skip }
                guard let value = outputs[name] else { return .fail(.missingInput(input.kind)) }
                value.apply(to: &values)
            case .ask:
                let key = "\(planned.step.id).\(input.kind.rawValue)"
                guard let answer = invocation.answers[key] else { return .fail(.missingAnswer) }
                guard answer.count <= SequenceLimits.maxAnswerLength else { return .fail(.invalidValue(.tooLarge)) }
                switch SequenceCoercion.value(fromText: answer, as: .text, fileExists: fileExists) {
                case .success(let value): value.apply(to: &values)
                case .failure(let problem): return .fail(.invalidValue(problem))
                }
            }
        }
        return .values(values)
    }
}

/// What a run has recorded so far. Written by the loop, read once the loop has ended or been cancelled.
final class RunState: @unchecked Sendable {
    enum Cause: Sendable { case timedOut, cancelled }

    private let lock = NSLock()
    private var _results: [SequenceStepResult] = []
    private var _cause: Cause?
    private var _outcome: SequenceOutcome?

    var cause: Cause? { lock.withLock { _cause } }

    func end(by cause: Cause) { lock.withLock { if _cause == nil { _cause = cause } } }

    func record(_ planned: PlannedStep, _ status: SequenceStepStatus, _ duration: TimeInterval) {
        lock.withLock {
            _results.append(
                SequenceStepResult(
                    index: planned.index, stepID: planned.step.id, title: planned.title, status: status,
                    duration: duration))
        }
    }

    func last() -> SequenceStepResult {
        lock.withLock {
            _results.last
                ?? SequenceStepResult(index: 0, stepID: "", title: "", status: .skipped(.cancelled), duration: 0)
        }
    }

    func results() -> [SequenceStepResult] { lock.withLock { _results } }

    func setOutcome(_ outcome: SequenceOutcome) { lock.withLock { _outcome = outcome } }

    func outcome() -> SequenceOutcome {
        lock.withLock {
            if let _outcome { return _outcome }
            let failed = _results.contains { if case .failed = $0.status { true } else { false } }
            switch _cause {
            case .timedOut: return .timedOut
            case .cancelled: return .cancelled
            case nil: break
            }
            if Task.isCancelled { return .cancelled }
            return failed ? .completedWithFailures : .completed
        }
    }
}
