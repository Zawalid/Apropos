import CoreGraphics
import Foundation
import Testing

@testable import Apropos

struct PanelPositionTests {
    private let screen = CGRect(x: 0, y: 40, width: 1600, height: 960)
    private let size = CGSize(width: 720, height: 480)

    @Test func centeredIsTheOldDefault() {
        let centered = PanelPlacement.frame(in: screen, size: size, mode: .centered, anchor: nil)
        #expect(centered == PanelPlacement.frame(in: screen, size: size))
    }

    @Test func underTheMenuBarHugsTheTop() {
        let frame = PanelPlacement.frame(in: screen, size: size, mode: .underMenuBar, anchor: nil)
        #expect(frame.maxY == screen.maxY - 12 && frame.midX == screen.midX)
    }

    @Test func aRememberedPlaceComesBackOnAnotherResolution() {
        let moved = CGRect(x: 100, y: 200, width: 720, height: 480)
        let anchor = PanelPlacement.anchor(for: moved, in: screen)
        let same = PanelPlacement.frame(in: screen, size: size, mode: .remember, anchor: anchor)
        #expect(same == moved)
        let smaller = CGRect(x: 0, y: 25, width: 1200, height: 700)
        let there = PanelPlacement.frame(in: smaller, size: size, mode: .remember, anchor: anchor)
        #expect(smaller.contains(there))
    }

    @Test func rememberWithNothingStoredFallsBackToCentered() {
        let frame = PanelPlacement.frame(in: screen, size: size, mode: .remember, anchor: nil)
        #expect(frame == PanelPlacement.frame(in: screen, size: size))
    }

    @Test func clampKeepsThePanelOnScreen() {
        let off = CGRect(x: 1500, y: -100, width: 720, height: 480)
        let kept = PanelPlacement.clamp(off, to: screen)
        #expect(screen.contains(kept))
    }

    @Test func snapPullsTheCentreToTheCentreAndThirds() {
        let near = CGRect(x: screen.midX - 360 + 6, y: screen.midY - 240 - 4, width: 720, height: 480)
        let result = PanelPlacement.snap(near, in: screen)
        #expect(result.frame.midX == screen.midX && result.frame.midY == screen.midY)
        #expect(result.guides.count == 2)
        let third = CGRect(x: screen.minX + screen.width / 3 - 360 - 5, y: 100, width: 720, height: 480)
        let onThird = PanelPlacement.snap(third, in: screen)
        #expect(onThird.guides.contains { $0.axis == .vertical })
        let far = CGRect(x: 40, y: 60, width: 720, height: 480)
        #expect(PanelPlacement.snap(far, in: screen).guides.isEmpty)
    }

    @Test func positionsAreRememberedPerDisplay() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pos-\(UUID().uuidString)/p.json")
        let store = PanelPositionStore(url: url)
        store.set(.init(x: 0.4, y: 0.7), forDisplay: "A")
        #expect(PanelPositionStore(url: url).anchor(forDisplay: "A") == .init(x: 0.4, y: 0.7))
        #expect(store.anchor(forDisplay: "B") == nil)
        store.forgetAll()
        #expect(PanelPositionStore(url: url).anchor(forDisplay: "A") == nil)
    }
}
