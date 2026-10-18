import Foundation
import Testing

@testable import Apropos

/// Collects the log lines the step engine writes.
final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.withLock { _lines } }
    var log: StepLog { StepLog { line in self.lock.withLock { self._lines.append(line) } } }
}

final class TaskBox: @unchecked Sendable {
    var task: Task<StepRunReport, Never>?
}

@Suite("Step replayer")
struct StepReplayerTests {
    let environment = StepFakeEnvironment()
    let capture = LogCapture()
    let warm = WarmApps()

    private func exportApp() -> StepFakeNode {
        FakeTree.app(menus: FakeTree.fixtureMenus())
    }

    private func replayer(
        configure: (inout StepReplayer.Configuration) -> Void = { _ in },
        privacy: @escaping @Sendable () -> ContextPrivacy = { ContextPrivacy() }
    ) -> StepReplayer {
        var configuration = StepReplayer.Configuration()
        configure(&configuration)
        return StepReplayer(
            environment: environment, configuration: configuration, privacy: privacy, warm: warm, log: capture.log)
    }

    private func run(_ backend: UIStepsBackend, _ replayer: StepReplayer? = nil, timeout: TimeInterval? = nil)
        async -> StepRunReport
    {
        await (replayer ?? self.replayer()).run(backend, actionID: "user:test", target: nil, timeout: timeout)
    }

    private func menuStep(_ id: String, wait: Double? = nil) -> UIStep {
        StepFixtures.step(
            locators: [.identifier(id)], wait: wait.map { StepWait(timeout: $0) })
    }

    // MARK: Success

    @Test func runsStepsInOrderAndReportsHowEachWasFound() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        let report = await run(StepFixtures.backend(menuStep("menu.save"), StepFixtures.exportPDF))
        #expect(report.succeeded)
        #expect(environment.pressed == ["menu.save", "menu.export"])
        #expect(report.steps.map(\.matchedKind) == [.identifier, .identifier])
        #expect(report.steps.map(\.step) == [1, 2])
        #expect(environment.activated.isEmpty)
    }

    @Test func aWeakerLocatorIsReportedAsDegraded() async {
        environment.install(FakeTree.app(menus: FakeTree.fixtureMenus(identifiers: false)), bundleID: StepFixtures.app)
        let report = await run(StepFixtures.backend(StepFixtures.exportPDF))
        #expect(report.steps.first?.matchedKind == .roleTitle)
        #expect(report.steps.first?.isDegraded == true)
    }

    @Test func activatesTheAppOnlyWhenTheStepAsks() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        let quiet = menuStep("menu.save")
        var loud = menuStep("menu.copy")
        loud.activates = true
        _ = await run(StepFixtures.backend(quiet))
        #expect(environment.activated.isEmpty)
        _ = await run(StepFixtures.backend(loud))
        #expect(environment.activated == [StepFixtures.app])
    }

    // MARK: Failure reasons

    @Test func notFoundAfterTheWaitAndNothingIsPressed() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        warm.markWarm(100)
        let report = await run(StepFixtures.backend(menuStep("missing", wait: 1)))
        #expect(report.failure == StepFailure(step: 1, reason: .notFound))
        #expect(environment.pressed.isEmpty)
        #expect(environment.elapsed >= 1 && environment.elapsed < 1.5)
    }

    @Test func ambiguousFailsAtOnceWithoutWaiting() async {
        let menus: [(String, [FakeItem])] = [
            ("File", [FakeItem(title: "Dup", id: "d"), FakeItem(title: "Dup", id: "e")])
        ]
        environment.install(FakeTree.app(menus: menus), bundleID: StepFixtures.app)
        let step = StepFixtures.step(locators: [.roleTitle(role: "AXMenuItem", title: "Dup")])
        let report = await run(StepFixtures.backend(step))
        #expect(report.failure == StepFailure(step: 1, reason: .ambiguous))
        #expect(environment.sleeps.isEmpty && environment.pressed.isEmpty)
    }

    @Test func aDisabledItemFailsAfterTheWaitUnlessItBecomesEnabled() async {
        let app = exportApp()
        environment.install(app, bundleID: StepFixtures.app)
        warm.markWarm(100)
        let report = await run(StepFixtures.backend(menuStep("menu.delete", wait: 1)))
        #expect(report.failure == StepFailure(step: 1, reason: .disabled))
        #expect(environment.pressed.isEmpty)

        let later = StepFakeEnvironment()
        let slow = FakeTree.app(menus: FakeTree.fixtureMenus())
        later.install(slow, bundleID: StepFixtures.app)
        later.onSleep = { time in
            if time > 0.3 { Self.setEnabled(slow, id: "menu.delete") }
        }
        let enabled = StepReplayer(environment: later, warm: warm, log: .silent)
        let again = await enabled.run(
            StepFixtures.backend(menuStep("menu.delete", wait: 2)), actionID: "user:test", target: nil)
        #expect(again.succeeded)
        #expect(later.pressed == ["menu.delete"])
    }

    private static func setEnabled(_ root: StepFakeNode, id: String) {
        func walk(_ node: StepFakeNode) {
            if node.strings[StepAX.identifier] == id { node.ints[StepAX.enabled] = 1 }
            node.children.forEach(walk)
        }
        if let bar = root.menuBar { walk(bar) }
    }

    @Test func appNotRunningPermissionMissingAndPrivacy() async {
        let backend = StepFixtures.backend(StepFixtures.exportPDF)
        let absent = await run(backend)
        #expect(absent.failure == StepFailure(step: 1, reason: .appNotRunning))

        environment.install(exportApp(), bundleID: StepFixtures.app)
        environment.trusted = false
        let untrusted = await run(backend)
        #expect(untrusted.failure == StepFailure(step: 1, reason: .permissionMissing))
        #expect(environment.pressed.isEmpty)

        environment.trusted = true
        let blocked = await run(backend, replayer(privacy: { ContextPrivacy(disabledBundleIDs: [StepFixtures.app]) }))
        #expect(blocked.failure == StepFailure(step: 1, reason: .notAllowed))
        #expect(environment.pressed.isEmpty)
    }

    @Test func aStepThatIsNoLongerValidIsNotRun() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        let apple = StepFixtures.step(locators: [.menuPath(["Apple", "Log Out"])])
        let report = await run(StepFixtures.backend(menuStep("menu.save"), apple))
        #expect(report.failure == StepFailure(step: 2, reason: .notAllowed))
        #expect(environment.pressed.isEmpty)
    }

    @Test func stopsAtTheFirstFailureAndNeverSkips() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        warm.markWarm(100)
        let backend = StepFixtures.backend(menuStep("menu.save"), menuStep("missing", wait: 0.5), menuStep("menu.copy"))
        let report = await run(backend)
        #expect(report.failure?.step == 2)
        #expect(report.steps.map(\.step) == [1])
        #expect(environment.pressed == ["menu.save"])
    }

    // MARK: Waiting

    @Test func pollsWithBackoffNotAFixedSleep() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        warm.markWarm(100)
        _ = await run(StepFixtures.backend(menuStep("missing", wait: 3)))
        let sleeps = environment.sleeps
        #expect(sleeps.count > 4)
        #expect(sleeps.first == 0.05)
        #expect(sleeps.dropLast().elementsEqual(sleeps.dropLast().sorted()))
        #expect(sleeps.max() ?? 0 <= 0.4 + 0.0001)
    }

    @Test func theFirstUseAfterAColdStartGetsMoreTime() async {
        let app = FakeTree.app(menus: [])
        environment.install(app, bundleID: StepFixtures.app, pid: 7)
        environment.onSleep = { time in
            // The menu bar only fills in after four seconds.
            if time >= 4, app.menuBar?.children.count == 1 {
                let full = FakeTree.app(menus: FakeTree.fixtureMenus())
                app.menuBar = full.menuBar
            }
        }
        let backend = StepFixtures.backend(menuStep("menu.save"))
        let cold = await run(backend)
        #expect(cold.succeeded)
        #expect(environment.elapsed >= 4)

        // The same delay on an app that is already warm is not tolerated.
        let second = StepFakeEnvironment()
        let slow = FakeTree.app(menus: [])
        second.install(slow, bundleID: StepFixtures.app, pid: 7)
        second.onSleep = { time in
            if time >= 4, slow.menuBar?.children.count == 1 {
                slow.menuBar = FakeTree.app(menus: FakeTree.fixtureMenus()).menuBar
            }
        }
        let replayer = StepReplayer(environment: second, warm: warm, log: .silent)
        let warmRun = await replayer.run(backend, actionID: "user:test", target: nil)
        #expect(warmRun.failure == StepFailure(step: 1, reason: .notFound))
    }

    @Test func theTotalTimeoutStopsTheRun() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        let report = await run(StepFixtures.backend(menuStep("missing", wait: 30)), timeout: 1)
        #expect(report.failure == StepFailure(step: 1, reason: .timedOut))
        #expect(environment.elapsed < 1.5)
    }

    @Test func aSlowAppCutsTheSearchShortInsteadOfStalling() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        warm.markWarm(100)
        environment.costPerLookup = 5
        let report = await run(StepFixtures.backend(menuStep("menu.save", wait: 1)), timeout: 2)
        #expect(report.failure?.reason == .timedOut || report.failure?.reason == .notFound)
        #expect(environment.pressed.isEmpty)
    }

    // MARK: Retries

    @Test func retriesTransientFailuresAndReportsHowMany() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        environment.script([.failed(code: -25205), .staleElement, .delivered])
        let report = await run(StepFixtures.backend(menuStep("menu.save")))
        #expect(report.succeeded)
        #expect(report.steps.first?.retries == 2)
        #expect(environment.pressed.count == 3)
    }

    @Test func givesUpAfterTheRetriesWithTheErrorCode() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        environment.script([.failed(code: -25205), .failed(code: -25205), .failed(code: -25205), .delivered])
        let report = await run(StepFixtures.backend(menuStep("menu.save")))
        #expect(report.failure == StepFailure(step: 1, reason: .actionFailed(code: -25205)))
        #expect(environment.pressed.count == 3)
    }

    @Test func aStaleElementThatNeverSettlesIsNotFound() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        environment.script([.staleElement, .staleElement, .staleElement])
        let report = await run(StepFixtures.backend(menuStep("menu.save")))
        #expect(report.failure == StepFailure(step: 1, reason: .notFound))
    }

    @Test func aLostGrantStopsWithoutRetrying() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        environment.script([.permissionLost, .delivered])
        let report = await run(StepFixtures.backend(menuStep("menu.save")))
        #expect(report.failure == StepFailure(step: 1, reason: .permissionMissing))
        #expect(environment.pressed.count == 1)
    }

    @Test func aPressThatTimesOutCountsAsDeliveredLikeAMenuThatOpensASheet() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        environment.script([.timedOut])
        let report = await run(StepFixtures.backend(menuStep("menu.export")))
        #expect(report.succeeded)
        #expect(environment.pressed == ["menu.export"])
    }

    // MARK: Cancel

    @Test func aCancelledTaskPressesNothing() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        let backend = StepFixtures.backend(menuStep("menu.save"))
        let replayer = replayer()
        let task = Task { await replayer.run(backend, actionID: "user:test", target: nil) }
        task.cancel()
        let report = await task.value
        #expect(report.failure == StepFailure(step: 1, reason: .cancelled))
        #expect(environment.pressed.isEmpty)
    }

    @Test func cancelDuringAWaitEndsItAtOnce() async {
        environment.install(exportApp(), bundleID: StepFixtures.app)
        warm.markWarm(100)
        let box = TaskBox()
        environment.onSleep = { _ in box.task?.cancel() }
        let backend = StepFixtures.backend(menuStep("menu.save"), menuStep("missing", wait: 20), menuStep("menu.copy"))
        let replayer = replayer()
        box.task = Task { await replayer.run(backend, actionID: "user:test", target: nil) }
        let report = await box.task?.value
        #expect(report?.failure == StepFailure(step: 2, reason: .cancelled))
        #expect(environment.pressed == ["menu.save"])
        #expect(environment.elapsed < 1)
    }

    // MARK: Expectations

    @Test func anExpectedWindowThatAppearsMakesTheStepSucceed() async {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus(), windows: [FakeTree.window([])])
        environment.install(app, bundleID: StepFixtures.app)
        environment.onPress = { _ in app.windows[0].children = [FakeTree.element(role: "AXSheet", id: "export.sheet")] }
        var step = menuStep("menu.export")
        step.expect = StepExpectation(condition: .appears, locator: .identifier("export.sheet"), timeout: 2)
        let report = await run(StepFixtures.backend(step))
        #expect(report.succeeded)
    }

    @Test func anExpectedWindowThatNeverAppearsIsAFailureNotASuccess() async {
        let app = FakeTree.app(menus: FakeTree.fixtureMenus(), windows: [FakeTree.window([])])
        environment.install(app, bundleID: StepFixtures.app)
        warm.markWarm(100)
        var step = menuStep("menu.export")
        step.expect = StepExpectation(condition: .appears, locator: .identifier("export.sheet"), timeout: 1)
        let report = await run(StepFixtures.backend(step))
        #expect(report.failure == StepFailure(step: 1, reason: .expectationNotMet))
        #expect(environment.pressed == ["menu.export"])
    }

    @Test func aWindowThatShouldGoAway() async {
        let sheet = FakeTree.element(role: "AXSheet", id: "export.sheet")
        let app = FakeTree.app(menus: FakeTree.fixtureMenus(), windows: [FakeTree.window([sheet])])
        environment.install(app, bundleID: StepFixtures.app)
        warm.markWarm(100)
        var step = menuStep("menu.save")
        step.expect = StepExpectation(condition: .gone, locator: .identifier("export.sheet"), timeout: 1)
        #expect((await run(StepFixtures.backend(step))).failure?.reason == .expectationNotMet)
        environment.onPress = { _ in app.windows[0].children = [] }
        #expect((await run(StepFixtures.backend(step))).succeeded)
    }

    @Test func anExpectationPointingAtAPasswordFieldIsRefused() async {
        let secure = FakeTree.element(role: "AXTextField", id: "pw", subrole: StepText.secureRole)
        let app = FakeTree.app(menus: FakeTree.fixtureMenus(), windows: [FakeTree.window([secure])])
        environment.install(app, bundleID: StepFixtures.app)
        var step = menuStep("menu.save")
        step.expect = StepExpectation(condition: .appears, locator: .identifier("pw"), timeout: 1)
        let report = await run(StepFixtures.backend(step))
        #expect(report.failure == StepFailure(step: 1, reason: .secureField))
    }
}

@Suite("Step logging")
struct StepLoggingTests {
    private let secretTitle = "ZZ-Secret-Title"
    private let secretID = "zz.secret.identifier"
    private let secretText = "ZZ-secret-description"

    private func sensitiveApp() -> StepFakeNode {
        FakeTree.app(
            menus: [("ZZ-Secret-Menu", [FakeItem(title: secretTitle, id: secretID, char: "j")])],
            apple: [FakeItem(title: "Log Out Jane Doe")])
    }

    private func step(_ locators: [StepLocator]) -> UIStep {
        StepFixtures.step(locators: locators, description: secretText)
    }

    @Test func linesCarryOnlyFixedWordsNumbersAndTheActionID() async {
        let capture = LogCapture()
        let environment = StepFakeEnvironment()
        environment.install(sensitiveApp(), bundleID: StepFixtures.app)
        let replayer = StepReplayer(environment: environment, warm: WarmApps(), log: capture.log)
        let good = UIStepsBackend(steps: [
            step([.identifier(secretID)]), step([.menuPath(["ZZ-Secret-Menu", secretTitle])]),
            step([.roleTitle(role: "AXMenuItem", title: secretTitle)]),
        ])
        _ = await replayer.run(good, actionID: "user:test", target: nil)
        let bad = UIStepsBackend(steps: [step([.identifier("ZZ-not-there"), .menuPath(["ZZ", secretTitle + "x"])])])
        let report = await replayer.run(bad, actionID: "user:test", target: nil)

        #expect(!capture.lines.isEmpty)
        for line in capture.lines {
            #expect(!line.contains("ZZ") && !line.localizedCaseInsensitiveContains("secret"))
            #expect(!line.localizedCaseInsensitiveContains("jane"))
            #expect(line.hasPrefix("steps user:test "))
        }
        if let failure = report.failure {
            #expect(!failure.message.contains("ZZ"))
            #expect(!"\(failure)".contains(secretTitle))
        }
    }

    @Test func reportsAndDryRunsHoldNoTitles() async {
        let environment = StepFakeEnvironment()
        environment.install(sensitiveApp(), bundleID: StepFixtures.app)
        let backend = UIStepsBackend(steps: [step([.menuPath(["ZZ-Secret-Menu", secretTitle])])])
        let run = await StepReplayer(environment: environment, warm: WarmApps(), log: .silent)
            .run(backend, actionID: "user:test", target: nil)
        let dry = StepDryRun().run(backend, environment: environment)
        for text in ["\(run)", "\(dry)"] {
            #expect(!text.contains(secretTitle) && !text.contains(secretID) && !text.contains("Jane"))
        }
    }
}
