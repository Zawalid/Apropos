import Foundation
import Testing

@testable import Apropos

@Suite("Step schema")
struct StepSchemaTests {
    @Test func aFullBackendRoundTripsThroughJSON() throws {
        let original = UIStepsBackend(steps: [
            StepFixtures.exportPDF,
            StepFixtures.step(
                locators: [.position([2, 4]), .shortcut(key: "S", modifiers: [.command, .shift])],
                description: "Save", wait: StepWait(timeout: 5),
                expect: StepExpectation(condition: .gone, locator: .identifier("sheet"), timeout: 4), activates: true),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UIStepsBackend.self, from: data)
        #expect(decoded == original)
        #expect(decoded.steps.map(\.id) == ["s1", "s2"])
    }

    @Test func aHandWrittenFileUsesDefaults() throws {
        let json = """
            {"steps": [{"action": "menu", "app": "com.example.fixture", "description": "Export",
              "locators": [{"by": "identifier", "value": "menu.export"}]}]}
            """
        let backend = try JSONDecoder().decode(UIStepsBackend.self, from: Data(json.utf8))
        #expect(backend.version == 1)
        #expect(backend.steps.first?.id == "s1")
        #expect(backend.steps.first?.activates == false)
        #expect(backend.steps.first?.wait == nil)
    }

    @Test func shortcutModifiersAreNamesInJSON() throws {
        let locator = StepLocator.shortcut(key: "N", modifiers: [.command, .shift])
        let text = String(decoding: try JSONEncoder().encode(locator), as: UTF8.self)
        #expect(text.contains("\"shift\"") && text.contains("\"command\""))
        #expect(try JSONDecoder().decode(StepLocator.self, from: Data(text.utf8)) == locator)
        let bad = #"{"by":"shortcut","key":"N","modifiers":["hyper"]}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(StepLocator.self, from: Data(bad.utf8)) }
    }

    @Test func coordinatesDecodeAsUnsupported() throws {
        for json in [
            #"{"by":"coordinate","x":10,"y":20}"#, #"{"by":"identifier","value":"a","x":3}"#,
            #"{"by":"point","point":[1,2]}"#,
        ] {
            let locator = try JSONDecoder().decode(StepLocator.self, from: Data(json.utf8))
            #expect(locator == .unsupported("coordinate"))
        }
        let unknown = try JSONDecoder().decode(StepLocator.self, from: Data(#"{"by":"ocr"}"#.utf8))
        #expect(unknown == .unsupported("ocr"))
    }

    @Test func locatorsAreRankedStrongestFirst() {
        #expect(LocatorKind.allCases == [.identifier, .roleTitle, .menuPath, .shortcut, .position])
        #expect(LocatorKind.identifier < .position)
    }
}

@Suite("Fragility")
struct FragilityTests {
    @Test func identifierOrShortcutIsSturdy() {
        #expect(StepFragility.rating(for: [.identifier("a")]) == .sturdy)
        #expect(
            StepFragility.rating(for: [.menuPath(["File", "X"]), .shortcut(key: "E", modifiers: [.command])]) == .sturdy
        )
    }

    @Test func titlesOnlyIsFair() {
        #expect(StepFragility.rating(for: [.menuPath(["File", "X"])]) == .fair)
        #expect(StepFragility.rating(for: [.roleTitle(role: "AXMenuItem", title: "X"), .position([1, 2])]) == .fair)
    }

    @Test func positionOnlyOrNothingIsFragile() {
        #expect(StepFragility.rating(for: [.position([1, 2])]) == .fragile)
        #expect(StepFragility.rating(for: []) == .fragile)
        #expect(StepFragility.rating(for: [.unsupported("ocr")]) == .fragile)
    }

    @Test func aCommandIsAsSturdyAsItsWeakestStep() {
        let sturdy = StepFixtures.step(locators: [.identifier("a")])
        let fair = StepFixtures.step(locators: [.menuPath(["File", "X"])])
        #expect(UIStepsBackend(steps: [sturdy]).fragility == .sturdy)
        #expect(UIStepsBackend(steps: [sturdy, fair]).fragility == .fair)
        #expect(
            UIStepsBackend(steps: [sturdy, fair, StepFixtures.step(locators: [.position([1, 1])])]).fragility
                == .fragile)
        #expect(StepFragility.sturdy < .fair && StepFragility.fair < .fragile)
    }
}
