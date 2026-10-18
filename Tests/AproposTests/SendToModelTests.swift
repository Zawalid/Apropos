import Foundation
import Testing

@testable import Apropos

@Suite("Send to: payloads")
struct PayloadTests {
    @Test func textPayloadHasATitleFromItsFirstLine() throws {
        let payload = try #require(Payload.text("\n  Hello   world \nsecond line"))
        #expect(payload.kind == .text)
        #expect(payload.title == "Hello world")
        #expect(payload.contextValues.selectedText == "\n  Hello   world \nsecond line")
        #expect(payload.contextValues.pageTitle == "Hello world")
    }

    @Test func emptyAndBlankTextIsNoPayload() {
        #expect(Payload.text(nil) == nil)
        #expect(Payload.text("") == nil)
        #expect(Payload.text(" \n\t ") == nil)
    }

    @Test func longTitlesAreClippedAndLongTextIsCapped() throws {
        let payload = try #require(Payload.text(String(repeating: "word ", count: 100)))
        #expect(payload.title.count <= 80)
        #expect(payload.title.hasSuffix("\u{2026}"))
        let huge = try #require(Payload.text(String(repeating: "a", count: PayloadLimits.maxTextCharacters + 5_000)))
        #expect(huge.textLength == PayloadLimits.maxTextCharacters)
    }

    @Test func controlCharactersAreRemovedButWhitespaceStays() throws {
        let payload = try #require(Payload.text("a\u{0}b\u{7}c\td\ne\r\nf"))
        #expect(payload.text == "abc\td\ne\r\nf")
    }

    @Test func textKeepsItsSourcePageOnlyWhenHttp() throws {
        let source = try #require(URL(string: "https://example.com/a"))
        #expect(Payload.text("x", source: source)?.url == source)
        #expect(Payload.text("x", source: URL(string: "file:///etc/passwd"))?.url == nil)
        #expect(Payload.text("x", source: URL(string: "javascript:alert(1)"))?.url == nil)
    }

    @Test func pageNeedsAnHttpURLAndFallsBackToTheHostForItsTitle() throws {
        let url = try #require(URL(string: "https://swift.org/blog"))
        #expect(Payload.page(url: url, title: "  Swift   Blog ")?.title == "Swift Blog")
        #expect(Payload.page(url: url, title: nil)?.title == "swift.org")
        #expect(Payload.page(url: URL(string: "ftp://x.org"), title: "x") == nil)
        #expect(Payload.page(url: nil, title: "x") == nil)
        let long = try #require(URL(string: "https://example.com/" + String(repeating: "a", count: 5_000)))
        #expect(Payload.page(url: long, title: "x") == nil)
    }

    @Test func filesNeedAbsolutePathsAndStayUnderTheLimit() {
        let one = URL(fileURLWithPath: "/tmp/a.txt")
        #expect(Payload.files([])?.kind == nil)
        #expect(Payload.files([one])?.title == "a.txt")
        #expect(Payload.files([one, one])?.title == "2 files")
        #expect(Payload.files([one, URL(string: "https://x.org/a")!]) != nil)
        let many = Array(repeating: one, count: PayloadLimits.maxFiles + 1)
        #expect(Payload.files(many) == nil)
    }

    @Test func candidatesFollowTheContext() throws {
        let values = ContextValues(
            selectedText: "hello", selectedFiles: [URL(fileURLWithPath: "/tmp/a.txt")],
            pageURL: URL(string: "https://swift.org"), pageTitle: "Swift", folderURL: URL(fileURLWithPath: "/tmp"))
        let kinds = Payload.candidates(from: values, bundleID: "com.apple.finder").map(\.kind)
        #expect(kinds == [.files, .text, .page])
        let folderOnly = ContextValues(folderURL: URL(fileURLWithPath: "/tmp/docs"))
        #expect(Payload.candidates(from: folderOnly, bundleID: "com.apple.finder").map(\.kind) == [.folder])
        // An editor always has a folder; that is not something to offer.
        #expect(Payload.candidates(from: folderOnly, bundleID: "com.example.editor").isEmpty)
        #expect(Payload.candidates(from: ContextValues(), bundleID: nil).isEmpty)
    }

    @Test func aTextPayloadFromAPageCarriesTheLink() throws {
        let values = ContextValues(selectedText: "quote", pageURL: URL(string: "https://swift.org"), pageTitle: "Swift")
        let text = try #require(Payload.candidates(from: values, bundleID: "com.apple.Safari").first { $0.kind == .text })
        #expect(text.contextValues.pageURL?.absoluteString == "https://swift.org")
        #expect(text.title == "quote")
    }

    @Test func printingNeverShowsContent() throws {
        let payload = try #require(Payload.text("super secret selection"))
        #expect(!String(describing: payload).contains("secret"))
        #expect(!String(reflecting: payload).contains("secret"))
        var dumped = ""
        dump(payload, to: &dumped)
        #expect(!dumped.contains("secret"))
    }
}

@Suite("Send to: destination packs")
struct DestinationPackTests {
    static let pack = """
        { "schemaVersion": 1, "name": "test", "destinations": [
          { "id": "dest:note", "title": "Note", "symbol": "note.text", "app": "com.example.notes",
            "accepts": ["text", "page"],
            "variants": [
              { "kinds": ["text"], "backend": { "type": "appleScript",
                "sourceLines": ["on run argv", "return item 1 of argv", "end run"],
                "arguments": ["--", "{title}", "{text}", "{url}"] } },
              { "backend": { "type": "appleScript", "source": "on run argv\\nreturn item 1 of argv\\nend run",
                "arguments": ["--", "{title}"] } }
            ] },
          { "id": "dest:link", "title": "Link", "symbol": "link", "accepts": ["text"],
            "variants": [ { "backend": { "type": "urlScheme", "url": "link:///add?title={title}&body={text}" } } ] }
        ] }
        """

    @Test func loadsDestinationsWithVariants() throws {
        let library = destinations(fromPack: Self.pack)
        #expect(library.issues.isEmpty)
        #expect(library.destinations.map(\.id.rawValue) == ["dest:note", "dest:link"])
        let note = try #require(library.destination(for: "dest:note"))
        #expect(note.variants.count == 2)
        #expect(note.appBundleID == "com.example.notes")
        let withSource = try #require(Payload.text("hi", source: URL(string: "https://x.org")))
        let without = try #require(Payload.text("hi"))
        // The first variant needs {url}; a selection with no source falls through to the second.
        #expect(note.variant(for: withSource) == note.variants[0])
        #expect(note.variant(for: without) == note.variants[1])
    }

    @Test func aDestinationDoesNotTakeKindsItDoesNotAccept() throws {
        let library = destinations(fromPack: Self.pack)
        let link = try #require(library.destination(for: "dest:link"))
        #expect(link.accepts(try #require(Payload.text("x"))))
        #expect(!link.accepts(try #require(Payload.page(url: URL(string: "https://x.org"), title: "x"))))
        #expect(!link.accepts(try #require(Payload.files([URL(fileURLWithPath: "/tmp/a")]))))
    }

    private func issues(for destination: String) -> [String] {
        destinations(fromPack: "{ \"schemaVersion\": 1, \"destinations\": [ \(destination) ] }").issues.map(\.reason)
    }

    @Test func refusesDefinitionsThatBreakTheSafetyRules() {
        func entry(_ backend: String, accepts: String = "[\"text\"]", extra: String = "") -> String {
            "{ \"id\": \"dest:x\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": \(accepts), \(extra) "
                + "\"variants\": [ { \"backend\": \(backend) } ] }"
        }
        // An AppleScript argument that could be read as an option.
        #expect(
            issues(for: entry("{ \"type\": \"appleScript\", \"source\": \"on run argv\\nend run\", \"arguments\": [\"{text}\"] }"))
                .contains { $0.contains("--") })
        // A shell with a placeholder in the executable.
        #expect(!issues(for: entry("{ \"type\": \"shell\", \"executable\": \"/bin/{text}\", \"arguments\": [] }")).isEmpty)
        // A placeholder in the host of a link.
        #expect(!issues(for: entry("{ \"type\": \"urlScheme\", \"url\": \"x://{text}/a\" }")).isEmpty)
        // Backends that act on the keyboard or call built-in functions have no place here.
        #expect(!issues(for: entry("{ \"type\": \"keyPress\", \"keyCode\": 9 }")).isEmpty)
        #expect(!issues(for: entry("{ \"type\": \"function\", \"name\": \"text.upper\" }")).isEmpty)
        // A bare text value in an option position.
        #expect(
            !issues(for: entry("{ \"type\": \"shell\", \"executable\": \"/bin/echo\", \"arguments\": [\"{text}\"] }")).isEmpty)
    }

    @Test func refusesMalformedMetadata() {
        let backend = "{ \"type\": \"urlScheme\", \"url\": \"x:///a\" }"
        func entry(_ fields: String) -> String {
            "{ \(fields), \"variants\": [ { \"backend\": \(backend) } ] }"
        }
        #expect(!issues(for: entry("\"id\": \"Bad ID\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": [\"text\"]")).isEmpty)
        #expect(!issues(for: entry("\"id\": \"ctx:x\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": [\"text\"]")).isEmpty)
        #expect(!issues(for: entry("\"id\": \"dest:x\", \"title\": \"\", \"symbol\": \"star\", \"accepts\": [\"text\"]")).isEmpty)
        #expect(!issues(for: entry("\"id\": \"dest:x\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": []")).isEmpty)
        #expect(
            !issues(for: entry("\"id\": \"dest:x\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": [\"text\"], \"app\": \"a b\""))
                .isEmpty)
        #expect(
            !issues(for: entry("\"id\": \"dest:x\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": [\"text\"], \"maxTextCharacters\": 0"))
                .isEmpty)
        #expect(!issues(for: "{ \"id\": \"dest:x\", \"title\": \"X\", \"symbol\": \"star\", \"accepts\": [\"text\"], \"variants\": [] }").isEmpty)
    }

    @Test func aVariantForAKindTheDestinationDoesNotAcceptIsRefused() {
        let json = """
            { "id": "dest:x", "title": "X", "symbol": "star", "accepts": ["text"],
              "variants": [ { "kinds": ["files"], "backend": { "type": "urlScheme", "url": "x:///a" } } ] }
            """
        #expect(!issues(for: json).isEmpty)
    }

    @Test func aBadFileOrAPackFromTheFutureIsSkippedAndTheRestLoads() {
        var library = DestinationLibrary()
        library.add(packData: Data("nonsense".utf8), source: "a.json", origin: .user)
        library.add(
            packData: Data("{ \"schemaVersion\": 99, \"destinations\": [] }".utf8), source: "b.json", origin: .user)
        library.add(packData: Data(Self.pack.utf8), source: "c.json", origin: .user)
        // Two bad files, plus the note destination that runs a script and waits for approval.
        #expect(library.issues.count == 3)
        #expect(library.destinations.count == 2)
        #expect(library.runnable.map(\.id.rawValue) == ["dest:link"])
    }

    @Test func aLaterDestinationWithTheSameIdReplacesTheEarlierOne() throws {
        var library = destinations(fromPack: Self.pack)
        let override = """
            { "schemaVersion": 1, "destinations": [ { "id": "dest:link", "title": "Mine", "symbol": "star",
              "accepts": ["text"], "variants": [ { "backend": { "type": "urlScheme", "url": "mine:///a" } } ] } ] }
            """
        library.add(packData: Data(override.utf8), source: "user.json", origin: .user)
        #expect(library.destinations.count == 2)
        #expect(library.destination(for: "dest:link")?.title == "Mine")
        #expect(library.destination(for: "dest:link")?.origin == .user)
    }

    @Test func theShareMenuHandlerIsForBuiltInDestinationsOnly() {
        let json = """
            { "schemaVersion": 1, "destinations": [ { "id": "dest:share", "title": "Share", "symbol": "square.and.arrow.up",
              "handler": "shareMenu", "accepts": ["text"], "confirm": "preview" } ] }
            """
        #expect(destinations(fromPack: json, origin: .bundled).destinations.count == 1)
        #expect(destinations(fromPack: json, origin: .user).destinations.isEmpty)
    }
}

@Suite("Send to: trust")
struct DestinationTrustTests {
    private func pack(backend: String, review: String = "") -> String {
        """
        { "schemaVersion": 1, "destinations": [ { "id": "user:x", "title": "X", "symbol": "star",
          "accepts": ["text"], \(review) "variants": [ { "backend": \(backend) } ] } ] }
        """
    }
    private let script = """
        { "type": "appleScript", "source": "on run argv\\nend run", "arguments": ["--", "{text}"] }
        """
    private let program = """
        { "type": "shell", "executable": "/usr/bin/say", "arguments": ["--", "{text}"] }
        """
    private let link = "{ \"type\": \"urlScheme\", \"url\": \"x:///a?t={text}\" }"

    @Test func userScriptsAndProgramsWaitForApproval() {
        for backend in [script, program] {
            let library = destinations(fromPack: pack(backend: backend), origin: .user)
            #expect(library.runnable.isEmpty)
            #expect(library.pending.map(\.id.rawValue) == ["user:x"])
        }
    }

    @Test func aUserDestinationRunsOnceMarkedApproved() {
        let library = destinations(fromPack: pack(backend: script, review: "\"review\": \"approved\","), origin: .user)
        #expect(library.runnable.map(\.id.rawValue) == ["user:x"])
        #expect(library.pending.isEmpty)
    }

    @Test func aUserLinkNeedsNoApprovalButOneToAWebsiteAsksBeforeSending() throws {
        let local = destinations(fromPack: pack(backend: link), origin: .user)
        #expect(local.runnable.count == 1)
        #expect(local.runnable[0].confirmation == .none)
        let web = destinations(
            fromPack: pack(backend: "{ \"type\": \"urlScheme\", \"url\": \"https://example.com/add?t={text}\" }"),
            origin: .user)
        #expect(web.runnable.first?.confirmation == .preview)
    }

    @Test func bundledDestinationsAreTrusted() {
        let library = destinations(fromPack: pack(backend: script), origin: .bundled)
        #expect(library.runnable.count == 1)
    }

    @Test func aPendingDestinationNeverRuns() async throws {
        let recorder = SendRecorder()
        let library = destinations(fromPack: pack(backend: script), origin: .user)
        let pending = try #require(library.destinations.first)
        let payload = try #require(Payload.text("hello"))
        let result = await recorder.runner.send(pending, payload: payload)
        #expect(result == .failure(.needsApproval(destination: "X")))
        #expect(recorder.processes.isEmpty)
    }
}
