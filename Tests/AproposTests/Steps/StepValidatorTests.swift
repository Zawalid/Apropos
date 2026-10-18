import Foundation
import Testing

@testable import Apropos

@Suite("Step validator")
struct StepValidatorTests {
    private func issues(_ steps: UIStep..., privacy: ContextPrivacy = ContextPrivacy()) -> [UIStepsValidationError] {
        UIStepsValidator.issues(in: UIStepsBackend(steps: steps), privacy: privacy)
    }

    @Test func aGoodSequencePasses() throws {
        try UIStepsValidator.validate(StepFixtures.backend(StepFixtures.exportPDF))
    }

    @Test func refusesTheAppleMenuByTitleOrByPosition() {
        #expect(issues(StepFixtures.step(locators: [.menuPath(["Apple", "About This Mac"])])) == [.appleMenu(step: 1)])
        #expect(issues(StepFixtures.step(locators: [.menuPath(["apple", "Log Out"])])) == [.appleMenu(step: 1)])
        #expect(issues(StepFixtures.step(locators: [.position([0, 3])])) == [.appleMenu(step: 1)])
    }

    @Test func refusesRecentItemsMenusInEnglishAndFrench() {
        let english = StepFixtures.step(locators: [.menuPath(["File", "Open Recent", "Notes.md"])])
        let french = StepFixtures.step(locators: [.menuPath(["Fichier", "Ouvrir récent", "Notes.md"])])
        let apple = StepFixtures.step(locators: [.menuPath(["Éléments récents", "Doc"])])
        #expect(issues(english) == [.recentItems(step: 1)])
        #expect(issues(french) == [.recentItems(step: 1)])
        #expect(issues(apple) == [.recentItems(step: 1)])
    }

    @Test func refusesSecureFields() {
        #expect(
            issues(StepFixtures.step(locators: [.roleTitle(role: "AXSecureTextField", title: "Password")])) == [
                .secureField(step: 1)
            ])
        let expectation = StepExpectation(
            condition: .appears, locator: .roleTitle(role: "AXSecureTextField", title: "x"))
        let withExpect = StepFixtures.step(locators: [.identifier("a")], expect: expectation)
        #expect(issues(withExpect) == [.secureField(step: 1)])
    }

    @Test func refusesAppsOnThePrivacyList() {
        let step = StepFixtures.step(app: "com.example.private", locators: [.identifier("a")])
        #expect(
            issues(step, privacy: ContextPrivacy(disabledBundleIDs: ["com.example.private"])) == [
                .appNotAllowed(step: 1)
            ])
        let manager = StepFixtures.step(app: "com.1password.1password", locators: [.identifier("a")])
        #expect(issues(manager) == [.appNotAllowed(step: 1)])
    }

    @Test func refusesMissingOrMalformedAppIDs() {
        #expect(issues(StepFixtures.step(app: "", locators: [.identifier("a")])) == [.missingAppID(step: 1)])
        #expect(issues(StepFixtures.step(app: "  ", locators: [.identifier("a")])) == [.missingAppID(step: 1)])
        #expect(issues(StepFixtures.step(app: "Finder", locators: [.identifier("a")])) == [.badAppID(step: 1)])
        #expect(
            issues(StepFixtures.step(app: "com.apple.finder; rm", locators: [.identifier("a")])) == [.badAppID(step: 1)]
        )
    }

    @Test func refusesAnythingThatNeedsAPixelCoordinate() {
        #expect(issues(StepFixtures.step(locators: [.unsupported("coordinate")])) == [.needsCoordinate(step: 1)])
        #expect(issues(StepFixtures.step(locators: [.unsupported("ocr")])) == [.unknownLocator(step: 1)])
    }

    @Test func refusesActionsThisVersionCannotRun() {
        for action in [StepAction.press, .setValue, .select] {
            #expect(
                issues(StepFixtures.step(locators: [.identifier("a")], action: action)) == [.unsupportedAction(step: 1)]
            )
        }
    }

    @Test func enforcesSizeLimits() {
        let many = (0..<(UIStepsValidator.maxSteps + 1)).map { _ in StepFixtures.step(locators: [.identifier("a")]) }
        let all = UIStepsValidator.issues(in: UIStepsBackend(steps: many))
        #expect(all.contains(.tooManySteps(limit: UIStepsValidator.maxSteps)))
        let atLimit = (0..<UIStepsValidator.maxSteps).map { _ in StepFixtures.step(locators: [.identifier("a")]) }
        #expect(UIStepsValidator.issues(in: UIStepsBackend(steps: atLimit)).isEmpty)

        let long = String(repeating: "a", count: UIStepsValidator.maxTextLength + 1)
        #expect(issues(StepFixtures.step(locators: [.identifier(long)])) == [.fieldTooLong(step: 1)])
        #expect(issues(StepFixtures.step(locators: [.identifier("a")], description: long)) == [.fieldTooLong(step: 1)])
        let tooMany = (0..<7).map { StepLocator.identifier("id\($0)") }
        #expect(issues(StepFixtures.step(locators: tooMany)) == [.tooManyLocators(step: 1)])
        let deep = (0..<9).map { _ in "x" }
        #expect(issues(StepFixtures.step(locators: [.menuPath(deep)])) == [.emptyLocator(step: 1)])
    }

    @Test func refusesEmptyThings() {
        #expect(UIStepsValidator.issues(in: UIStepsBackend(steps: [])) == [.noSteps])
        #expect(issues(StepFixtures.step(locators: [])) == [.noLocators(step: 1)])
        #expect(issues(StepFixtures.step(locators: [.identifier(" ")])) == [.emptyLocator(step: 1)])
        #expect(
            issues(StepFixtures.step(locators: [.identifier("a")], description: " ")) == [.missingDescription(step: 1)])
        #expect(issues(StepFixtures.step(locators: [.shortcut(key: "E", modifiers: [])])) == [.emptyLocator(step: 1)])
    }

    @Test func refusesBadVersionsDuplicateIDsAndBadWaits() {
        let future = UIStepsBackend(version: 2, steps: [StepFixtures.exportPDF])
        #expect(UIStepsValidator.issues(in: future) == [.unsupportedVersion(2)])
        let a = StepFixtures.step("same", locators: [.identifier("a")])
        #expect(UIStepsValidator.issues(in: UIStepsBackend(steps: [a, a])) == [.duplicateStepID(step: 2)])
        #expect(
            issues(StepFixtures.step(locators: [.identifier("a")], wait: StepWait(timeout: 0))) == [
                .badTimeout(step: 1)
            ])
        #expect(
            issues(StepFixtures.step(locators: [.identifier("a")], wait: StepWait(timeout: 99))) == [
                .badTimeout(step: 1)
            ])
    }

    @Test func expectationsNeedAWindowLocator() {
        let menu = StepExpectation(condition: .appears, locator: .menuPath(["File", "X"]))
        #expect(issues(StepFixtures.step(locators: [.identifier("a")], expect: menu)) == [.badExpectation(step: 1)])
        let fine = StepExpectation(condition: .appears, locator: .identifier("sheet"), timeout: 4)
        #expect(issues(StepFixtures.step(locators: [.identifier("a")], expect: fine)).isEmpty)
    }

    @Test func messagesNeverRepeatTheContent() {
        let secret = "Jane-Doe-Recent.pdf"
        let all = issues(StepFixtures.step(locators: [.menuPath(["File", "Open Recent", secret])]))
        #expect(!all.isEmpty && all.allSatisfy { !$0.description.contains(secret) })
    }
}
