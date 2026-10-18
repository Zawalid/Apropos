import Foundation

/// Why a recording ended before the person stopped it.
public enum RecordingStopReason: Equatable, Sendable {
    /// The person pressed Stop.
    case stoppedByPerson
    /// The person switched to Apropos itself, which is how they open the review.
    case switchedToApropos
    case reachedStepLimit
    case reachedTimeLimit

    public var description: String {
        switch self {
        case .stoppedByPerson: "You stopped the recording."
        case .switchedToApropos: "The recording ended when you switched to Apropos."
        case .reachedStepLimit: "The recording ended because it reached the step limit."
        case .reachedTimeLimit: "The recording ended because it reached the time limit."
        }
    }
}

/// Why a recording could not run.
public enum RecordingFailure: Equatable, Sendable {
    case permissionMissing([RecordingPermissionKind])
    /// macOS refused to create the event source even though the permissions looked granted.
    case eventSourceUnavailable
    case internalError

    public var description: String {
        switch self {
        case .permissionMissing(let kinds): RecordingPermissionCopy.missing(kinds)
        case .eventSourceUnavailable: "Apropos could not start listening for clicks and shortcuts."
        case .internalError: "The recording stopped because of an internal problem."
        }
    }
}

/// What a recording is doing right now.
public enum RecordingState: Equatable, Sendable {
    case idle
    /// Recording was requested and the permissions are fine; the event source is about to start.
    case armed
    case recording
    /// Secure input is on, or a password field is active. Nothing is observed until it ends.
    case pausedForSecureInput
    case finished(RecordingStopReason)
    case cancelled
    case failed(RecordingFailure)

    /// Events are still being handled.
    public var isLive: Bool {
        switch self {
        case .armed, .recording, .pausedForSecureInput: true
        case .idle, .finished, .cancelled, .failed: false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .finished, .cancelled, .failed: true
        case .idle, .armed, .recording, .pausedForSecureInput: false
        }
    }
}

/// The limits of one recording. They are hard: reaching one ends the recording, it is never extended.
public struct RecordingLimits: Equatable, Sendable {
    public static let defaultMaxDuration: TimeInterval = 300

    public var maxDuration: TimeInterval
    public var maxSteps: Int

    public init(maxDuration: TimeInterval = defaultMaxDuration, maxSteps: Int = UIStepsValidator.maxSteps) {
        self.maxDuration = min(max(maxDuration, 1), 1800)
        self.maxSteps = min(max(maxSteps, 1), UIStepsValidator.maxSteps)
    }
}

/// The life of one recording. A value type driven by explicit calls and by times the caller passes in, so tests need no
/// clock. Once a recording is finished, cancelled or failed it stays that way: start a new session instead.
public struct RecordingSession: Equatable, Sendable {
    public private(set) var state: RecordingState = .idle
    public let limits: RecordingLimits
    /// Steps accepted so far.
    public private(set) var stepCount = 0
    private var startedAt: TimeInterval?

    public init(limits: RecordingLimits = RecordingLimits()) { self.limits = limits }

    /// Seconds since recording began, or zero before that.
    public func elapsed(at now: TimeInterval) -> TimeInterval { startedAt.map { max(0, now - $0) } ?? 0 }

    // MARK: Transitions

    /// Idle to armed, if the permissions allow it. Otherwise the session fails and says what is missing.
    public mutating func arm(permissions: RecordingPermissionStatus) {
        guard state == .idle else { return }
        state = permissions.canRecord ? .armed : .failed(.permissionMissing(permissions.missing))
    }

    /// Armed to recording, once the event source is live.
    public mutating func start(at now: TimeInterval) {
        guard state == .armed else { return }
        startedAt = now
        state = .recording
    }

    /// The event source could not start.
    public mutating func sourceUnavailable() {
        guard state.isLive else { return }
        state = .failed(.eventSourceUnavailable)
    }

    public mutating func fail(_ failure: RecordingFailure) {
        guard state.isLive else { return }
        state = .failed(failure)
    }

    /// Recording to paused, or back. Secure input is the only reason to pause. Ignored in any other state.
    public mutating func setSecureInput(_ isOn: Bool) {
        switch (state, isOn) {
        case (.recording, true): state = .pausedForSecureInput
        case (.pausedForSecureInput, false): state = .recording
        default: break
        }
    }

    public mutating func finish(_ reason: RecordingStopReason = .stoppedByPerson) {
        guard state.isLive else { return }
        state = .finished(reason)
    }

    public mutating func cancel() {
        guard state.isLive || state == .idle else { return }
        state = .cancelled
    }

    /// Frontmost app changed. Ends the recording when it is Apropos itself.
    public mutating func frontmostChanged(isApropos: Bool) {
        if isApropos { finish(.switchedToApropos) }
    }

    /// Time moves on. Ends the recording at the hard limit, paused or not.
    public mutating func tick(at now: TimeInterval) {
        guard state == .recording || state == .pausedForSecureInput else { return }
        if elapsed(at: now) >= limits.maxDuration { finish(.reachedTimeLimit) }
    }

    /// A step was added to the draft. Returns false when the session is not recording or is full.
    @discardableResult
    public mutating func acceptStep() -> Bool {
        guard state == .recording, stepCount < limits.maxSteps else { return false }
        stepCount += 1
        if stepCount >= limits.maxSteps { finish(.reachedStepLimit) }
        return true
    }
}
