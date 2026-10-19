import Foundation

/// What an `apropos://` link asks for, after parsing. Nothing here has been checked against the person's commands.
public enum ExternalRequest: Equatable, Sendable {
    /// `apropos://open`: show the panel.
    case open
    /// `apropos://search?q=...`: show the panel with this query typed in.
    case search(query: String)
    /// `apropos://run?command=<id or alias>&text=...`: run a command that allows it.
    case run(reference: String, parameters: [ActionVariable: String])
}

public enum ExternalRouteError: Error, Equatable, Sendable, CustomStringConvertible {
    case notOurLink
    case unknownAction(String)
    case missingParameter(String)
    case unknownParameter(String)
    case duplicateParameter(String)
    case badValue(String)

    public var description: String {
        switch self {
        case .notOurLink: "That is not an Apropos link."
        case .unknownAction(let name): "Apropos links do not have an action called \(name)."
        case .missingParameter(let name): "The link needs a \(name) parameter."
        case .unknownParameter(let name): "The link has a parameter Apropos does not accept: \(name)."
        case .duplicateParameter(let name): "The link repeats the \(name) parameter."
        case .badValue(let name): "The \(name) parameter has a value Apropos cannot use."
        }
    }
}

/// Why a request was not carried out.
public enum ExternalRejection: Error, Equatable, Sendable, CustomStringConvertible {
    case route(ExternalRouteError)
    /// No command with that id or alias is available to outside callers. One answer for "does not exist", "not allowed",
    /// and "waiting for approval", so a caller learns nothing about what the person has.
    case notAvailable
    /// A parameter value does not fit the variable it is for (a url that is not http or https, a relative path).
    case badParameter(String)
    /// The person turned off control from outside.
    case turnedOff

    public var description: String {
        switch self {
        case .route(let error): error.description
        case .notAvailable: "No command like that is set up to run from links or Shortcuts."
        case .badParameter(let name): "The \(name) value cannot be used."
        case .turnedOff: "Control from outside is turned off in the Apropos settings."
        }
    }
}

public enum ExternalRouter {
    public static let scheme = "apropos"
    /// Variables a link may supply. They describe the thing to act on, never how to act.
    public static let allowedVariables: [ActionVariable] = [.text, .url, .title, .file, .folder]
    static let maxTextLength = ContextLimits.maxValueTextLength
    static let maxValueLength = 4_096
    static let maxQueryLength = 500

    /// Parses a link strictly: only the three known actions, only their own parameters, each at most once, no path,
    /// port, user info or fragment.
    public static func parse(_ url: URL) -> Result<ExternalRequest, ExternalRouteError> {
        guard url.scheme?.lowercased() == scheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .failure(.notOurLink) }
        guard components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else { return .failure(.notOurLink) }
        let action = (components.host ?? "").lowercased()

        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard values[item.name] == nil else { return .failure(.duplicateParameter(item.name)) }
            values[item.name] = item.value ?? ""
        }

        switch action {
        case "open":
            if let extra = values.keys.sorted().first { return .failure(.unknownParameter(extra)) }
            return .success(.open)

        case "search":
            if let extra = values.keys.sorted().first(where: { $0 != "q" }) { return .failure(.unknownParameter(extra)) }
            guard let raw = values["q"] else { return .failure(.missingParameter("q")) }
            guard raw.count <= maxQueryLength else { return .failure(.badValue("q")) }
            let cleaned = String(raw.map { $0.isNewline || $0 == "\t" || $0.unicodeScalars.contains { $0.value < 0x20 } ? " " : $0 })
            return .success(.search(query: cleaned.trimmingCharacters(in: .whitespaces)))

        case "run":
            let allowed = Set(["command"] + allowedVariables.map(\.rawValue))
            if let extra = values.keys.sorted().first(where: { !allowed.contains($0) }) {
                return .failure(.unknownParameter(extra))
            }
            guard let reference = values["command"], !reference.isEmpty else {
                return .failure(.missingParameter("command"))
            }
            guard reference.count <= 100, !reference.contains(where: { $0.isNewline }) else {
                return .failure(.badValue("command"))
            }
            var parameters: [ActionVariable: String] = [:]
            for variable in allowedVariables {
                guard let value = values[variable.rawValue] else { continue }
                let limit = variable == .text ? maxTextLength : maxValueLength
                guard value.count <= limit, !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
                    return .failure(.badValue(variable.rawValue))
                }
                parameters[variable] = value
            }
            return .success(.run(reference: reference, parameters: parameters))

        default:
            return .failure(.unknownAction(action))
        }
    }

    /// Context values built only from what the caller supplied. Live context is never mixed in: an outside request runs
    /// on exactly what it passed. Every value is data for the engine's variable rules, never program text.
    static func values(from parameters: [ActionVariable: String]) -> Result<ContextValues, ExternalRejection> {
        var values = ContextValues()
        if let text = parameters[.text], !text.isEmpty { values.selectedText = text }
        if let url = parameters[.url] {
            guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                parsed.host != nil
            else { return .failure(.badParameter("url")) }
            values.pageURL = parsed
        }
        if let title = parameters[.title] { values.pageTitle = title }
        if let file = parameters[.file] {
            guard file.hasPrefix("/") else { return .failure(.badParameter("file")) }
            values.selectedFiles = [URL(fileURLWithPath: file)]
        }
        if let folder = parameters[.folder] {
            guard folder.hasPrefix("/") else { return .failure(.badParameter("folder")) }
            values.folderURL = URL(fileURLWithPath: folder)
        }
        return .success(values)
    }
}

/// A command ready to run on behalf of an outside caller, with what is still needed from the person.
public struct ExternalRun: Equatable, Sendable {
    /// The command with outside-run limits applied: a replace-the-selection result goes to the clipboard instead.
    public let command: UserCommand
    public let values: ContextValues
    /// True the first time an outside caller runs this command, and every time for commands that ask for confirmation.
    public let needsConfirmation: Bool
    public let isFirstUse: Bool
}

/// Resolves outside requests (links, Shortcuts) against the person's commands and runs them under one set of rules:
/// only commands marked "allow from URL" and approved, a confirmation the first time, values only from the request, and
/// the same engine and injection rules as anything else.
@MainActor
public struct ExternalRunner {
    public let store: UserCommandStore
    public let center: ContextActionCenter
    /// False when the person turned off control from outside: nothing resolves.
    public var isEnabled = true
    /// Ask before every outside run, not only the first.
    public var alwaysConfirm = false

    public init(store: UserCommandStore, center: ContextActionCenter) {
        self.store = store
        self.center = center
    }

    /// Commands an outside caller may run, by title.
    public var available: [UserCommand] { isEnabled ? store.runnable.filter(\.allowFromURL) : [] }

    /// Available commands whose title, alias or id contains `text`.
    public func search(_ text: String) -> [UserCommand] {
        let wanted = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return available }
        return available.filter { command in
            command.title.lowercased().contains(wanted) || command.aliases.contains { $0.contains(wanted) }
                || command.id.rawValue == wanted
        }
    }

    public func resolve(
        reference: String, parameters: [ActionVariable: String]
    ) -> Result<ExternalRun, ExternalRejection> {
        guard isEnabled else { return .failure(.turnedOff) }
        guard let command = store.runnableCommand(matching: reference), command.allowFromURL else {
            return .failure(.notAvailable)
        }
        let values: ContextValues
        switch ExternalRouter.values(from: parameters) {
        case .success(let built): values = built
        case .failure(let rejection): return .failure(rejection)
        }
        var limited = command
        if limited.output == .replaceSelection { limited.output = .clipboard }
        return .success(
            ExternalRun(
                command: limited, values: values, needsConfirmation: alwaysConfirm || !command.urlConfirmed || command.needsConfirmation,
                isFirstUse: !command.urlConfirmed))
    }

    /// Runs a resolved request. Pass `confirmed: true` only after the person said yes when `needsConfirmation` was true.
    public func perform(
        _ run: ExternalRun, confirmed: Bool, target: TargetApp?
    ) async -> Result<ActionOutcome, ActionError> {
        if run.needsConfirmation, !confirmed { return .failure(.confirmationRequired) }
        if run.isFirstUse { try? store.markURLConfirmed(run.command.id) }
        return await center.run(run.command, values: run.values, target: target, confirmed: confirmed || !run.needsConfirmation)
    }
}
