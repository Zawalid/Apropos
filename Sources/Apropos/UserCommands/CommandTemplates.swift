import Foundation

/// A ready-made command to start from. Each is harmless to run and uses the same engine and safety rules as any other
/// command, so adding one is the same as writing it by hand.
public struct CommandTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    /// One plain sentence: what it does and when it is offered.
    public let summary: String
    public let symbol: String
    public let alias: String?
    private let backend: ActionBackend
    private let requires: Set<ContextRequirement>
    private let output: ActionOutput
    private let timeout: TimeInterval

    init(
        id: String, title: String, summary: String, symbol: String, alias: String?, backend: ActionBackend,
        requires: Set<ContextRequirement>, output: ActionOutput = .none, timeout: TimeInterval = 10
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.alias = alias
        self.backend = backend
        self.requires = requires
        self.output = output
        self.timeout = timeout
    }

    /// A new command with a fresh id, ready for `UserCommandStore.create`.
    public func command() -> UserCommand {
        UserCommand(
            title: title, subtitle: summary, symbol: symbol, aliases: alias.map { [$0] } ?? [], requires: requires,
            backend: backend, output: output, timeout: timeout)
    }

    public static let all: [CommandTemplate] = {
        func template(
            _ id: String, _ title: String, _ summary: String, _ symbol: String, alias: String?,
            requires: Set<ContextRequirement>, output: ActionOutput = .none, timeout: TimeInterval = 10,
            backend: () throws -> ActionBackend
        ) -> CommandTemplate? {
            guard let backend = try? backend() else { return nil }
            return CommandTemplate(
                id: id, title: title, summary: summary, symbol: symbol, alias: alias, backend: backend,
                requires: requires, output: output, timeout: timeout)
        }
        return [
            template(
                "terminal-here", "Open in Terminal here", "Opens the folder you are looking at in Terminal.",
                "terminal", alias: "term", requires: [.folder]
            ) {
                .shell(
                    ShellBackend(
                        executable: "/usr/bin/open",
                        arguments: [try ActionTemplate("-a"), try ActionTemplate("Terminal"), try ActionTemplate("{directory}")],
                        standardInput: nil, workingDirectory: nil))
            },
            template(
                "search-web", "Search the web for the selection", "Searches Google for the text you selected.",
                "magnifyingglass", alias: "google", requires: [.selectedText]
            ) {
                .urlScheme(try ActionTemplate("https://www.google.com/search?q={text}"))
            },
            template(
                "speak", "Speak the selection", "Reads the selected text aloud. A harmless one to try first.",
                "speaker.wave.2", alias: "say", requires: [.selectedText], timeout: 30
            ) {
                .shell(ShellBackend(executable: "/usr/bin/say", arguments: [], standardInput: .text))
            },
            template(
                "open-docs", "Open Apple documentation", "Opens developer.apple.com/documentation in your browser.",
                "book", alias: "docs", requires: []
            ) {
                .urlScheme(try ActionTemplate("https://developer.apple.com/documentation"))
            },
        ].compactMap { $0 }
    }()
}
