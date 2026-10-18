import Foundation
import Testing

@testable import Apropos

private struct Backend: RecordingPermissionBackend {
    var accessibility = true
    var inputMonitoring = true
    func accessibilityGranted() -> Bool { accessibility }
    func inputMonitoringGranted() -> Bool { inputMonitoring }
    func requestAccessibility() {}
    func requestInputMonitoring() {}
}

private func makeRecorder(
    _ world: RecorderWorld, source: FakeEventSource, backend: Backend = Backend()
) -> Recorder {
    Recorder(
        engine: RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: backend), log: .silent),
        source: source)
}

@Suite("Recorder")
struct RecorderFacadeTests {
    @Test func nothingListensBeforeBegin() {
        let world = RecorderWorld()
        let source = FakeEventSource()
        let recorder = makeRecorder(world, source: source)
        #expect(source.startCount == 0)
        #expect(recorder.state == .idle)
    }

    @Test func aMissingPermissionFailsWithoutStartingTheSource() {
        let world = RecorderWorld()
        let source = FakeEventSource()
        let recorder = makeRecorder(
            world, source: source, backend: Backend(accessibility: true, inputMonitoring: false))
        #expect(recorder.begin() == .failed(.permissionMissing([.inputMonitoring])))
        #expect(source.startCount == 0)
    }

    @Test func aSourceThatCannotStartFails() {
        let world = RecorderWorld()
        let source = FakeEventSource()
        source.failsToStart = true
        let recorder = makeRecorder(world, source: source)
        #expect(recorder.begin() == .failed(.eventSourceUnavailable))
        #expect(!source.isListening)
    }

    @Test func eventsFlowIntoTheDraftAndFinishStopsListening() {
        let world = RecorderWorld()
        let source = FakeEventSource()
        let recorder = makeRecorder(world, source: source)
        #expect(recorder.begin() == .recording)
        #expect(source.isListening)
        source.send(.keyDown(.command(Key.s)))
        source.send(.flagsChanged)
        #expect(recorder.draft.stepCount == 1)
        let draft = recorder.finish()
        #expect(draft.stepCount == 1)
        #expect(!source.isListening)
        #expect(recorder.state == .finished(.stoppedByPerson))
    }

    @Test func theSourceIsStoppedWhenTheRecordingEndsByItself() {
        let world = RecorderWorld()
        let source = FakeEventSource()
        let recorder = makeRecorder(world, source: source)
        recorder.begin()
        source.send(.appActivated(world.apropos))
        #expect(recorder.state == .finished(.switchedToApropos))
        #expect(!source.isListening)
    }

    @Test func cancelDiscardsListening() {
        let world = RecorderWorld()
        let source = FakeEventSource()
        let recorder = makeRecorder(world, source: source)
        recorder.begin()
        recorder.cancel()
        #expect(recorder.state == .cancelled)
        #expect(!source.isListening)
    }
}
