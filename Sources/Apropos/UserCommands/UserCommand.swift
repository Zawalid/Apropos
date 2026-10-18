import Foundation

/// Whether a command may run. Commands that arrive from an import and can run scripts start out `pending`.
public enum CommandReview: String, Sendable, Codable {
    case approved
    /// Waiting for the person to read it and approve. A pending command is stored but never listed, bound to a key,
    /// reachable by URL or Shortcuts, or run.
    case pending
}

/// A command the person made, or imported. It is a `ContextAction` (same backends, variables and safety rules) plus
/// what makes it theirs: aliases, a hotkey, and the switches for running it from outside the app.
public struct UserCommand: Identifiable, Equatable, Sendable {
    public static let currentVersion = 1

    /// `user:<lowercase uuid>`. Never changes, so usage, pins and hotkeys follow the command through edits.
    public let id: ActionID
    public var title: String
    public var subtitle: String?
    /// An SF Symbol name.
    public var symbol: String
    /// Short names typed in the search; a typed alias ranks its command first. Lowercase, unique across commands.
    public var aliases: [String]
    /// Empty means every app; otherwise only these bundle identifiers (or all but `exclude`).
    public var apps: AppFilter
    /// Context that must be present. May be empty for commands that need none.
    public var requires: Set<ContextRequirement>
    public var conditions: Set<ActionCondition>
    public var backend: ActionBackend
    public var output: ActionOutput
    public var needsConfirmation: Bool
    public var keywords: [String]
    public var timeout: TimeInterval
    /// A global shortcut that runs the command on the context of the app in front.
    public var hotkey: HotKeyCombo?
    /// Whether `apropos://run`, Shortcuts and similar outside callers may run it. Off unless the person turns it on.
    public var allowFromURL: Bool
    /// Set once the person confirmed the first outside run. Cleared when the backend changes.
    public var urlConfirmed: Bool
    public var review: CommandReview

    public init(
        id: ActionID = UserCommand.newID(), title: String, subtitle: String? = nil, symbol: String = "star",
        aliases: [String] = [], apps: AppFilter = .anyApp, requires: Set<ContextRequirement> = [],
        conditions: Set<ActionCondition> = [], backend: ActionBackend, output: ActionOutput = .clipboard,
        needsConfirmation: Bool = false, keywords: [String] = [], timeout: TimeInterval = 10,
        hotkey: HotKeyCombo? = nil, allowFromURL: Bool = false, urlConfirmed: Bool = false,
        review: CommandReview = .approved
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.aliases = aliases
        self.apps = apps
        self.requires = requires
        self.conditions = conditions
        self.backend = backend
        self.output = output
        self.needsConfirmation = needsConfirmation
        self.keywords = keywords
        self.timeout = timeout
        self.hotkey = hotkey
        self.allowFromURL = allowFromURL
        self.urlConfirmed = urlConfirmed
        self.review = review
    }

    public static func newID() -> ActionID { ActionID(rawValue: "user:" + UUID().uuidString.lowercased()) }

    /// True when the command may run at all.
    public var isRunnable: Bool { review == .approved }

    /// Shell and AppleScript can do anything the person can. They need approval after an import and are never offered
    /// to outside callers unless the person says so.
    public var runsScripts: Bool {
        switch backend {
        case .shell, .appleScript: true
        default: false
        }
    }

    /// The action the engine runs.
    public var action: ContextAction {
        ContextAction(
            id: id, title: title, subtitle: subtitle, symbol: symbol, requires: requires, conditions: conditions,
            apps: apps, backend: backend, output: output, needsConfirmation: needsConfirmation, keywords: keywords,
            group: .yourCommands, timeout: timeout)
    }
}

// MARK: Files

/// The JSON file of one command. Versioned: a newer file is refused rather than half-read.
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "command": { "id": "user:...", "title": "...", "symbol": "star", "requires": [], "backend": { ... } },
///   "aliases": ["x"], "allowFromURL": false, "urlConfirmed": false, "review": "approved",
///   "hotkey": { "keyCode": 49, "modifiers": ["control", "option"] }
/// }
/// ```
struct UserCommandFile: Codable {
    var schemaVersion = UserCommand.currentVersion
    var command: ActionDefinition
    var aliases: [String]?
    var allowFromURL: Bool?
    var urlConfirmed: Bool?
    var review: CommandReview?
    var hotkey: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, command, aliases, allowFromURL, urlConfirmed, review, hotkey
    }

    /// An entry inside a pack file may leave `schemaVersion` out; the pack carries it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? UserCommand.currentVersion
        command = try container.decode(ActionDefinition.self, forKey: .command)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases)
        allowFromURL = try container.decodeIfPresent(Bool.self, forKey: .allowFromURL)
        urlConfirmed = try container.decodeIfPresent(Bool.self, forKey: .urlConfirmed)
        review = try container.decodeIfPresent(CommandReview.self, forKey: .review)
        hotkey = try container.decodeIfPresent(JSONValue.self, forKey: .hotkey)
    }

    init(_ source: UserCommand) {
        var definition = ActionDefinition(source.action)
        definition.group = nil
        command = definition
        aliases = source.aliases
        allowFromURL = source.allowFromURL
        urlConfirmed = source.urlConfirmed
        review = source.review
        hotkey = source.hotkey.map { SettingsDocument.json(from: .hotkey($0)) }
    }

    /// Builds the command, or says what is wrong with the file.
    func makeCommand() throws -> UserCommand {
        let action = try command.makeAction()
        let combo: HotKeyCombo?
        if let hotkey {
            guard case .hotkey(let parsed)? = SettingsDocument.value(from: hotkey, for: .hotkey), parsed.isValid else {
                throw UserCommandError.badHotkey
            }
            combo = parsed
        } else {
            combo = nil
        }
        return UserCommand(
            id: action.id, title: action.title, subtitle: action.subtitle, symbol: action.symbol,
            aliases: aliases ?? [], apps: action.apps, requires: action.requires, conditions: action.conditions,
            backend: action.backend, output: action.output, needsConfirmation: action.needsConfirmation,
            keywords: action.keywords, timeout: action.timeout, hotkey: combo, allowFromURL: allowFromURL ?? false,
            urlConfirmed: urlConfirmed ?? false, review: review ?? .approved)
    }
}

/// What can be wrong with a command. Messages are for the person editing it and never include running data.
public enum UserCommandError: Error, Equatable, Sendable, CustomStringConvertible {
    case badID
    case titleEmpty
    case titleTooLong
    case badAlias(String)
    case aliasTaken(alias: String, by: String)
    case tooManyAliases
    case invalid(ActionValidationError)
    case badBackend
    case badHotkey
    case hotkeyTaken(by: String)
    case notFound
    case pendingReview
    case newerVersion
    case unreadable
    case saveFailed

    public var description: String {
        switch self {
        case .badID: "The id must be user: followed by lowercase letters, digits and dashes."
        case .titleEmpty: "Give the command a title."
        case .titleTooLong: "The title is too long."
        case .badAlias(let alias): "\"\(alias)\" cannot be an alias: use lowercase letters, digits, dashes and underscores."
        case .aliasTaken(let alias, let title): "The alias \"\(alias)\" already belongs to \(title)."
        case .tooManyAliases: "A command can have at most 8 aliases."
        case .invalid(let error): error.description
        case .badBackend: "The command's backend is incomplete or unknown."
        case .badHotkey: "The shortcut needs at least one modifier key."
        case .hotkeyTaken(let title): "That shortcut is already used by \(title)."
        case .notFound: "That command does not exist."
        case .pendingReview: "That command is waiting for your approval."
        case .newerVersion: "That file was written by a newer version of Apropos."
        case .unreadable: "That file could not be read."
        case .saveFailed: "The command could not be saved."
        }
    }
}

enum UserCommandLimits {
    static let maxTitle = 80
    static let maxAliases = 8
    static let maxAliasLength = 32
    static let maxFileBytes = 256 * 1024
    static let maxSubtitle = 500
    static let maxKeywords = 20
    static let maxKeywordLength = 64
    static let maxScript = 20_000
    static let maxArguments = 64
    static let maxArgumentLength = 4_000
    static let maxNameLength = 200
    static let maxAppEntries = 50
}

enum UserCommandValidator {
    /// Rejects absurdly large fields so a hostile or broken file cannot bloat memory or the palette.
    static func checkSizes(_ command: UserCommand) throws {
        let limits = UserCommandLimits.self
        func fail() -> UserCommandError { .invalid(.tooLarge) }
        if (command.subtitle?.count ?? 0) > limits.maxSubtitle { throw fail() }
        if command.keywords.count > limits.maxKeywords || command.keywords.contains(where: { $0.count > limits.maxKeywordLength }) {
            throw fail()
        }
        if command.symbol.count > 100 { throw fail() }
        if command.apps.include.count > limits.maxAppEntries || command.apps.exclude.count > limits.maxAppEntries { throw fail() }
        func tooBig(_ templates: [ActionTemplate]) -> Bool {
            templates.count > limits.maxArguments || templates.contains { $0.source.count > limits.maxArgumentLength }
        }
        switch command.backend {
        case .function(let name): if name.count > limits.maxNameLength { throw fail() }
        case .shell(let shell):
            if tooBig(shell.arguments) || shell.executable.count > limits.maxArgumentLength { throw fail() }
        case .appleScript(let script):
            if script.source.count > limits.maxScript || tooBig(script.arguments) { throw fail() }
        case .shortcut(let shortcut): if shortcut.name.count > limits.maxNameLength { throw fail() }
        case .urlScheme(let template): if template.source.count > limits.maxArgumentLength { throw fail() }
        case .keyPress, .uiSteps, .sequence: break
        }
    }

    /// Cleans what can be cleaned (case and whitespace of aliases) and throws for the rest. Hotkey and alias
    /// uniqueness need the other commands, so the store checks those.
    static func normalized(_ command: UserCommand, functions: ActionFunctionRegistry) throws -> UserCommand {
        var command = command
        guard command.id.rawValue.hasPrefix("user:"), command.id.isWellFormed else { throw UserCommandError.badID }
        command.title = command.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.title.isEmpty else { throw UserCommandError.titleEmpty }
        guard command.title.count <= UserCommandLimits.maxTitle else { throw UserCommandError.titleTooLong }

        var seen = Set<String>()
        var aliases: [String] = []
        for raw in command.aliases {
            let alias = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if alias.isEmpty { continue }
            let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
            guard alias.count <= UserCommandLimits.maxAliasLength, alias.allSatisfy(allowed.contains) else {
                throw UserCommandError.badAlias(alias)
            }
            if seen.insert(alias).inserted { aliases.append(alias) }
        }
        guard aliases.count <= UserCommandLimits.maxAliases else { throw UserCommandError.tooManyAliases }
        command.aliases = aliases

        if let hotkey = command.hotkey, !hotkey.isValid { throw UserCommandError.badHotkey }
        try checkSizes(command)
        do {
            try ActionValidator.validate(command.action, functions: functions, requireContext: false)
        } catch let error as ActionValidationError {
            throw UserCommandError.invalid(error)
        }
        return command
    }
}
