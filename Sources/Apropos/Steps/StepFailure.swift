import Foundation

/// Why a step did not run, or did not finish. Fixed vocabulary: it never carries a title, a name or a value, so it can
/// be logged and shown anywhere.
public enum StepFailureReason: Equatable, Sendable {
    /// No locator found the element before the wait ran out.
    case notFound
    /// Locators matched more than one element; the step refuses to guess.
    case ambiguous
    /// The element was found but is disabled.
    case disabled
    /// The step or the whole run took too long.
    case timedOut
    case appNotRunning
    /// Apropos has no Accessibility access.
    case permissionMissing
    case cancelled
    /// The target is a password field.
    case secureField
    /// The privacy rules no longer allow the step (the app was added to the privacy list, or the file was edited).
    case notAllowed
    /// The action was delivered but the expected outcome did not happen.
    case expectationNotMet
    /// The app refused the action with this Accessibility error code.
    case actionFailed(code: Int32)

    public var message: String {
        switch self {
        case .notFound: "the item was not found"
        case .ambiguous: "more than one item matched"
        case .disabled: "the item is disabled"
        case .timedOut: "it took too long"
        case .appNotRunning: "the app is not running"
        case .permissionMissing: "Apropos needs Accessibility access"
        case .cancelled: "it was cancelled"
        case .secureField: "it points at a password field"
        case .notAllowed: "the app is on the privacy list"
        case .expectationNotMet: "the expected result did not appear"
        case .actionFailed: "the app refused the action"
        }
    }

    /// A short stable word for logs.
    public var code: String {
        switch self {
        case .notFound: "notFound"
        case .ambiguous: "ambiguous"
        case .disabled: "disabled"
        case .timedOut: "timedOut"
        case .appNotRunning: "appNotRunning"
        case .permissionMissing: "permissionMissing"
        case .cancelled: "cancelled"
        case .secureField: "secureField"
        case .notAllowed: "notAllowed"
        case .expectationNotMet: "expectationNotMet"
        case .actionFailed(let code): "actionFailed(\(code))"
        }
    }

    init(_ failure: StepResolveFailure) {
        switch failure {
        case .notFound, .noMenuBar: self = .notFound
        case .ambiguous: self = .ambiguous
        case .secureField: self = .secureField
        case .budgetExceeded: self = .timedOut
        }
    }
}

/// The step a run stopped at, and why.
public struct StepFailure: Error, Equatable, Sendable {
    /// Counted from 1.
    public let step: Int
    public let reason: StepFailureReason

    public init(step: Int, reason: StepFailureReason) {
        self.step = step
        self.reason = reason
    }

    public var message: String { "Step \(step) stopped: \(reason.message)." }
}
