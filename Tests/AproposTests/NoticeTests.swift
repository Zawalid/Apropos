import Foundation
import Testing

@testable import Apropos

@MainActor
@Suite("Footer notes that fade")
struct NoticeTests {
    private func makeModel(run: (@MainActor (Command) async -> Result<Void, CommandRunError>)? = nil) -> PaletteModel {
        let tracker = FrontmostAppTracker(ownBundleID: "test")
        let menus = AppMenuModel(tracker: tracker, permission: AccessibilityPermission(probe: { true }))
        menus.seed(MenuCommandMapper.commands(from: Fixtures.menuBar(), bundleID: nil))
        return PaletteModel(menus: menus, tracker: tracker, runner: run)
    }

    private func failingRun() async -> PaletteModel {
        let model = makeModel { _ in .failure(.failed(-25204)) }
        model.prepareForOpen()
        if let row = model.results.first?.command { _ = await model.run(row) }
        return model
    }

    @Test func notesLastThreeSecondsAndFailuresFive() {
        #expect(NoticePolicy.lifetime(isFailure: false) == 3)
        #expect(NoticePolicy.lifetime(isFailure: true) == 5)
        #expect(PaletteNotice(text: "Saved", isFailure: false).lifetime == 3)
        #expect(PaletteNotice(text: "Stopped", isFailure: true).lifetime == 5)
    }

    @Test func aFailedRunIsANoteOfTheFailureKind() async throws {
        let model = await failingRun()
        let notice = try #require(model.notice)
        #expect(notice.isFailure && notice.text == model.runError)
    }

    @Test func theTimerClearsTheNoteItWasStartedFor() async throws {
        let model = await failingRun()
        let shown = try #require(model.notice)
        model.expireNotice(shown)
        #expect(model.notice == nil && model.runError == nil)
    }

    @Test func aNewerNoteIsNotClearedByTheOlderTimer() async throws {
        let model = await failingRun()
        let old = PaletteNotice(text: "something that already went", isFailure: true)
        model.expireNotice(old)
        #expect(model.notice != nil)
    }

    @Test func typingMovingAndEscapeAllClearTheNote() async throws {
        var model = await failingRun()
        model.query = "a"
        #expect(model.notice == nil)
        model = await failingRun()
        model.moveSelection(by: 1)
        #expect(model.notice == nil)
        model = await failingRun()
        // Escape dismisses the note and is used up by it: the panel stays open.
        #expect(model.goBack())
        #expect(model.notice == nil)
        #expect(!model.goBack())
    }

    @Test func aSavedSequenceNoteIsAnInfoNoteThatFades() throws {
        let note = PaletteNotice(text: "Saved Shout under Your commands", isFailure: false)
        #expect(note.signature != PaletteNotice(text: note.text, isFailure: true).signature)
        #expect(note.lifetime == NoticePolicy.info)
    }
}
