import Foundation
import Testing

@testable import Apropos

@Suite @MainActor struct CommandDraftTests {
    private func store() -> UserCommandStore {
        UserCommandStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID().uuidString)"))
    }

    @Test func aLinkDraftBecomesACommand() throws {
        var draft = CommandDraft()
        draft.title = "Search Linear"
        draft.alias = "Lin Ear"
        draft.context = .selectedText
        draft.link = "https://linear.app/search?q={text}"
        let made = try store().create(try draft.build())
        #expect(made.aliases == ["lin-ear"])
        #expect(made.requires == [.selectedText])
    }

    @Test func aShortcutDraftCanTakeTheSelection() throws {
        var draft = CommandDraft()
        draft.kind = .shortcut
        draft.title = "Summarize"
        draft.shortcutName = "Summarize Text"
        draft.context = .selectedText
        draft.sendsSelection = true
        let made = try store().create(try draft.build())
        guard case .shortcut(let backend) = made.backend else {
            Issue.record("not a shortcut")
            return
        }
        #expect(backend.input == .text)
    }

    @Test func aProgramDraftNeedsAFullPathAndKeepsArgumentsApart() throws {
        var draft = CommandDraft()
        draft.kind = .program
        draft.title = "Terminal here"
        draft.context = .folder
        draft.program = "/usr/bin/open"
        draft.arguments = "-a\nTerminal\n{directory}"
        let made = try store().create(try draft.build())
        guard case .shell(let backend) = made.backend else {
            Issue.record("not a program")
            return
        }
        #expect(backend.arguments.count == 3)
        draft.program = "open"
        #expect(throws: CommandDraft.Problem.self) { try draft.build() }
    }

    @Test func emptyFieldsExplainWhatIsMissing() {
        var draft = CommandDraft()
        #expect(throws: CommandDraft.Problem.self) { try draft.build() }
        draft.title = "x"
        #expect(throws: CommandDraft.Problem.self) { try draft.build() }
    }

    @Test func aPlaceholderWithoutItsContextIsRefusedByTheStore() throws {
        var draft = CommandDraft()
        draft.title = "Bad"
        draft.link = "https://example.com/?q={text}"
        let command = try draft.build()
        #expect(throws: (any Error).self) { try store().create(command) }
    }
}
