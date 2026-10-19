import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Sequence builder in the palette")
struct SequenceBuilderTests {
    private let app = TargetApp(pid: 100, bundleID: "com.example.editor", name: "Editor")

    private struct Rig {
        let model: PaletteModel
        let center: SequenceCenter
        let context: ContextActionCenter
        let send: SendToCenter
        let runner: FakeStepRunner
        let store: UserCommandStore
        let tracker: FrontmostAppTracker
    }

    private func rig(
        runner: FakeStepRunner? = nil,
        installed: Set<String> = ["com.apple.Notes", "com.apple.mail", "com.apple.Preview"]
    ) -> Rig {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        tracker.pin(app)
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        let model = PaletteModel(menus: menus, tracker: tracker)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-seq-\(UUID().uuidString)")
        let recorder = SendRecorder()
        recorder.installed = installed
        let send = SendToCenter(
            library: .bundled(), services: recorder.services,
            folders: SendFolderStore(url: directory.appendingPathComponent("f.json")))
        model.attachSend(send)
        let library = ActionPackLibrary.bundled()
        let context = ContextActionCenter(
            library: library, engine: ActionEngine(functions: library.functions, services: ServiceRecorder().services))
        context.attach(to: model)
        let store = UserCommandStore(directory: directory.appendingPathComponent("commands"))
        let fake = runner ?? FakeStepRunner { _, _, _ in .done(produced: "RESULT") }
        let center = SequenceCenter(
            store: store, runner: fake,
            catalogue: {
                SequenceCatalogue(
                    contextActions: library.actions, userCommands: store.commands,
                    destinations: send.sequenceDestinations,
                    isInstalled: { installed.contains($0) })
            })
        model.attachSequences(center)
        menus.seed(MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: app.bundleID))
        return Rig(
            model: model, center: center, context: context, send: send, runner: fake, store: store, tracker: tracker)
    }

    private func feed(_ rig: Rig, _ values: ContextValues = ContextValues(selectedText: "hello world")) {
        let snapshot = ContextSnapshot(
            appName: "Editor", bundleID: "com.example.editor", pid: 100, capturedAt: Date(), values: values)
        rig.context.update(with: snapshot)
        rig.send.update(with: snapshot)
        rig.center.update(with: snapshot)
    }

    private func row(_ rig: Rig, _ id: String) -> Command? { rig.model.results.first { $0.command.id == id }?.command }

    private func titles(_ rig: Rig) -> [String] { rig.model.results.map(\.command.title) }

    @discardableResult
    private func add(_ rig: Rig, _ id: String) -> SequenceAddResult {
        guard let command = row(rig, id) else { return .refused("no such row \(id)") }
        return rig.model.addToSequence(command)
    }

    /// Opens the draft level the way the person would: Return on the top row.
    private func openDraft(_ rig: Rig) async {
        guard let top = rig.model.results.first?.command else { return }
        _ = await rig.model.run(top)
    }

    // MARK: The draft row

    @Test func thereIsNoDraftRowUntilSomethingIsAdded() {
        let rig = rig()
        feed(rig)
        #expect(!titles(rig).contains { $0.hasPrefix("Sequence draft") })
        #expect(rig.model.draftRowCount == 0 && rig.model.draftStepCount == 0)
    }

    @Test func addingARowMakesTheDraftRowHeadTheList() {
        let rig = rig()
        feed(rig)
        #expect(add(rig, "ctx:text.upper") == .added(steps: 1))
        #expect(rig.model.results.first?.command.title == "Sequence draft (1 step)")
        #expect(rig.model.draftRowCount == 1 && rig.model.draftStepCount == 1)
        add(rig, "send:text>dest:notes")
        // No direct row exists before a destination has been used, so go through the list for this one.
        #expect(rig.model.results.first?.command.title == "Sequence draft (1 step)")
    }

    @Test func theDraftRowIsFoundBySearchToo() {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        rig.model.query = "draft"
        #expect(rig.model.results.contains { $0.command.title == "Sequence draft (1 step)" })
        #expect(rig.model.draftRowCount == 0)
    }

    @Test func theDraftSurvivesTheNextOpeningOfThePanel() {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        rig.model.prepareForOpen()
        feed(rig, ContextValues(selectedText: "other"))
        #expect(rig.model.results.first?.command.title == "Sequence draft (1 step)")
    }

    @Test func theTopPredictionStillMeansTheFirstPredictedRow() {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        #expect(rig.model.topPrediction == nil)
    }

    // MARK: Adding

    @Test func menuItemsContextActionsAndDestinationsCanBeAdded() async throws {
        let rig = rig()
        feed(rig)
        let menu = try #require(rig.model.results.first { $0.command.source == .menuItem(bundleID: app.bundleID) })
            .command
        #expect(rig.model.addToSequence(menu) == .added(steps: 1))
        #expect(add(rig, "ctx:text.upper") == .added(steps: 2))
        // Open the destination list and add Notes from it.
        let generic = try #require(row(rig, "send:text"))
        _ = await rig.model.run(generic)
        let notes = try #require(row(rig, "send:text>dest:notes"))
        #expect(rig.model.addToSequence(notes) == .added(steps: 3))
        let kinds = rig.center.steps.map(\.kind.tag)
        #expect(kinds == ["uiSteps", "contextAction", "destination"])
    }

    // MARK: Step ids

    private func menuRow(_ rig: Rig, _ title: String) -> Command? {
        rig.model.results.first { $0.command.title == title && $0.command.source == .menuItem(bundleID: app.bundleID) }?
            .command
    }

    private func filesContext() -> ContextValues {
        ContextValues(selectedText: "hello", selectedFiles: [URL(fileURLWithPath: "/tmp")])
    }

    private func editorRig() -> Rig {
        rig(installed: ["com.apple.Notes", "com.apple.mail", "com.apple.Preview", "com.example.editor"])
    }

    private func menuStepIDs(_ rig: Rig) -> [String] {
        rig.center.steps.flatMap { step -> [String] in
            if case .uiSteps(let backend) = step.kind { backend.steps.map(\.id) } else { [] }
        }
    }

    @Test func aDraftOfDifferentKindsOfStepsValidates() throws {
        let rig = editorRig()
        feed(rig, filesContext())
        #expect(rig.model.addToSequence(try #require(menuRow(rig, "New Folder"))) == .added(steps: 1))
        #expect(add(rig, "ctx:files.copy-path") == .added(steps: 2))
        #expect(rig.model.addToSequence(try #require(menuRow(rig, "Show Preview"))) == .added(steps: 3))
        let ids = rig.center.steps.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(SequenceValidator.issues(in: SequenceBackend(steps: rig.center.steps)).isEmpty)
        #expect(rig.center.plan().refusal == nil)
    }

    /// The rows of the draft level, steps only, the way the palette lists them.
    private func stepRows(_ rig: Rig) -> [Command] {
        rig.model.results.map(\.command).filter {
            if case .sequence(.step) = $0.source { true } else { false }
        }
    }

    /// The flow of the bug report: menu items from the app menu added one after another, one of them twice.
    private func addFinderMenuItems(_ rig: Rig) throws {
        for title in ["New Folder", "Settings\u{2026}", "Settings\u{2026}", "About Finder"] {
            let command = try #require(menuRow(rig, title))
            let expected = rig.center.steps.count + 1
            #expect(rig.model.addToSequence(command) == .added(steps: expected))
        }
    }

    @Test func everyMenuItemAddedIsItsOwnStepWithItsOwnId() throws {
        let rig = editorRig()
        feed(rig, filesContext())
        try addFinderMenuItems(rig)
        #expect(rig.center.steps.count == 4 && rig.model.draftStepCount == 4)
        let ids = rig.center.steps.map(\.id)
        #expect(Set(ids).count == 4)
        for step in rig.center.steps {
            guard case .uiSteps(let backend) = step.kind else {
                Issue.record("expected a menu step")
                return
            }
            #expect(backend.steps.count == 1)
        }
        #expect(SequenceValidator.issues(in: SequenceBackend(steps: rig.center.steps)).isEmpty)
        #expect(rig.center.plan().refusal == nil)
    }

    @Test func theDraftLevelListsEveryStepNumberedOneToN() async throws {
        let rig = editorRig()
        feed(rig, filesContext())
        try addFinderMenuItems(rig)
        add(rig, "ctx:files.copy-path")
        #expect(rig.model.results.first?.command.title == "Sequence draft (5 steps)")
        await openDraft(rig)
        let rows = stepRows(rig)
        #expect(rows.count == 5)
        #expect(rows.enumerated().allSatisfy { $1.title.hasPrefix("\($0 + 1). ") })
        #expect(Set(rows.map(\.id)).count == 5)
        // The two Settings rows read the same but are two rows.
        #expect(rows[1].title.dropFirst(3) == rows[2].title.dropFirst(3))
        #expect(rig.model.results.count == 8)
    }

    @Test func theConfirmationNumbersTheStepsOneToN() async throws {
        let rig = editorRig()
        feed(rig, filesContext())
        try addFinderMenuItems(rig)
        await openDraft(rig)
        let closes = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(!closes && rig.runner.ids.isEmpty)
        let pending = try #require(rig.model.sequencePending)
        #expect(pending.heading == "Allow these 4 things?")
        #expect(pending.lines.enumerated().allSatisfy { $1.hasPrefix("\($0 + 1). ") })
        #expect(await rig.model.confirmPending())
        #expect(rig.runner.ids == rig.center.steps.map(\.id))
    }

    @Test func theSameCommandAddedTwiceIsTwoStepsThatDeleteAndMoveOneByOne() async throws {
        let rig = editorRig()
        feed(rig, filesContext())
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.upper")
        rig.model.addToSequence(try #require(menuRow(rig, "New Folder")))
        rig.model.addToSequence(try #require(menuRow(rig, "New Folder")))
        let ids = rig.center.steps.map(\.id)
        #expect(ids.count == 4 && Set(ids).count == 4)
        await openDraft(rig)
        // Highlight the last step and move it up, then delete the new first one.
        rig.model.moveSelection(by: 6)
        #expect(rig.model.selectedStepID == ids[3])
        rig.model.moveSelectedStep(by: -1)
        #expect(rig.center.steps.map(\.id) == [ids[0], ids[1], ids[3], ids[2]])
        #expect(rig.model.selectedStepID == ids[3])
        rig.model.moveSelection(by: -1)
        #expect(rig.model.selectedStepID == ids[1])
        rig.model.deleteSelectedStep()
        #expect(rig.center.steps.map(\.id) == [ids[0], ids[3], ids[2]])
        let rows = stepRows(rig)
        #expect(rows.enumerated().allSatisfy { $1.title.hasPrefix("\($0 + 1). ") })
        // A step added after a delete never takes a used id.
        _ = rig.model.goBack()
        add(rig, "ctx:text.upper")
        #expect(!ids.contains(rig.center.steps.last?.id ?? ""))
    }

    @Test func aMixOfMenuItemsActionsAndDestinationsRunsAndSaves() async throws {
        let rig = editorRig()
        feed(rig, filesContext())
        rig.model.addToSequence(try #require(menuRow(rig, "New Folder")))
        add(rig, "ctx:text.upper")
        rig.model.addToSequence(try #require(menuRow(rig, "Show Preview")))
        rig.model.addToSequence(try #require(menuRow(rig, "Show Preview")))
        let generic = try #require(row(rig, "send:text"))
        _ = await rig.model.run(generic)
        add(rig, "send:text>dest:notes")
        _ = rig.model.goBack()
        add(rig, "ctx:files.copy-path")
        #expect(rig.center.steps.count == 6)
        let ids = rig.center.steps.map(\.id)
        #expect(Set(ids).count == 6)
        #expect(SequenceValidator.issues(in: SequenceBackend(steps: rig.center.steps)).isEmpty)
        await openDraft(rig)
        #expect(await rig.model.run(try #require(row(rig, "seq:run"))) == false)
        let lines = try #require(rig.model.sequencePending?.lines)
        #expect(lines.count >= 3 && lines.allSatisfy { $0.first?.isNumber == true })
        #expect(await rig.model.confirmPending())
        #expect(rig.runner.ids == ids)
        // And saving the same draft stores every step.
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        rig.center.form.name = "Mixed"
        #expect(rig.model.saveSequence())
        #expect(rig.store.commands.first?.sequenceBackend?.steps.map(\.id) == ids)
    }

    @Test func removingAStepBetweenTwoMenuStepsStillValidates() throws {
        let rig = editorRig()
        feed(rig, filesContext())
        rig.model.addToSequence(try #require(menuRow(rig, "New Folder")))
        add(rig, "ctx:files.copy-path")
        rig.model.addToSequence(try #require(menuRow(rig, "Show Preview")))
        rig.center.delete(stepID: rig.center.steps[1].id)
        rig.model.addToSequence(try #require(menuRow(rig, "Show Path Bar")))
        #expect(SequenceValidator.issues(in: SequenceBackend(steps: rig.center.steps)).isEmpty)
        #expect(rig.center.plan().refusal == nil)
    }

    @Test func deletingAndReAddingNeverReusesAnId() throws {
        let rig = editorRig()
        feed(rig, filesContext())
        var seen = Set<String>()
        for _ in 0..<4 {
            add(rig, "ctx:text.upper")
            let id = try #require(rig.center.steps.last?.id)
            #expect(seen.insert(id).inserted)
            rig.center.delete(stepID: id)
        }
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.upper")
        let ids = rig.center.steps.map(\.id)
        #expect(Set(ids).count == 2 && Set(ids).isDisjoint(with: seen))
    }

    @Test func aDiscardedDraftDoesNotReuseIdsEither() {
        let rig = editorRig()
        feed(rig)
        add(rig, "ctx:text.upper")
        let first = rig.center.steps[0].id
        rig.center.discard()
        add(rig, "ctx:text.upper")
        #expect(rig.center.steps[0].id != first)
    }

    @Test func theGenericSendRowCannotBeAdded() throws {
        let rig = rig()
        feed(rig)
        let generic = try #require(row(rig, "send:text"))
        let result = rig.model.addToSequence(generic)
        #expect(result == .refused("Choose a destination first, then add it."))
        #expect(rig.model.sequenceFailure == "Choose a destination first, then add it.")
        #expect(rig.center.steps.isEmpty)
    }

    @Test func aSequenceCommandCannotBeAddedToASequence() throws {
        let rig = rig()
        let inner = CommandSequence(title: "Inner", steps: [Seq.upper(output: "a")]).userCommand()
        try rig.store.create(inner)
        rig.context.setUserCommands(rig.store.commands)
        feed(rig)
        let row = try #require(row(rig, inner.id.rawValue))
        #expect(rig.model.addToSequence(row) == .refused("A sequence cannot run another sequence."))
    }

    @Test func aSequenceHasAtMostTwentySteps() {
        let rig = rig()
        feed(rig)
        for _ in 0..<SequenceLimits.maxSteps { add(rig, "ctx:text.upper") }
        #expect(rig.center.steps.count == SequenceLimits.maxSteps)
        #expect(add(rig, "ctx:text.upper") == .refused("A sequence can have at most 20 steps."))
    }

    @Test func menuItemsInPrivateMenusAreRefusedWithTheReason() {
        let rig = rig()
        let recent = Command(
            id: "1.2", title: "Report.pdf", path: ["File", "Open Recent"],
            source: .menuItem(bundleID: "com.apple.Preview"))
        let result = rig.model.addToSequence(recent)
        guard case .refused(let message) = result else {
            Issue.record("expected a refusal")
            return
        }
        #expect(message.contains("recent items"))
    }

    // MARK: Chaining

    @Test func aStepReadsTheResultOfTheStepBeforeWhenItGivesText() throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        let steps = rig.center.steps
        #expect(steps[0].output?.name == "from-\(steps[0].id)")
        #expect(steps[1].inputs == [SequenceInput(.text, from: .output("from-\(steps[0].id)"))])
        #expect(rig.center.plan().isRunnable)
    }

    @Test func aStepAfterOneThatGivesNoTextReadsTheSelection() {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "https://example.com"))
        add(rig, "ctx:text.open-link")
        add(rig, "ctx:text.upper")
        let steps = rig.center.steps
        #expect(steps[0].output == nil)
        #expect(steps[1].inputs == [SequenceInput(.text)])
    }

    @Test func aStepCanBeSwitchedToTheSelectionOrToAQuestion() {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        let second = rig.center.steps[1].id
        rig.center.setUsesSelection(true, stepID: second)
        #expect(rig.center.steps[1].inputs == [SequenceInput(.text)] && rig.center.steps[0].output == nil)
        rig.center.setAsking(true, stepID: second)
        #expect(rig.center.isAsking(stepID: second))
        #expect(rig.center.steps[1].inputs.count == 1)
        rig.center.setAsking(false, stepID: second)
        rig.center.setUsesSelection(false, stepID: second)
        #expect(rig.center.steps[1].inputs == [SequenceInput(.text, from: .output("from-\(rig.center.steps[0].id)"))])
    }

    @Test func deletingTheStepBeforeSendsTheNextOneBackToTheSelection() {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        rig.center.delete(stepID: rig.center.steps[0].id)
        #expect(rig.center.steps.count == 1)
        #expect(rig.center.steps[0].inputs == [SequenceInput(.text)])
        #expect(rig.center.steps[0].output == nil)
    }

    @Test func movingAStepRechainsTheOthers() {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        add(rig, "ctx:text.trim")
        let ids = rig.center.steps.map(\.id)
        rig.center.move(stepID: ids[2], by: -1)
        #expect(rig.center.steps.map(\.id) == [ids[0], ids[2], ids[1]])
        #expect(rig.center.steps[1].inputs == [SequenceInput(.text, from: .output("from-\(ids[0])"))])
        #expect(rig.center.steps[2].inputs == [SequenceInput(.text, from: .output("from-\(ids[2])"))])
        // Past either end nothing moves.
        rig.center.move(stepID: ids[0], by: -1)
        rig.center.move(stepID: ids[1], by: 1)
        #expect(rig.center.steps.map(\.id) == [ids[0], ids[2], ids[1]])
        rig.center.move(stepID: ids[1], by: -1)
        #expect(rig.center.steps.map(\.id) == [ids[0], ids[1], ids[2]])
    }

    // MARK: The level

    @Test func returnOnTheDraftRowOpensTheDraftLevelInTheSamePanel() async {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        rig.model.query = "seq"
        guard let top = rig.model.results.first?.command else { return }
        let closes = await rig.model.run(top)
        #expect(!closes)
        #expect(rig.model.sequenceLevel == .steps && rig.model.sequenceLevel?.title == "Sequence draft")
        #expect(rig.model.query.isEmpty)
        #expect(titles(rig).prefix(3) == ["Run sequence", "Save as command...", "Discard draft"])
        #expect(Array(titles(rig).dropFirst(3)) == ["1. UPPERCASE", "2. lowercase"])
        #expect(rig.model.content == .results)
    }

    @Test func stepRowsSayWhereTheirInputComesFrom() async {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        await openDraft(rig)
        let details = rig.model.results.map(\.command.detail)
        #expect(details[3] == "Uses the selected text")
        #expect(details[4] == "Uses the result of step 1")
    }

    @Test func escapeGoesBackOneLevelAndRestoresTheQuery() async {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        rig.model.query = "seq"
        await openDraft(rig)
        #expect(rig.model.goBack())
        #expect(rig.model.sequenceLevel == nil)
        #expect(rig.model.query == "seq")
        #expect(!rig.model.goBack())
    }

    @Test func theSelectedStepIsKnownAndEditableByKeyboardRoutes() async {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        add(rig, "ctx:text.trim")
        await openDraft(rig)
        rig.model.moveSelection(by: 4)
        let second = rig.center.steps[1].id
        #expect(rig.model.selectedStepID == second)
        rig.model.moveSelectedStep(by: -1)
        #expect(rig.center.steps.map(\.id).first == second)
        #expect(rig.model.selectedStepID == second)
        rig.model.deleteSelectedStep()
        #expect(rig.center.steps.count == 2)
        #expect(!rig.center.steps.contains { $0.id == second })
        // The highlight stays in the list instead of vanishing.
        #expect(rig.model.selected != nil)
    }

    @Test func deletingTheLastStepLeavesTheLevel() async {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        await openDraft(rig)
        rig.model.moveSelection(by: 3)
        rig.model.deleteSelectedStep()
        #expect(rig.model.sequenceLevel == nil)
        #expect(!titles(rig).contains { $0.hasPrefix("Sequence draft") })
    }

    @Test func deletingStepsOneByOneEndsOnTheMainListWithTheOldQuery() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        add(rig, "ctx:text.trim")
        rig.model.query = "seq"
        await openDraft(rig)
        #expect(rig.model.sequenceLevel == .steps && rig.model.query.isEmpty)
        var deleted = 0
        rig.model.moveSelection(by: 3)
        // Backspace keeps working as long as a step is highlighted; it must be after every deletion.
        while rig.model.sequenceLevel != nil {
            let id = try #require(rig.model.selectedStepID)
            rig.model.deleteSelectedStep()
            #expect(!rig.center.steps.contains { $0.id == id })
            deleted += 1
            #expect(deleted <= 3)
        }
        #expect(deleted == 3)
        #expect(rig.center.steps.isEmpty && !rig.center.isInLevel)
        #expect(rig.model.sequenceLevel == nil && rig.model.draftStepCount == 0)
        #expect(rig.model.query == "seq")
        #expect(rig.model.content != .sequenceSave && rig.model.sequenceLevel == nil)
        #expect(!titles(rig).contains { $0.hasPrefix("Sequence draft") || $0 == "Run sequence" })
    }

    @Test func deletingTheLastStepFromTheActionsAlsoLeaves() async {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        await openDraft(rig)
        rig.model.moveSelection(by: 3)
        rig.model.deleteSelectedStep()
        #expect(rig.model.sequenceLevel == nil && rig.model.content == .results)
        #expect(!rig.model.goBack())
    }

    @Test func discardClearsTheDraftAndTheLevel() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        rig.model.query = "seq"
        await openDraft(rig)
        let discard = try #require(row(rig, "seq:discard"))
        _ = await rig.model.run(discard)
        #expect(rig.center.steps.isEmpty && rig.model.sequenceLevel == nil)
        #expect(rig.model.query == "seq")
        #expect(!titles(rig).contains { $0.hasPrefix("Sequence draft") })
    }

    // MARK: Running

    @Test func aRunWithNoEffectsRunsAtOnceOnTheSensedContext() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "sensed"))
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.count")
        await openDraft(rig)
        let run = try #require(row(rig, "seq:run"))
        let closes = await rig.model.run(run)
        #expect(closes)
        #expect(rig.runner.ids == [rig.center.steps[0].id, rig.center.steps[1].id])
        #expect(rig.runner.calls[0].values.selectedText == "sensed")
        #expect(rig.runner.calls[1].values.selectedText == "RESULT")
        #expect(rig.center.stepStates.values.allSatisfy { $0 == .done })
    }

    @Test func externalEffectsShowOneCombinedConfirmationFirst() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        let generic = try #require(row(rig, "send:text"))
        _ = await rig.model.run(generic)
        add(rig, "send:text>dest:mail")
        add(rig, "send:text>dest:notes")
        _ = rig.model.goBack()
        await openDraft(rig)
        let run = try #require(row(rig, "seq:run"))
        let closes = await rig.model.run(run)
        #expect(!closes && rig.runner.ids.isEmpty)
        let pending = try #require(rig.model.sequencePending)
        #expect(pending.heading == "Allow these 2 things?")
        #expect(pending.lines.count == 2 && pending.lines[0].hasPrefix("2. ") && pending.lines[1].hasPrefix("3. "))
        #expect(rig.model.hasPendingConfirmation)
        let finished = await rig.model.confirmPending()
        #expect(finished)
        #expect(rig.runner.ids.count == 3)
    }

    @Test func typingOrEscapeDropsTheConfirmation() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        let generic = try #require(row(rig, "send:text"))
        _ = await rig.model.run(generic)
        add(rig, "send:text>dest:mail")
        _ = rig.model.goBack()
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(rig.model.sequencePending != nil)
        rig.model.query = "m"
        #expect(rig.model.sequencePending == nil && rig.runner.ids.isEmpty)
        rig.model.query = ""
        _ = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(rig.model.goBack())
        #expect(rig.model.sequencePending == nil && rig.model.sequenceLevel == .steps)
    }

    @Test func askMeAtRunTimeAsksInTheSearchFieldBeforeAnythingRuns() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "https://example.com"))
        add(rig, "ctx:text.open-link")
        rig.center.setAsking(true, stepID: rig.center.steps[0].id)
        await openDraft(rig)
        let closes = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(!closes)
        let asking = try #require(rig.model.sequenceAsking)
        #expect(asking.number == 1 && asking.total == 1 && asking.prompt.hasPrefix("Text for "))
        // A blank answer is refused and the question stays.
        rig.model.query = "   "
        #expect(await rig.model.runSelected() == false)
        #expect(rig.model.sequenceAsking != nil && rig.model.sequenceFailure != nil)
        rig.model.query = "https://example.com"
        let done = await rig.model.runSelected()
        #expect(done)
        #expect(rig.runner.calls.first?.values.selectedText == "https://example.com")
    }

    @Test func escapeWhileAskedStopsTheRun() async throws {
        let rig = rig()
        feed(rig, ContextValues(selectedText: "https://example.com"))
        add(rig, "ctx:text.open-link")
        rig.center.setAsking(true, stepID: rig.center.steps[0].id)
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(rig.model.goBack())
        #expect(rig.model.sequenceAsking == nil && rig.model.sequenceLevel == .steps)
        #expect(rig.runner.ids.isEmpty)
    }

    @Test func aFailureStaysOnScreenWithTheStepsMarkedAndTheDraftIntact() async throws {
        let runner = FakeStepRunner { planned, _, _ in
            planned.index == 1 ? .failed(.backend("The action failed.")) : .done(produced: "RESULT")
        }
        let rig = rig(runner: runner)
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        add(rig, "ctx:text.count")
        await openDraft(rig)
        let closes = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(!closes)
        #expect(rig.model.sequenceFailure == "Step 2 (lowercase) stopped the sequence: the action failed.")
        let details = rig.model.results.map(\.command.detail)
        #expect(details[3] == "Done" && details[4] == "Stopped: the action failed" && details[5] == "Skipped")
        #expect(rig.center.steps.count == 3)
        // Return tries again.
        _ = await rig.model.run(try #require(row(rig, "seq:run")))
        #expect(rig.runner.ids.count == 4)
    }

    @Test func aRunCanBeCancelledWithEscape() async throws {
        let runner = FakeStepRunner { _, _, _ in
            do { try await Task.sleep(for: .seconds(30)) } catch { return .failed(.cancelled) }
            return .done(produced: "x")
        }
        let rig = rig(runner: runner)
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.count")
        await openDraft(rig)
        let run = try #require(row(rig, "seq:run"))
        let running = Task { await rig.model.run(run) }
        // Wait until the first step is really in flight; a loaded machine can be slow to start it.
        for _ in 0..<100 where rig.runner.ids.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(rig.center.isRunning)
        #expect(rig.model.goBack())
        let closes = await running.value
        #expect(!closes)
        #expect(rig.runner.ids.count == 1)
        guard case .finished(let report)? = rig.center.phase else {
            Issue.record("expected a finished run")
            return
        }
        #expect(report.outcome == .cancelled)
    }

    // MARK: Saving

    @Test func saveAsCommandOpensTheFormWithASuggestedName() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        #expect(rig.model.sequenceLevel == .save && rig.model.content == .sequenceSave)
        #expect(rig.center.form.name == "UPPERCASE, lowercase")
        // The symbol comes from the first step, and the sequence symbol is offered right after it.
        #expect(rig.center.form.symbol == "textformat.size.larger")
        #expect(rig.center.form.suggestedSymbols == ["textformat.size.larger", "square.stack.3d.up"])
        #expect(rig.model.goBack() && rig.model.sequenceLevel == .steps)
    }

    private func openSaveForm(_ rig: Rig) async throws {
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
    }

    @Test func aMenuStepSuggestsASymbolFromItsMenuPath() async throws {
        let rig = editorRig()
        feed(rig)
        rig.model.addToSequence(try #require(menuRow(rig, "New Folder")))
        try await openSaveForm(rig)
        let suggested = try #require(rig.center.form.suggestedSymbols.first)
        #expect(suggested != "questionmark.circle")
        #expect(rig.center.form.symbol == suggested)
        #expect(rig.center.form.suggestedSymbols.contains("square.stack.3d.up"))
    }

    @Test func theSymbolSearchKeepsTheChoiceOnWhatIsShown() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        try await openSaveForm(rig)
        rig.center.form.symbolQuery = "mail"
        let shown = rig.center.symbolSections.flatMap(\.symbols).map(\.name)
        #expect(shown.contains("envelope"))
        #expect(rig.center.form.symbol == shown.first)
        rig.center.moveSymbol(.right)
        #expect(rig.center.form.symbol == shown[1])
        // Clearing the search keeps the choice.
        let chosen = rig.center.form.symbol
        rig.center.form.symbolQuery = ""
        #expect(rig.center.form.symbol == chosen)
    }

    @Test func aTypedSymbolNameIsUsedWhenItIsReal() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        try await openSaveForm(rig)
        rig.center.form.symbolQuery = "folder.badge.gearshape"
        #expect(rig.center.symbolSections.map(\.title) == ["Custom"])
        #expect(rig.center.form.symbol == "folder.badge.gearshape")
        rig.center.form.name = "Raw name"
        #expect(rig.model.saveSequence())
        #expect(rig.store.commands.first?.symbol == "folder.badge.gearshape")
    }

    @Test func aNameThatIsNoSymbolOffersNothingAndKeepsTheChoice() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        try await openSaveForm(rig)
        let before = rig.center.form.symbol
        rig.center.form.symbolQuery = "zzzzqx"
        #expect(rig.center.symbolSections.isEmpty)
        #expect(rig.center.form.symbol == before)
        #expect(!rig.center.moveSymbol(.right))
    }

    @Test func arrowKeysWalkTheGridAndStopAtItsEdges() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        try await openSaveForm(rig)
        // The first symbol is the suggestion: nothing above it.
        #expect(!rig.center.moveSymbol(.up) && !rig.center.moveSymbol(.left))
        #expect(rig.center.moveSymbol(.right))
        #expect(rig.center.form.symbol == "square.stack.3d.up")
        #expect(rig.center.moveSymbol(.down))
        #expect(rig.center.moveSymbol(.left))
    }

    @Test func savingWritesAnOrdinaryCommandUnderYourCommands() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        let steps = rig.center.steps
        rig.model.query = "seq"
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        rig.center.form.name = "Shout then whisper"
        rig.center.form.alias = "  SW "
        rig.center.form.symbol = "megaphone"
        #expect(rig.model.saveSequence())
        let saved = try #require(rig.store.commands.first)
        #expect(saved.title == "Shout then whisper" && saved.aliases == ["sw"] && saved.symbol == "megaphone")
        #expect(
            saved.sequenceBackend?.steps
                == steps.map {
                    var step = $0
                    step.trust = .trusted
                    return step
                })
        #expect(saved.review == .approved)
        // The draft is gone, the query is back and a notice says where it went.
        #expect(rig.center.steps.isEmpty && rig.model.sequenceLevel == nil && rig.model.query == "seq")
        #expect(rig.model.sequenceNotice == "Saved Shout then whisper under Your commands")
        // And it is listed like any command of yours.
        rig.context.setUserCommands(rig.store.commands)
        feed(rig)
        rig.model.query = ""
        #expect(rig.model.results.contains { $0.command.title == "Shout then whisper" && $0.command.aliases == ["sw"] })
    }

    @Test func aSavedSequenceThatSendsAsksBeforeItRuns() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        let generic = try #require(row(rig, "send:text"))
        _ = await rig.model.run(generic)
        add(rig, "send:text>dest:mail")
        _ = rig.model.goBack()
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        rig.center.form.name = "Mail it"
        #expect(rig.model.saveSequence())
        #expect(rig.store.commands.first?.needsConfirmation == true)
    }

    @Test func aBadNameAliasOrShortcutIsReportedAndNothingIsLost() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        try rig.store.create(shoutCommand(title: "Taken", aliases: ["taken"]))
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        rig.center.form.name = "  "
        #expect(!rig.model.saveSequence() && rig.model.sequenceFailure == "Give the command a title.")
        rig.center.form.name = "Mine"
        rig.center.form.alias = "taken"
        #expect(!rig.model.saveSequence() && rig.model.sequenceFailure?.contains("already belongs to") == true)
        rig.center.form.alias = "Bad Alias!"
        #expect(!rig.model.saveSequence())
        rig.center.form.alias = ""
        rig.center.form.symbol = "has spaces"
        #expect(!rig.model.saveSequence())
        #expect(rig.center.steps.count == 1 && rig.model.sequenceLevel == .save)
        rig.center.form.symbol = "star"
        #expect(rig.model.saveSequence())
    }

    @Test func aSavedSequenceRoundTripsThroughTheFileAndRunsAfterReload() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        add(rig, "ctx:text.lower")
        let steps = rig.center.steps
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        rig.center.form.name = "Round trip"
        rig.center.form.hotkey = HotKeyCombo(keyCode: 6, modifiers: [.control, .option])
        #expect(rig.model.saveSequence())
        let reloaded = UserCommandStore(directory: rig.store.directory)
        let command = try #require(reloaded.commands.first)
        #expect(command.hotkey == HotKeyCombo(keyCode: 6, modifiers: [.control, .option]))
        #expect(CommandSequence(command: command)?.steps == steps)
    }

    @Test func aSecondCommandCannotTakeTheSameShortcut() async throws {
        let rig = rig()
        feed(rig)
        add(rig, "ctx:text.upper")
        let combo = HotKeyCombo(keyCode: 6, modifiers: [.control, .option])
        try rig.store.create(shoutCommand(title: "Other", hotkey: combo))
        await openDraft(rig)
        _ = await rig.model.run(try #require(row(rig, "seq:save")))
        rig.center.form.name = "Mine"
        rig.center.form.hotkey = combo
        #expect(!rig.model.saveSequence())
        #expect(rig.model.sequenceFailure == "That shortcut is already used by Other.")
    }
}

@MainActor
@Suite("Sequence builder: steps from outside and failure policy")
struct SequenceBuilderExtrasTests {
    private func center() -> SequenceCenter {
        let library = ActionPackLibrary.bundled()
        return SequenceCenter(
            store: nil, runner: FakeStepRunner(),
            catalogue: {
                SequenceCatalogue(
                    contextActions: library.actions, destinations: DestinationLibrary.bundled().destinations)
            })
    }

    private func recorded(app: String = "com.apple.Preview") -> [UIStep] {
        [UIStep(app: app, locators: [.shortcut(key: "E", modifiers: [.command, .shift])], description: "Export")]
    }

    @Test func recordedMenuStepsJoinTheDraftAsOneStep() {
        let center = center()
        #expect(center.add(uiSteps: recorded()) == .added(steps: 1))
        #expect(center.steps.count == 1 && center.steps[0].kind.tag == "uiSteps" && center.steps[0].trust == .trusted)
        #expect(center.plan().trust == .trusted && center.plan().steps.count == 1)
    }

    @Test func recordedStepsAreCheckedAgainstTheStepEngineRules() {
        let center = center()
        let apple = [UIStep(app: "com.apple.Preview", locators: [.menuPath(["Apple", "About"])], description: "x")]
        guard case .refused = center.add(uiSteps: apple) else {
            Issue.record("expected a refusal")
            return
        }
        guard case .refused = center.add(uiSteps: recorded(app: "com.1password.1password")) else {
            Issue.record("expected a refusal for a password manager")
            return
        }
        #expect(center.steps.isEmpty && center.failure != nil)
    }

    @Test func untrustedRecordedStepsMakeTheDraftUntrustedAndUnrunnable() {
        let center = center()
        center.add(uiSteps: recorded(), trusted: false)
        let plan = center.plan()
        #expect(plan.trust == .untrusted && plan.refusal == .untrusted)
    }

    @Test func aStepCanBeToldToKeepGoing() {
        let center = center()
        center.add(uiSteps: recorded())
        let id = center.steps[0].id
        #expect(!center.continuesOnFailure(stepID: id))
        center.setContinuesOnFailure(true, stepID: id)
        #expect(center.steps[0].continueOnFailure && center.continuesOnFailure(stepID: id))
        center.setContinuesOnFailure(false, stepID: id)
        #expect(!center.steps[0].continueOnFailure)
    }
}
