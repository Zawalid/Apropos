import AppKit
import Foundation

/// What became of a Share menu request.
public enum ShareResult: Sendable, Equatable {
    case shared
    /// The person closed the menu without choosing a service.
    case dismissed
    case unavailable
}

/// What sending needs from the outside world, as replaceable closures so tests run without touching apps.
public struct SendServices: Sendable {
    /// Whether the app with this bundle identifier is installed.
    public var isInstalled: @Sendable (String) -> Bool
    /// Shows the system Share menu for the payload. Returns when the person chose a service or dismissed the menu.
    public var share: @Sendable (Payload) async -> ShareResult
    /// What the action engine uses to run processes and open links.
    public var actions: ActionServices

    public init(
        isInstalled: @escaping @Sendable (String) -> Bool, share: @escaping @Sendable (Payload) async -> ShareResult,
        actions: ActionServices
    ) {
        self.isInstalled = isInstalled
        self.share = share
        self.actions = actions
    }

    /// Installed means `NSWorkspace` can find the app by bundle identifier. The Share menu needs the app to present it,
    /// so the default reports it unavailable until the app installs its own presenter.
    public static let live = SendServices(
        isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
        share: { _ in .unavailable }, actions: .live)
}

/// What a successful send reports.
public struct SendOutcome: Sendable, Equatable {
    public let destination: ActionID
    public let title: String
    /// A short notice for the footer: "Sent to Notes".
    public var notice: String { "Sent to \(title)" }
}

/// Why a send did not happen. Messages name the destination, never the content.
public enum SendError: Error, Equatable, Sendable {
    case notInstalled(destination: String)
    case notApplicable(destination: String)
    case tooLarge(String)
    case needsApproval(destination: String)
    case confirmationRequired
    case cancelled
    case timedOut(destination: String)
    case failed(destination: String, hint: String?)

    public var message: String {
        switch self {
        case .notInstalled(let name): "\(name) is not installed."
        case .notApplicable(let name): "\(name) cannot take this."
        case .tooLarge(let reason): reason
        case .needsApproval(let name): "\(name) is waiting for your approval."
        case .confirmationRequired: "Press Return to confirm."
        case .cancelled: "Nothing was sent."
        case .timedOut(let name): "\(name) took too long. Nothing was lost; try again."
        case .failed(let name, let hint):
            ["Could not send to \(name).", hint].compactMap { $0 }.joined(separator: " ")
        }
    }
}

/// Sends a payload to a destination. It checks that the destination can take it, then runs the destination's variant
/// through the action engine, so the engine's rules apply: values reach scripts and programs only as separate
/// arguments, standard input, environment entries or percent-encoded URL parts.
///
/// It logs the destination id and whether it worked, nothing else. The payload is not consumed: whatever the outcome,
/// the caller still holds it.
public struct DestinationRunner: Sendable {
    public let engine: ActionEngine
    public let services: SendServices

    public init(services: SendServices = .live) {
        self.services = services
        engine = ActionEngine(functions: ActionFunctionRegistry(), services: services.actions)
    }

    /// - Parameter confirmed: Pass true after the person confirmed a destination whose `confirmation` is `.preview`.
    public func send(
        _ destination: Destination, payload: Payload, confirmed: Bool = false
    ) async -> Result<SendOutcome, SendError> {
        let result = await perform(destination, payload: payload, confirmed: confirmed)
        switch result {
        case .success:
            AproposLog.app.info("send \(destination.id.rawValue, privacy: .public) succeeded")
        case .failure(let error):
            AproposLog.app.info(
                "send \(destination.id.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .private)"
            )
        }
        return result
    }

    private func perform(
        _ destination: Destination, payload: Payload, confirmed: Bool
    ) async -> Result<SendOutcome, SendError> {
        guard destination.isRunnable else { return .failure(.needsApproval(destination: destination.title)) }
        if let app = destination.appBundleID, !services.isInstalled(app) {
            return .failure(.notInstalled(destination: destination.title))
        }
        guard destination.accepts(payload) else { return .failure(.notApplicable(destination: destination.title)) }
        if let problem = destination.sizeProblem(for: payload) { return .failure(.tooLarge(problem)) }
        if destination.confirmation == .preview, !confirmed { return .failure(.confirmationRequired) }
        if Task.isCancelled { return .failure(.cancelled) }

        let outcome = SendOutcome(destination: destination.id, title: destination.title)
        switch destination.handler {
        case .shareMenu:
            switch await services.share(payload) {
            case .shared: return .success(outcome)
            case .dismissed: return .failure(.cancelled)
            case .unavailable:
                return .failure(.failed(destination: destination.title, hint: destination.failureHint))
            }
        case .chooseFolder:
            // Resolved to a concrete folder before it gets here; nothing to run without one.
            return .failure(.notApplicable(destination: destination.title))
        case .engine:
            guard let variant = destination.variant(for: payload) else {
                return .failure(.notApplicable(destination: destination.title))
            }
            var action = variant.action
            // The payload was matched against the variant above; the engine's context check is not needed.
            action.requires = []
            action.timeout = destination.timeout
            let result = await engine.run(
                action, values: payload.contextValues, target: nil, confirmed: true)
            switch result {
            case .success: return .success(outcome)
            case .failure(.timedOut): return .failure(.timedOut(destination: destination.title))
            case .failure(.cancelled): return .failure(.cancelled)
            case .failure: return .failure(.failed(destination: destination.title, hint: destination.failureHint))
            }
        }
    }
}
