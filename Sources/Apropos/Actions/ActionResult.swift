import Foundation

/// Why an action did not run or did not finish. Messages never include the input or output.
public enum ActionError: Error, Equatable, Sendable {
    /// The action does not apply to this app or these values.
    case notApplicable
    case missingContext(ContextRequirement)
    case confirmationRequired
    case timedOut
    case cancelled
    /// The program, script or Shortcut ran and reported failure.
    case backendFailed(status: Int32?)
    case launchFailed
    case outputTooLarge
    /// The text could not be transformed (bad base64, bad JSON).
    case invalidInput
    case unknownFunction(String)
    /// The thing the action needs is not available: no remote, no Accessibility, no such Shortcut.
    case unavailable(String)
    /// A `uiSteps` command stopped at a step.
    case uiStepFailed(StepFailure)

    public var message: String {
        switch self {
        case .notApplicable: "That action does not apply here."
        case .missingContext: "There is nothing selected for that action."
        case .confirmationRequired: "That action needs your confirmation."
        case .timedOut: "The action took too long and was stopped."
        case .cancelled: "The action was cancelled."
        case .backendFailed: "The action failed."
        case .launchFailed: "The action could not be started."
        case .outputTooLarge: "The action produced too much output."
        case .invalidInput: "The selection is not valid for that action."
        case .unknownFunction: "That action is not available in this version."
        case .unavailable(let reason): reason
        case .uiStepFailed(let failure): failure.message
        }
    }
}

/// What became of an action's result text.
public enum ActionDelivery: Sendable, Equatable {
    case copied
    case replaced
    /// Replaced by pasting, with the clipboard restored afterwards.
    case pasted
    /// Replacing was not possible here, so the result went to the clipboard.
    case copiedInstead
    case notified
    /// Nothing to deliver: the action's effect was the point.
    case done
}

public struct ActionOutcome: Sendable, Equatable {
    public let id: ActionID
    public let delivery: ActionDelivery
    /// Text for a short notice in the UI ("Copied", "12 words, 80 characters"). Present for `.notified`.
    public let notice: String?

    public init(id: ActionID, delivery: ActionDelivery, notice: String? = nil) {
        self.id = id
        self.delivery = delivery
        self.notice = notice
    }
}
