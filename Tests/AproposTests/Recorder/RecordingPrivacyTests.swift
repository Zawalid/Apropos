import CoreGraphics
import Foundation
import Testing

@testable import Apropos

/// A deterministic random source, so a failing run can be reproduced.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private struct AllowedBackend: RecordingPermissionBackend {
    func accessibilityGranted() -> Bool { true }
    func inputMonitoringGranted() -> Bool { true }
    func requestAccessibility() {}
    func requestInputMonitoring() {}
}

/// Every place the recorder could put a character: the draft, its JSON, the validated steps, notes, the session, the
/// engine, the log lines and the description of each chord.
private final class Evidence: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func record(_ line: String) { lock.withLock { lines.append(line) } }
    var logLines: [String] { lock.withLock { lines } }
}

private func everything(
    engine: RecordingEngine, evidence: Evidence, chords: [KeyChord]
) throws -> String {
    var parts: [String] = []
    let draft = engine.currentDraft
    parts.append(String(describing: draft))
    parts.append(String(reflecting: draft))
    var dumped = ""
    dump(draft, to: &dumped)
    parts.append(dumped)
    var engineDump = ""
    dump(engine.state, to: &engineDump)
    parts.append(engineDump)
    parts.append(draft.items.map(\.summary).joined(separator: "\n"))
    parts.append(draft.skipped.map(\.text).joined(separator: "\n"))
    parts.append(evidence.logLines.joined(separator: "\n"))
    parts.append(RecorderLog.word(engine.state))
    for chord in chords {
        parts.append(String(describing: chord))
        parts.append(String(reflecting: chord))
        var chordDump = ""
        dump(chord, to: &chordDump)
        parts.append(chordDump)
    }
    if let steps = try? draft.validated(dropTextEntries: true) {
        parts.append(try steps.backend.jsonString())
    }
    return parts.joined(separator: "\n")
}

extension UIStepsBackend {
    fileprivate func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

@Suite("Recording privacy")
struct RecordingPrivacyTests {
    /// Each key code types its own private-use character, so no ordinary word in a description can contain it.
    private func marker(for keyCode: UInt16) -> String {
        String(UnicodeScalar(0xE000 + UInt32(keyCode)) ?? "?")
    }

    private func isMarker(_ scalar: Unicode.Scalar) -> Bool { (0xE000...0xE07F).contains(scalar.value) }

    private func world() -> RecorderWorld {
        let world = RecorderWorld()
        var layout: [UInt16: String] = [:]
        for code in UInt16(0)...127 { layout[code] = marker(for: code) }
        world.setLayout(layout)
        return world
    }

    @Test(arguments: [1, 7, 42, 2026, 90_210])
    func randomTypingNeverLeavesACharacterAnywhere(seed: UInt64) throws {
        let world = world()
        let evidence = Evidence()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: RecorderLog { evidence.record($0) })
        engine.arm()
        engine.beginRecording()

        var generator = SeededGenerator(state: seed)
        var chords: [KeyChord] = []
        for _ in 0..<600 {
            let code = UInt16.random(in: 0...127, using: &generator)
            var modifiers = ModifierSet()
            if Bool.random(using: &generator) { modifiers.insert(.shift) }
            if Int.random(in: 0..<4, using: &generator) == 0 { modifiers.insert(.option) }
            if Int.random(in: 0..<5, using: &generator) == 0 { modifiers.insert(.command) }
            if Int.random(in: 0..<9, using: &generator) == 0 { modifiers.insert(.control) }
            let chord = KeyChord(keyCode: code, modifiers: modifiers)
            chords.append(chord)
            engine.handle(.keyDown(chord))
            if Int.random(in: 0..<25, using: &generator) == 0 {
                world.hit = nil
                engine.handle(.mouseDown(CGPoint(x: 5, y: 5)))
            }
            if engine.state != .recording { break }
        }

        let text = try everything(engine: engine, evidence: evidence, chords: chords)
        let leaked = text.unicodeScalars.filter(isMarker)
        #expect(leaked.isEmpty)
        // Typing leaves nothing but placeholders and content-free notes.
        for item in engine.currentDraft.items {
            #expect(item.content == .textEntered || item.step != nil)
        }
        #expect(!text.contains("keyCode"))
    }

    @Test func aTypedPassphraseLeavesOnlyAPlaceholder() throws {
        let world = RecorderWorld()
        let evidence = Evidence()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: RecorderLog { evidence.record($0) })
        engine.arm()
        engine.beginRecording()
        // "hunter2" on the US layout.
        let codes: [UInt16] = [4, 32, 45, 17, 14, 15, 19]
        let chords = codes.map { KeyChord.plain($0) }
        for chord in chords { engine.handle(.keyDown(chord)) }
        let draft = engine.currentDraft
        #expect(draft.items.map(\.content) == [.textEntered])
        let text = try everything(engine: engine, evidence: evidence, chords: chords)
        #expect(!text.lowercased().contains("hunter"))
        for character in "hunter2" where !"aeiou ".contains(character) {
            // None of the typed letters appears as a lone token anywhere outside ordinary words: check the placeholder.
            #expect(!draft.items[0].summary.contains("\(character)\(character)"))
        }
        #expect(draft.items[0].summary == "Text was entered here. What you typed is not recorded.")
    }

    @Test func typingKeepsNoCountAndNoTiming() {
        let world = RecorderWorld()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: .silent)
        engine.arm()
        engine.beginRecording()
        engine.handle(.keyDown(.plain(Key.a)))
        let short = engine.currentDraft
        for index in 0..<500 {
            world.time += 0.1
            engine.handle(.keyDown(.plain(UInt16(index % 40))))
        }
        #expect(engine.currentDraft == short)
    }

    @Test func plainKeysDoNotReadMenusAndDoNotAskForFocusMoreThanOncePerRun() {
        let world = RecorderWorld()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: .silent)
        engine.arm()
        engine.beginRecording()
        for code: UInt16 in [0, 1, 2, 3, 4, 5, 49, 36, 48, 53, 123] { engine.handle(.keyDown(.plain(code))) }
        #expect(world.menuReads == 0)
        #expect(engine.currentDraft.items.map(\.content) == [.textEntered])
    }

    @Test func typingInANonTextControlLeavesNothing() {
        let world = RecorderWorld()
        world.setFocus(.other, pid: 100)
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: .silent)
        engine.arm()
        engine.beginRecording()
        for code: UInt16 in [0, 1, 2, 3] { engine.handle(.keyDown(.plain(code))) }
        #expect(engine.currentDraft.isEmpty)
        #expect(engine.currentDraft.skipped.isEmpty)
    }

    @Test func aClickStartsANewTextRun() {
        let world = RecorderWorld()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: .silent)
        engine.arm()
        engine.beginRecording()
        engine.handle(.keyDown(.plain(Key.a)))
        engine.handle(.keyDown(.plain(Key.s)))
        world.hit = world.menuItemHit(["File", "Save"])
        engine.handle(.mouseDown(CGPoint(x: 1, y: 1)))
        engine.handle(.keyDown(.plain(Key.a)))
        #expect(engine.currentDraft.items.map(\.content.isTextEntry) == [true, false, true])
    }

    @Test func noLogLineCarriesAnythingButFixedWordsAndNumbers() {
        let world = RecorderWorld()
        let evidence = Evidence()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: RecorderLog { evidence.record($0) })
        engine.arm()
        engine.beginRecording()
        world.hit = world.menuItemHit(["File", "Budget 2026 SECRET.numbers"], identifier: "secret.id")
        engine.handle(.mouseDown(CGPoint(x: 1, y: 1)))
        world.setMenus(
            [
                StepResolver.MenuItemInfo(
                    path: ["File", "Budget 2026 SECRET.numbers"], identifier: "secret.id",
                    shortcut: KeyShortcut(key: "S", modifiers: .command), isEnabled: true)
            ], pid: 100)
        engine.handle(.keyDown(.command(Key.s)))
        engine.handle(.appActivated(world.notes))
        engine.stop()
        let log = evidence.logLines.joined(separator: "\n")
        #expect(!log.isEmpty)
        #expect(
            !log.contains("SECRET") && !log.contains("secret") && !log.contains("Preview") && !log.contains("Notes"))
    }

    @Test func theDraftHoldsNoTitleBeyondWhatAStepHolds() {
        let world = RecorderWorld()
        let engine = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: "com.zawalid.apropos"),
            permission: RecordingPermission(backend: AllowedBackend()), log: .silent)
        engine.arm()
        engine.beginRecording()
        // Everything refused or skipped must leave no title behind, only fixed sentences.
        let hits: [HitElement] = [
            world.menuItemHit(["Apple", "Log Out Jane Doe\u{2026}"], barIndex: 0),
            world.menuItemHit(["File", "Open Recent", "Tax-Return-2025.pdf"]),
            world.menuItemHit(["Window", "Confidential memo.pages"]),
            HitElement(
                pid: 100, bundleID: "com.apple.Preview", role: "AXButton", title: "Delete Jane's data", place: .window),
            HitElement(
                pid: 100, bundleID: "com.apple.Preview", role: "AXMenuItem", title: "Jane Doe", place: .contextMenuItem),
        ]
        for hit in hits {
            world.hit = hit
            engine.handle(.mouseDown(CGPoint(x: 1, y: 1)))
        }
        var dumped = ""
        dump(engine.currentDraft, to: &dumped)
        for word in ["Jane", "Tax-Return", "Confidential", "Delete", "Doe"] { #expect(!dumped.contains(word)) }
    }
}

extension DraftItem.Content {
    fileprivate var isTextEntry: Bool { self == .textEntered }
}
