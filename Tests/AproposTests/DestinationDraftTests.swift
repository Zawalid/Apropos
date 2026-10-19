import Foundation
import Testing

@testable import Apropos

@Suite struct DestinationDraftTests {
    private func library(_ data: Data) -> DestinationLibrary {
        var library = DestinationLibrary()
        library.add(packData: data, source: "t.json", origin: .user)
        return library
    }

    @Test func aLinkDraftBecomesARunnableDestination() throws {
        var draft = DestinationDraft()
        draft.title = "Bear inbox"
        draft.link = "bear://x-callback-url/create?text={text}"
        let found = library(try draft.packData()).runnable
        #expect(found.count == 1)
        #expect(found[0].title == "Bear inbox")
    }

    @Test func aShortcutAndAFileDraftAreAccepted() throws {
        var shortcut = DestinationDraft()
        shortcut.kind = .shortcut
        shortcut.title = "Summarize"
        shortcut.shortcutName = "Summarize Text"
        #expect(library(try shortcut.packData()).runnable.count == 1)
        var file = DestinationDraft()
        file.kind = .appendToFile
        file.title = "Running notes"
        file.filePath = "/Users/me/notes.txt"
        #expect(library(try file.packData()).runnable.count == 1)
    }

    @Test func missingFieldsExplainWhatIsMissing() {
        var draft = DestinationDraft()
        #expect(throws: DestinationDraft.Problem.self) { try draft.packData() }
        draft.title = "x"
        #expect(throws: DestinationDraft.Problem.self) { try draft.packData() }
        draft.kind = .appendToFile
        draft.filePath = "notes.txt"
        #expect(throws: DestinationDraft.Problem.self) { try draft.packData() }
    }

    @Test func saveWritesAPackIntoTheFolder() throws {
        var draft = DestinationDraft()
        draft.title = "Bear inbox"
        draft.link = "bear://x-callback-url/create?text={text}"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dest-\(UUID().uuidString)")
        let url = try draft.save(to: directory)
        #expect(url.lastPathComponent == "my-bear-inbox.json")
        #expect(DestinationLibrary.bundled(plus: directory).destinations.contains { $0.title == "Bear inbox" })
    }

    @Test func togglesPersist() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tog-\(UUID().uuidString).json")
        let toggles = DestinationToggles(url: url)
        let id = ActionID(rawValue: "dest:bear")
        toggles.set(id, enabled: false)
        #expect(DestinationToggles(url: url).disabled == [id])
        toggles.set(id, enabled: true)
        #expect(DestinationToggles(url: url).disabled.isEmpty)
    }

    @Test func summaryNamesWhatItRuns() throws {
        var draft = DestinationDraft()
        draft.title = "Bear inbox"
        draft.link = "bear://x-callback-url/create?text={text}"
        let destination = try #require(library(try draft.packData()).runnable.first)
        let lines = DestinationSummary.lines(for: destination)
        #expect(lines.contains { $0.contains("Opens") })
        #expect(DestinationSummary.risks(for: destination).contains(.opensLink))
    }
}
