import Foundation
import Testing

@testable import Apropos

@Suite("Step dry run")
struct StepDryRunTests {
    private func environment(menus: [(String, [FakeItem])] = FakeTree.fixtureMenus()) -> StepFakeEnvironment {
        let environment = StepFakeEnvironment()
        environment.install(FakeTree.app(menus: menus), bundleID: StepFixtures.app)
        return environment
    }

    @Test func reportsWhichLocatorWouldMatchWithoutTouchingAnything() {
        let env = environment()
        let report = StepDryRun().run(StepFixtures.backend(StepFixtures.exportPDF), environment: env)
        #expect(report.health == .healthy)
        #expect(report.results.first?.matchedKind == .identifier)
        #expect(report.results.first?.isEnabled == true)
        #expect(env.pressed.isEmpty && env.activated.isEmpty && env.sleeps.isEmpty)
    }

    @Test func aStepThatNeededAFallbackIsDegraded() {
        let env = environment(menus: FakeTree.fixtureMenus(identifiers: false))
        let report = StepDryRun().run(StepFixtures.backend(StepFixtures.exportPDF), environment: env)
        #expect(report.health == .degraded)
        #expect(report.health.needsAttention)
        #expect(report.results.first?.matchedKind == .roleTitle)
    }

    @Test func aStepThatNoLongerResolvesIsBroken() {
        let env = environment(menus: FakeTree.fixtureMenus(french: true, identifiers: false))
        let step = StepFixtures.step(locators: [.menuPath(["File", "Export as PDF"])])
        let report = StepDryRun().run(StepFixtures.backend(step), environment: env)
        #expect(report.health == .broken)
        #expect(report.results.first?.failure == .notFound)
    }

    @Test func missingAccessibilityOrAppMeansUnknown() {
        let env = environment()
        env.trusted = false
        let blocked = StepDryRun().run(StepFixtures.backend(StepFixtures.exportPDF), environment: env)
        #expect(blocked.blocked == .permissionMissing && blocked.health == .unknown)
        env.trusted = true
        env.remove(bundleID: StepFixtures.app)
        let absent = StepDryRun().run(StepFixtures.backend(StepFixtures.exportPDF), environment: env)
        #expect(absent.results.first?.failure == .appNotRunning && absent.health == .unknown)
        #expect(!absent.health.needsAttention)
    }

    @Test func theCurrentPrivacyListIsApplied() {
        let env = environment()
        let privacy = ContextPrivacy(disabledBundleIDs: [StepFixtures.app])
        let report = StepDryRun(privacy: privacy).run(StepFixtures.backend(StepFixtures.exportPDF), environment: env)
        #expect(report.results.first?.failure == .notAllowed && report.health == .broken)
    }
}
