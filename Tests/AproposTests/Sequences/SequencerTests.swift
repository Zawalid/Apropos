import Foundation
import Testing

@testable import Apropos

/// A runner that does what the test says and remembers what it was given. It never touches an app.
final class FakeStepRunner: SequenceStepRunner, @unchecked Sendable {
    typealias Behavior = @Sendable (PlannedStep, ContextValues, Bool) async -> StepRunResult

    private let lock = NSLock()
    private var _calls: [(id: String, values: ContextValues, capture: Bool)] = []
    private let behavior: Behavior

    init(_ behavior: @escaping Behavior = { _, _, _ in .done(produced: nil) }) { self.behavior = behavior }

    var calls: [(id: String, values: ContextValues, capture: Bool)] { lock.withLock { _calls } }
    var ids: [String] { calls.map(\.id) }

    func run(_ step: PlannedStep, values: ContextValues, target: TargetApp?, capture: Bool) async -> StepRunResult {
        lock.withLock { _calls.append((step.step.id, values, capture)) }
        return await behavior(step, values, capture)
    }
}

/// Collects progress events from any thread.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [SequenceProgress] = []
    var events: [SequenceProgress] { lock.withLock { _events } }
    func add(_ event: SequenceProgress) { lock.withLock { _events.append(event) } }
}

func planFor(_ steps: SequenceStep..., trust: SequenceTrust = .trusted, catalogue: SequenceCatalogue? = nil)
    -> SequencePlan
{
    SequencePlanner.plan(SequenceBackend(steps: steps), trust: trust, catalogue: catalogue ?? bundledCatalogue())
}

let sensed = ContextValues(
    selectedText: "context text", pageURL: URL(string: "https://example.com/page"), pageTitle: "Page")

@Suite("Sequencer")
struct SequencerTests {
    private func run(
        _ plan: SequencePlan, runner: FakeStepRunner, values: ContextValues = sensed, answers: [String: String] = [:],
        confirmed: Bool = true, timeout: TimeInterval = 20, progress: ProgressLog? = nil
    ) async -> SequenceReport {
        await Sequencer(runner: runner).run(
            plan,
            invocation: SequenceInvocation(values: values, answers: answers, confirmed: confirmed, timeout: timeout),
            onProgress: { progress?.add($0) })
    }

    // MARK: Passing values

    @Test func aStepSeesOnlyWhatItDeclared() async {
        let runner = FakeStepRunner()
        let catalogue = bundledCatalogue(userCommands: [
            UserCommand(id: "user:x", title: "Mine", backend: .function("text.upper"))
        ])
        let plan = planFor(Seq.upper(), SequenceStep(kind: .userCommand("user:x")), catalogue: catalogue)
        _ = await run(plan, runner: runner, confirmed: true)
        #expect(runner.calls[0].values.selectedText == "context text")
        #expect(runner.calls[0].values.pageURL == nil)
        #expect(runner.calls[1].values.isEmpty)
    }

    @Test func anOutputReachesTheNextStepAsItsInput() async {
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s1" ? .done(produced: "SHOUTED") : .done(produced: nil)
        }
        let plan = planFor(Seq.upper(output: "shout"), Seq.send("dest:notes", from: .output("shout")))
        let report = await run(plan, runner: runner)
        #expect(report.outcome == .completed)
        #expect(runner.calls[0].capture && !runner.calls[1].capture)
        #expect(runner.calls[1].values.selectedText == "SHOUTED")
        // The context text never reaches the second step: it declared the output only.
        #expect(runner.calls[1].values.pageURL == nil)
    }

    @Test func outputsCanChangeKindOnTheWay() async {
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s1" ? .done(produced: " https://example.com/found \n") : .done(produced: nil)
        }
        let find = SequenceStep(
            kind: .userCommand("user:x"), inputs: [SequenceInput(.text)],
            output: SequenceOutput(name: "link", kind: .page))
        let catalogue = bundledCatalogue(userCommands: [
            UserCommand(id: "user:x", title: "Find", backend: .function("text.upper"))
        ])
        let report = await run(
            planFor(find, Seq.send("dest:notes", kind: .page, from: .output("link")), catalogue: catalogue),
            runner: runner)
        #expect(report.outcome == .completed)
        #expect(runner.calls[1].values.pageURL == URL(string: "https://example.com/found"))
        #expect(runner.calls[1].values.pageTitle == "example.com")
    }

    @Test func aProducedValueThatIsNotTheDeclaredKindFailsTheStep() async {
        let runner = FakeStepRunner { _, _, _ in .done(produced: "javascript:alert(1)") }
        let step = SequenceStep(
            kind: .userCommand("user:x"), inputs: [SequenceInput(.text)],
            output: SequenceOutput(name: "link", kind: .url))
        let catalogue = bundledCatalogue(userCommands: [
            UserCommand(id: "user:x", title: "Find", backend: .function("text.upper"))
        ])
        let report = await run(planFor(step, Seq.upper(), catalogue: catalogue), runner: runner)
        #expect(report.results[0].status == .failed(.invalidValue(.notALink)))
        #expect(report.results[1].status == .skipped(.afterFailure))
    }

    @Test func aNamedOutputThatCameBackEmptyFailsTheStep() async {
        for produced in [nil, "", "  \n"] as [String?] {
            let runner = FakeStepRunner { _, _, _ in .done(produced: produced) }
            let report = await run(planFor(Seq.upper(output: "a")), runner: runner)
            #expect(report.results[0].status == .failed(.invalidValue(.empty)))
        }
    }

    @Test func controlCharactersNeverSurviveAHandOver() async {
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s1" ? .done(produced: "a\u{0}b\u{1B}[31mc") : .done(produced: nil)
        }
        _ = await run(planFor(Seq.upper(output: "a"), Seq.send(from: .output("a"))), runner: runner)
        let text = runner.calls[1].values.selectedText ?? ""
        #expect(!text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" && $0 != "\t" })
    }

    @Test func aContextInputThatIsMissingFailsTheStepBeforeItRuns() async {
        let runner = FakeStepRunner()
        let report = await run(planFor(Seq.upper()), runner: runner, values: ContextValues())
        #expect(report.results[0].status == .failed(.missingInput(.text)))
        #expect(runner.ids.isEmpty)
        #expect(report.outcome == .stopped(atStep: 0))
    }

    @Test func contextIsTakenOnceAtTheStart() async {
        // Both steps read the same snapshot even though the first one might change the world.
        let runner = FakeStepRunner()
        _ = await run(planFor(Seq.upper(), Seq.upper()), runner: runner)
        #expect(runner.calls.map { $0.values.selectedText } == ["context text", "context text"])
    }

    // MARK: Questions

    @Test func unansweredQuestionsStopTheRunBeforeAnythingHappens() async {
        let runner = FakeStepRunner()
        let report = await run(planFor(Seq.upper(input: .ask(prompt: "Which?"))), runner: runner)
        #expect(report.outcome == .needsAnswers(["s1.text"]))
        #expect(runner.ids.isEmpty)
    }

    @Test func answersAreCleanedAndPassedAsText() async {
        let runner = FakeStepRunner()
        let report = await run(
            planFor(Seq.upper(input: .ask(prompt: "Which?"))), runner: runner,
            answers: ["s1.text": "tone\u{0}: \"warm\"; $(x)"])
        #expect(report.outcome == .completed)
        #expect(runner.calls[0].values.selectedText == "tone: \"warm\"; $(x)")
    }

    @Test func aBlankOrHugeAnswerFailsTheStep() async {
        let blank = await run(
            planFor(Seq.upper(input: .ask(prompt: "Which?"))), runner: FakeStepRunner(), answers: ["s1.text": "  "])
        #expect(blank.results[0].status == .failed(.invalidValue(.empty)))
        let huge = String(repeating: "x", count: SequenceLimits.maxAnswerLength + 1)
        let big = await run(
            planFor(Seq.upper(input: .ask(prompt: "Which?"))), runner: FakeStepRunner(), answers: ["s1.text": huge])
        #expect(big.results[0].status == .failed(.invalidValue(.tooLarge)))
    }

    // MARK: Failure paths

    @Test func itStopsAtTheFirstFailureAndSkipsTheRest() async {
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s2" ? .failed(.backend("Could not send to Notes.")) : .done(produced: "x")
        }
        let report = await run(planFor(Seq.upper(), Seq.send(), Seq.upper()), runner: runner)
        #expect(report.outcome == .stopped(atStep: 1))
        #expect(
            report.results.map(\.status) == [
                .ok, .failed(.backend("Could not send to Notes.")), .skipped(.afterFailure),
            ])
        #expect(runner.ids == ["s1", "s2"])
        #expect(report.message == "Step 2 (Notes) stopped the sequence: could not send to Notes.")
        #expect(report.firstFailure?.step.stepID == "s2")
    }

    @Test func aStepMayContinueAfterItsOwnFailure() async {
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s1" ? .failed(.backend("Boom.")) : .done(produced: nil)
        }
        var first = Seq.upper()
        first.continueOnFailure = true
        let report = await run(planFor(first, Seq.send()), runner: runner)
        #expect(report.outcome == .completedWithFailures)
        #expect(report.results.map(\.status) == [.failed(.backend("Boom.")), .ok])
        #expect(runner.ids == ["s1", "s2"])
        #expect(report.message == "1 step failed and the run went on.")
    }

    @Test func aStepThatReadsAFailedOutputIsSkippedNotRun() async {
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s1" ? .failed(.backend("Boom.")) : .done(produced: nil)
        }
        var first = Seq.upper(output: "a")
        first.continueOnFailure = true
        let report = await run(planFor(first, Seq.send(from: .output("a")), Seq.upper()), runner: runner)
        #expect(report.results[1].status == .skipped(.inputUnavailable))
        #expect(report.results[2].status == .ok)
        #expect(!runner.ids.contains("s2"))
        #expect(report.outcome == .completedWithFailures)
    }

    @Test func aPlanProblemOnAContinuingStepFailsThatStepWhenReached() async {
        var send = Seq.send("dest:notes")
        send.continueOnFailure = true
        let catalogue = bundledCatalogue(installed: { $0 != "com.apple.Notes" })
        let runner = FakeStepRunner()
        let report = await run(planFor(send, Seq.upper(), catalogue: catalogue), runner: runner)
        #expect(report.results[0].status == .failed(.unavailable(.destinationAppNotInstalled(title: "Notes"))))
        #expect(runner.ids == ["s2"])
    }

    // MARK: Before anything runs

    @Test func anUntrustedPlanRunsNothing() async {
        let runner = FakeStepRunner()
        let report = await run(planFor(Seq.upper(), trust: .untrusted), runner: runner)
        #expect(report.outcome == .refused(.untrusted))
        #expect(runner.ids.isEmpty && report.results.isEmpty)
        #expect(report.message == "This sequence is waiting for your approval.")
    }

    @Test func aBlockedPlanRunsNothing() async {
        let runner = FakeStepRunner()
        let plan = planFor(Seq.upper(), SequenceStep(kind: .contextAction("ctx:nope"), inputs: [SequenceInput(.text)]))
        let report = await run(plan, runner: runner)
        #expect(report.outcome == .refused(.blocked(step: 1, .unknownAction)))
        #expect(runner.ids.isEmpty)
    }

    @Test func externalEffectsNeedTheCombinedConfirmationFirst() async {
        let runner = FakeStepRunner { _, _, _ in .done(produced: "x") }
        let plan = planFor(Seq.upper(output: "a"), Seq.send("dest:mail", from: .output("a")))
        let unconfirmed = await run(plan, runner: runner, confirmed: false)
        #expect(unconfirmed.outcome == .needsConfirmation)
        #expect(runner.ids.isEmpty)
        let confirmed = await run(plan, runner: runner, confirmed: true)
        #expect(confirmed.outcome == .completed)
        #expect(runner.ids == ["s1", "s2"])
    }

    @Test func aSequenceWithoutEffectsNeedsNoConfirmation() async {
        let runner = FakeStepRunner { _, _, _ in .done(produced: "x") }
        let report = await run(planFor(Seq.upper(output: "a")), runner: runner, confirmed: false)
        #expect(report.outcome == .completed)
    }

    // MARK: Time and cancel

    @Test func aStepThatTakesTooLongFailsAndStopsTheRun() async {
        let runner = FakeStepRunner { planned, _, _ in
            if planned.step.id == "s1" { try? await Task.sleep(for: .seconds(30)) }
            return .done(produced: nil)
        }
        var slow = Seq.upper()
        slow.timeout = 0.5
        let started = ContinuousClock.now
        let report = await run(planFor(slow, Seq.upper()), runner: runner)
        // Well under the 30 s the step would sleep: it proves the run did not wait, without depending on a busy machine.
        #expect(ContinuousClock.now - started < .seconds(20))
        #expect(report.results.map(\.status) == [.failed(.timedOut), .skipped(.afterFailure)])
        #expect(report.outcome == .stopped(atStep: 0))
    }

    @Test func theWholeRunHasATimeToo() async {
        let runner = FakeStepRunner { planned, _, _ in
            if planned.step.id == "s1" { try? await Task.sleep(for: .seconds(30)) }
            return .done(produced: nil)
        }
        var slow = Seq.upper()
        slow.timeout = 60
        let started = ContinuousClock.now
        let report = await run(planFor(slow, Seq.upper()), runner: runner, timeout: 0.4)
        #expect(ContinuousClock.now - started < .seconds(20))
        #expect(report.outcome == .timedOut)
        #expect(report.results.map(\.status) == [.failed(.timedOut), .skipped(.timedOut)])
        #expect(report.message == "Step 1 (UPPERCASE) stopped the sequence: it took too long.")
    }

    @Test func cancellingStopsTheStepInFlightAndStartsNoOther() async throws {
        let runner = FakeStepRunner { planned, _, _ in
            if planned.step.id == "s1" {
                do { try await Task.sleep(for: .seconds(30)) } catch { return .failed(.cancelled) }
            }
            return .done(produced: nil)
        }
        let plan = planFor(Seq.upper(), Seq.upper())
        let sequencer = Sequencer(runner: runner)
        let task = Task {
            await sequencer.run(plan, invocation: SequenceInvocation(values: sensed, confirmed: true))
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        let report = await task.value
        #expect(report.outcome == .cancelled)
        #expect(report.results.map(\.status) == [.failed(.cancelled), .skipped(.cancelled)])
        #expect(runner.ids == ["s1"])
    }

    @Test func aRunCancelledBeforeItStartsDoesNothing() async {
        let runner = FakeStepRunner()
        let sequencer = Sequencer(runner: runner)
        let plan = planFor(Seq.upper(), Seq.upper())
        let task = Task {
            try? await Task.sleep(for: .milliseconds(200))
            return await sequencer.run(plan, invocation: SequenceInvocation(values: sensed, confirmed: true))
        }
        task.cancel()
        let report = await task.value
        #expect(report.outcome == .cancelled)
        #expect(runner.ids.isEmpty)
    }

    // MARK: Progress

    @Test func progressTellsTheInterfaceEachStepAndTheEnd() async {
        let log = ProgressLog()
        let runner = FakeStepRunner()
        let report = await run(planFor(Seq.upper(), Seq.upper()), runner: runner, progress: log)
        let events = log.events
        #expect(events.count == 5)
        #expect(events[0] == .started(index: 0, title: "UPPERCASE"))
        if case .finished(let first) = events[1] {
            #expect(first.index == 0 && first.status == .ok)
        } else {
            Issue.record("expected finished")
        }
        #expect(events[2] == .started(index: 1, title: "UPPERCASE"))
        #expect(events.last == .ended(report.outcome))
    }

    @Test func theEndIsReportedEvenWhenNothingRuns() async {
        let log = ProgressLog()
        _ = await run(planFor(Seq.upper(), trust: .untrusted), runner: FakeStepRunner(), progress: log)
        #expect(log.events == [.ended(.refused(.untrusted))])
    }

    // MARK: Privacy

    @Test func messagesAndReportsNeverCarryValues() async {
        let secret = "SECRET-PASSPHRASE-9931"
        let runner = FakeStepRunner { planned, _, _ in
            planned.step.id == "s1" ? .done(produced: secret) : .failed(.backend("Could not send to Notes."))
        }
        let log = ProgressLog()
        let report = await run(
            planFor(Seq.upper(output: "a"), Seq.send(from: .output("a"))), runner: runner,
            values: ContextValues(selectedText: secret), progress: log)
        let everything = "\(report)\(log.events)\(report.message ?? "")"
        #expect(!everything.contains(secret))
    }

    @Test func noLoggingCallInTheSequencerCarriesAValue() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/Apropos/Sequences")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
            $0.hasSuffix(".swift")
        }
        #expect(!files.isEmpty)
        // The only things interpolated into a log line are step numbers and fixed words.
        let allowed: Set<String> = ["Self.word(for: outcome)", "Self.word(for: status)", "index + 1"]
        var logCalls = 0
        for name in files {
            let source = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            let lines = source.components(separatedBy: "\n")
            var inLog = false
            for line in lines {
                if line.contains("AproposLog.") {
                    inLog = true
                    logCalls += 1
                }
                guard inLog else { continue }
                for part in line.components(separatedBy: "\\(").dropFirst() {
                    let expression = part.components(separatedBy: ", privacy").first ?? part
                    #expect(allowed.contains(expression), "log interpolation \(expression) in \(name)")
                }
                if line.hasSuffix(")") { inLog = false }
            }
        }
        #expect(logCalls >= 2)
    }
}
