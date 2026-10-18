import Foundation
import Testing

@testable import Apropos

/// Payload text must only ever reach a script, a program or a link as a value. These tests send hostile text through
/// each kind of backend and look at exactly what the engine was asked to run.
@Suite("Send to: injection")
struct SendToInjectionTests {
    static let script = "on run argv\nreturn item 1 of argv\nend run"
    static let pack = """
        { "schemaVersion": 1, "destinations": [
          { "id": "dest:script", "title": "Script", "symbol": "star", "accepts": ["text", "page"], "variants": [
            { "kinds": ["text"], "backend": { "type": "appleScript", "source": "on run argv\\nreturn item 1 of argv\\nend run",
              "arguments": ["--", "{title}", "{text}"] } },
            { "kinds": ["page"], "backend": { "type": "appleScript", "source": "on run argv\\nreturn item 1 of argv\\nend run",
              "arguments": ["--", "{title}", "{url}"] } } ] },
          { "id": "dest:link", "title": "Link", "symbol": "link", "accepts": ["text", "page"], "variants": [
            { "kinds": ["text"], "backend": { "type": "urlScheme", "url": "link:///add?title={title}&notes={text}" } },
            { "kinds": ["page"], "backend": { "type": "urlScheme", "url": "link:///add?title={title}&notes={url}" } } ] },
          { "id": "dest:program", "title": "Program", "symbol": "terminal", "accepts": ["text", "files"], "variants": [
            { "kinds": ["text"], "backend": { "type": "shell", "executable": "/usr/bin/tee", "arguments": ["--"], "stdin": "text" } },
            { "kinds": ["files"], "backend": { "type": "shell", "executable": "/bin/cp",
              "arguments": ["-R", "-n", "--", "{files}", "/tmp/target/"] } } ] }
        ] }
        """

    private func library() -> DestinationLibrary { destinations(fromPack: Self.pack) }

    @Test func theTestPackLoadsCleanly() {
        #expect(library().issues.isEmpty)
    }

    @Test(arguments: hostileTexts)
    func textReachesAnAppleScriptOnlyAsAnArgument(_ text: String) async throws {
        let recorder = SendRecorder()
        let destination = try #require(library().destination(for: "dest:script"))
        let payload = try #require(Payload.text(text))
        let result = await recorder.runner.send(destination, payload: payload)
        #expect(result == .success(SendOutcome(destination: "dest:script", title: "Script")))

        let request = try #require(recorder.processes.first)
        #expect(request.executable == "/usr/bin/osascript")
        // The program text is the literal script; `--` ends option parsing before any value.
        #expect(Array(request.arguments.prefix(3)) == ["-e", Self.script, "--"])
        #expect(request.arguments.count == 5)
        #expect(request.arguments[4] == payload.text)
        #expect(request.arguments[3] == payload.title)
    }

    @Test(arguments: hostileTexts)
    func textReachesALinkOnlyPercentEncoded(_ text: String) async throws {
        let recorder = SendRecorder()
        let destination = try #require(library().destination(for: "dest:link"))
        let payload = try #require(Payload.text(text))
        let result = await recorder.runner.send(destination, payload: payload)
        #expect(result == .success(SendOutcome(destination: "dest:link", title: "Link")))

        let url = try #require(recorder.opened.first)
        let raw = url.absoluteString
        #expect(raw.hasPrefix("link:///add?title="))
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~%:/?&=")
        #expect(raw.allSatisfy(allowed.contains))
        let items = try #require(URLComponents(string: raw)?.queryItems)
        #expect(items.map(\.name) == ["title", "notes"])
        #expect(items[0].value == payload.title)
        #expect(items[1].value == payload.text)
    }

    @Test(arguments: hostileTexts)
    func textReachesAProgramOnlyOnStandardInput(_ text: String) async throws {
        let recorder = SendRecorder()
        let destination = try #require(library().destination(for: "dest:program"))
        let payload = try #require(Payload.text(text))
        _ = await recorder.runner.send(destination, payload: payload)

        let request = try #require(recorder.processes.first)
        #expect(request.executable == "/usr/bin/tee")
        #expect(request.arguments == ["--"])
        #expect(request.standardInput == Data(try #require(payload.text).utf8))
    }

    @Test func filePathsReachAProgramAsSeparateArguments() async throws {
        let recorder = SendRecorder()
        let destination = try #require(library().destination(for: "dest:program"))
        let hostile = [
            URL(fileURLWithPath: "/tmp/$(touch pwn).txt"), URL(fileURLWithPath: "/tmp/a b; delete everything.txt"),
            URL(fileURLWithPath: "/tmp/-r"), URL(fileURLWithPath: "/tmp/{files} \u{1F600}.txt"),
        ]
        let payload = try #require(Payload.files(hostile))
        _ = await recorder.runner.send(destination, payload: payload)
        let request = try #require(recorder.processes.first)
        #expect(request.executable == "/bin/cp")
        #expect(request.arguments == ["-R", "-n", "--"] + hostile.map(\.path) + ["/tmp/target/"])
    }

    @Test func aPageReachesAScriptAndALinkAsValues() async throws {
        let recorder = SendRecorder()
        let url = try #require(URL(string: "https://example.com/a?x=1&y=%22quoted%22#frag"))
        let payload = try #require(Payload.page(url: url, title: "Title \"with\" quotes; $(x) & more"))
        let library = library()
        _ = await recorder.runner.send(try #require(library.destination(for: "dest:script")), payload: payload)
        _ = await recorder.runner.send(try #require(library.destination(for: "dest:link")), payload: payload)
        let script = try #require(recorder.processes.first)
        #expect(script.arguments.suffix(2) == ["Title \"with\" quotes; $(x) & more", url.absoluteString])
        let opened = try #require(recorder.opened.first)
        #expect(opened.absoluteString.hasPrefix("link:///add?title="))
        #expect(URLComponents(string: opened.absoluteString)?.queryItems?.last?.value == url.absoluteString)
    }

    @Test func environmentCarriesValuesNeverCode() async throws {
        let recorder = SendRecorder()
        let destination = try #require(library().destination(for: "dest:script"))
        let payload = try #require(Payload.text("$(touch pwn)"))
        _ = await recorder.runner.send(destination, payload: payload)
        let request = try #require(recorder.processes.first)
        #expect(request.environment["APROPOS_TEXT"] == "$(touch pwn)")
        #expect(request.arguments[1] == Self.script)
    }

    @Test func braceTextInsideScriptSourceIsNeverExpanded() async throws {
        // Braces are ordinary AppleScript (lists and records). The engine expands placeholders only in `arguments`.
        let json = """
            { "schemaVersion": 1, "destinations": [ { "id": "user:braces", "title": "Braces", "symbol": "star",
              "accepts": ["text"], "review": "approved", "variants": [ { "backend": { "type": "appleScript",
              "source": "set x to {text}", "arguments": ["--", "{text}"] } } ] } ] }
            """
        let library = destinations(fromPack: json, origin: .user)
        let destination = try #require(library.runnable.first)
        let recorder = SendRecorder()
        _ = await recorder.runner.send(destination, payload: try #require(Payload.text("SECRET")))
        let request = try #require(recorder.processes.first)
        #expect(request.arguments[1] == "set x to {text}")
        #expect(request.arguments.last == "SECRET")
    }

    @Test func aFailingDestinationReportsTheDestinationNotTheContent() async throws {
        let recorder = SendRecorder()
        recorder.processStatus = 1
        let destination = try #require(library().destination(for: "dest:script"))
        let payload = try #require(Payload.text("my secret note"))
        let result = await recorder.runner.send(destination, payload: payload)
        guard case .failure(let error) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(error.message == "Could not send to Script.")
        #expect(!error.message.contains("secret"))
        // The payload is still intact for a retry.
        #expect(payload.text == "my secret note")
    }

    @Test func aLinkThatCannotOpenIsAFailure() async throws {
        let recorder = SendRecorder()
        recorder.openAnswer = false
        let destination = try #require(library().destination(for: "dest:link"))
        let result = await recorder.runner.send(destination, payload: try #require(Payload.text("x")))
        #expect(result == .failure(.failed(destination: "Link", hint: nil)))
    }
}
