import Foundation

/// The identity of an action: stable across releases, used as the command identity and the usage key. Built-in
/// actions start with `ctx:` (`ctx:text.upper`), user actions with `user:`, pack actions with their pack's prefix.
public struct ActionID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral
{
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// `prefix:rest`, lowercase letters, digits and `. _ -`.
    var isWellFormed: Bool {
        let halves = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789._-")
        return rawValue.filter { $0 != ":" }.allSatisfy(allowed.contains)
    }
}

/// The section of the palette an action is listed under.
public enum ActionGroup: String, Sendable, CaseIterable, Codable {
    case selectedText
    case selectedFiles
    case page
    case folder
    /// Commands the person made.
    case yourCommands

    public var title: String {
        switch self {
        case .selectedText: "Selected text"
        case .selectedFiles: "Selected files"
        case .page: "This page"
        case .folder: "This folder"
        case .yourCommands: "Your commands"
        }
    }

    static func inferred(from requirements: Set<ContextRequirement>) -> ActionGroup {
        if requirements.contains(.selectedText) { return .selectedText }
        if requirements.contains(.selectedFiles) { return .selectedFiles }
        if requirements.contains(.pageURL) { return .page }
        return .folder
    }
}

/// Facts about the selection beyond its presence. Evaluated against the values, so an action that only makes sense
/// for a URL or for JSON shows up only then.
public enum ActionCondition: String, Sendable, CaseIterable, Codable {
    case selectionIsURL
    case selectionIsJSON
    case selectionIsMultiline

    func holds(for values: ContextValues) -> Bool {
        guard let text = values.selectedText else { return false }
        switch self {
        case .selectionIsURL:
            return TextTools.webURL(from: text) != nil
        case .selectionIsJSON:
            return TextTools.isJSON(text)
        case .selectionIsMultiline:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).contains(where: \.isNewline)
        }
    }
}

/// Restricts an action to some apps, by bundle identifier. An empty `include` means every app.
public struct AppFilter: Sendable, Equatable, Codable {
    public var include: Set<String>
    public var exclude: Set<String>

    public init(include: Set<String> = [], exclude: Set<String> = []) {
        self.include = include
        self.exclude = exclude
    }

    public static let anyApp = AppFilter()

    public func allows(_ bundleID: String?) -> Bool {
        if let bundleID, exclude.contains(bundleID) { return false }
        if include.isEmpty { return true }
        return bundleID.map(include.contains) ?? false
    }
}

/// What happens to an action's result text.
public enum ActionOutput: String, Sendable, Codable, CaseIterable {
    /// Put it on the clipboard. The default.
    case clipboard
    /// Replace the selection with it. Falls back to the clipboard where the selection cannot be edited.
    case replaceSelection
    /// Show it in a short notification.
    case notify
    /// Discard it. For actions whose effect is the point (reveal in Finder).
    case none
}

public struct ShellBackend: Sendable, Equatable {
    /// Absolute path of the program. Literal: no placeholders.
    public var executable: String
    public var arguments: [ActionTemplate]
    /// A variable written to the program's standard input.
    public var standardInput: ActionVariable?
    /// A variable naming the working directory.
    public var workingDirectory: ActionVariable?

    public init(
        executable: String, arguments: [ActionTemplate] = [], standardInput: ActionVariable? = nil,
        workingDirectory: ActionVariable? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.standardInput = standardInput
        self.workingDirectory = workingDirectory
    }
}

public struct AppleScriptBackend: Sendable, Equatable {
    /// The script, literal. Variables reach it only as the items of `argv` in `on run argv`.
    public var source: String
    public var arguments: [ActionTemplate]

    public init(source: String, arguments: [ActionTemplate] = []) {
        self.source = source
        self.arguments = arguments
    }
}

public struct ShortcutBackend: Sendable, Equatable {
    /// The name of the Shortcut, literal.
    public var name: String
    /// A variable given to the Shortcut as its input.
    public var input: ActionVariable?

    public init(name: String, input: ActionVariable? = nil) {
        self.name = name
        self.input = input
    }
}

public struct KeyPressBackend: Sendable, Equatable {
    public var keyCode: UInt32
    public var modifiers: ModifierSet

    public init(keyCode: UInt32, modifiers: ModifierSet = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// How an action does its work.
public enum ActionBackend: Sendable, Equatable {
    /// A Swift function from `ActionFunctionRegistry`, by name.
    case function(String)
    /// A program with arguments. Never a shell line.
    case shell(ShellBackend)
    case appleScript(AppleScriptBackend)
    /// An Apple Shortcut, by name, run with `shortcuts run`.
    case shortcut(ShortcutBackend)
    /// Opens a URL. Every placeholder is percent-encoded and none may appear before the path.
    case urlScheme(ActionTemplate)
    case keyPress(KeyPressBackend)
    /// Menu picks (and later presses) in other apps through Accessibility. See `UIStepsBackend`.
    case uiSteps(UIStepsBackend)
}

/// One thing Apropos can do with the current context.
public struct ContextAction: Sendable, Identifiable, Equatable {
    public let id: ActionID
    public var title: String
    public var subtitle: String?
    /// An SF Symbol name.
    public var symbol: String
    /// Context that must all be present.
    public var requires: Set<ContextRequirement>
    public var conditions: Set<ActionCondition>
    public var apps: AppFilter
    public var backend: ActionBackend
    public var output: ActionOutput
    /// Ask before running: for actions that delete, overwrite or send.
    public var needsConfirmation: Bool
    /// Extra words the palette search matches.
    public var keywords: [String]
    public var group: ActionGroup
    public var timeout: TimeInterval

    public init(
        id: ActionID, title: String, subtitle: String? = nil, symbol: String, requires: Set<ContextRequirement>,
        conditions: Set<ActionCondition> = [], apps: AppFilter = .anyApp, backend: ActionBackend,
        output: ActionOutput = .clipboard, needsConfirmation: Bool = false, keywords: [String] = [],
        group: ActionGroup? = nil, timeout: TimeInterval = 10
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.requires = requires
        self.conditions = conditions
        self.apps = apps
        self.backend = backend
        self.output = output
        self.needsConfirmation = needsConfirmation
        self.keywords = keywords
        self.group = group ?? ActionGroup.inferred(from: requires)
        self.timeout = timeout
    }

    /// Whether the action is on offer for this app and these values.
    public func applies(to values: ContextValues, bundleID: String?) -> Bool {
        apps.allows(bundleID) && requires.allSatisfy(values.has) && conditions.allSatisfy { $0.holds(for: values) }
    }
}
