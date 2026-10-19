import AppKit
import Foundation
import Observation

/// What a finished recording came to, in words the recording bar can show.
public struct RecordingOutcome: Equatable, Sendable {
    public let steps: Int
    public let message: String
    /// True when the steps were put in the sequence draft.
    public let addedToDraft: Bool

    public init(steps: Int, message: String, addedToDraft: Bool) {
        self.steps = steps
        self.message = message
        self.addedToDraft = addedToDraft
    }
}

/// What a person sees of a recording from start to finish: the permission screen, the live bar, and the result. It owns
/// no window and no timer: the app calls `refresh()` a few times a second and draws what the model says. The recorder
/// underneath does the listening and keeps every privacy rule.
///
/// A recording ends in the sequence draft: the steps are handed over as one menu step, so they can be run, edited and saved
/// from the panel with everything else, until the review sheet exists.
@MainActor
@Observable
public final class RecordingModel {
    public enum Phase: Equatable {
        case idle
        /// A permission is missing. `status` says which.
        case needsPermission
        case recording
        case finished(RecordingOutcome)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var status: RecordingPermissionStatus
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var stepCount = 0
    /// Recording is paused because a password field is active.
    public private(set) var pausedForSecureInput = false

    /// The most the recorder may run, for a quiet countdown near the end.
    public let maxDuration: TimeInterval

    @ObservationIgnored private let permission: RecordingPermission
    @ObservationIgnored private let makeRecorder: @MainActor () -> Recorder
    @ObservationIgnored private let handOff: @MainActor ([UIStep], String) -> SequenceAddResult
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void
    @ObservationIgnored private let now: @MainActor () -> TimeInterval
    @ObservationIgnored private var recorder: Recorder?
    @ObservationIgnored private var startedAt: TimeInterval = 0

    public init(
        permission: RecordingPermission = RecordingPermission(), maxDuration: TimeInterval = 300,
        makeRecorder: @escaping @MainActor () -> Recorder,
        handOff: @escaping @MainActor ([UIStep], String) -> SequenceAddResult,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.permission = permission
        self.maxDuration = maxDuration
        self.makeRecorder = makeRecorder
        self.handOff = handOff
        self.openURL = openURL
        self.now = now
        status = permission.status()
    }

    public var isRecording: Bool { phase == .recording }

    /// Whether the bar or the permission screen is showing something that needs a response.
    public var isActive: Bool { phase != .idle }

    /// Puts the model in a state without recording anything, for previews and screenshots.
    public func seed(
        phase: Phase, status: RecordingPermissionStatus? = nil, elapsed: TimeInterval = 0, stepCount: Int = 0,
        pausedForSecureInput: Bool = false
    ) {
        self.phase = phase
        if let status { self.status = status }
        self.elapsed = elapsed
        self.stepCount = stepCount
        self.pausedForSecureInput = pausedForSecureInput
    }

    // MARK: Starting

    /// Starts a recording, or shows what is missing. Never prompts for a permission by itself.
    public func start() {
        guard !isRecording else { return }
        status = permission.status()
        guard status.canRecord else {
            phase = .needsPermission
            return
        }
        let recorder = makeRecorder()
        let state = recorder.begin()
        guard state == .recording else {
            if case .failed(.permissionMissing) = state {
                status = permission.status()
                phase = .needsPermission
            } else {
                phase = .failed("Recording could not start. Check that Input Monitoring is allowed, then try again.")
            }
            return
        }
        self.recorder = recorder
        startedAt = now()
        elapsed = 0
        stepCount = 0
        pausedForSecureInput = false
        phase = .recording
    }

    /// Asks macOS for one permission and opens the System Settings page that holds its switch. Only a button the person
    /// pressed calls this.
    public func allow(_ kind: RecordingPermissionKind) {
        permission.request(kind)
        if let url = kind.settingsURL { openURL(url) }
    }

    /// The permission screen, closed without recording.
    public func dismiss() {
        if isRecording { return }
        phase = .idle
    }

    // MARK: While recording

    /// Reads the clock, the recorder and the permissions. Call it a few times a second while anything is showing.
    public func refresh() {
        switch phase {
        case .needsPermission:
            status = permission.status()
        case .recording:
            guard let recorder else { return }
            elapsed = max(0, now() - startedAt)
            stepCount = recorder.draft.stepCount
            pausedForSecureInput = recorder.state == .pausedForSecureInput
            if recorder.state.isTerminal { finish() }
        case .idle, .finished, .failed:
            break
        }
    }

    // MARK: Ending

    /// Stops listening and hands what was recorded over to the sequence draft.
    public func stop() {
        guard isRecording else { return }
        finish()
    }

    /// Throws the recording away.
    public func cancel() {
        recorder?.cancel()
        recorder = nil
        phase = .idle
    }

    /// Closes the result.
    public func dismissOutcome() {
        if case .finished = phase { phase = .idle }
        if case .failed = phase { phase = .idle }
    }

    private func finish() {
        guard let recorder else { return }
        let draft = recorder.finish()
        self.recorder = nil
        elapsed = max(0, now() - startedAt)
        stepCount = draft.stepCount
        pausedForSecureInput = false
        guard draft.stepCount > 0 else {
            phase = .finished(
                RecordingOutcome(
                    steps: 0,
                    message: "Nothing was recorded. Menu items you click and shortcuts you press are recorded.",
                    addedToDraft: false))
            return
        }
        let steps: [UIStep]
        do {
            steps = try draft.validated(dropTextEntries: true).backend.steps
        } catch {
            phase = .finished(
                RecordingOutcome(steps: 0, message: "Those steps could not be used: \(error)", addedToDraft: false))
            return
        }
        let label = steps.count == 1 ? "Recorded step" : "Recorded steps"
        switch handOff(steps, label) {
        case .added:
            var message = "Recorded \(steps.count) step\(steps.count == 1 ? "" : "s"), now in your draft."
            if draft.textEntryCount > 0 { message += " What you typed was not recorded." }
            phase = .finished(RecordingOutcome(steps: steps.count, message: message, addedToDraft: true))
        case .refused(let reason):
            phase = .finished(RecordingOutcome(steps: steps.count, message: reason, addedToDraft: false))
        }
    }
}
