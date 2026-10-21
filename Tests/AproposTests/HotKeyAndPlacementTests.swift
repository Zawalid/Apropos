import CoreGraphics
import Foundation
import Testing

@testable import Apropos

@Suite("HotKey and placement")
struct HotKeyAndPlacementTests {
    @Test func defaultIsOptionSpace() {
        #expect(HotKeyCombo.default.display == "⌥Space")
        #expect(HotKeyCombo.default.isValid)
    }

    @Test func aComboNeedsAModifier() {
        #expect(!HotKeyCombo(keyCode: 49, modifiers: []).isValid)
    }

    @Test func unknownKeyCodesAreInvalid() {
        #expect(!HotKeyCombo(keyCode: 200, modifiers: [.command]).isValid)
    }

    @Test func displayOrdersModifiersLikeMacOS() {
        let combo = HotKeyCombo(keyCode: 8, modifiers: [.command, .shift, .control, .option])
        #expect(combo.display == "⌃⌥⇧⌘C")
    }

    @Test func storeRoundTripsAndFallsBack() throws {
        let suite = scratchDefaultsSuite("hotkey")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HotKeyStore(defaults: defaults)
        #expect(store.load() == .default)
        let custom = HotKeyCombo(keyCode: 40, modifiers: [.command, .option])
        store.save(custom)
        #expect(store.load() == custom)
        store.save(HotKeyCombo(keyCode: 40, modifiers: []))
        #expect(store.load() == custom)
    }

    @Test func panelIsCentredHorizontallyAndJustAboveTheMiddle() {
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let frame = PanelPlacement.frame(in: screen)
        #expect(frame.midX == screen.midX)
        #expect(frame.midY == 540)  // 46% of the way down: 4% above the true centre
        #expect(screen.contains(frame))
    }

    @Test func panelFollowsASecondaryScreen() {
        let screen = CGRect(x: 1600, y: -200, width: 1200, height: 800)
        let frame = PanelPlacement.frame(in: screen)
        #expect(frame.midX == screen.midX)
        #expect(screen.contains(frame))
    }

    @Test func picksTheScreenUnderThePointer() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 100, y: 0, width: 100, height: 100)]
        #expect(PanelPlacement.index(containing: CGPoint(x: 150, y: 50), in: frames) == 1)
        #expect(PanelPlacement.index(containing: CGPoint(x: -50, y: 50), in: frames) == 0)
        #expect(PanelPlacement.index(containing: .zero, in: []) == nil)
    }
}
