import Foundation
import Testing

@testable import Apropos

/// Everything a sequence run touches, faked: the engine's services for context actions, links and Shortcuts, the send
/// services for destinations, and the menu steps.
final class SequenceRig: @unchecked Sendable {
    let actions = ServiceRecorder()
    let sends = SendRecorder()
    let menuCalls = CallCounter()
    var menuFailure: StepFailure?
    let userCommands: [UserCommand]

    init(
        userCommands: [UserCommand] = [],
        installed: Set<String> = ["com.apple.Notes", "com.apple.mail", "com.apple.Preview"]
    ) {
        self.userCommands = userCommands
        sends.installed = installed
    }

    var catalogue: SequenceCatalogue {
        let library = DestinationLibrary.bundled()
        return SequenceCatalogue(
            contextActions: ActionPackLibrary.bundled().actions, userCommands: userCommands,
            destinations: library.runnable, isInstalled: { [sends] in sends.installed.contains($0) })
    }

    /// Programs the steps asked for, other than `cat`, which really runs: nothing else is ever launched.
    let programs = ProgramLog()

    var baseServices: ActionServices {
        var services = actions.services
        services.process = { [programs] request in
            if request.executable == "/bin/cat" { return try await ProcessRunner.run(request) }
            programs.add(request)
            return ProcessOutput(status: 0, standardOutput: Data(), standardErrorByteCount: 0)
        }
        return services
    }

    var executor: SequenceExecutor {
        var services = baseServices
        services.uiSteps = UIStepsExecutor { [menuCalls, menuFailure] backend, _, _, _ in
            menuCalls.add(backend.steps.count)
            return StepRunReport(steps: [], failure: menuFailure, milliseconds: 0)
        }
        let catalogue = self.catalogue
        return .live(catalogue: { catalogue }, actions: services, send: sends.services, privacy: { ContextPrivacy() })
    }

    /// The engine a command runs through, with the sequencer connected.
    var engine: ActionEngine {
        var services = baseServices
        services.sequences = executor
        return ActionEngine(services: services)
    }

    func run(
        _ steps: [SequenceStep], values: ContextValues = textValues("hello"), confirmed: Bool = true
    ) async -> Result<ActionOutcome, ActionError> {
        let command = CommandSequence(title: "Test", steps: steps).userCommand(needsConfirmation: false)
        return await engine.run(command.action, values: values, target: nil, confirmed: confirmed)
    }
}

final class ProgramLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [ProcessRequest] = []
    func add(_ request: ProcessRequest) { lock.withLock { _requests.append(request) } }
    var requests: [ProcessRequest] { lock.withLock { _requests } }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int] = []
    func add(_ value: Int) { lock.withLock { _values.append(value) } }
    var values: [Int] { lock.withLock { _values } }
}

/// A command that prints its standard input: stands in for any step that gives text back.
func echoCommand(_ id: String = "user:echo") -> UserCommand {
    UserCommand(
        id: ActionID(rawValue: id), title: "Echo", requires: [.selectedText],
        backend: .shell(ShellBackend(executable: "/bin/cat", standardInput: .text)), output: .clipboard)
}

@Suite("Sequence through the engine")
struct SequenceEngineTests {
    @Test func aTextFunctionFeedsADestination() async {
        let rig = SequenceRig()
        let result = await rig.run([Seq.upper(output: "shout"), Seq.send("dest:notes", from: .output("shout"))])
        #expect(throws: Never.self) { try result.get() }
        let request = rig.sends.processes.first
        #expect(request?.executable == "/usr/bin/osascript")
        #expect(request?.arguments.contains("HELLO") == true)
        // Capturing the output means it was not also delivered to the clipboard.
        #expect(rig.actions.clipboard.isEmpty)
    }

    @Test func aStepWithoutAnOutputDeliversNormally() async {
        let rig = SequenceRig()
        let result = await rig.run([Seq.upper()])
        #expect(throws: Never.self) { try result.get() }
        #expect(rig.actions.replaced.isEmpty)
        // Upper replaces the selection; with no target app it lands on the clipboard instead.
        #expect(rig.actions.clipboard == ["HELLO"])
    }

    @Test func linksGetTheirValuesAsTheEngineAlwaysGivesThem() async {
        let rig = SequenceRig()
        let result = await rig.run([Seq.link("https://example.com/search?q={text}")])
        #expect(throws: Never.self) { try result.get() }
        #expect(rig.actions.opened.map(\.absoluteString) == ["https://example.com/search?q=hello"])
    }

    @Test func menuStepsRunThroughTheStepEngine() async {
        let rig = SequenceRig()
        let result = await rig.run([Seq.menu(), Seq.upper()])
        #expect(throws: Never.self) { try result.get() }
        #expect(rig.menuCalls.values == [1])
    }

    @Test func aFailingMenuStepStopsTheRunAndNamesTheStep() async {
        let rig = SequenceRig()
        rig.menuFailure = StepFailure(step: 1, reason: .notFound)
        let result = await rig.run([Seq.menu(), Seq.upper()])
        guard case .failure(.sequenceFailed(let sentence)) = result else {
            Issue.record("expected a sequence failure, got \(result)")
            return
        }
        #expect(sentence.hasPrefix("Step 1 ("))
        #expect(sentence.contains("stopped the sequence"))
        #expect(rig.actions.clipboard.isEmpty)
    }

    @Test func aFailedSendNamesTheDestinationAndStopsTheRest() async {
        let rig = SequenceRig()
        rig.sends.processStatus = 1
        let result = await rig.run([Seq.send("dest:notes"), Seq.link("https://example.com/?q={text}")])
        guard case .failure(.sequenceFailed(let sentence)) = result else {
            Issue.record("expected a sequence failure, got \(result)")
            return
        }
        #expect(sentence.contains("Notes"))
        #expect(rig.actions.opened.isEmpty)
    }

    @Test func aMissingAppRefusesTheWholeRunBeforeAnythingHappens() async {
        let rig = SequenceRig(installed: [])
        let result = await rig.run([Seq.upper(output: "a"), Seq.send("dest:notes", from: .output("a"))])
        guard case .failure(.unavailable(let sentence)) = result else {
            Issue.record("expected unavailable, got \(result)")
            return
        }
        #expect(sentence.contains("Notes is not installed"))
        #expect(rig.sends.processes.isEmpty)
    }

    @Test func externalEffectsNeedTheConfirmationThatTheCommandAsks() async {
        let rig = SequenceRig()
        let steps = [Seq.upper(output: "a"), Seq.send("dest:notes", from: .output("a"))]
        let command = CommandSequence(title: "Test", steps: steps).userCommand(needsConfirmation: true)
        let asked = await rig.engine.run(command.action, values: textValues("x"), target: nil, confirmed: false)
        #expect(asked == .failure(.confirmationRequired))
        #expect(rig.sends.processes.isEmpty)
        // Even a command that forgot to ask is held by the sequencer's own check.
        let forgetful = CommandSequence(title: "Test", steps: steps).userCommand(needsConfirmation: false)
        let held = await rig.engine.run(forgetful.action, values: textValues("x"), target: nil, confirmed: false)
        #expect(held == .failure(.confirmationRequired))
        #expect(rig.sends.processes.isEmpty)
        let allowed = await rig.engine.run(command.action, values: textValues("x"), target: nil, confirmed: true)
        #expect(throws: Never.self) { try allowed.get() }
        #expect(rig.sends.processes.count == 1)
    }

    @Test func withoutASequencerTheCommandSaysSo() async {
        let command = CommandSequence(title: "Test", steps: [Seq.upper()]).userCommand()
        let engine = ActionEngine(services: ServiceRecorder().services)
        let result = await engine.run(command.action, values: textValues("x"), target: nil)
        #expect(result == .failure(.unavailable("Sequences are not available here.")))
    }

    @Test func aSequenceCannotRunAnotherSequence() async {
        let inner = CommandSequence(title: "Inner", steps: [Seq.upper(output: "a")]).userCommand()
        let rig = SequenceRig(userCommands: [inner])
        let outer = SequenceStep(kind: .userCommand(inner.id), inputs: [SequenceInput(.text)])
        let plan = SequencePlanner.plan(Seq.backend(outer), catalogue: rig.catalogue)
        #expect(plan.steps[0].problems == [.nestedSequence])
        let result = await rig.run([outer])
        guard case .failure(.unavailable(let sentence)) = result else {
            Issue.record("expected unavailable, got \(result)")
            return
        }
        #expect(sentence.contains("cannot run another sequence"))
    }

    @Test func aUserCommandStepRunsAndGivesItsText() async {
        let rig = SequenceRig(userCommands: [echoCommand()])
        let echo = SequenceStep(
            kind: .userCommand("user:echo"), inputs: [SequenceInput(.text)], output: SequenceOutput(name: "echoed"))
        let result = await rig.run(
            [echo, Seq.send("dest:notes", from: .output("echoed"))], values: textValues("through cat"))
        #expect(throws: Never.self) { try result.get() }
        #expect(rig.sends.processes.first?.arguments.contains("through cat") == true)
    }

    @Test func theStepsOfAPackSequenceAreChecked() {
        let json = """
            {"schemaVersion":1,"actions":[
              {"id":"user:good","title":"Good","symbol":"star","requires":[],
               "backend":{"type":"sequence","sequence":{"version":1,"steps":[
                 {"kind":"contextAction","action":"ctx:text.upper","inputs":[{"kind":"text"}]}]}},"output":"none"},
              {"id":"user:bad","title":"Bad","symbol":"star","requires":[],
               "backend":{"type":"sequence","sequence":{"version":1,"steps":[
                 {"kind":"contextAction","action":"ctx:text.upper","inputs":[{"kind":"text","from":"output","name":"ghost"}]}]}},"output":"none"}
            ]}
            """
        var library = ActionPackLibrary()
        library.add(packData: Data(json.utf8), source: "test.json")
        #expect(library.actions.map(\.id.rawValue) == ["user:good"])
        #expect(library.issues.count == 1 && library.issues[0].reason.contains("Step 1"))
    }
}

@Suite("Sequence values reach backends only as values")
struct SequenceInjectionTests {
    @Test(arguments: hostileTexts)
    func hostileTextsStayValuesAllTheWayThrough(_ hostile: String) async throws {
        let rig = SequenceRig(userCommands: [echoCommand()])
        let echo = SequenceStep(
            kind: .userCommand("user:echo"), inputs: [SequenceInput(.text)], output: SequenceOutput(name: "echoed"))
        let steps = [
            echo,
            Seq.send("dest:notes", from: .output("echoed")),
            SequenceStep(
                kind: .openURL(Seq.tpl("https://example.com/search?q={text}")),
                inputs: [SequenceInput(.text, from: .output("echoed"))]),
            SequenceStep(
                kind: .shortcut(name: "Take text"), inputs: [SequenceInput(.text, from: .output("echoed"))]),
        ]
        let result = await rig.run(steps, values: textValues(hostile))
        let cleaned = Payload.clean(hostile)
        let tooBig = cleaned.count > PayloadLimits.maxTextCharacters
        let blank = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tooBig || blank {
            // Refused as a value: nothing was sent anywhere.
            #expect(rig.sends.processes.isEmpty && rig.actions.opened.isEmpty)
            return
        }
        #expect(throws: Never.self) { try result.get() }

        // The note: the script is the literal from the pack, the text is a separate argument after it.
        let note = try #require(rig.sends.processes.first)
        #expect(note.executable == "/usr/bin/osascript")
        let notes = DestinationLibrary.bundled().destination(for: "dest:notes")
        let sources = (notes?.variants ?? []).compactMap { variant -> String? in
            if case .appleScript(let script) = variant.action.backend { script.source } else { nil }
        }
        #expect(sources.contains(note.arguments[1]))
        #expect(
            note.arguments.dropFirst(2).contains(cleaned)
                || note.arguments.dropFirst(2).contains { $0.hasPrefix(String(cleaned.prefix(20))) })

        // The Shortcut: the text travels in a file, never in the arguments.
        let shortcut = try #require(rig.programs.requests.first)
        #expect(shortcut.executable == "/usr/bin/shortcuts")
        #expect(shortcut.arguments.prefix(2) == ["run", "Take text"])
        #expect(!shortcut.arguments.contains(cleaned))

        // The link: percent-encoded, so the query holds the whole text and nothing else.
        let opened = try #require(rig.actions.opened.first)
        let components = try #require(URLComponents(url: opened, resolvingAgainstBaseURL: false))
        #expect(components.host == "example.com" && components.path == "/search")
        #expect(components.queryItems?.count == 1)
        #expect(components.queryItems?.first?.value == cleaned)
    }

    @Test func aHostileAnswerIsAValueToo() async throws {
        let rig = SequenceRig()
        let step = SequenceStep(
            kind: .openURL(Seq.tpl("https://example.com/?q={text}")),
            inputs: [SequenceInput(.text, from: .ask(prompt: "What?"))])
        let command = CommandSequence(title: "Ask", steps: [step]).userCommand()
        // Answers travel with the execution, never as part of a template.
        let execution = SequenceExecution(
            actionID: command.id, values: ContextValues(), target: nil, confirmed: true, timeout: 10,
            answers: ["s1.text": "\"; touch ~/pwn #\u{0}&x=1"])
        let report = await rig.executor.run(try #require(command.sequenceBackend), execution)
        #expect(report.outcome == .completed)
        let opened = try #require(rig.actions.opened.first)
        let items = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.count == 1)
        #expect(items?.first?.value == "\"; touch ~/pwn #&x=1")
    }

    @Test func aHostileProducedLinkCannotBecomeAnotherScheme() async throws {
        let rig = SequenceRig(userCommands: [echoCommand()])
        let echo = SequenceStep(
            kind: .userCommand("user:echo"), inputs: [SequenceInput(.text)],
            output: SequenceOutput(name: "found", kind: .url))
        let open = SequenceStep(
            kind: .openURL(Seq.tpl("{url}")), inputs: [SequenceInput(.url, from: .output("found"))])
        // A template that is nothing but a placeholder has no scheme of its own: refused outright.
        let issues = SequenceValidator.issues(in: Seq.backend(echo, open))
        #expect(issues.contains { if case .invalidTemplate = $0 { true } else { false } })
        // And a produced value that is not a web address never reaches a step.
        let ok = SequenceStep(
            kind: .openURL(Seq.tpl("https://example.com/go?to={url}")),
            inputs: [SequenceInput(.url, from: .output("found"))])
        for bad in [
            "javascript:alert(1)", "file:///etc/passwd", "x-apple.systempreferences:", "data:text/html,<script>",
        ] {
            let result = await rig.run([echo, ok], values: textValues(bad))
            guard case .failure(.sequenceFailed(let sentence)) = result else {
                Issue.record("expected failure for \(bad.prefix(8))")
                continue
            }
            #expect(sentence.contains("not a web address"))
        }
        #expect(rig.actions.opened.isEmpty)
    }

    @Test func aProducedFileListCannotPointAtWhatDoesNotExist() async throws {
        let rig = SequenceRig(userCommands: [echoCommand()])
        let echo = SequenceStep(
            kind: .userCommand("user:echo"), inputs: [SequenceInput(.text)],
            output: SequenceOutput(name: "list", kind: .files))
        let mail = SequenceStep(
            kind: .destination("dest:mail"), inputs: [SequenceInput(.files, from: .output("list"))])
        for bad in ["/nonexistent/secret", "relative.txt", "/tmp/../etc/passwd", "~/Documents"] {
            let result = await rig.run([echo, mail], values: textValues(bad))
            guard case .failure(.sequenceFailed(let sentence)) = result else {
                Issue.record("expected failure for \(bad)")
                continue
            }
            #expect(sentence.contains("list of files that exist"))
        }
        #expect(rig.sends.processes.isEmpty)
    }

    @Test func nothingTheRunReportsCarriesAValue() async {
        let secret = "SECRET-TOKEN-7741"
        let rig = SequenceRig()
        rig.sends.processStatus = 1
        let result = await rig.run(
            [Seq.upper(output: "a"), Seq.send("dest:notes", from: .output("a"))], values: textValues(secret))
        guard case .failure(let error) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(!"\(error)".uppercased().contains(secret))
        #expect(!error.message.uppercased().contains(secret))
    }
}
