import Foundation

@testable import Apropos

enum StepFixtures {
    static let app = "com.example.fixture"

    static func step(
        _ id: String = "", app: String = StepFixtures.app, locators: [StepLocator], action: StepAction = .menu,
        description: String = "Choose Export", wait: StepWait? = nil, expect: StepExpectation? = nil,
        activates: Bool = false
    ) -> UIStep {
        UIStep(
            id: id, action: action, app: app, locators: locators, description: description, wait: wait,
            expect: expect, activates: activates)
    }

    static func backend(_ steps: UIStep...) -> UIStepsBackend { UIStepsBackend(steps: steps) }

    static let exportPDF = step(
        locators: [
            .identifier("menu.export"), .roleTitle(role: "AXMenuItem", title: "Export as PDF"),
            .menuPath(["File", "Export as PDF"]), .shortcut(key: "E", modifiers: [.command]),
        ])
}
