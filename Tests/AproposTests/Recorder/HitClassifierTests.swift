import Foundation
import Testing

@testable import Apropos

/// A fake element with a parent, so the classifier can climb. No Accessibility API is involved.
private final class HitNode: ComparableAXNode, @unchecked Sendable {
    var strings: [String: String]
    var ints: [String: Int]
    var children: [HitNode] = []
    weak var parent: HitNode?
    private(set) var asked: [String] = []

    init(role: String, title: String = "", id: String = "", subrole: String? = nil, enabled: Bool = true) {
        strings = [AXAttr.role: role]
        if !title.isEmpty { strings[AXAttr.title] = title }
        if !id.isEmpty { strings[StepAX.identifier] = id }
        if let subrole { strings[AXAttr.subrole] = subrole }
        ints = [StepAX.enabled: enabled ? 1 : 0]
    }

    @discardableResult
    func add(_ child: HitNode) -> HitNode {
        child.parent = self
        children.append(child)
        return child
    }

    func string(_ attribute: String) -> String? {
        asked.append(attribute)
        return strings[attribute]
    }
    func int(_ attribute: String) -> Int? {
        asked.append(attribute)
        return ints[attribute]
    }
    func node(_ attribute: String) -> (any AXNode)? {
        asked.append(attribute)
        return attribute == HitAX.parent ? parent : nil
    }
    func nodes(_ attribute: String) -> [any AXNode] {
        asked.append(attribute)
        return attribute == AXAttr.children ? children : []
    }
    func count(_ attribute: String) -> Int? { attribute == AXAttr.children ? children.count : nil }
    func isSameElement(as other: any AXNode) -> Bool { (other as? HitNode) === self }
}

/// An app with a menu bar of Apple, File (Save, Open Recent > one document, Share > one item) and an extra.
private struct World {
    let bar = HitNode(role: "AXMenuBar")
    let apple: HitNode
    let file: HitNode
    let save: HitNode
    let recent: HitNode
    let recentDoc: HitNode
    let share: HitNode
    let airDrop: HitNode

    init() {
        apple = bar.add(HitNode(role: "AXMenuBarItem", title: "Apple"))
        file = bar.add(HitNode(role: "AXMenuBarItem", title: "File"))
        let fileMenu = file.add(HitNode(role: "AXMenu"))
        save = fileMenu.add(HitNode(role: "AXMenuItem", title: "Save", id: "menu.save"))
        recent = fileMenu.add(HitNode(role: "AXMenuItem", title: "Open Recent", id: "_NSRecentDocumentsMenu"))
        recentDoc = recent.add(HitNode(role: "AXMenu", id: "recent-menu")).add(
            HitNode(role: "AXMenuItem", title: "Taxes.pdf"))
        share = fileMenu.add(HitNode(role: "AXMenuItem", title: "Share"))
        airDrop = share.add(HitNode(role: "AXMenu")).add(HitNode(role: "AXMenuItem", title: "AirDrop"))
    }
}

@Suite("Hit classifier")
struct HitClassifierTests {
    @Test func aMenuItemKnowsItsPathBarIndexAndMenuIdentifiers() {
        let world = World()
        let hit = HitClassifier.classify(world.save, pid: 7, bundleID: "com.example.app")
        #expect(hit.pid == 7 && hit.bundleID == "com.example.app")
        #expect(hit.identifier == "menu.save")
        #expect(
            hit.place == .menuItem(path: ["File", "Save"], barIndex: 1, ancestorIdentifiers: [], hasSubmenu: false))
    }

    @Test func aSubmenuItemKeepsTheWholePath() {
        let world = World()
        let hit = HitClassifier.classify(world.airDrop, pid: 7, bundleID: nil)
        #expect(
            hit.place
                == .menuItem(
                    path: ["File", "Share", "AirDrop"], barIndex: 1, ancestorIdentifiers: [], hasSubmenu: false))
    }

    @Test func aSubmenuHeaderIsMarked() {
        let world = World()
        let hit = HitClassifier.classify(world.share, pid: 7, bundleID: nil)
        #expect(
            hit.place == .menuItem(path: ["File", "Share"], barIndex: 1, ancestorIdentifiers: [], hasSubmenu: true))
    }

    @Test func recentItemsMenusAreRecognisableFromTheAncestors() {
        let world = World()
        let hit = HitClassifier.classify(world.recentDoc, pid: 7, bundleID: nil)
        guard case .menuItem(let path, _, let ancestors, _) = hit.place else {
            Issue.record("expected a menu item")
            return
        }
        #expect(path == ["File", "Open Recent", "Taxes.pdf"])
        #expect(ancestors.contains { StepText.isRecentMenuIdentifier($0) })
    }

    @Test func theAppleMenuHasBarIndexZero() {
        let world = World()
        let item = world.apple.add(HitNode(role: "AXMenu")).add(
            HitNode(role: "AXMenuItem", title: "Log Out Jane Doe\u{2026}"))
        let hit = HitClassifier.classify(item, pid: 7, bundleID: nil)
        guard case .menuItem(let path, let index, _, _) = hit.place else {
            Issue.record("expected a menu item")
            return
        }
        #expect(index == 0 && path.first == "Apple")
        #expect(HitClassifier.classify(world.apple, pid: 7, bundleID: nil).place == .menuBarTitle(barIndex: 0))
    }

    @Test func aMenuBarTitleIsNotAnItem() {
        let world = World()
        #expect(HitClassifier.classify(world.file, pid: 7, bundleID: nil).place == .menuBarTitle(barIndex: 1))
    }

    @Test func aMenuWithNoMenuBarAboveItIsAContextMenu() {
        let window = HitNode(role: "AXWindow")
        let item = window.add(HitNode(role: "AXMenu")).add(HitNode(role: "AXMenuItem", title: "Copy"))
        #expect(HitClassifier.classify(item, pid: 7, bundleID: nil).place == .contextMenuItem)
    }

    @Test func aMenuExtraIsNotTheAppsMenuBar() {
        let extra = HitNode(role: "AXMenuBarItem", title: "Wi-Fi", subrole: "AXMenuExtra")
        let item = extra.add(HitNode(role: "AXMenu")).add(HitNode(role: "AXMenuItem", title: "Settings"))
        #expect(HitClassifier.classify(extra, pid: 9, bundleID: nil).place == .menuExtra)
        #expect(HitClassifier.classify(item, pid: 9, bundleID: nil).place == .menuExtra)
    }

    @Test func anythingElseIsInAWindow() {
        let button = HitNode(role: "AXButton", title: "Save", id: "save-button")
        let hit = HitClassifier.classify(button, pid: 7, bundleID: nil)
        #expect(hit.place == .window)
        #expect(hit.isAddressable)
        #expect(!HitClassifier.classify(HitNode(role: "AXGroup"), pid: 7, bundleID: nil).isAddressable)
    }

    @Test func aPasswordFieldIsReadForItsRoleOnly() {
        let field = HitNode(role: "AXTextField", title: "Password", id: "pw", subrole: "AXSecureTextField")
        let hit = HitClassifier.classify(field, pid: 7, bundleID: nil)
        #expect(hit.isSecure)
        #expect(hit.title.isEmpty && hit.identifier.isEmpty)
        #expect(!field.asked.contains(AXAttr.title))
        #expect(!field.asked.contains(StepAX.identifier))
    }

    @Test func noValueIsEverRead() {
        let world = World()
        let field = HitNode(role: "AXTextField", title: "Name")
        _ = HitClassifier.classify(world.save, pid: 7, bundleID: nil)
        _ = HitClassifier.classify(field, pid: 7, bundleID: nil)
        _ = HitClassifier.focus(of: field)
        for node in [world.save, field] {
            #expect(!node.asked.contains("AXValue"))
            #expect(!node.asked.contains("AXSelectedText"))
        }
    }

    @Test func focusIsClassifiedFromRoleAlone() {
        #expect(HitClassifier.focus(of: HitNode(role: "AXTextField")) == .textInput)
        #expect(HitClassifier.focus(of: HitNode(role: "AXTextArea")) == .textInput)
        #expect(HitClassifier.focus(of: HitNode(role: "AXTextField", subrole: "AXSecureTextField")) == .secure)
        #expect(HitClassifier.focus(of: HitNode(role: "AXButton")) == .other)
        #expect(HitClassifier.focus(of: nil) == .unknown)
        #expect(HitClassifier.focus(of: HitNode(role: "")) == .unknown)
    }
}

@Suite("Key chords and layouts")
struct KeyChordTests {
    @Test func aChordNeverDescribesItself() {
        let chord = KeyChord(keyCode: Key.s, modifiers: [.command, .shift])
        #expect(String(describing: chord) == "key event")
        #expect(String(reflecting: chord) == "key event")
        var out = ""
        dump(chord, to: &out)
        #expect(!out.contains("keyCode") && !out.contains("115") && !out.contains("1"))
    }

    @Test func candidatesAreCommandControlAndFunctionKeysOnly() {
        #expect(KeyChord(keyCode: Key.a, modifiers: .command).isShortcutCandidate)
        #expect(KeyChord(keyCode: Key.a, modifiers: .control).isShortcutCandidate)
        #expect(KeyChord(keyCode: Key.f5, modifiers: []).isShortcutCandidate)
        #expect(!KeyChord(keyCode: Key.a, modifiers: [.shift, .option]).isShortcutCandidate)
        #expect(!KeyChord(keyCode: Key.return, modifiers: []).isShortcutCandidate)
    }

    @Test func chordsComparedWithMenuSymbols() {
        let layout = USKeyLayout()
        #expect(
            KeyChord(keyCode: Key.e, modifiers: [.command, .shift]).shortcut(using: layout)
                == KeyShortcut(key: "E", modifiers: [.command, .shift]))
        #expect(
            KeyChord(keyCode: Key.f5, modifiers: []).shortcut(using: layout) == KeyShortcut(key: "F5", modifiers: []))
        #expect(
            KeyChord(keyCode: Key.leftArrow, modifiers: .command).shortcut(using: layout)
                == KeyShortcut(key: "\u{2190}", modifiers: .command))
        #expect(KeyChord(keyCode: 127, modifiers: .command).shortcut(using: layout) == nil)
    }

    @Test func keyClassesDoNotDependOnACharacter() {
        #expect(KeySymbols.keyClass(Key.a) == .text)
        #expect(KeySymbols.keyClass(49) == .text)
        #expect(KeySymbols.keyClass(Key.return) == .navigation)
        #expect(KeySymbols.keyClass(Key.escape) == .navigation)
        #expect(KeySymbols.keyClass(Key.f5) == .function)
    }
}
