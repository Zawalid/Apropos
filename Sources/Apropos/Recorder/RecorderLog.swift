import Foundation

/// The only way the recorder writes a log line. Every message is a fixed word plus a count: no app, title, identifier,
/// key or position is a parameter of any function here, so there is nothing to leak.
public struct RecorderLog: Sendable {
    public var sink: @Sendable (String) -> Void

    public init(sink: @escaping @Sendable (String) -> Void) { self.sink = sink }

    public static let standard = RecorderLog { line in
        AproposLog.app.info("\(line, privacy: .public)")
    }

    public static let silent = RecorderLog { _ in }

    func began() { sink("recorder began") }
    func stepAdded(_ origin: StepOrigin, total: Int) {
        sink("recorder step added via \(origin.rawValue), \(total) steps")
    }
    func skipped(_ reason: SkipReason) { sink("recorder skipped: \(reason.rawValue)") }
    func paused() { sink("recorder paused for secure input") }
    func resumed() { sink("recorder resumed") }
    func ended(_ state: RecordingState) { sink("recorder ended: \(Self.word(state))") }

    public static func word(_ state: RecordingState) -> String {
        switch state {
        case .idle: "idle"
        case .armed: "armed"
        case .recording: "recording"
        case .pausedForSecureInput: "paused"
        case .finished(let reason): "finished (\(reasonWord(reason)))"
        case .cancelled: "cancelled"
        case .failed(let failure): "failed (\(failureWord(failure)))"
        }
    }

    private static func reasonWord(_ reason: RecordingStopReason) -> String {
        switch reason {
        case .stoppedByPerson: "stopped"
        case .switchedToApropos: "switched to Apropos"
        case .reachedStepLimit: "step limit"
        case .reachedTimeLimit: "time limit"
        }
    }

    private static func failureWord(_ failure: RecordingFailure) -> String {
        switch failure {
        case .permissionMissing: "permission missing"
        case .eventSourceUnavailable: "event source unavailable"
        case .internalError: "internal error"
        }
    }
}
