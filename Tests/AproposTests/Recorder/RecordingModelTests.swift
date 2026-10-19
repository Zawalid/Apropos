import Foundation
import Testing

@testable import Apropos

private final class MutableBackend: RecordingPermissionBackend, @unchecked Sendable {
    var accessibility = true
    var inputMonitoring = true
    private(set) var requested: [RecordingPermissionKind] = []
    func accessibilityGranted() -> Bool { accessibility }
    func inputMonitoringGranted() -> Bool { inputMonitoring }
    func requestAccessibility() { requested.append(.accessibility) }
    func requestInputMonitoring() { requested.append(.inputMonitoring) }
}

@MainActor
private final class Rig {
    let world = RecorderWorld()
    let source = FakeEventSource()
    let backend = MutableBackend()
    var clock: TimeInterval = 100
    var handedOff: [(steps: [UIStep], label: String)] = []
    var opened: [URL] = []
    var refuseHandOff: String?
    let store = UserCommandStore(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("apropos-rec-\(UUID().uuidString)"))
    lazy var model = RecordingModel(
        permission: RecordingPermission(backend: backend), maxDuration: 300,
        makeRecorder: { [self] in
            Recorder(
                engine: RecordingEngine(
                    services: world.services,
                    configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
                    permission: RecordingPermission(backend: backend), log: .silent),
                source: source)
        },
        makeReview: { [self] draft in
            RecordingReview(
                draft: draft, suggestedName: "Test", store: store,
                dryRun: { _, _ in StepDryRunReport(results: [], health: .unknown, blocked: .permissionMissing) },
                addToDraft: { [self] steps, label in
                    if let refuseHandOff { return .refused(refuseHandOff) }
                    handedOff.append((steps, label))
                    return .added(steps: handedOff.count)
                })
        },
        openURL: { [self] in opened.append($0) }, now: { [self] in clock })
}

@MainActor
@Suite("RecordingModel")
struct RecordingModelTests {
    @Test func aMissingPermissionShowsTheScreenAndNeverListens() {
        let rig = Rig()
        rig.backend.inputMonitoring = false
        rig.model.start()
        #expect(rig.model.phase == .needsPermission)
        #expect(rig.model.status.missing == [.inputMonitoring])
        #expect(rig.source.startCount == 0)
        #expect(rig.backend.requested.isEmpty)
    }

    @Test func thePermissionScreenNoticesWhenItIsGranted() {
        let rig = Rig()
        rig.backend.inputMonitoring = false
        rig.model.start()
        rig.backend.inputMonitoring = true
        rig.model.refresh()
        #expect(rig.model.status.canRecord)
        rig.model.start()
        #expect(rig.model.isRecording)
    }

    @Test func allowingAsksForOnePermissionAndOpensItsPage() {
        let rig = Rig()
        rig.model.allow(.inputMonitoring)
        #expect(rig.backend.requested == [.inputMonitoring])
        #expect(rig.opened == [RecordingPermissionKind.inputMonitoring.settingsURL].compactMap { $0 })
    }

    @Test func stepsCountUpAndAStopHandsThemToTheDraft() {
        let rig = Rig()
        rig.model.start()
        #expect(rig.model.isRecording)
        rig.source.send(.keyDown(.command(Key.s)))
        rig.clock = 107
        rig.model.refresh()
        #expect(rig.model.stepCount == 1)
        #expect(rig.model.elapsed == 7)
        rig.source.send(.keyDown(.command(Key.c)))
        rig.model.stop()
        #expect(rig.model.phase == .reviewing)
        #expect(rig.model.review?.stepCount == 2)
        #expect(rig.handedOff.isEmpty)
        rig.model.addReviewToDraft()
        #expect(rig.handedOff.count == 1)
        #expect(rig.handedOff.first?.steps.count == 2)
        #expect(rig.handedOff.first?.label == "Recorded steps")
        guard case .finished(let outcome) = rig.model.phase else {
            Issue.record("not finished")
            return
        }
        #expect(outcome.steps == 2 && outcome.addedToDraft)
        #expect(!rig.source.isListening)
    }

    @Test func typingLeavesOnlyANoteInTheMessage() {
        let rig = Rig()
        rig.model.start()
        rig.source.send(.keyDown(.command(Key.s)))
        rig.source.send(.keyDown(.plain(Key.a)))
        rig.model.stop()
        rig.model.addReviewToDraft()
        guard case .finished(let outcome) = rig.model.phase else {
            Issue.record("not finished")
            return
        }
        #expect(outcome.message.contains("What you typed was not recorded"))
        #expect(outcome.steps == 1)
    }

    @Test func aRecordingWithNoStepsHandsNothingOver() {
        let rig = Rig()
        rig.model.start()
        rig.model.stop()
        #expect(rig.handedOff.isEmpty)
        guard case .finished(let outcome) = rig.model.phase else {
            Issue.record("not finished")
            return
        }
        #expect(outcome.steps == 0 && !outcome.addedToDraft)
        #expect(outcome.message.hasPrefix("Nothing was recorded"))
    }

    @Test func aRecordingThatEndsByItselfIsFinishedOnTheNextRefresh() {
        let rig = Rig()
        rig.model.start()
        rig.source.send(.keyDown(.command(Key.s)))
        rig.source.send(.appActivated(rig.world.apropos))
        rig.model.refresh()
        #expect(rig.model.phase == .reviewing)
        #expect(rig.model.review?.stepCount == 1)
    }

    @Test func cancelThrowsTheRecordingAway() {
        let rig = Rig()
        rig.model.start()
        rig.source.send(.keyDown(.command(Key.s)))
        rig.model.cancel()
        #expect(rig.model.phase == .idle)
        #expect(rig.handedOff.isEmpty)
        #expect(!rig.source.isListening)
    }

    @Test func aRefusedHandOffSaysWhy() {
        let rig = Rig()
        rig.refuseHandOff = "A sequence can have at most 20 steps."
        rig.model.start()
        rig.source.send(.keyDown(.command(Key.s)))
        rig.model.stop()
        rig.model.addReviewToDraft()
        #expect(rig.model.phase == .reviewing)
        #expect(rig.model.review?.problem == "A sequence can have at most 20 steps.")
    }

    @Test func aSecondStartWhileRecordingDoesNothing() {
        let rig = Rig()
        rig.model.start()
        rig.model.start()
        #expect(rig.source.startCount == 1)
    }

    @Test func dismissingTheResultReturnsToIdle() {
        let rig = Rig()
        rig.model.start()
        rig.model.stop()
        rig.model.dismissOutcome()
        #expect(rig.model.phase == .idle)
    }

    @Test func savingFromTheReviewEndsInAFinishedNote() {
        let rig = Rig()
        rig.model.start()
        rig.source.send(.keyDown(.command(Key.s)))
        rig.model.stop()
        rig.model.saveReview()
        guard case .finished(let outcome) = rig.model.phase else {
            Issue.record("not finished")
            return
        }
        #expect(outcome.message.contains("Saved"))
        #expect(rig.store.commands.count == 1)
        #expect(rig.model.review == nil)
    }

    @Test func discardingTheReviewSavesNothing() {
        let rig = Rig()
        rig.model.start()
        rig.source.send(.keyDown(.command(Key.s)))
        rig.model.stop()
        rig.model.discardReview()
        #expect(rig.model.phase == .idle)
        #expect(rig.store.commands.isEmpty && rig.handedOff.isEmpty)
    }
}
