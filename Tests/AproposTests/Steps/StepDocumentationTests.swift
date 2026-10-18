import Foundation
import Testing

@testable import Apropos

/// The example in docs/ui-steps.md, kept here so the documented format cannot drift from the code.
@Suite("Documented example")
struct StepDocumentationTests {
    private let example = #"""
        {
          "schemaVersion": 1,
          "command": {
            "id": "user:export-and-close",
            "title": "Export as PDF and close",
            "symbol": "rectangle.stack",
            "requires": [],
            "apps": { "include": ["com.apple.Preview"], "exclude": [] },
            "backend": {
              "type": "uiSteps",
              "version": 1,
              "steps": [
                {
                  "id": "s1",
                  "action": "menu",
                  "app": "com.apple.Preview",
                  "description": "Choose File > Export as PDF",
                  "locators": [
                    { "by": "identifier", "value": "menu.exportPDF" },
                    { "by": "roleTitle", "role": "AXMenuItem", "title": "Export as PDF" },
                    { "by": "menuPath", "titles": ["File", "Export as PDF"] },
                    { "by": "shortcut", "key": "E", "modifiers": ["command", "shift"] }
                  ],
                  "wait": { "timeout": 5 },
                  "expect": { "condition": "appears", "locator": { "by": "identifier", "value": "export.sheet" }, "timeout": 4 }
                },
                {
                  "action": "menu",
                  "app": "com.apple.Preview",
                  "description": "Choose File > Close",
                  "locators": [{ "by": "shortcut", "key": "W", "modifiers": ["command"] }],
                  "activates": false
                }
              ]
            },
            "output": "none",
            "confirm": false,
            "timeout": 30
          }
        }
        """#

    @Test func theExampleInTheDocumentationLoadsAndValidates() throws {
        let file = try JSONDecoder().decode(UserCommandFile.self, from: Data(example.utf8))
        let command = try file.makeCommand()
        let steps = try #require(command.backend.steps)
        #expect(steps.steps.map(\.id) == ["s1", "s2"])
        #expect(steps.fragility == .sturdy)
        #expect(steps.steps[0].expect?.condition == .appears)
        #expect(steps.apps == ["com.apple.Preview"])
        #expect(UIStepsValidator.issues(in: steps).isEmpty)
        let normalized = try UserCommandValidator.normalized(command, functions: ActionFunctionRegistry())
        #expect(normalized.id == "user:export-and-close")
        #expect(try UIStepsFile.load(Data(example.utf8)) == steps)
    }
}
