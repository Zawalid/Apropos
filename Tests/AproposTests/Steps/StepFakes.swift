import Foundation

@testable import Apropos

/// Every attribute name asked of any node of a fake tree, so a test can prove which attributes were never read.
final class AttributeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    func record(_ name: String) { lock.withLock { names.append(name) } }
    var all: Set<String> { lock.withLock { Set(names) } }
    var count: Int { lock.withLock { names.count } }
}

/// A fake Accessibility element: plain attributes and children, no app behind it.
final class StepFakeNode: AXNode, @unchecked Sendable {
    var strings: [String: String]
    var ints: [String: Int]
    var children: [StepFakeNode]
    var menuBar: StepFakeNode?
    var windows: [StepFakeNode] = []
    let log: AttributeLog
    /// Identifies the node in tests that check which element was acted on.
    let tag: String

    init(
        tag: String = "", strings: [String: String] = [:], ints: [String: Int] = [:], children: [StepFakeNode] = [],
        log: AttributeLog = AttributeLog()
    ) {
        self.tag = tag
        self.strings = strings
        self.ints = ints
        self.children = children
        self.log = log
    }

    func string(_ attribute: String) -> String? {
        log.record(attribute)
        return strings[attribute]
    }

    func int(_ attribute: String) -> Int? {
        log.record(attribute)
        return ints[attribute]
    }

    func node(_ attribute: String) -> (any AXNode)? {
        log.record(attribute)
        return attribute == StepAX.menuBar ? menuBar : nil
    }

    func nodes(_ attribute: String) -> [any AXNode] {
        log.record(attribute)
        switch attribute {
        case AXAttr.children: return children
        case AXAttr.windows: return windows
        default: return []
        }
    }

    func count(_ attribute: String) -> Int? {
        log.record(attribute)
        return attribute == AXAttr.children ? children.count : nil
    }
}

/// A menu item for a fake menu bar. `children` makes it a submenu header.
struct FakeItem {
    var title: String
    var id = ""
    var char = ""
    var mods = 0
    var enabled = true
    var glyph = 0
    var children: [FakeItem]?

    static func separator() -> FakeItem { FakeItem(title: "") }
}

enum FakeTree {
    /// A menu bar of `menus` (title, items) behind an Apple menu, in an app element.
    static func app(
        menus: [(String, [FakeItem])], apple: [FakeItem]? = nil, windows: [StepFakeNode] = [],
        log: AttributeLog = AttributeLog()
    ) -> StepFakeNode {
        let appleItems =
            apple ?? [
                FakeItem(title: "About This Mac"),
                FakeItem(title: "Recent Items", children: [FakeItem(title: "Secret-Plan.pdf")]),
                FakeItem(title: "Log Out Jane Doe\u{2026}", id: "apple.logout", char: "Q", mods: 1),
            ]
        let root = StepFakeNode(tag: "app", log: log)
        let bar = StepFakeNode(tag: "bar", strings: [AXAttr.role: "AXMenuBar"], log: log)
        let all = [("Apple", appleItems)] + menus
        bar.children = all.map { title, items in
            let menu = StepFakeNode(
                tag: "menu:\(title)", strings: [AXAttr.role: StepAX.menu], children: items.map { item($0, log: log) },
                log: log)
            return StepFakeNode(
                tag: "bar:\(title)", strings: [AXAttr.role: StepAX.menuBarItem, AXAttr.title: title],
                children: [menu], log: log)
        }
        root.menuBar = bar
        root.windows = windows
        return root
    }

    static func item(_ item: FakeItem, log: AttributeLog) -> StepFakeNode {
        var strings: [String: String] = [AXAttr.role: StepAX.menuItem, AXAttr.title: item.title]
        if !item.id.isEmpty { strings[StepAX.identifier] = item.id }
        if !item.char.isEmpty { strings[StepAX.cmdChar] = item.char }
        var ints: [String: Int] = [StepAX.enabled: item.enabled ? 1 : 0, StepAX.cmdModifiers: item.mods]
        if item.glyph != 0 { ints[StepAX.cmdGlyph] = item.glyph }
        var children: [StepFakeNode] = []
        if let sub = item.children {
            children = [
                StepFakeNode(
                    tag: "submenu:\(item.title)", strings: [AXAttr.role: StepAX.menu],
                    children: sub.map { Self.item($0, log: log) }, log: log)
            ]
        }
        return StepFakeNode(
            tag: item.id.isEmpty ? item.title : item.id, strings: strings, ints: ints, children: children, log: log)
    }

    /// A window holding the given elements.
    static func window(_ children: [StepFakeNode], log: AttributeLog = AttributeLog()) -> StepFakeNode {
        StepFakeNode(tag: "window", strings: [AXAttr.role: "AXWindow"], children: children, log: log)
    }

    static func element(
        role: String, title: String = "", id: String = "", subrole: String? = nil, log: AttributeLog = AttributeLog(),
        tag: String? = nil
    ) -> StepFakeNode {
        var strings: [String: String] = [AXAttr.role: role]
        if !title.isEmpty { strings[AXAttr.title] = title }
        if !id.isEmpty { strings[StepAX.identifier] = id }
        if let subrole { strings[AXAttr.subrole] = subrole }
        return StepFakeNode(tag: tag ?? (id.isEmpty ? title : id), strings: strings, log: log)
    }

    /// The fixture's File and Edit menus, in English or French. Identifiers are the same in both.
    static func fixtureMenus(french: Bool = false, identifiers: Bool = true, appended: Bool = false) -> [(
        String, [FakeItem]
    )] {
        func id(_ value: String) -> String { identifiers ? value : "" }
        let file = french ? "Fichier" : "File"
        let edit = french ? "Édition" : "Edit"
        var editItems = [
            FakeItem(title: french ? "Copier" : "Copy", id: id("menu.copy"), char: "c"),
            FakeItem(title: french ? "Coller" : "Paste", id: id("menu.paste"), char: "v"),
            FakeItem(title: french ? "Tout sélectionner" : "Select All", id: id("menu.selectAll"), char: "a"),
        ]
        if appended {
            editItems.insert(
                contentsOf: [
                    FakeItem.separator(), FakeItem(title: "Writing Tools", children: [FakeItem(title: "Proofread")]),
                    FakeItem(title: "AutoFill"),
                ], at: 2)
        }
        return [
            (
                file,
                [
                    FakeItem(title: french ? "Enregistrer" : "Save", id: id("menu.save"), char: "s"),
                    FakeItem(title: french ? "Exporter en PDF" : "Export as PDF", id: id("menu.export"), char: "e"),
                    FakeItem.separator(),
                    FakeItem(
                        title: french ? "Ouvrir récent" : "Open Recent",
                        children: [FakeItem(title: "Quarterly-Report.numbers")]),
                    FakeItem(title: french ? "Supprimer" : "Delete", id: id("menu.delete"), enabled: false),
                ]
            ),
            (edit, editItems),
        ]
    }
}

/// A scriptable outside world for the step engine: apps with fake trees, a virtual clock that only moves when the code
/// sleeps, and a record of every press, activation and sleep.
final class StepFakeEnvironment: StepEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var apps: [String: StepApplication] = [:]
    private var time: TimeInterval = 0
    private var _pressed: [String] = []
    private var _activated: [String] = []
    private var _sleeps: [TimeInterval] = []
    private var pressResults: [StepPressResult] = []
    var trusted = true
    /// Called after every sleep with the new time, so a test can change a tree while the code waits.
    var onSleep: (@Sendable (TimeInterval) -> Void)?
    /// Called on every press with the element, before the result is returned.
    var onPress: (@Sendable (any AXNode) -> Void)?
    /// Seconds one resolve is taken to cost on the virtual clock, to test total timeouts.
    var costPerLookup: TimeInterval = 0

    var pressed: [String] { lock.withLock { _pressed } }
    var activated: [String] { lock.withLock { _activated } }
    var sleeps: [TimeInterval] { lock.withLock { _sleeps } }
    var elapsed: TimeInterval { lock.withLock { time } }

    func install(_ root: StepFakeNode, bundleID: String, pid: pid_t = 100) {
        lock.withLock { apps[bundleID] = StepApplication(pid: pid, bundleID: bundleID, root: root) }
    }

    func remove(bundleID: String) { lock.withLock { apps[bundleID] = nil } }

    /// Results for the next presses, in order; once used up, presses are delivered.
    func script(_ results: [StepPressResult]) { lock.withLock { pressResults = results } }

    func isTrusted() -> Bool { trusted }

    func application(bundleID: String, preferring pid: pid_t?) -> StepApplication? {
        lock.withLock {
            time += costPerLookup
            return apps[bundleID]
        }
    }

    func now() -> TimeInterval { lock.withLock { time } }

    func press(_ element: any AXNode) -> StepPressResult {
        let tag = (element as? StepFakeNode)?.tag ?? "?"
        onPress?(element)
        return lock.withLock {
            _pressed.append(tag)
            return pressResults.isEmpty ? .delivered : pressResults.removeFirst()
        }
    }

    func activate(_ application: StepApplication) async -> Bool {
        lock.withLock { _activated.append(application.bundleID) }
        return true
    }

    func sleep(_ seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        let current = lock.withLock {
            _sleeps.append(seconds)
            time += seconds
            return time
        }
        onSleep?(current)
    }
}
