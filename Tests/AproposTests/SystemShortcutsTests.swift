import Carbon.HIToolbox
import Testing

@testable import Apropos

struct SystemShortcutsTests {
    @Test func knownCombinationsAreNamed() {
        #expect(SystemShortcuts.name(for: HotKeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command])) == "Spotlight")
        #expect(SystemShortcuts.name(for: HotKeyCombo.default) == nil)
    }

    @Test func noCombinationIsListedTwice() {
        let combos = SystemShortcuts.all.map(\.combo)
        #expect(Set(combos).count == combos.count)
    }
}
