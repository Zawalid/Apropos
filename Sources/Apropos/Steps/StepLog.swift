import Foundation
import os

/// The only way the step engine writes a log line. Every message is built from the action id, a step number, a fixed
/// word and a number, so there is nothing sensitive to leak: titles, identifiers, descriptions and values are not
/// parameters of any function here.
public struct StepLog: Sendable {
    public var sink: @Sendable (String) -> Void

    public init(sink: @escaping @Sendable (String) -> Void) { self.sink = sink }

    public static let standard = StepLog { line in
        AproposLog.app.info("\(line, privacy: .public)")
    }

    public static let silent = StepLog { _ in }

    func started(_ action: String, steps: Int) { sink("steps \(action) started, \(steps) steps") }

    func matched(_ action: String, step: Int, kind: LocatorKind, degraded: Bool, milliseconds: Int, retries: Int) {
        sink(
            "steps \(action) step \(step) done via \(kind.rawValue)\(degraded ? " (fallback)" : ""), "
                + "\(milliseconds) ms, \(retries) retries")
    }

    func failed(_ action: String, _ failure: StepFailure) {
        sink("steps \(action) stopped at step \(failure.step): \(failure.reason.code)")
    }

    func completed(_ action: String, milliseconds: Int) { sink("steps \(action) completed in \(milliseconds) ms") }
}
