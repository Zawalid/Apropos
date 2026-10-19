import Foundation

/// What a person fills in to make a command by hand: a few plain fields that become a validated `UserCommand`.
public struct CommandDraft: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case link, shortcut, program

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .link: "Open a link"
            case .shortcut: "Run a Shortcut"
            case .program: "Run a program"
            }
        }

        public var explanation: String {
            switch self {
            case .link: "Opens a web address or an app link. Write {text} where the selected text should go."
            case .shortcut: "Runs an Apple Shortcut you already made, by its name."
            case .program: "Runs a program on this Mac. Anything that runs a program is kept as a script."
            }
        }

        public var symbol: String {
            switch self {
            case .link: "link"
            case .shortcut: "square.stack.3d.up"
            case .program: "terminal"
            }
        }
    }

    /// What has to be present for the command to be offered.
    public enum Context: String, CaseIterable, Sendable, Identifiable {
        case anywhere, selectedText, folder, selectedFiles, pageURL

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .anywhere: "Anywhere"
            case .selectedText: "When text is selected"
            case .folder: "When a folder is open"
            case .selectedFiles: "When files are selected"
            case .pageURL: "On a web page"
            }
        }

        var requirement: ContextRequirement? {
            switch self {
            case .anywhere: nil
            case .selectedText: .selectedText
            case .folder: .folder
            case .selectedFiles: .selectedFiles
            case .pageURL: .pageURL
            }
        }
    }

    public struct Problem: Error, Equatable, Sendable, CustomStringConvertible {
        public let description: String
    }

    public var kind: Kind = .link
    public var title = ""
    public var alias = ""
    public var context: Context = .anywhere
    /// For a link: the address, with optional placeholders such as {text}.
    public var link = ""
    public var shortcutName = ""
    /// For a program: its absolute path, then one argument per line.
    public var program = ""
    public var arguments = ""
    /// Hands the selected text to the Shortcut or program as its input. Only with "When text is selected".
    public var sendsSelection = false

    public init() {}

    /// The command this draft describes, with a fresh id. It is checked again by the store when saved.
    public func build() throws -> UserCommand {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Problem(description: "Give the command a name.") }
        let cleanAlias = alias.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        let requires: Set<ContextRequirement> = context.requirement.map { [$0] } ?? []
        let input: ActionVariable? = sendsSelection && context == .selectedText ? .text : nil
        let backend: ActionBackend
        var output = ActionOutput.none
        switch kind {
        case .link:
            let address = link.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { throw Problem(description: "Enter the address to open.") }
            do { backend = .urlScheme(try ActionTemplate(address)) } catch {
                throw Problem(description: "That address cannot be used: \(error)")
            }
        case .shortcut:
            let shortcut = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !shortcut.isEmpty else { throw Problem(description: "Enter the name of the Shortcut.") }
            backend = .shortcut(ShortcutBackend(name: shortcut, input: input))
        case .program:
            let path = program.trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else {
                throw Problem(description: "Enter the full path of the program, starting with /.")
            }
            do {
                let lines = arguments.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                backend = .shell(
                    ShellBackend(
                        executable: path, arguments: try lines.filter { !$0.isEmpty }.map { try ActionTemplate($0) },
                        standardInput: input))
            } catch {
                throw Problem(description: "An argument cannot be used: \(error)")
            }
            output = input == nil ? .none : .notify
        }
        return UserCommand(
            title: name, symbol: kind.symbol, aliases: cleanAlias.isEmpty ? [] : [cleanAlias], requires: requires,
            backend: backend, output: output, timeout: kind == .program ? 30 : 10)
    }
}
