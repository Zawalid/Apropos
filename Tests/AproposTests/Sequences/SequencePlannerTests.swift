import Foundation
import Testing

@testable import Apropos

func bundledCatalogue(
    userCommands: [UserCommand] = [], installed: @escaping @Sendable (String) -> Bool = { _ in true }
) -> SequenceCatalogue {
    SequenceCatalogue(
        contextActions: ActionPackLibrary.bundled().actions, userCommands: userCommands,
        destinations: DestinationLibrary.bundled().runnable + DestinationLibrary.bundled().pending,
        isInstalled: installed)
}

@Suite("Sequence planner")
struct SequencePlannerTests {
    @Test func stepsResolveAgainstTheCatalogue() {
        let plan = SequencePlanner.plan(
            Seq.backend(Seq.upper(output: "shout"), Seq.send("dest:notes", from: .output("shout"))),
            catalogue: bundledCatalogue())
        #expect(plan.isRunnable)
        #expect(plan.steps.map(\.title) == ["UPPERCASE", "Notes"])
        #expect(plan.steps[1].name == "Step 2 (Notes)")
    }

    @Test func unknownThingsAreFlagged() {
        let backend = Seq.backend(
            SequenceStep(kind: .contextAction("ctx:nope"), inputs: [SequenceInput(.text)]),
            SequenceStep(kind: .userCommand("user:gone")),
            Seq.send("dest:nowhere"))
        let plan = SequencePlanner.plan(backend, catalogue: bundledCatalogue())
        #expect(plan.steps[0].problems == [.unknownAction])
        #expect(plan.steps[1].problems == [.unknownCommand])
        #expect(plan.steps[2].problems == [.unknownDestination])
        #expect(plan.refusal == .blocked(step: 0, .unknownAction))
    }

    @Test func aMissingAppIsFlaggedForDestinationsAndMenuSteps() {
        let catalogue = bundledCatalogue(installed: { $0 != "com.apple.Notes" && $0 != "com.apple.Preview" })
        let plan = SequencePlanner.plan(Seq.backend(Seq.send("dest:notes"), Seq.menu()), catalogue: catalogue)
        #expect(plan.steps[0].problems == [.destinationAppNotInstalled(title: "Notes")])
        #expect(plan.steps[1].problems == [.appNotInstalled(bundleID: "com.apple.Preview")])
        #expect(!plan.isRunnable)
        #expect(plan.refusal?.message.contains("Notes is not installed") == true)
    }

    @Test func aStepThatContinuesOnFailureDoesNotBlockThePlan() {
        var send = Seq.send("dest:notes")
        send.continueOnFailure = true
        let catalogue = bundledCatalogue(installed: { $0 != "com.apple.Notes" })
        let plan = SequencePlanner.plan(Seq.backend(Seq.upper(), send), catalogue: catalogue)
        #expect(plan.steps[1].problems.count == 1)
        #expect(plan.isRunnable)
    }

    @Test func aStepNeedsInputsForWhatItRequires() {
        let noInputs = SequenceStep(kind: .contextAction("ctx:text.upper"))
        let plan = SequencePlanner.plan(Seq.backend(noInputs), catalogue: bundledCatalogue())
        #expect(plan.steps[0].problems == [.needsContext(.selectedText)])
        let files = SequenceStep(kind: .contextAction("ctx:text.upper"), inputs: [SequenceInput(.files)])
        #expect(
            SequencePlanner.plan(Seq.backend(files), catalogue: bundledCatalogue()).steps[0].problems == [
                .needsContext(.selectedText)
            ])
    }

    @Test func aDestinationThatCannotTakeThePayloadIsFlagged() {
        let plan = SequencePlanner.plan(
            Seq.backend(Seq.send("dest:notes", kind: .files)), catalogue: bundledCatalogue())
        #expect(plan.steps[0].problems == [.destinationCannotTake(title: "Notes")])
    }

    @Test func aDestinationThatAsksForAFolderCannotRunUnattended() {
        let chooser = FolderDestinations.chooser(move: true)
        let catalogue = SequenceCatalogue(destinations: [chooser])
        let plan = SequencePlanner.plan(Seq.backend(Seq.send(chooser.id.rawValue, kind: .files)), catalogue: catalogue)
        #expect(plan.steps[0].problems.contains(.needsFolderChoice(title: chooser.title)))
    }

    @Test func importedAndUntrustedThingsMakeThePlanUntrusted() {
        let backend = Seq.backend(Seq.upper())
        #expect(SequencePlanner.plan(backend, trust: .trusted, catalogue: bundledCatalogue()).trust == .trusted)
        let plan = SequencePlanner.plan(backend, trust: .untrusted, catalogue: bundledCatalogue())
        #expect(plan.trust == .untrusted)
        #expect(plan.refusal == .untrusted)
        #expect(!plan.isRunnable)

        var step = Seq.upper()
        step.trust = .untrusted
        #expect(SequencePlanner.plan(Seq.backend(step), catalogue: bundledCatalogue()).trust == .untrusted)
    }

    @Test func aReferencedCommandThatWaitsForApprovalTaintsTheWholeSequence() {
        let pending = UserCommand(
            title: "Imported thing", backend: .shell(ShellBackend(executable: "/bin/echo")), review: .pending)
        let step = SequenceStep(kind: .userCommand(pending.id))
        let plan = SequencePlanner.plan(
            Seq.backend(Seq.upper(), step), catalogue: bundledCatalogue(userCommands: [pending]))
        #expect(plan.trust == .untrusted)
        #expect(plan.steps[1].problems == [.commandPending(title: "Imported thing")])
        #expect(!plan.isRunnable)
    }

    @Test func approvedCommandsDoNotTaint() {
        let approved = UserCommand(title: "Mine", backend: .shell(ShellBackend(executable: "/bin/echo")))
        let plan = SequencePlanner.plan(
            Seq.backend(SequenceStep(kind: .userCommand(approved.id))),
            catalogue: bundledCatalogue(userCommands: [approved]))
        #expect(plan.trust == .trusted && plan.isRunnable)
    }

    @Test func structuralIssuesRefuseThePlan() {
        let plan = SequencePlanner.plan(Seq.backend(Seq.upper(input: .output("ghost"))), catalogue: bundledCatalogue())
        #expect(plan.refusal == .invalid(.unknownOutput(step: 1)))
    }

    @Test func questionsComeFromAskInputsInOrder() {
        let backend = Seq.backend(
            Seq.upper(input: .ask(prompt: "First?")),
            SequenceStep(kind: .shortcut(name: "X"), inputs: [SequenceInput(.text, from: .ask(prompt: "Second?"))]))
        let questions = SequencePlanner.plan(backend, catalogue: bundledCatalogue()).questions
        #expect(questions.map(\.prompt) == ["First?", "Second?"])
        #expect(questions.map(\.id) == ["s1.text", "s2.text"])
        #expect(questions.map(\.stepIndex) == [0, 1])
    }
}

@Suite("Sequence confirmation")
struct SequenceConfirmationTests {
    private func plan(_ steps: SequenceStep...) -> SequencePlan {
        SequencePlanner.plan(SequenceBackend(steps: steps), catalogue: bundledCatalogue())
    }

    @Test func aStepThatReplacesTheSelectionSaysSoUnlessItsResultIsCaptured() {
        let loose = plan(Seq.upper())
        #expect(loose.effects.map(\.kind) == [.replacesSelection])
        #expect(plan(Seq.upper(output: "a")).effects.isEmpty)
    }

    @Test func handingTextToAnAppAloneAsksForNothingButIsListedWhenSomethingElseAsks() {
        let quiet = plan(Seq.upper(output: "a"), Seq.send("dest:notes", from: .output("a")))
        #expect(quiet.effects.map(\.kind) == [.sendsToApp])
        #expect(!quiet.requiresConfirmation)
        let loud = plan(
            Seq.upper(output: "a"), Seq.send("dest:notes", from: .output("a")),
            Seq.link("https://example.com/?q={text}"))
        #expect(loud.requiresConfirmation)
        #expect(loud.confirmation.lines().count == 2)
        #expect(loud.confirmation.lines()[0].contains("Notes"))
    }

    @Test func pureTextStepsAskForNothing() {
        let plan = plan(
            Seq.upper(output: "a"),
            SequenceStep(
                kind: .contextAction("ctx:text.trim"), inputs: [SequenceInput(.text, from: .output("a"))],
                output: SequenceOutput(name: "b")))
        #expect(!plan.requiresConfirmation && plan.confirmation.lines().isEmpty)
    }

    @Test func everyExternalEffectIsListedInOrder() {
        let plan = plan(
            Seq.upper(output: "shout"),
            Seq.send("dest:mail", from: .output("shout")),
            Seq.send("dest:share", from: .output("shout")),
            Seq.send("dest:notes", from: .output("shout")),
            Seq.link("https://example.com/search?q={text}"),
            SequenceStep(kind: .shortcut(name: "Resize")),
            Seq.menu())
        #expect(plan.requiresConfirmation)
        let kinds = plan.effects.map(\.kind)
        #expect(kinds == [.mailDraft, .shareMenu, .sendsToApp, .opensLink, .runsShortcut, .menuSteps])
        #expect(plan.effects.map(\.step) == [2, 3, 4, 5, 6, 7])
        let lines = plan.confirmation.lines()
        #expect(lines.count == 6)
        #expect(lines[0].hasPrefix("2. ") && lines[0].contains("Mail"))
        #expect(lines[1] == "3. Open the Share menu")
        #expect(lines[3] == "5. Open a link to example.com")
        #expect(lines[4].contains("Resize"))
        #expect(plan.confirmation.heading == "Allow these 6 things?")
    }

    @Test func movingFilesAndWebDestinationsAreNamed() {
        let folder = URL(fileURLWithPath: "/tmp/Archive")
        let move = FolderDestinations.destination(for: folder, move: true)
        let copy = FolderDestinations.destination(for: folder, move: false)
        var web = Destination(
            id: "user:web", title: "Paste site", symbol: "globe", accepts: [.text],
            variants: [
                DestinationVariant(
                    action: ContextAction(
                        id: "user:web", title: "x", symbol: "star", requires: [.selectedText],
                        backend: .urlScheme(Seq.tpl("https://paste.example/new?body={text}")), output: .none))
            ], origin: .user)
        web.previewVerb = "Post to a paste site"
        let destinations = [move, copy, web].compactMap { $0 }
        let catalogue = SequenceCatalogue(destinations: destinations)
        let plan = SequencePlanner.plan(
            Seq.backend(
                Seq.send(destinations[0].id.rawValue, kind: .files),
                Seq.send(destinations[1].id.rawValue, kind: .files),
                Seq.send("user:web")),
            catalogue: catalogue)
        #expect(plan.effects.map(\.kind) == [.moveFiles, .copyFiles, .webAddress])
        #expect(plan.effects[2].line.contains("web address"))
    }

    @Test func scriptsAndSelectionReplacementAreListed() {
        let shell = UserCommand(
            title: "Run tool", backend: .shell(ShellBackend(executable: "/usr/bin/true")), output: .none)
        let replace = UserCommand(
            title: "Fix", requires: [.selectedText], backend: .function("text.upper"), output: .replaceSelection)
        let script = UserCommand(
            title: "Script", backend: .appleScript(AppleScriptBackend(source: "return 1")), output: .none)
        let catalogue = bundledCatalogue(userCommands: [shell, replace, script])
        let plan = SequencePlanner.plan(
            SequenceBackend(steps: [
                SequenceStep(kind: .userCommand(shell.id)),
                SequenceStep(kind: .userCommand(replace.id), inputs: [SequenceInput(.text)]),
                SequenceStep(kind: .userCommand(script.id)),
            ]), catalogue: catalogue)
        #expect(plan.effects.map(\.kind) == [.runsProgram, .replacesSelection, .runsAppleScript])
    }

    @Test func anActionThatAsksFirstStillAsksOnce() {
        let risky = UserCommand(
            title: "Delete things", requires: [.selectedText], backend: .function("text.upper"), output: .clipboard,
            needsConfirmation: true)
        let plan = SequencePlanner.plan(
            SequenceBackend(steps: [SequenceStep(kind: .userCommand(risky.id), inputs: [SequenceInput(.text)])]),
            catalogue: bundledCatalogue(userCommands: [risky]))
        #expect(plan.effects.map(\.kind) == [.asksFirst])
        #expect(plan.confirmation.heading == "Allow this?")
    }

    @Test func longListsAreCutWithACount() {
        let steps = (0..<12).map { _ in Seq.menu() }
        let plan = SequencePlanner.plan(SequenceBackend(steps: steps), catalogue: bundledCatalogue())
        let lines = plan.confirmation.lines(maxLines: 8)
        #expect(lines.count == 9 && lines.last == "and 4 more")
    }

    @Test func linkWordingNeverIncludesAValue() {
        let link = Seq.link("https://example.com/s?q={text}&k=SECRET")
        let plan = plan(link)
        #expect(plan.effects[0].line == "Open a link to example.com")
        let custom = Seq.link("dash://?query={text}")
        #expect(plan.effects.count == 1)
        #expect(SequenceEffects.linkDescription(Seq.tpl("dash://?query={text}")) == "a link in the app for dash")
        _ = custom
    }
}
