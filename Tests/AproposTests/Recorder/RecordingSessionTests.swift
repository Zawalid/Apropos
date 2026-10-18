import Testing

@testable import Apropos

private final class FakePermissionBackend: RecordingPermissionBackend, @unchecked Sendable {
    var accessibility = false
    var inputMonitoring = false
    private(set) var requests: [String] = []

    func accessibilityGranted() -> Bool { accessibility }
    func inputMonitoringGranted() -> Bool { inputMonitoring }
    func requestAccessibility() { requests.append("accessibility") }
    func requestInputMonitoring() { requests.append("inputMonitoring") }
}

@Suite("Recording permission")
struct RecordingPermissionTests {
    @Test func readingTheStateNeverPrompts() {
        let backend = FakePermissionBackend()
        let permission = RecordingPermission(backend: backend)
        _ = permission.status()
        _ = permission.status()
        #expect(backend.requests.isEmpty)
    }

    @Test func reportsWhatIsMissingInGrantingOrder() {
        let backend = FakePermissionBackend()
        let permission = RecordingPermission(backend: backend)
        #expect(permission.status().missing == [.accessibility, .inputMonitoring])
        backend.accessibility = true
        #expect(permission.status().missing == [.inputMonitoring])
        backend.inputMonitoring = true
        #expect(permission.status().canRecord)
        #expect(permission.status().missing.isEmpty)
    }

    @Test func requestingIsExplicitAndPerKind() {
        let backend = FakePermissionBackend()
        let permission = RecordingPermission(backend: backend)
        permission.request(.inputMonitoring)
        #expect(backend.requests == ["inputMonitoring"])
        permission.request(.accessibility)
        #expect(backend.requests == ["inputMonitoring", "accessibility"])
    }

    @Test func everyKindHasWordingAndASettingsPane() {
        for kind in RecordingPermissionKind.allCases {
            #expect(!kind.whatItAllows.isEmpty)
            #expect(!kind.whyRecording.isEmpty)
            #expect(kind.settingsURL != nil)
        }
        #expect(RecordingPermissionCopy.missing([.inputMonitoring]).contains("Input Monitoring"))
        #expect(RecordingPermissionCopy.missing([]).contains("allowed"))
        #expect(RecordingPermissionCopy.neverStored.contains { $0.contains("letters you type") })
    }
}

@Suite("Recording session")
struct RecordingSessionTests {
    private let allowed = RecordingPermissionStatus(accessibility: true, inputMonitoring: true)

    private func recording(limits: RecordingLimits = RecordingLimits()) -> RecordingSession {
        var session = RecordingSession(limits: limits)
        session.arm(permissions: allowed)
        session.start(at: 100)
        return session
    }

    @Test func idleArmedRecording() {
        var session = RecordingSession()
        #expect(session.state == .idle)
        session.arm(permissions: allowed)
        #expect(session.state == .armed)
        session.start(at: 0)
        #expect(session.state == .recording)
    }

    @Test func missingPermissionFailsAndNamesIt() {
        var session = RecordingSession()
        session.arm(permissions: RecordingPermissionStatus(accessibility: true, inputMonitoring: false))
        #expect(session.state == .failed(.permissionMissing([.inputMonitoring])))
        session.start(at: 0)
        #expect(session.state == .failed(.permissionMissing([.inputMonitoring])))
    }

    @Test func cannotStartWithoutArming() {
        var session = RecordingSession()
        session.start(at: 0)
        #expect(session.state == .idle)
    }

    @Test func secureInputPausesAndResumes() {
        var session = recording()
        session.setSecureInput(true)
        #expect(session.state == .pausedForSecureInput)
        let rejected = session.acceptStep()
        #expect(!rejected)
        session.setSecureInput(false)
        #expect(session.state == .recording)
        let accepted = session.acceptStep()
        #expect(accepted)
    }

    @Test func secureInputDoesNothingOutsideARecording() {
        var session = RecordingSession()
        session.setSecureInput(true)
        #expect(session.state == .idle)
        var done = recording()
        done.finish()
        done.setSecureInput(true)
        #expect(done.state == .finished(.stoppedByPerson))
    }

    @Test func switchingToAproposEndsIt() {
        var session = recording()
        session.frontmostChanged(isApropos: false)
        #expect(session.state == .recording)
        session.frontmostChanged(isApropos: true)
        #expect(session.state == .finished(.switchedToApropos))
    }

    @Test func switchingToAproposEndsAPausedRecordingToo() {
        var session = recording()
        session.setSecureInput(true)
        session.frontmostChanged(isApropos: true)
        #expect(session.state == .finished(.switchedToApropos))
    }

    @Test func hardTimeLimitEndsEvenWhenPaused() {
        var session = recording(limits: RecordingLimits(maxDuration: 30))
        session.tick(at: 129)
        #expect(session.state == .recording)
        session.setSecureInput(true)
        session.tick(at: 130)
        #expect(session.state == .finished(.reachedTimeLimit))
    }

    @Test func stepLimitEndsOnTheLastStep() {
        var session = recording(limits: RecordingLimits(maxSteps: 3))
        let first = session.acceptStep()
        let second = session.acceptStep()
        #expect(first && second)
        #expect(session.state == .recording)
        let third = session.acceptStep()
        #expect(third)
        #expect(session.state == .finished(.reachedStepLimit))
        let fourth = session.acceptStep()
        #expect(!fourth)
        #expect(session.stepCount == 3)
    }

    @Test func limitsCannotExceedTheStepEngine() {
        #expect(RecordingLimits(maxSteps: 500).maxSteps == UIStepsValidator.maxSteps)
        #expect(RecordingLimits(maxDuration: 99_999).maxDuration <= 1800)
        #expect(RecordingLimits(maxDuration: 0).maxDuration >= 1)
    }

    @Test func terminalStatesStay() {
        var finished = recording()
        finished.finish()
        finished.cancel()
        finished.fail(.internalError)
        finished.start(at: 0)
        #expect(finished.state == .finished(.stoppedByPerson))

        var cancelled = recording()
        cancelled.cancel()
        cancelled.finish()
        #expect(cancelled.state == .cancelled)

        var failed = recording()
        failed.sourceUnavailable()
        #expect(failed.state == .failed(.eventSourceUnavailable))
        failed.setSecureInput(true)
        #expect(failed.state == .failed(.eventSourceUnavailable))
    }

    @Test func cancelWorksFromIdleAndEveryLiveState() {
        var idle = RecordingSession()
        idle.cancel()
        #expect(idle.state == .cancelled)
        var armed = RecordingSession()
        armed.arm(permissions: allowed)
        armed.cancel()
        #expect(armed.state == .cancelled)
        var paused = recording()
        paused.setSecureInput(true)
        paused.cancel()
        #expect(paused.state == .cancelled)
    }

    @Test func elapsedIsZeroBeforeStart() {
        var session = RecordingSession()
        #expect(session.elapsed(at: 50) == 0)
        session.arm(permissions: allowed)
        session.start(at: 10)
        #expect(session.elapsed(at: 25) == 15)
    }
}
