import Foundation

/// The recorder a UI drives: permissions, an event source and the engine that builds the draft.
///
/// ```swift
/// let recorder = Recorder(engine: engine, source: LiveCaptureSource(...))
/// recorder.begin()               // arms, starts listening; state is .recording, or .failed(...) with the reason
/// ...                            // the person does the task
/// let draft = recorder.finish()  // review, edit, then draft.validated() / draft.save(in:)
/// ```
///
/// Nothing is listened to before `begin()` and nothing after the recording ends or `cancel()` is called. The recorder
/// never prompts for a permission; if one is missing `begin()` fails and `state` says which.
public final class Recorder: @unchecked Sendable {
    public let engine: RecordingEngine
    private let source: any CaptureEventSource

    public init(engine: RecordingEngine, source: any CaptureEventSource) {
        self.engine = engine
        self.source = source
    }

    public var state: RecordingState { engine.state }
    public var draft: RecordingDraft { engine.currentDraft }

    @discardableResult
    public func begin() -> RecordingState {
        guard engine.arm() == .armed else { return engine.state }
        engine.beginRecording()
        do {
            try source.start { [engine, source] event in
                if engine.handle(event).isTerminal { source.stop() }
            }
        } catch {
            engine.sourceUnavailable()
        }
        return engine.state
    }

    /// Stops listening and returns what was recorded.
    @discardableResult
    public func finish() -> RecordingDraft {
        engine.stop()
        source.stop()
        return engine.currentDraft
    }

    public func cancel() {
        engine.cancel()
        source.stop()
    }
}
