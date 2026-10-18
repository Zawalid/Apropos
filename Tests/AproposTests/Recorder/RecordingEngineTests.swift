import CoreGraphics
import Foundation
import Testing

@testable import Apropos

private let own = "com.zawalid.apropos"

private func makeEngine(
    _ world: RecorderWorld, limits: RecordingLimits = RecordingLimits(), privacy: ContextPrivacy = ContextPrivacy(),
    log: RecorderLog = .silent
) -> RecordingEngine {
    let engine = RecordingEngine(
        services: world.services,
        configuration: RecordingConfiguration(limits: limits, privacy: privacy, ownBundleID: own),
        permission: RecordingPermission(backend: AllowedBackend()), log: log)
    engine.arm()
    engine.beginRecording()
    return engine
}

private struct AllowedBackend: RecordingPermissionBackend {
    func accessibilityGranted() -> Bool { true }
    func inputMonitoringGranted() -> Bool { true }
    func requestAccessibility() {}
    func requestInputMonitoring() {}
}

private let point = CGPoint(x: 10, y: 10)

@Suite("Recording engine: shortcuts")
struct RecordingShortcutTests {
    @Test func aShortcutBecomesTheMenuItemItTriggers() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.e, extra: .shift)))
        let items = engine.currentDraft.items
        #expect(items.count == 1)
        let step = items[0].step
        #expect(step?.app == "com.apple.Preview")
        #expect(step?.description == "Choose File > Export as PDF in Preview")
        #expect(
            step?.locators == [
                .identifier("menu.export"), .roleTitle(role: "AXMenuItem", title: "Export as PDF"),
                .menuPath(["File", "Export as PDF"]), .shortcut(key: "E", modifiers: [.command, .shift]),
            ])
        #expect(items[0].originNote == "Recorded from a keyboard shortcut")
        #expect(items[0].fragility == .sturdy)
    }

    @Test func aFunctionKeyShortcutIsRecordedWithoutModifiers() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.keyDown(.plain(Key.f5)))
        #expect(engine.currentDraft.items.first?.step?.description == "Choose View > Reload in Preview")
    }

    @Test func aShortcutThatIsNotAMenuItemIsDroppedWithANote() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.q)))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.shortcutNotInMenu])
    }

    @Test func aDisabledMenuItemIsNotRecorded() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.w)))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.shortcutNotInMenu])
    }

    @Test func twoMenuItemsWithTheSameShortcutAreAmbiguous() {
        let world = RecorderWorld()
        let twin = StepResolver.MenuItemInfo(
            path: ["File", "Save Copy"], identifier: "", shortcut: KeyShortcut(key: "S", modifiers: .command),
            isEnabled: true)
        world.setMenus(RecorderWorld.previewMenus + [twin], pid: 100)
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.ambiguousShortcut])
    }

    @Test func menusAreReadOnlyForShortcutCandidates() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        for code: UInt16 in [Key.a, Key.s, Key.return, Key.escape, Key.leftArrow] {
            engine.handle(.keyDown(.plain(code)))
        }
        #expect(world.menuReads == 0)
        engine.handle(.keyDown(.command(Key.c)))
        #expect(world.menuReads == 1)
    }

    @Test func theShortcutKeyComesFromTheMenuNotFromTheKeyboardLayout() {
        let world = RecorderWorld()
        // A layout where the C key types something else entirely: the stored key is still what the menu advertises.
        world.setLayout([Key.c: "c"])
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.c)))
        #expect(
            engine.currentDraft.items.first?.step?.locators.contains(.shortcut(key: "C", modifiers: .command)) == true)
    }
}

@Suite("Recording engine: clicks")
struct RecordingClickTests {
    @Test func aMenuItemClickBecomesAStep() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = world.menuItemHit(["File", "Save"])
        engine.handle(.mouseDown(point))
        let step = engine.currentDraft.items.first?.step
        #expect(step?.description == "Choose File > Save in Preview")
        // The shortcut and identifier the menu advertises are filled in from the app's own listing.
        #expect(step?.locators.contains(.shortcut(key: "S", modifiers: .command)) == true)
        #expect(engine.currentDraft.items.first?.originNote == "Recorded from a menu click")
    }

    @Test func aClickWithAnIdentifierKeepsItFirst() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = world.menuItemHit(["File", "Export as PDF"], identifier: "menu.export")
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.first?.step?.locators.first == .identifier("menu.export"))
    }

    @Test func openingAMenuOrASubmenuIsNotAStep() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(
            pid: 100, bundleID: "com.apple.Preview", role: "AXMenuBarItem", title: "File",
            place: .menuBarTitle(barIndex: 2))
        engine.handle(.mouseDown(point))
        world.hit = world.menuItemHit(["File", "Share"], hasSubmenu: true)
        engine.handle(.mouseDown(point))
        world.hit = world.menuItemHit(["File", "Close"], enabled: false)
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.isEmpty)
    }

    @Test func aCoordinateOnlyClickIsSkippedAndNoPositionIsKept() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(pid: 100, bundleID: "com.apple.Preview", role: "AXGroup", place: .window)
        engine.handle(.mouseDown(CGPoint(x: 123_456, y: 654_321)))
        world.hit = nil
        engine.handle(.mouseDown(CGPoint(x: 123_456, y: 654_321)))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.coordinateOnlyClick])
        #expect(engine.currentDraft.skipped.first?.count == 2)
        let dump = String(reflecting: engine.currentDraft)
        #expect(!dump.contains("123456"))
        #expect(!dump.contains("654321"))
    }

    @Test func aButtonClickIsSkippedWithItsOwnReason() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(
            pid: 100, bundleID: "com.apple.Preview", role: "AXButton", title: "Save", identifier: "save-button",
            place: .window)
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.skipped.map(\.reason) == [.controlNotRecordedYet])
        #expect(!engine.currentDraft.skipped[0].text.contains("Save"))
    }

    @Test func contextMenusAndMenuBarIconsAreSkipped() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(
            pid: 100, bundleID: "com.apple.Preview", role: "AXMenuItem", title: "Copy", place: .contextMenuItem)
        engine.handle(.mouseDown(point))
        world.hit = HitElement(
            pid: 300, bundleID: "com.apple.controlcenter", role: "AXMenuBarItem", title: "Wi-Fi", place: .menuExtra)
        engine.handle(.mouseDown(point))
        // A menu item whose process is not the frontmost app's is a menu bar icon's menu, too.
        world.hit = world.menuItemHit(["Wi-Fi", "Settings"], app: AppIdentity(pid: 300, bundleID: "x.y", name: "Y"))
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.skipped.map(\.reason) == [.contextMenu, .menuExtra])
        #expect(engine.currentDraft.skipped[1].count == 2)
        #expect(engine.currentDraft.items.isEmpty)
    }

    @Test func theAppleMenuIsRefusedInEveryWayItCanBeReached() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(
            pid: 100, bundleID: "com.apple.Preview", role: "AXMenuBarItem", title: "Apple",
            place: .menuBarTitle(barIndex: 0))
        engine.handle(.mouseDown(point))
        world.hit = world.menuItemHit(["Apple", "Log Out Jane Doe\u{2026}"], barIndex: 0)
        engine.handle(.mouseDown(point))
        // A localised or unusual title is caught by the index alone, and a bar index alone is caught by the title.
        world.hit = world.menuItemHit(["Pomme", "Quitter la session"], barIndex: 0)
        engine.handle(.mouseDown(point))
        world.hit = world.menuItemHit(["Apple", "About This Mac"], barIndex: 3)
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.appleMenu])
        #expect(engine.currentDraft.skipped.first?.count == 4)
    }

    @Test func recentItemsAreRefused() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = world.menuItemHit(["File", "Open Recent", "Quarterly-Report.numbers"])
        engine.handle(.mouseDown(point))
        world.hit = world.menuItemHit(["Fichier", "Autre", "Secret.pdf"], ancestors: ["_NSRecentDocumentsMenu"])
        engine.handle(.mouseDown(point))
        world.hit = world.menuItemHit(["File", "Reopen"], identifier: "recentThing")
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.recentItems])
        let notes = engine.currentDraft.skipped.map(\.text).joined()
        #expect(!notes.contains("Quarterly") && !notes.contains("Secret"))
    }

    @Test func windowMenuItemsNamedAfterDocumentsAreRefused() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = world.menuItemHit(["Window", "Budget 2026.numbers"])
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.windowMenuDocument])
        // With an identifier the item can be found without its title, so it is kept.
        world.hit = world.menuItemHit(["Window", "Minimize"], identifier: "menu.minimize")
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.stepCount == 1)
    }

    @Test func apropoOwnWindowsAreNeverRecorded() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(pid: 1, bundleID: own, role: "AXButton", title: "Stop", place: .window)
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.isEmpty)
        #expect(engine.state == .recording)
    }
}

@Suite("Recording engine: apps")
struct RecordingAppTests {
    @Test func switchingAppsIsABoundaryThatActivatesTheNextStep() throws {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.s)))
        world.front = world.notes
        engine.handle(.appActivated(world.notes))
        engine.handle(.keyDown(.command(0x2D)))  // key N
        let items = engine.currentDraft.items
        #expect(
            items.map(\.summary) == [
                "Choose File > Save in Preview", "Switch to Notes", "Choose File > New Note in Notes",
            ])
        let steps = try engine.currentDraft.validated().steps
        #expect(steps.map(\.activates) == [false, true])
        #expect(steps.map(\.app) == ["com.apple.Preview", "com.apple.Notes"])
        #expect(steps.map(\.id) == ["s1", "s2"])
    }

    @Test func aLateActivationNotificationDoesNotDuplicateTheBoundary() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.front = world.notes
        engine.handle(.keyDown(.command(0x2D)))
        engine.handle(.appActivated(world.notes))
        #expect(engine.currentDraft.items.map(\.summary) == ["Switch to Notes", "Choose File > New Note in Notes"])
    }

    @Test func backToBackSwitchesKeepOnlyWhereThePersonEndedUp() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.appActivated(world.notes))
        engine.handle(.appActivated(world.preview))
        #expect(engine.currentDraft.items.map(\.summary) == ["Switch to Preview"])
    }

    @Test func switchingToAproposEndsTheRecording() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.s)))
        engine.handle(.appActivated(world.apropos))
        #expect(engine.state == .finished(.switchedToApropos))
        #expect(engine.currentDraft.items.count == 1)
        engine.handle(.keyDown(.command(Key.c)))
        #expect(engine.currentDraft.items.count == 1)
    }

    @Test func aTickNoticesApropossFrontmostWithoutANotification() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.front = world.apropos
        engine.handle(.tick)
        #expect(engine.state == .finished(.switchedToApropos))
    }

    @Test func appsOnThePrivacyListAreNeverRecorded() {
        let world = RecorderWorld()
        let privacy = ContextPrivacy(disabledBundleIDs: ["com.apple.Notes"])
        let engine = makeEngine(world, privacy: privacy)
        world.front = world.notes
        engine.handle(.appActivated(world.notes))
        engine.handle(.keyDown(.command(0x2D)))
        world.hit = world.menuItemHit(["File", "New Note"], app: world.notes)
        engine.handle(.mouseDown(point))
        #expect(engine.currentDraft.items.isEmpty)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.appOnPrivacyList])
        #expect(engine.currentDraft.skipped.first?.count == 3)
    }

    @Test func passwordManagersAreOnTheDefaultList() {
        let world = RecorderWorld()
        let vault = AppIdentity(pid: 400, bundleID: "com.1password.1password", name: "Vault")
        world.front = vault
        world.setMenus(RecorderWorld.previewMenus, pid: 400)
        let engine = makeEngine(world)
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.currentDraft.items.isEmpty)
    }
}

@Suite("Recording engine: secure input and limits")
struct RecordingSecureTests {
    @Test func secureEventInputPausesAndDropsEverything() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.secureInput = true
        engine.handle(.keyDown(.command(Key.s)))
        world.hit = world.menuItemHit(["File", "Save"])
        engine.handle(.mouseDown(point))
        engine.handle(.keyDown(.plain(Key.a)))
        #expect(engine.state == .pausedForSecureInput)
        #expect(engine.currentDraft.items.isEmpty)
        #expect(world.hitTests == 0)
        #expect(world.menuReads == 0)
        #expect(engine.currentDraft.skipped.map(\.reason) == [.passwordField])
        world.secureInput = false
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.state == .recording)
        #expect(engine.currentDraft.stepCount == 1)
    }

    @Test func aTickAloneResumesAfterSecureInputEnds() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.secureInput = true
        engine.handle(.tick)
        #expect(engine.state == .pausedForSecureInput)
        world.secureInput = false
        engine.handle(.tick)
        #expect(engine.state == .recording)
    }

    @Test func aPasswordFieldUnderThePointerPauses() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.hit = HitElement(
            pid: 100, bundleID: "com.apple.Preview", role: "AXTextField", subrole: "AXSecureTextField",
            title: "Password", place: .window)
        engine.handle(.mouseDown(point))
        #expect(engine.state == .pausedForSecureInput)
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.currentDraft.items.isEmpty)
        // The latch holds until a tick sees the focus move away.
        world.setFocus(.secure, pid: 100)
        engine.handle(.tick)
        #expect(engine.state == .pausedForSecureInput)
        world.setFocus(.other, pid: 100)
        engine.handle(.tick)
        #expect(engine.state == .recording)
    }

    @Test func typingIntoAPasswordFieldPausesWithoutAPlaceholder() {
        let world = RecorderWorld()
        world.setFocus(.secure, pid: 100)
        let engine = makeEngine(world)
        engine.handle(.keyDown(.plain(Key.a)))
        #expect(engine.state == .pausedForSecureInput)
        #expect(engine.currentDraft.items.isEmpty)
    }

    @Test func resumingAfterAPauseNotesAnAppChangeThatHappenedMeanwhile() {
        let world = RecorderWorld()
        let engine = makeEngine(world)
        world.secureInput = true
        engine.handle(.tick)
        world.front = world.notes
        engine.handle(.appActivated(world.notes))
        world.secureInput = false
        engine.handle(.tick)
        #expect(engine.currentDraft.items.map(\.summary) == ["Switch to Notes"])
    }

    @Test func theStepLimitEndsTheRecordingAtTheLimit() {
        let world = RecorderWorld()
        let engine = makeEngine(world, limits: RecordingLimits(maxSteps: 2))
        engine.handle(.keyDown(.command(Key.s)))
        engine.handle(.keyDown(.command(Key.c)))
        #expect(engine.state == .finished(.reachedStepLimit))
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.currentDraft.stepCount == 2)
    }

    @Test func theTimeLimitEndsTheRecordingWithoutAnyInput() {
        let world = RecorderWorld()
        let engine = makeEngine(world, limits: RecordingLimits(maxDuration: 20))
        world.time = 19
        engine.handle(.tick)
        #expect(engine.state == .recording)
        world.time = 20
        engine.handle(.tick)
        #expect(engine.state == .finished(.reachedTimeLimit))
    }

    @Test func anEventAfterTheTimeLimitIsNotRecorded() {
        let world = RecorderWorld()
        let engine = makeEngine(world, limits: RecordingLimits(maxDuration: 20))
        world.time = 25
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.state == .finished(.reachedTimeLimit))
        #expect(engine.currentDraft.isEmpty)
    }

    @Test func eventsBeforeRecordingAndAfterStopAreIgnored() {
        let world = RecorderWorld()
        let idle = RecordingEngine(
            services: world.services, configuration: RecordingConfiguration(ownBundleID: own),
            permission: RecordingPermission(backend: AllowedBackend()), log: .silent)
        idle.handle(.keyDown(.command(Key.s)))
        #expect(idle.currentDraft.isEmpty)
        idle.arm()
        idle.handle(.keyDown(.command(Key.s)))
        #expect(idle.currentDraft.isEmpty)
        let engine = makeEngine(world)
        engine.stop()
        engine.handle(.keyDown(.command(Key.s)))
        #expect(engine.currentDraft.isEmpty)
    }
}
