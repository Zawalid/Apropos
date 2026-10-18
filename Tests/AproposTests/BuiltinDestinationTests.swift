import AppKit
import Foundation
import Testing

@testable import Apropos

@Suite("Send to: built-in destinations")
struct BuiltinDestinationTests {
    static let library = DestinationLibrary.bundled()

    private func destination(_ id: String) throws -> Destination {
        try #require(Self.library.destination(for: ActionID(rawValue: id)))
    }

    private func recorder(installing apps: String...) -> SendRecorder {
        let recorder = SendRecorder()
        recorder.installed = Set(apps)
        return recorder
    }

    private let page = Payload.page(url: URL(string: "https://swift.org/blog?a=1&b=2"), title: "Swift \"Blog\" & more")
    private let source = URL(string: "https://swift.org/blog")

    @Test func theCatalogueLoadsCleanlyAndEveryDestinationIsRunnable() {
        #expect(Self.library.issues.isEmpty)
        #expect(
            Self.library.destinations.map(\.id.rawValue)
                == [
                    "dest:notes", "dest:reminders", "dest:things", "dest:obsidian", "dest:bear", "dest:mail",
                    "dest:share",
                ])
        #expect(Self.library.pending.isEmpty)
        #expect(Self.library.destinations.allSatisfy { $0.origin == .bundled })
    }

    @Test func everySymbolExists() {
        for destination in Self.library.destinations {
            #expect(
                NSImage(systemSymbolName: destination.symbol, accessibilityDescription: nil) != nil, "\(destination.id)"
            )
        }
        for move in [false, true] {
            let chooser = FolderDestinations.chooser(move: move)
            #expect(NSImage(systemSymbolName: chooser.symbol, accessibilityDescription: nil) != nil)
            let folder = FolderDestinations.destination(for: URL(fileURLWithPath: "/tmp/x"), move: move)
            #expect(folder.flatMap { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) } != nil)
        }
    }

    @Test func appsAreDetectedByBundleIdentifier() throws {
        let ids = Dictionary(uniqueKeysWithValues: Self.library.destinations.map { ($0.id.rawValue, $0.appBundleID) })
        #expect(ids["dest:notes"] == "com.apple.Notes")
        #expect(ids["dest:reminders"] == "com.apple.reminders")
        #expect(ids["dest:things"] == "com.culturedcode.ThingsMac")
        #expect(ids["dest:obsidian"] == "md.obsidian")
        #expect(ids["dest:bear"] == "net.shinyfrog.bear")
        #expect(ids["dest:mail"] == "com.apple.mail")
        #expect(ids["dest:share"] == .some(nil))
    }

    @Test func aDestinationWhoseAppIsMissingDoesNotRun() async throws {
        let recorder = recorder()
        let payload = try #require(Payload.text("hello"))
        let result = await recorder.runner.send(try destination("dest:notes"), payload: payload)
        #expect(result == .failure(.notInstalled(destination: "Notes")))
        #expect(recorder.processes.isEmpty)
        #expect(recorder.opened.isEmpty)
    }

    // MARK: Notes and Reminders

    @Test func notesTakesTheTextAsTheBodyAndTheSourceAsALink() async throws {
        let recorder = recorder(installing: "com.apple.Notes")
        let payload = try #require(Payload.text("Buy milk\nand eggs", source: source))
        let result = await recorder.runner.send(try destination("dest:notes"), payload: payload)
        #expect(result == .success(SendOutcome(destination: "dest:notes", title: "Notes")))
        let request = try #require(recorder.processes.first)
        #expect(request.executable == "/usr/bin/osascript")
        #expect(request.arguments[2] == "--")
        #expect(Array(request.arguments.dropFirst(3)) == ["Buy milk", "Buy milk\nand eggs", "https://swift.org/blog"])
        #expect(request.arguments[1].contains("tell application \"Notes\""))
    }

    @Test func notesWithoutASourceSendsAnEmptyLink() async throws {
        let recorder = recorder(installing: "com.apple.Notes")
        _ = await recorder.runner.send(try destination("dest:notes"), payload: try #require(Payload.text("just text")))
        let request = try #require(recorder.processes.first)
        #expect(Array(request.arguments.dropFirst(3)) == ["just text", "just text", ""])
    }

    @Test func notesTakesAPageAsATitleAndALink() async throws {
        let recorder = recorder(installing: "com.apple.Notes")
        _ = await recorder.runner.send(try destination("dest:notes"), payload: try #require(page))
        let request = try #require(recorder.processes.first)
        #expect(
            Array(request.arguments.dropFirst(3)) == ["Swift \"Blog\" & more", "", "https://swift.org/blog?a=1&b=2"])
    }

    @Test func notesAndRemindersDoNotTakeFiles() throws {
        let files = try #require(Payload.files([URL(fileURLWithPath: "/tmp/a.txt")]))
        #expect(!(try destination("dest:notes")).accepts(files))
        #expect(!(try destination("dest:reminders")).accepts(files))
    }

    @Test func remindersCreatesOneReminder() async throws {
        let recorder = recorder(installing: "com.apple.reminders")
        let payload = try #require(Payload.text("Call Sam", source: nil))
        let result = await recorder.runner.send(try destination("dest:reminders"), payload: payload)
        #expect(result == .success(SendOutcome(destination: "dest:reminders", title: "Reminders")))
        let request = try #require(recorder.processes.first)
        #expect(request.arguments[1].contains("make new reminder"))
        #expect(!request.arguments[1].contains("make new list"))
        #expect(Array(request.arguments.dropFirst(3)) == ["Call Sam", "Call Sam", ""])
    }

    // MARK: Links

    @Test func thingsAddsAToDoWithALink() async throws {
        let recorder = recorder(installing: "com.culturedcode.ThingsMac")
        _ = await recorder.runner.send(try destination("dest:things"), payload: try #require(page))
        let opened = try #require(recorder.opened.first)
        #expect(opened.scheme == "things")
        let items = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "title" }?.value == "Swift \"Blog\" & more")
        #expect(items?.first { $0.name == "notes" }?.value == "https://swift.org/blog?a=1&b=2")
        #expect(opened.absoluteString.hasPrefix("things:///add?"))
    }

    @Test func thingsRefusesTextTooLongForALink() async throws {
        let recorder = recorder(installing: "com.culturedcode.ThingsMac")
        let long = try #require(Payload.text(String(repeating: "x", count: 9_000)))
        let result = await recorder.runner.send(try destination("dest:things"), payload: long)
        guard case .failure(.tooLarge(let message)) = result else {
            Issue.record("expected tooLarge")
            return
        }
        #expect(message.contains("Things"))
        #expect(recorder.opened.isEmpty)
        #expect(long.textLength == 9_000)
    }

    @Test func obsidianCreatesANoteWithTheContentAndASourceLine() async throws {
        let recorder = recorder(installing: "md.obsidian")
        let payload = try #require(Payload.text("A quote & more", source: source))
        _ = await recorder.runner.send(try destination("dest:obsidian"), payload: payload)
        let opened = try #require(recorder.opened.first)
        #expect(opened.absoluteString.hasPrefix("obsidian://new?"))
        let items = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "name" }?.value == "A quote & more")
        #expect(items?.first { $0.name == "content" }?.value == "A quote & more\n\nSource: https://swift.org/blog")
        #expect(items?.first { $0.name == "silent" }?.value == "true")
    }

    @Test func obsidianTurnsAPageIntoAMarkdownLink() async throws {
        let recorder = recorder(installing: "md.obsidian")
        let payload = try #require(Payload.page(url: URL(string: "https://swift.org"), title: "Swift"))
        _ = await recorder.runner.send(try destination("dest:obsidian"), payload: payload)
        let opened = try #require(recorder.opened.first)
        let items = try #require(URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "content" }?.value == "[Swift](https://swift.org)")
    }

    @Test func bearCreatesANoteWithTheTextAsItsBody() async throws {
        let recorder = recorder(installing: "net.shinyfrog.bear")
        _ = await recorder.runner.send(
            try destination("dest:bear"), payload: try #require(Payload.text("Heading\nbody")))
        let opened = try #require(recorder.opened.first)
        #expect(opened.absoluteString.hasPrefix("bear://x-callback-url/create?"))
        let items = URLComponents(url: opened, resolvingAgainstBaseURL: false)?.queryItems
        #expect(items?.first { $0.name == "text" }?.value == "Heading\nbody")
        #expect(items?.first { $0.name == "open_note" }?.value == "no")
    }

    // MARK: Mail

    @Test func mailOpensADraftAndNeverSends() async throws {
        let mail = try destination("dest:mail")
        #expect(mail.confirmation == .preview)
        for variant in mail.variants {
            guard case .appleScript(let script) = variant.action.backend else {
                Issue.record("mail must be an AppleScript")
                continue
            }
            let lowered = script.source.lowercased()
            #expect(lowered.contains("make new outgoing message"))
            let words = lowered.split { !$0.isLetter }
            #expect(!words.contains("send"), "the Mail script must never send")
            #expect(!words.contains("sent"))
        }
    }

    @Test func mailAsksForConfirmationBeforeAnythingRuns() async throws {
        let recorder = recorder(installing: "com.apple.mail")
        let payload = try #require(Payload.text("Hello there"))
        let first = await recorder.runner.send(try destination("dest:mail"), payload: payload)
        #expect(first == .failure(.confirmationRequired))
        #expect(recorder.processes.isEmpty)
        let second = await recorder.runner.send(try destination("dest:mail"), payload: payload, confirmed: true)
        #expect(second == .success(SendOutcome(destination: "dest:mail", title: "Mail draft")))
        let request = try #require(recorder.processes.first)
        #expect(Array(request.arguments.dropFirst(3)) == ["Hello there", "Hello there", ""])
    }

    @Test func mailAttachesFilesAsExtraArguments() async throws {
        let recorder = recorder(installing: "com.apple.mail")
        let paths = ["/tmp/a b.txt", "/tmp/$(x).png"]
        let payload = try #require(Payload.files(paths.map { URL(fileURLWithPath: $0) }))
        _ = await recorder.runner.send(try destination("dest:mail"), payload: payload, confirmed: true)
        let request = try #require(recorder.processes.first)
        #expect(Array(request.arguments.dropFirst(3)) == ["2 files", "", ""] + paths)
    }

    @Test func theConfirmationLineSaysWhatWillHappen() throws {
        let mail = try destination("dest:mail")
        let payload = try #require(Payload.text("Hello world", source: nil))
        #expect(mail.previewLine(for: payload) == "Open a draft in Mail: \"Hello world\" (11 characters)")
        let share = try destination("dest:share")
        #expect(share.previewLine(for: try #require(page)).hasPrefix("Open the Share menu with: \"Swift"))
    }

    // MARK: Share menu

    @Test func theShareMenuTakesEverythingAndNeedsConfirmation() async throws {
        let share = try destination("dest:share")
        #expect(share.confirmation == .preview)
        let recorder = recorder()
        let payload = try #require(Payload.folder(URL(fileURLWithPath: "/tmp/docs")))
        #expect(share.accepts(payload))
        #expect(await recorder.runner.send(share, payload: payload) == .failure(.confirmationRequired))
        #expect(recorder.shared.isEmpty)
        let result = await recorder.runner.send(share, payload: payload, confirmed: true)
        #expect(result == .success(SendOutcome(destination: "dest:share", title: "Share...")))
        #expect(recorder.shared == [payload])
    }

    @Test func aDismissedShareMenuIsCancelledNotFailed() async throws {
        let recorder = recorder()
        recorder.shareAnswer = .dismissed
        let result = await recorder.runner.send(
            try destination("dest:share"), payload: try #require(Payload.text("x")), confirmed: true)
        #expect(result == .failure(.cancelled))
        recorder.shareAnswer = .unavailable
        let failed = await recorder.runner.send(
            try destination("dest:share"), payload: try #require(Payload.text("x")), confirmed: true)
        #expect(failed == .failure(.failed(destination: "Share...", hint: "The Share menu could not be opened.")))
    }

    // MARK: Folders

    @Test func copyingFilesIntoAFolderPassesThemAsArguments() async throws {
        let recorder = SendRecorder()
        let folder = URL(fileURLWithPath: "/Users/me/Documents/Taxes")
        let destination = try #require(FolderDestinations.destination(for: folder, move: false))
        #expect(destination.title == "Copy to Taxes")
        #expect(destination.confirmation == .none)
        let files = try #require(Payload.files([URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/-rf")]))
        let result = await recorder.runner.send(destination, payload: files)
        #expect(result == .success(SendOutcome(destination: destination.id, title: "Copy to Taxes")))
        let request = try #require(recorder.processes.first)
        #expect(request.executable == "/bin/cp")
        #expect(request.arguments == ["-R", "-n", "--", "/tmp/a.pdf", "/tmp/-rf", "/Users/me/Documents/Taxes/"])
    }

    @Test func movingNeedsConfirmationAndNeverOverwrites() async throws {
        let recorder = SendRecorder()
        let destination = try #require(
            FolderDestinations.destination(for: URL(fileURLWithPath: "/tmp/dest"), move: true))
        #expect(destination.confirmation == .preview)
        let files = try #require(Payload.files([URL(fileURLWithPath: "/tmp/a.pdf")]))
        #expect(await recorder.runner.send(destination, payload: files) == .failure(.confirmationRequired))
        #expect(recorder.processes.isEmpty)
        _ = await recorder.runner.send(destination, payload: files, confirmed: true)
        let request = try #require(recorder.processes.first)
        #expect(request.executable == "/bin/mv")
        #expect(request.arguments == ["-n", "--", "/tmp/a.pdf", "/tmp/dest/"])
    }

    @Test func aFolderPayloadIsCopiedWhole() async throws {
        let recorder = SendRecorder()
        let destination = try #require(
            FolderDestinations.destination(for: URL(fileURLWithPath: "/tmp/dest"), move: false))
        let payload = try #require(Payload.folder(URL(fileURLWithPath: "/tmp/src")))
        _ = await recorder.runner.send(destination, payload: payload)
        #expect(try #require(recorder.processes.first).arguments == ["-R", "-n", "--", "/tmp/src", "/tmp/dest/"])
    }

    @Test func bracesInAFolderPathStayLiteral() async throws {
        let recorder = SendRecorder()
        let folder = URL(fileURLWithPath: "/tmp/{files} and {{x}}")
        let destination = try #require(FolderDestinations.destination(for: folder, move: false))
        let files = try #require(Payload.files([URL(fileURLWithPath: "/tmp/a.pdf")]))
        _ = await recorder.runner.send(destination, payload: files)
        #expect(try #require(recorder.processes.first).arguments.last == "/tmp/{files} and {{x}}/")
    }

    @Test func folderDestinationsPassTheValidatorAndKeepStableIDs() throws {
        let folder = URL(fileURLWithPath: "/tmp/dest")
        for move in [false, true] {
            let destination = try #require(FolderDestinations.destination(for: folder, move: move))
            for variant in destination.variants {
                try ActionValidator.validate(variant.action, functions: ActionFunctionRegistry(), requireContext: false)
            }
            #expect(destination.id.isWellFormed)
            #expect(destination.id == FolderDestinations.id(for: folder, move: move))
        }
        #expect(FolderDestinations.id(for: folder, move: false) != FolderDestinations.id(for: folder, move: true))
        #expect(
            FolderDestinations.id(for: folder, move: false)
                != FolderDestinations.id(for: URL(fileURLWithPath: "/tmp/other"), move: false))
    }

    @Test func rememberedFoldersAreRecentFirstAndBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "apropos-send-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("send-folders.json")
        let store = SendFolderStore(url: file)
        #expect(store.folders.isEmpty)
        let made = try (0..<7).map { index -> URL in
            let url = directory.appendingPathComponent("f\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        for url in made { store.remember(url) }
        store.remember(made[3])
        #expect(store.folders.count == SendFolderStore.limit)
        #expect(store.folders.first?.lastPathComponent == "f3")
        // A new store reads the same list back, and folders that vanished are not returned.
        try FileManager.default.removeItem(at: made[3])
        let again = SendFolderStore(url: file)
        #expect(again.folders.first?.lastPathComponent == "f6")
        again.forgetAll()
        #expect(SendFolderStore(url: file).folders.isEmpty)
    }
}
