import Foundation
import Testing

@testable import Apropos

private func menuStep(
    _ path: [String], app: String = "com.apple.Preview", identifier: String? = nil, shortcut: KeyShortcut? = nil
) -> UIStep {
    var locators: [StepLocator] = []
    if let identifier { locators.append(.identifier(identifier)) }
    locators.append(.roleTitle(role: "AXMenuItem", title: path.last ?? ""))
    locators.append(.menuPath(path))
    if let shortcut { locators.append(.shortcut(key: shortcut.key, modifiers: shortcut.modifiers)) }
    return UIStep(app: app, locators: locators, description: "Choose \(path.joined(separator: " > ")) in App")
}

private func draft(_ contents: [DraftItem.Content]) -> RecordingDraft {
    var draft = RecordingDraft()
    for content in contents { draft.append(content) }
    return draft
}

@Suite("Recording draft")
struct RecordingDraftTests {
    @Test func rowsCarryWordsFragilityAndLocatorKinds() {
        let sturdy = menuStep(["File", "Save"], shortcut: KeyShortcut(key: "S", modifiers: .command))
        let fair = menuStep(["File", "Export"])
        let d = draft([.step(sturdy, origin: .shortcut), .step(fair, origin: .menuClick), .textEntered])
        #expect(d.items[0].fragility == .sturdy)
        #expect(d.items[1].fragility == .fair)
        #expect(d.items[2].fragility == nil)
        #expect(d.items[0].locatorKinds == [.roleTitle, .menuPath, .shortcut])
        #expect(d.items[2].locatorKinds.isEmpty)
        #expect(d.fragility == .fair)
        #expect(d.stepCount == 2)
        #expect(d.items[2].summary.contains("not recorded"))
    }

    @Test func deleteRemovesARowAndReanchorsItsNotes() throws {
        var d = draft([.step(menuStep(["File", "Save"]), origin: .menuClick), .textEntered])
        d.note(.coordinateOnlyClick)
        let last = d.items[1].id
        #expect(d.skipped.first?.afterItemID == last)
        try d.delete(last)
        #expect(d.items.count == 1)
        #expect(d.skipped.first?.afterItemID == d.items[0].id)
        #expect(throws: DraftError.noSuchItem) { try d.delete(9999) }
    }

    @Test func moveReorders() throws {
        var d = draft([
            .step(menuStep(["File", "Save"]), origin: .menuClick),
            .step(menuStep(["Edit", "Copy"]), origin: .menuClick),
        ])
        try d.move(d.items[0].id, to: 1)
        #expect(
            d.items.map { $0.step?.derivedSummary } == [
                "Choose Edit > Copy in com.apple.Preview", "Choose File > Save in com.apple.Preview",
            ])
        #expect(throws: DraftError.noSuchItem) { try d.move(d.items[0].id, to: 5) }
    }

    @Test func renameChangesTheWordsOnly() throws {
        var d = draft([.step(menuStep(["File", "Save"], identifier: "menu.save"), origin: .menuClick), .textEntered])
        let id = d.items[0].id
        let before = d.items[0].step?.locators
        try d.rename(id, to: "  Save the file  ")
        #expect(d.items[0].summary == "Save the file")
        #expect(d.items[0].step?.locators == before)
        #expect(throws: DraftError.emptyName) { try d.rename(id, to: "   ") }
        #expect(throws: DraftError.nameTooLong) { try d.rename(id, to: String(repeating: "x", count: 201)) }
        #expect(throws: DraftError.notAStep) { try d.rename(d.items[1].id, to: "Hi") }
    }

    @Test func mergeCombinesRowsThatMeanTheSameThing() throws {
        let save = menuStep(["File", "Save"])
        var d = draft([
            .step(save, origin: .menuClick), .step(save, origin: .shortcut), .textEntered, .textEntered,
            .appSwitch(bundleID: "a.b", name: "A"), .appSwitch(bundleID: "c.d", name: "C"),
        ])
        try d.merge(d.items[0].id)
        try d.merge(d.items[1].id)
        try d.merge(d.items[2].id)
        #expect(d.items.count == 3)
        #expect(d.items[2].summary == "Switch to C")
    }

    @Test func mergeRefusesDifferentRows() {
        var d = draft([
            .step(menuStep(["File", "Save"]), origin: .menuClick),
            .step(menuStep(["Edit", "Copy"]), origin: .menuClick),
            .textEntered,
        ])
        #expect(throws: DraftError.cannotMerge) { try d.merge(d.items[0].id) }
        #expect(throws: DraftError.cannotMerge) { try d.merge(d.items[1].id) }
        #expect(throws: DraftError.noSuchItem) { try d.merge(d.items[2].id) }
    }

    @Test func skippedNotesCountRepeatsAndAreBounded() {
        var d = RecordingDraft()
        for _ in 0..<3 { d.note(.contextMenu) }
        #expect(d.skipped.count == 1 && d.skipped[0].count == 3)
        #expect(d.skipped[0].text.hasSuffix("(3 times)"))
        for index in 0..<400 {
            d.append(.textEntered)
            d.note(index.isMultiple(of: 2) ? .contextMenu : .menuExtra)
        }
        #expect(d.skipped.count <= 200)
    }

    @Test func everySkipReasonHasAFixedSentenceThatNamesNothing() {
        for reason in SkipReason.allCases {
            #expect(!reason.explanation.isEmpty)
            #expect(reason.explanation.hasSuffix("."))
        }
    }
}

@Suite("Recording draft hand-off")
struct RecordingHandOffTests {
    @Test func validatedStepsAreRenumberedAndFoldAppSwitches() throws {
        let d = draft([
            .step(menuStep(["File", "Save"]), origin: .menuClick),
            .appSwitch(bundleID: "com.apple.Notes", name: "Notes"),
            .step(menuStep(["File", "New Note"], app: "com.apple.Notes"), origin: .shortcut),
            .appSwitch(bundleID: "com.apple.Mail", name: "Mail"),
        ])
        let validated = try d.validated()
        #expect(validated.steps.map(\.id) == ["s1", "s2"])
        #expect(validated.steps.map(\.activates) == [false, true])
        #expect(validated.backend.version == UIStepsBackend.currentVersion)
    }

    @Test func aSwitchToAnAppWithNoFollowingStepIsDropped() throws {
        let d = draft([
            .step(menuStep(["File", "Save"]), origin: .menuClick),
            .appSwitch(bundleID: "com.apple.Notes", name: "Notes"),
            .step(menuStep(["Edit", "Copy"]), origin: .menuClick),
        ])
        #expect(try d.validated().steps.map(\.activates) == [false, false])
    }

    @Test func textEntryRowsBlockSavingUntilDeletedOrDropped() throws {
        var d = draft([.step(menuStep(["File", "Save"]), origin: .menuClick), .textEntered, .textEntered])
        #expect(throws: DraftError.unresolvedText(count: 2)) { try d.validated() }
        #expect(try d.validated(dropTextEntries: true).steps.count == 1)
        d.removeTextEntries()
        #expect(try d.validated().steps.count == 1)
        #expect(DraftError.unresolvedText(count: 1).description.contains("Delete"))
    }

    @Test func theValidatorHasTheLastWord() {
        let bad = UIStep(app: "com.apple.Preview", locators: [.menuPath(["Apple", "Log Out"])], description: "Log out")
        let d = draft([.step(bad, origin: .menuClick)])
        #expect(d.issues() == [.appleMenu(step: 1)])
        #expect(throws: DraftError.invalid([.appleMenu(step: 1)])) { try d.validated() }
    }

    @Test func anEmptyDraftIsRefused() {
        #expect(throws: DraftError.invalid([.noSteps])) { try RecordingDraft().validated() }
    }

    @Test func thePrivacyListIsHonouredAtHandOff() {
        let d = draft([.step(menuStep(["File", "Save"], app: "com.apple.Notes"), origin: .menuClick)])
        let privacy = ContextPrivacy(disabledBundleIDs: ["com.apple.Notes"])
        #expect(throws: DraftError.invalid([.appNotAllowed(step: 1)])) { try d.validated(privacy: privacy) }
    }

    @Test func tooManyStepsAreRefused() {
        var d = RecordingDraft()
        for index in 0..<(UIStepsValidator.maxSteps + 1) {
            d.append(.step(menuStep(["File", "Item \(index)"]), origin: .menuClick))
        }
        #expect(throws: DraftError.self) { try d.validated() }
    }

    @Test func theSequenceBuilderTakesOverTheValidatedSteps() throws {
        let d = draft([.step(menuStep(["File", "Save"]), origin: .menuClick)])
        let builder = try d.sequenceBuilder()
        #expect(builder.steps.count == 1)
        #expect(builder.issues().isEmpty)
    }

    @MainActor
    @Test func savingMakesAnOrdinaryUserCommand() throws {
        var d = draft([
            .step(menuStep(["File", "Save"], shortcut: KeyShortcut(key: "S", modifiers: .command)), origin: .shortcut),
            .step(menuStep(["File", "Export"], identifier: "menu.export"), origin: .menuClick),
        ])
        let directory = tempCommandsDirectory()
        let store = UserCommandStore(directory: directory)
        #expect(throws: DraftError.emptyName) { try d.save(in: store) }
        d.title = "Save and export"
        let saved = try d.save(in: store)
        let reloaded = UserCommandStore(directory: directory)
        #expect(reloaded.command(withID: saved.id)?.backend.steps?.steps.count == 2)
        #expect(reloaded.command(withID: saved.id)?.stepFragility == .sturdy)
    }

    @MainActor
    @Test func aDraftWithTextEntryIsNotSaved() throws {
        let d = draft([.step(menuStep(["File", "Save"]), origin: .menuClick), .textEntered])
        let store = UserCommandStore(directory: tempCommandsDirectory())
        #expect(throws: DraftError.unresolvedText(count: 1)) { try d.save(as: "X", in: store) }
        #expect(store.commands.isEmpty)
    }
}
