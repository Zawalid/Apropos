import Foundation
import Testing

@testable import Apropos

@Suite("Sequence model")
struct SequenceModelTests {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @Test func everyStepKindSurvivesAJSONRoundTrip() throws {
        let steps = [
            Seq.upper(output: "shout"),
            Seq.send("dest:notes", from: .output("shout")),
            SequenceStep(kind: .userCommand("user:abc"), inputs: [SequenceInput(.files)]),
            Seq.link("https://example.com/search?q={text}"),
            SequenceStep(
                kind: .shortcut(name: "Summarize"), inputs: [SequenceInput(.text, from: .ask(prompt: "Which tone?"))],
                output: SequenceOutput(name: "summary"), continueOnFailure: true, timeout: 20),
            Seq.menu(),
        ]
        let backend = SequenceBackend(steps: steps)
        let again = try roundTrip(backend)
        #expect(again == backend)
        #expect(again.steps.map(\.id) == ["s1", "s2", "s3", "s4", "s5", "s6"])
    }

    @Test func aHandWrittenFileGetsDefaults() throws {
        let json = """
            {"steps":[{"kind":"contextAction","action":"ctx:text.upper","inputs":[{"kind":"text"}]},
                      {"kind":"openURL","url":"https://example.com"}]}
            """
        let backend = try JSONDecoder().decode(SequenceBackend.self, from: Data(json.utf8))
        #expect(backend.version == SequenceBackend.currentVersion)
        #expect(backend.steps[0].id == "s1" && backend.steps[1].id == "s2")
        #expect(backend.steps[0].inputs == [SequenceInput(.text, from: .context)])
        #expect(!backend.steps[0].continueOnFailure)
        #expect(backend.steps[0].trust == .trusted)
    }

    @Test func anUnknownStepKindOrSourceIsRefused() {
        let bad = [
            #"{"steps":[{"kind":"teleport"}]}"#,
            #"{"steps":[{"kind":"contextAction","action":"ctx:x","inputs":[{"kind":"text","from":"clipboard"}]}]}"#,
            #"{"steps":[{"kind":"contextAction","action":"ctx:x","inputs":[{"kind":"banana"}]}]}"#,
        ]
        for json in bad {
            #expect((try? JSONDecoder().decode(SequenceBackend.self, from: Data(json.utf8))) == nil)
        }
    }

    @Test func theSequenceFileCarriesIdentityAndTrust() throws {
        let sequence = CommandSequence(
            title: "Shout and note", aliases: ["shout"], symbol: "megaphone",
            steps: [Seq.upper(output: "shout"), Seq.send(from: .output("shout"))])
        let again = try roundTrip(sequence)
        #expect(again == sequence)
        #expect(again.schemaVersion == CommandSequence.currentVersion)
        #expect(again.id.rawValue.hasPrefix("user:"))
        #expect(again.effectiveTrust == .trusted)
    }

    @Test func importedSequencesAreUntrustedUntilApproved() throws {
        let sequence = CommandSequence(title: "x", steps: [Seq.upper(), Seq.send()])
        let imported = sequence.imported()
        #expect(imported.effectiveTrust == .untrusted)
        #expect(imported.steps.allSatisfy { $0.trust == .untrusted })
        #expect(try roundTrip(imported).effectiveTrust == .untrusted)
        #expect(imported.approved().effectiveTrust == .trusted)
    }

    @Test func oneUntrustedStepMakesTheWholeSequenceUntrusted() {
        var steps = [Seq.upper(), Seq.send()]
        steps[1].trust = .untrusted
        let sequence = CommandSequence(title: "x", steps: steps)
        #expect(sequence.trust == .trusted)
        #expect(sequence.effectiveTrust == .untrusted)
    }

    @Test func untrustedStepsKeepTheirTrustInTheFile() throws {
        var step = Seq.upper()
        step.trust = .untrusted
        #expect(try roundTrip(SequenceBackend(steps: [step])).steps[0].trust == .untrusted)
    }

    @Test func menuStepAppsAndTheSuggestedTimeoutFollowTheSteps() {
        let backend = Seq.backend(Seq.menu(app: "a.b"), Seq.upper(), Seq.menu(app: "c.d"), Seq.menu(app: "a.b"))
        #expect(backend.uiApps == ["a.b", "c.d"])
        #expect(backend.suggestedTimeout <= SequenceLimits.maxTotalTimeout)
        #expect(backend.suggestedTimeout >= 10)
    }
}

@Suite("Sequence validation")
struct SequenceValidationTests {
    private func issues(_ steps: SequenceStep...) -> [SequenceIssue] {
        SequenceValidator.issues(in: SequenceBackend(steps: steps))
    }

    @Test func aSensibleSequenceHasNoIssues() {
        #expect(
            issues(
                Seq.upper(output: "shout"), Seq.send(from: .output("shout")), Seq.link("https://example.com/?q={text}")
            ).isEmpty)
    }

    @Test func emptyAndTooLongSequencesAreRefused() {
        #expect(SequenceValidator.issues(in: SequenceBackend(steps: [])) == [.noSteps])
        let many = SequenceBackend(steps: Array(repeating: Seq.upper(), count: SequenceLimits.maxSteps + 1))
        #expect(SequenceValidator.issues(in: many).contains(.tooManySteps(limit: SequenceLimits.maxSteps)))
    }

    @Test func aNewerFormatIsRefused() {
        let backend = SequenceBackend(version: 2, steps: [Seq.upper()])
        #expect(SequenceValidator.issues(in: backend) == [.unsupportedVersion(2)])
    }

    @Test func duplicateAndBadIdsAreRefused() {
        var a = Seq.upper()
        a.id = "same"
        var b = Seq.upper()
        b.id = "same"
        #expect(issues(a, b).contains(.duplicateStepID(step: 2)))
        var c = Seq.upper()
        c.id = "Bad Id"
        #expect(issues(c).contains(.badStepID(step: 1)))
    }

    @Test func readingAnOutputBeforeItExistsIsACycle() {
        // Step 1 reads what step 2 gives.
        let first = Seq.upper(input: .output("later"))
        let second = Seq.upper(output: "later")
        #expect(issues(first, second).contains(.cycle(step: 1)))
        // A step reading its own output.
        #expect(issues(Seq.upper(output: "me", input: .output("me"))).contains(.cycle(step: 1)))
    }

    @Test func readingAnOutputNoStepGivesIsUnknown() {
        #expect(issues(Seq.upper(input: .output("ghost"))).contains(.unknownOutput(step: 1)))
    }

    @Test func outputNamesAreUniqueAndWellFormed() {
        #expect(issues(Seq.upper(output: "a"), Seq.upper(output: "a")).contains(.duplicateOutputName(step: 2)))
        #expect(issues(Seq.upper(output: "Bad Name")).contains(.badOutputName(step: 1)))
        #expect(issues(Seq.upper(output: "")).contains(.badOutputName(step: 1)))
    }

    @Test func onlyStepsThatProduceTextCanNameAnOutput() {
        var send = Seq.send()
        send.output = SequenceOutput(name: "x")
        #expect(issues(send).contains(.outputNotSupported(step: 1)))
        var menu = Seq.menu()
        menu.output = SequenceOutput(name: "x")
        #expect(issues(menu).contains(.menuStepTakesNoValues(step: 1)))
        var folder = Seq.upper()
        folder.output = SequenceOutput(name: "x", kind: .folder)
        #expect(issues(folder).contains(.outputKindNotSupported(step: 1)))
    }

    @Test func anOutputIsReadAsTheKindItWasGiven() {
        let giver = Seq.upper(output: "shout")
        let reader = Seq.send("dest:notes", kind: .files, from: .output("shout"))
        #expect(issues(giver, reader).contains(.outputKindMismatch(step: 2)))
        let contextOnly = SequenceStep(
            kind: .userCommand("user:x"), inputs: [SequenceInput(.folder, from: .output("shout"))])
        #expect(issues(giver, contextOnly).contains(.badInput(step: 2)))
    }

    @Test func askingIsForTextOnlyAndNeedsAQuestion() {
        let files = SequenceStep(
            kind: .userCommand("user:x"), inputs: [SequenceInput(.files, from: .ask(prompt: "Which?"))])
        #expect(issues(files).contains(.askNeedsText(step: 1)))
        let empty = Seq.upper(input: .ask(prompt: "  "))
        #expect(issues(empty).contains(.badPrompt(step: 1)))
        let long = Seq.upper(input: .ask(prompt: String(repeating: "x", count: SequenceLimits.maxPromptLength + 1)))
        #expect(issues(long).contains(.badPrompt(step: 1)))
        #expect(issues(Seq.upper(input: .ask(prompt: "Which tone?"))).isEmpty)
    }

    @Test func inputsAreLimitedAndNotRepeated() {
        let twice = SequenceStep(kind: .userCommand("user:x"), inputs: [SequenceInput(.text), SequenceInput(.text)])
        #expect(issues(twice).contains(.duplicateInput(step: 1, kind: .text)))
        let kinds: [SequenceValueKind] = [.text, .url, .files, .folder, .document]
        let many = SequenceStep(kind: .userCommand("user:x"), inputs: kinds.map { SequenceInput($0) })
        #expect(issues(many).contains(.tooManyInputs(step: 1)))
    }

    @Test func aSendTakesExactlyOnePayload() {
        let none = SequenceStep(kind: .destination("dest:notes"))
        #expect(issues(none).contains(.needsPayload(step: 1)))
        let two = SequenceStep(kind: .destination("dest:notes"), inputs: [SequenceInput(.text), SequenceInput(.files)])
        #expect(issues(two).contains(.needsPayload(step: 1)))
    }

    @Test func referencesMustLookLikeWhatTheyName() {
        #expect(issues(SequenceStep(kind: .contextAction("user:x"))).contains(.badReference(step: 1)))
        #expect(issues(SequenceStep(kind: .contextAction("Bad Id"))).contains(.badReference(step: 1)))
        #expect(issues(SequenceStep(kind: .userCommand("ctx:text.upper"))).contains(.badReference(step: 1)))
        #expect(
            issues(SequenceStep(kind: .destination("ctx:x"), inputs: [SequenceInput(.text)])).contains(
                .badReference(step: 1)))
    }

    @Test func linksAreHeldToTheEnginesUrlRules() {
        // A placeholder in the host would let a value choose where the link goes.
        let host = issues(Seq.link("https://{text}.example.com/"))
        #expect(host.contains { if case .invalidTemplate = $0 { true } else { false } })
        let blocked = issues(Seq.link("javascript:alert({text})"))
        #expect(blocked.contains { if case .invalidTemplate = $0 { true } else { false } })
        let file = issues(Seq.link("file:///etc/passwd?{text}"))
        #expect(file.contains { if case .invalidTemplate = $0 { true } else { false } })
        // A value no input provides.
        #expect(
            issues(Seq.link("https://example.com/?u={url}", kinds: [SequenceInput(.text)])).contains(
                .inputMissingForTemplate(step: 1)))
        #expect(issues(Seq.link("https://example.com/?u={url}", kinds: [SequenceInput(.page)])).isEmpty)
    }

    @Test func shortcutNamesCannotBeOptionsOrTemplates() {
        for name in ["", "  ", "-x", "{text}", String(repeating: "a", count: 201)] {
            #expect(issues(SequenceStep(kind: .shortcut(name: name))).contains(.invalidShortcutName(step: 1)))
        }
        #expect(issues(SequenceStep(kind: .shortcut(name: "Resize images"))).isEmpty)
    }

    @Test func menuStepsFollowTheStepEnginesPrivacyRules() {
        let apple = SequenceStep(
            kind: .uiSteps(
                UIStepsBackend(steps: [
                    UIStep(app: "com.apple.Preview", locators: [.menuPath(["Apple", "About"])], description: "x")
                ])))
        #expect(issues(apple).contains { if case .invalidMenuSteps = $0 { true } else { false } })
        let manager = Seq.menu(app: "com.1password.1password")
        #expect(
            SequenceValidator.issues(in: Seq.backend(manager), privacy: ContextPrivacy()).contains {
                if case .invalidMenuSteps = $0 { true } else { false }
            })
    }

    @Test func menuStepsAreLimitedInAll() {
        let big = SequenceStep(
            kind: .uiSteps(
                UIStepsBackend(
                    steps: (0..<50).map {
                        UIStep(
                            app: "com.apple.Preview", locators: [.shortcut(key: "E", modifiers: [.command])],
                            description: "x \($0)")
                    })))
        let backend = SequenceBackend(steps: [big, big, big])
        #expect(SequenceValidator.issues(in: backend).contains(.tooManyMenuSteps(limit: SequenceLimits.maxUISteps)))
    }

    @Test func timeoutsStayInRange() {
        var step = Seq.upper()
        step.timeout = 0.1
        #expect(issues(step).contains(.badTimeout(step: 1)))
        step.timeout = 61
        #expect(issues(step).contains(.badTimeout(step: 1)))
        step.timeout = 30
        #expect(issues(step).isEmpty)
    }

    @Test func messagesNameTheStepAndNeverQuoteContent() {
        let text = issues(Seq.upper(output: "Bad Name With Secret-Value-123"))
        #expect(text.first?.description.hasPrefix("Step 1: ") == true)
        #expect(!text.map(\.description).joined().contains("Secret-Value-123"))
    }
}

@Suite("Sequence values")
struct SequenceValueTests {
    @Test func textIsCleanedAndMustNotBeBlank() throws {
        let value = try SequenceCoercion.value(fromText: "a\u{0}b\u{7}c\nd\te", as: .text).get()
        #expect(value == .text("abc\nd\te"))
        #expect(throws: SequenceValueProblem.empty) { try SequenceCoercion.value(fromText: "  \n ", as: .text).get() }
    }

    @Test func hugeTextIsRefusedNotCut() {
        let huge = String(repeating: "x", count: PayloadLimits.maxTextCharacters + 1)
        #expect(throws: SequenceValueProblem.tooLarge) { try SequenceCoercion.value(fromText: huge, as: .text).get() }
    }

    @Test func linksMustBeRealWebAddresses() throws {
        #expect(
            try SequenceCoercion.value(fromText: " https://example.com/a?b=c \n", as: .url).get()
                == .url(URL(string: "https://example.com/a?b=c")!))
        for bad in [
            "javascript:alert(1)", "file:///etc/passwd", "not a link", "https://a.com https://b.com", "ftp://x.org/f",
        ] {
            #expect(throws: SequenceValueProblem.notALink) { try SequenceCoercion.value(fromText: bad, as: .url).get() }
        }
        if case .page(let url, let title) = try SequenceCoercion.value(fromText: "https://example.com/x", as: .page)
            .get()
        {
            #expect(url.host == "example.com" && title == "example.com")
        } else {
            Issue.record("expected a page")
        }
    }

    @Test func fileListsMustBeAbsoluteExistingPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("seq-values-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        let ok = try SequenceCoercion.value(fromText: file.path + "\n", as: .files).get()
        #expect(ok == .files([file.standardizedFileURL]))
        for bad in [
            "relative/a.txt", "~/a.txt", directory.path + "/../etc/passwd", directory.path + "/missing",
            "/dev/null\u{0}x",
        ] {
            #expect(throws: SequenceValueProblem.notFiles) {
                try SequenceCoercion.value(fromText: bad, as: .files).get()
            }
        }
        let tooMany = (0...SequenceLimits.maxFilesInValue).map { _ in file.path }.joined(separator: "\n")
        #expect(throws: SequenceValueProblem.tooLarge) {
            try SequenceCoercion.value(fromText: tooMany, as: .files).get()
        }
    }

    @Test func contextOnlyKindsCannotBeProducedFromText() {
        for kind in [SequenceValueKind.folder, .document, .repo] {
            #expect(throws: SequenceValueProblem.notAllowed) {
                try SequenceCoercion.value(fromText: "/tmp", as: kind).get()
            }
        }
    }

    @Test func valuesPrintAsCountsOnly() {
        let secret = "SECRET-VALUE-42"
        let values: [SequenceValue] = [
            .text(secret), .url(URL(string: "https://example.com/\(secret)")!),
            .page(URL(string: "https://example.com/\(secret)")!, title: secret),
            .files([URL(fileURLWithPath: "/tmp/\(secret)")]), .folder(URL(fileURLWithPath: "/tmp/\(secret)")),
        ]
        for value in values {
            #expect(!"\(value)".contains(secret))
            #expect(!String(reflecting: value).contains(secret))
            #expect(!String(describing: Mirror(reflecting: value).children.map { "\($0.value)" }).contains(secret))
        }
    }

    @Test func aValueFillsOnlyItsOwnPlaceInTheContext() {
        var values = ContextValues()
        SequenceValue.page(URL(string: "https://example.com")!, title: "Example").apply(to: &values)
        #expect(values.pageURL?.host == "example.com" && values.pageTitle == "Example")
        #expect(values.selectedText == nil && values.selectedFiles.isEmpty)
    }

    @Test func contextValuesAreReadByKind() {
        let context = ContextValues(
            selectedText: "hi", selectedFiles: [URL(fileURLWithPath: "/tmp/a")], pageURL: URL(string: "https://e.com"),
            pageTitle: "T", folderURL: URL(fileURLWithPath: "/tmp"), documentURL: URL(fileURLWithPath: "/tmp/d"),
            gitBranch: "main", repoRoot: URL(fileURLWithPath: "/tmp/r"))
        for kind in SequenceValueKind.allCases {
            #expect(SequenceValue.from(context: context, kind: kind)?.kind == kind)
            #expect(SequenceValue.from(context: ContextValues(), kind: kind) == nil)
        }
    }
}
