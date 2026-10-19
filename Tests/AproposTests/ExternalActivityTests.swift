import Foundation
import Testing

@testable import Apropos

@MainActor
struct ExternalActivityTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)/activity.json")
    }

    private func command(alias: String? = "up") throws -> UserCommand {
        UserCommand(
            title: "Shout", aliases: alias.map { [$0] } ?? [], requires: [.selectedText],
            backend: .shell(ShellBackend(executable: "/usr/bin/tr", arguments: [try ActionTemplate("a-z"), try ActionTemplate("A-Z")], standardInput: .text)),
            output: .clipboard)
    }

    @Test func linksParseBackToTheRequestTheyDescribe() throws {
        let link = ExternalLinks.run(command: try command(), parameters: [.text: "hello world & more", .url: "https://swift.org/a b"])
        let parsed = try #require(URL(string: link))
        guard case .success(.run(let reference, let parameters)) = ExternalRouter.parse(parsed) else {
            Issue.record("did not parse")
            return
        }
        #expect(reference == "up")
        #expect(parameters[.text] == "hello world & more")
        #expect(parameters[.url] == "https://swift.org/a b")
        #expect(ExternalRouter.parse(URL(string: ExternalLinks.open)!) == .success(.open))
        #expect(ExternalRouter.parse(URL(string: ExternalLinks.search("a b"))!) == .success(.search(query: "a b")))
    }

    @Test func aCommandWithoutAnAliasUsesItsID() throws {
        let command = try command(alias: nil)
        #expect(ExternalLinks.run(command: command).contains(command.id.rawValue.replacingOccurrences(of: ":", with: "%3A")))
    }

    @Test func activityKeepsTheLastFiftyNewestFirstAndNoValues() {
        let log = ExternalActivityLog(url: tempURL())
        for index in 0..<60 { log.record(action: "run", command: "C\(index)", result: .ran, at: Date(timeIntervalSince1970: Double(index))) }
        #expect(log.entries.count == ExternalActivityLog.limit)
        #expect(log.entries.first?.command == "C59")
        log.clear()
        #expect(log.entries.isEmpty)
    }

    @Test func activityPersists() {
        let url = tempURL()
        ExternalActivityLog(url: url).record(action: "open", result: .ran)
        #expect(ExternalActivityLog(url: url).entries.count == 1)
    }

    @Test func turnedOffMeansNothingResolves() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)")
        let store = UserCommandStore(directory: directory)
        var made = try command()
        made.allowFromURL = true
        _ = try store.create(made)
        var runner = ExternalRunner(store: store, center: ContextActionCenter(library: ActionPackLibrary(), engine: ActionEngine()))
        #expect(runner.available.count == 1)
        runner.isEnabled = false
        #expect(runner.available.isEmpty)
        #expect(runner.resolve(reference: "up", parameters: [:]) == .failure(.turnedOff))
        runner.isEnabled = true
        runner.alwaysConfirm = true
        if case .success(let run) = runner.resolve(reference: "up", parameters: [:]) { #expect(run.needsConfirmation) }
    }

    @Test func resettingTheConfirmationAsksAgain() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ext-\(UUID().uuidString)")
        let store = UserCommandStore(directory: directory)
        var made = try command()
        made.allowFromURL = true
        let stored = try store.create(made)
        try store.markURLConfirmed(stored.id)
        #expect(store.command(withID: stored.id)?.urlConfirmed == true)
        try store.resetURLConfirmation(stored.id)
        #expect(store.command(withID: stored.id)?.urlConfirmed == false)
    }
}
