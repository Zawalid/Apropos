import Foundation

/// Whether the person must see what will be sent and press Return once more.
public enum DestinationConfirmation: String, Sendable, Codable, Equatable {
    case none
    /// A one-line preview and a confirming Return. For anything that leaves the Mac or leaves a visible side effect.
    case preview
}

/// Whether a destination may run. User-pack destinations that run a program, a script or a Shortcut start out
/// `pending`, exactly like imported user commands, and do nothing until they are marked approved.
public enum DestinationReview: String, Sendable, Codable, Equatable {
    case approved
    case pending
}

/// Where a destination came from. Bundled ones are part of the app; user ones are files in the destinations folder.
public enum DestinationOrigin: String, Sendable, Equatable {
    case bundled
    case user
}

/// How a destination does its work.
public enum DestinationHandler: Sendable, Equatable {
    /// One of the variants runs through the action engine (a URL scheme, an AppleScript, a program, a Shortcut).
    case engine
    /// The system Share menu. Needs the app to present it, so it goes through `SendServices.share`.
    case shareMenu
    /// Asks the person for a folder first (copy or move into it), then sends to that folder. `SendToCenter` resolves it
    /// to a concrete folder destination before anything runs.
    case chooseFolder(move: Bool)
}

/// One way a destination handles a kind of payload: an engine backend, checked by the same validator as every context
/// action. A destination with several variants uses the first one whose payload kind matches and whose placeholders
/// the payload can fill (a note with a source link, then a note without).
public struct DestinationVariant: Sendable, Equatable {
    /// The payload kinds this variant is for. Empty means every kind the destination accepts.
    public var kinds: Set<PayloadKind>
    /// The validated action. Its `output` is `.none`; its `requires` only satisfy the validator and are not enforced.
    public var action: ContextAction

    public init(kinds: Set<PayloadKind> = [], action: ContextAction) {
        self.kinds = kinds
        self.action = action
    }

    /// The variables the backend fills from the payload.
    var variables: [ActionVariable] {
        switch action.backend {
        case .shell(let shell):
            shell.arguments.flatMap(\.variables) + [shell.standardInput, shell.workingDirectory].compactMap { $0 }
        case .appleScript(let script): script.arguments.flatMap(\.variables)
        case .shortcut(let shortcut): [shortcut.input].compactMap { $0 }
        case .urlScheme(let template): template.variables
        default: []
        }
    }

    /// Whether the payload has a value for every placeholder.
    func canFill(from payload: Payload) -> Bool {
        let input = ActionInput(values: payload.contextValues)
        return variables.allSatisfy { input.scalar($0) != nil || input.list($0) != nil }
    }

    /// True when running it can run a program or a script, which is what needs the person's approval.
    var runsCode: Bool {
        switch action.backend {
        case .shell, .appleScript, .shortcut: true
        default: false
        }
    }

    /// True when the backend opens a web address, which hands the payload to a website.
    var opensWebAddress: Bool {
        guard case .urlScheme(let template) = action.backend, case .literal(let head)? = template.parts.first else {
            return false
        }
        let scheme = head.prefix { $0 != ":" }.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

/// A place the selection, page, files or folder can be sent. Data wherever possible: a destination is a JSON entry in a
/// pack that reuses the action engine's backends and its safety rules.
public struct Destination: Sendable, Identifiable, Equatable {
    /// Stable, like `dest:notes`. Usage, recents and the run log follow it across releases. Never rename a shipped id.
    public let id: ActionID
    public var title: String
    public var subtitle: String?
    /// An SF Symbol name.
    public var symbol: String
    public var keywords: [String]
    /// The app that must be installed, by bundle identifier. Nil for destinations that need no app.
    public var appBundleID: String?
    public var accepts: Set<PayloadKind>
    public var variants: [DestinationVariant]
    public var handler: DestinationHandler
    public var confirmation: DestinationConfirmation
    /// What the confirmation line says will happen: "Create a draft in Mail".
    public var previewVerb: String?
    /// A lower text limit than `PayloadLimits.maxTextCharacters`, for destinations that cannot take long text.
    public var maxTextCharacters: Int?
    public var timeout: TimeInterval
    /// A sentence added to the failure message when this destination fails, for the likely cause.
    public var failureHint: String?
    /// True when the title already reads as an action ("Copy to Downloads"), so a direct row does not add "Send ... to".
    public var titleIsAction: Bool
    public var review: DestinationReview
    public var origin: DestinationOrigin

    public init(
        id: ActionID, title: String, subtitle: String? = nil, symbol: String, keywords: [String] = [],
        appBundleID: String? = nil, accepts: Set<PayloadKind>, variants: [DestinationVariant] = [],
        handler: DestinationHandler = .engine, confirmation: DestinationConfirmation = .none,
        previewVerb: String? = nil, maxTextCharacters: Int? = nil, timeout: TimeInterval = 15,
        failureHint: String? = nil, titleIsAction: Bool = false, review: DestinationReview = .approved,
        origin: DestinationOrigin = .bundled
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.keywords = keywords
        self.appBundleID = appBundleID
        self.accepts = accepts
        self.variants = variants
        self.handler = handler
        self.confirmation = confirmation
        self.previewVerb = previewVerb
        self.maxTextCharacters = maxTextCharacters
        self.timeout = timeout
        self.failureHint = failureHint
        self.titleIsAction = titleIsAction
        self.review = review
        self.origin = origin
    }

    public var isRunnable: Bool { review == .approved }

    /// Whether this destination takes this payload at all (kind and size), ignoring whether its app is installed.
    public func accepts(_ payload: Payload) -> Bool {
        guard accepts.contains(payload.kind) else { return false }
        if handler != .engine { return true }
        return variant(for: payload) != nil
    }

    /// Why the payload is too big for this destination, or nil.
    public func sizeProblem(for payload: Payload) -> String? {
        if let limit = maxTextCharacters, payload.textLength > limit {
            return "Too long for \(title) (\(limit.formatted()) characters at most)"
        }
        return nil
    }

    /// The first variant that handles the payload's kind and can fill its placeholders.
    public func variant(for payload: Payload) -> DestinationVariant? {
        variants.first { ($0.kinds.isEmpty || $0.kinds.contains(payload.kind)) && $0.canFill(from: payload) }
    }

    /// True when any variant runs a program, a script or a Shortcut.
    var runsCode: Bool { variants.contains(where: \.runsCode) }

    /// True when any variant hands the payload to a website.
    var opensWebAddress: Bool { variants.contains(where: \.opensWebAddress) }

    /// The line shown before sending: "Create a draft in Mail: "Title" (240 characters)".
    public func previewLine(for payload: Payload) -> String {
        let verb = previewVerb ?? "Send to \(title)"
        return "\(verb): \(payload.previewLine)"
    }
}
