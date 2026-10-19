import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("RecordingReview")
struct RecordingReviewTests {
    private func draftWith(_ keys: [UInt16], typing: Bool = false, reload: Bool = false) -> RecordingDraft {
        let world = RecorderWorld()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowAll()), log: .silent)
        let source = FakeEventSource()
        let recorder = Recorder(engine: engine, source: source)
        recorder.begin()
        for key in keys { source.send(.keyDown(.command(key))) }
        if reload { source.send(.keyDown(.plain(Key.f5))) }
        if typing { source.send(.keyDown(.plain(Key.a))) }
        return recorder.finish()
    }

    private struct AllowAll: RecordingPermissionBackend {
        func accessibilityGranted() -> Bool { true }
        func inputMonitoringGranted() -> Bool { true }
        func requestAccessibility() {}
        func requestInputMonitoring() {}
    }

    private func store() -> UserCommandStore {
        UserCommandStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("apropos-review-\(UUID().uuidString)"))
    }

    private func review(
        _ draft: RecordingDraft, store: UserCommandStore? = nil,
        dryRun: @escaping @Sendable (UIStepsBackend, ContextPrivacy) -> StepDryRunReport = { _, _ in
            StepDryRunReport(results: [], health: .unknown, blocked: .permissionMissing)
        }
    ) -> RecordingReview {
        RecordingReview(draft: draft, store: store, dryRun: dryRun, addToDraft: { _, _ in .added(steps: 1) })
    }

    @Test func savingNeedsANameAndAtLeastOneStep() {
        let r = review(draftWith([Key.s]), store: store())
        #expect(r.blocker == "Give it a name.")
        r.name = "Save it"
        #expect(r.canSave)
        let empty = review(draftWith([]), store: store())
        empty.name = "x"
        #expect(empty.blocker == "There are no steps left to save.")
    }

    @Test func deleteMoveAndRenameEditTheRows() throws {
        let r = review(draftWith([Key.s, Key.c], reload: true), store: store())
        let ids = r.items.map(\.id)
        r.moveDown(ids[0])
        #expect(r.items.map(\.id) == [ids[1], ids[0], ids[2]])
        r.moveUp(ids[2])
        #expect(r.items.map(\.id) == [ids[1], ids[2], ids[0]])
        r.rename(ids[0], to: "Save the file")
        #expect(r.items.first { $0.id == ids[0] }?.summary == "Save the file")
        r.delete(ids[1])
        #expect(r.stepCount == 2)
        r.rename(ids[0], to: "  ")
        #expect(r.problem != nil)
    }

    @Test func savingMakesACommandThatAsksFirstWithItsAliasAndShortcut() throws {
        let store = store()
        let r = review(draftWith([Key.s, Key.c]), store: store)
        r.name = "  Save and copy "
        r.alias = "Save Copy"
        r.hotkey = HotKeyCombo(keyCode: 0, modifiers: [.control, .option])
        #expect(r.save() == .saved(name: "Save and copy"))
        let saved = try #require(store.commands.first)
        #expect(saved.title == "Save and copy")
        #expect(saved.aliases == ["save-copy"])
        #expect(saved.hotkey == HotKeyCombo(keyCode: 0, modifiers: [.control, .option]))
        #expect(saved.needsConfirmation)
    }

    @Test func aShortcutAnotherCommandUsesIsRefusedWithTheReason() {
        let store = store()
        store.reservedHotKeys = { [HotKeyCombo(keyCode: 49, modifiers: [.option])] }
        let r = review(draftWith([Key.s]), store: store)
        r.name = "x"
        r.hotkey = HotKeyCombo(keyCode: 49, modifiers: [.option])
        #expect(r.save() == nil)
        #expect(r.problem == "That shortcut opens Apropos.")
        #expect(store.commands.isEmpty)
    }

    @Test func typedTextRowsDoNotBlockSavingAndAreDropped() throws {
        let store = store()
        let r = review(draftWith([Key.s], typing: true), store: store)
        #expect(r.textEntryCount == 1)
        r.name = "x"
        #expect(r.canSave)
        #expect(r.save() != nil)
        #expect(store.commands.count == 1)
    }

    @Test func checkingMarksEachStepFromTheDryRun() {
        let report: @Sendable (UIStepsBackend, ContextPrivacy) -> StepDryRunReport = { backend, _ in
            let results = backend.steps.enumerated().map { offset, step in
                StepDryResult(
                    step: offset + 1, stepID: step.id, matchedKind: offset == 0 ? .shortcut : nil,
                    isDegraded: false, isEnabled: true, failure: offset == 0 ? nil : .notFound, attempts: [])
            }
            return StepDryRunReport(results: results, health: .broken, blocked: nil)
        }
        let r = review(draftWith([Key.s, Key.c]), dryRun: report)
        r.check()
        let ids = r.items.map(\.id)
        #expect(r.checks[ids[0]] == .found)
        #expect(r.checks[ids[1]] == .missing("the item was not found"))
        r.delete(ids[1])
        #expect(r.checks.isEmpty)
    }

    @Test func checkingWithoutAccessSaysItCannot() {
        let r = review(draftWith([Key.s]))
        r.check()
        guard case .unchecked? = r.checks[r.items[0].id] else {
            Issue.record("expected unchecked")
            return
        }
    }

    @Test func addToDraftHandsTheStepsOver() {
        let r = review(draftWith([Key.s, Key.c]))
        #expect(r.addToDraft() == .addedToDraft)
    }
}
