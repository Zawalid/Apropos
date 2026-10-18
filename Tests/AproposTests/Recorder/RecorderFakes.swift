import CoreGraphics
import Foundation

@testable import Apropos

/// A scripted outside world for the recorder: a frontmost app, menus per app, a thing under the pointer, a clock and a
/// secure input switch. No event tap exists anywhere in tests; events are fed by hand.
final class RecorderWorld: RecordingSystem, ElementHitTester, MenuInspecting, KeyLayout, @unchecked Sendable {
    private let lock = NSLock()
    private var _time: TimeInterval = 0
    private var _front: AppIdentity?
    private var _secureInput = false
    private var _focus: [Int32: TextFocus] = [:]
    private var _menus: [Int32: [StepResolver.MenuItemInfo]] = [:]
    private var _hit: HitElement?
    private var _layout: [UInt16: String] = [:]
    private var _menuReads = 0
    private var _hitTests = 0

    let preview = AppIdentity(pid: 100, bundleID: "com.apple.Preview", name: "Preview")
    let notes = AppIdentity(pid: 200, bundleID: "com.apple.Notes", name: "Notes")
    let apropos = AppIdentity(pid: 1, bundleID: "com.zawalid.apropos", name: "Apropos")

    init() {
        _front = preview
        _menus[100] = Self.previewMenus
        _menus[200] = [
            StepResolver.MenuItemInfo(
                path: ["File", "New Note"], identifier: "", shortcut: KeyShortcut(key: "N", modifiers: .command),
                isEnabled: true)
        ]
    }

    static let previewMenus: [StepResolver.MenuItemInfo] = [
        StepResolver.MenuItemInfo(
            path: ["File", "Export as PDF"], identifier: "menu.export",
            shortcut: KeyShortcut(key: "E", modifiers: [.command, .shift]), isEnabled: true),
        StepResolver.MenuItemInfo(
            path: ["File", "Save"], identifier: "", shortcut: KeyShortcut(key: "S", modifiers: .command),
            isEnabled: true),
        StepResolver.MenuItemInfo(
            path: ["File", "Close"], identifier: "", shortcut: KeyShortcut(key: "W", modifiers: .command),
            isEnabled: false),
        StepResolver.MenuItemInfo(
            path: ["Edit", "Copy"], identifier: "", shortcut: KeyShortcut(key: "C", modifiers: .command),
            isEnabled: true),
        StepResolver.MenuItemInfo(path: ["View", "Zoom In"], identifier: "", shortcut: nil, isEnabled: true),
        StepResolver.MenuItemInfo(
            path: ["View", "Reload"], identifier: "", shortcut: KeyShortcut(key: "F5", modifiers: []),
            isEnabled: true),
    ]

    // Scripting
    var time: TimeInterval {
        get { lock.withLock { _time } }
        set { lock.withLock { _time = newValue } }
    }
    var front: AppIdentity? {
        get { lock.withLock { _front } }
        set { lock.withLock { _front = newValue } }
    }
    var secureInput: Bool {
        get { lock.withLock { _secureInput } }
        set { lock.withLock { _secureInput = newValue } }
    }
    var hit: HitElement? {
        get { lock.withLock { _hit } }
        set { lock.withLock { _hit = newValue } }
    }
    func setFocus(_ focus: TextFocus, pid: Int32) { lock.withLock { _focus[pid] = focus } }
    func setMenus(_ items: [StepResolver.MenuItemInfo], pid: Int32) { lock.withLock { _menus[pid] = items } }
    func setLayout(_ layout: [UInt16: String]) { lock.withLock { _layout = layout } }
    var menuReads: Int { lock.withLock { _menuReads } }
    var hitTests: Int { lock.withLock { _hitTests } }

    // RecordingSystem
    func now() -> TimeInterval { time }
    func frontmostApp() -> AppIdentity? { front }
    func isSecureEventInputOn() -> Bool { secureInput }

    // ElementHitTester
    func hitTest(at point: CGPoint) -> HitElement? {
        lock.withLock {
            _hitTests += 1
            return _hit
        }
    }
    func textFocus(in app: AppIdentity) -> TextFocus { lock.withLock { _focus[app.pid] ?? .textInput } }

    // MenuInspecting
    func menuItems(of app: AppIdentity) -> [StepResolver.MenuItemInfo] {
        lock.withLock {
            _menuReads += 1
            return _menus[app.pid] ?? []
        }
    }

    // KeyLayout
    func baseCharacter(forKeyCode keyCode: UInt16) -> String? {
        lock.withLock { _layout[keyCode] } ?? USKeyLayout().baseCharacter(forKeyCode: keyCode)
    }

    var services: RecordingServices {
        RecordingServices(system: self, hitTester: self, menus: self, keyLayout: self)
    }

    /// A menu item click as the live hit tester would report it.
    func menuItemHit(
        _ path: [String], barIndex: Int = 2, identifier: String = "", app: AppIdentity? = nil,
        hasSubmenu: Bool = false, enabled: Bool = true, ancestors: [String] = []
    ) -> HitElement {
        let owner = app ?? preview
        return HitElement(
            pid: owner.pid, bundleID: owner.bundleID, role: StepAX.menuItem, title: path.last ?? "",
            identifier: identifier, isEnabled: enabled,
            place: .menuItem(path: path, barIndex: barIndex, ancestorIdentifiers: ancestors, hasSubmenu: hasSubmenu))
    }
}

/// An event source that never touches the system: tests push events through it.
final class FakeEventSource: CaptureEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (CaptureEvent) -> Void)?
    var failsToStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(handler: @escaping @Sendable (CaptureEvent) -> Void) throws {
        if failsToStart { throw CaptureSourceError.tapUnavailable }
        lock.withLock {
            startCount += 1
            self.handler = handler
        }
    }

    func stop() {
        lock.withLock {
            stopCount += 1
            handler = nil
        }
    }

    var isListening: Bool { lock.withLock { handler != nil } }

    func send(_ event: CaptureEvent) {
        let current = lock.withLock { handler }
        current?(event)
    }
}

extension KeyChord {
    static func command(_ keyCode: UInt16, extra: ModifierSet = []) -> KeyChord {
        KeyChord(keyCode: keyCode, modifiers: extra.union(.command))
    }
    static func plain(_ keyCode: UInt16) -> KeyChord { KeyChord(keyCode: keyCode, modifiers: []) }
}

/// Key codes used by the tests (US layout).
enum Key {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let c: UInt16 = 8
    static let e: UInt16 = 14
    static let w: UInt16 = 13
    static let q: UInt16 = 12
    static let `return`: UInt16 = 36
    static let escape: UInt16 = 53
    static let f5: UInt16 = 96
    static let leftArrow: UInt16 = 123
}
