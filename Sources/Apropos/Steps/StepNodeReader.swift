import ApplicationServices
import Foundation

/// The Accessibility attribute names the step code reads. No value attribute is among them: the step engine never reads
/// what is typed in a field.
enum StepAX {
    static let menuBar = "AXMenuBar"
    static let enabled = "AXEnabled"
    static let identifier = "AXIdentifier"
    static let cmdChar = "AXMenuItemCmdChar"
    static let cmdModifiers = "AXMenuItemCmdModifiers"
    static let cmdGlyph = "AXMenuItemCmdGlyph"
    static let cmdVirtualKey = "AXMenuItemCmdVirtualKey"

    static let menu = "AXMenu"
    static let menuItem = "AXMenuItem"
    static let menuBarItem = "AXMenuBarItem"
}

/// What the resolver needs to know about one element, read once.
struct NodeFacts: Sendable {
    var role = ""
    var subrole = ""
    var title = ""
    var identifier = ""
    var isEnabled = true
    var cmdChar = ""
    var cmdModifiers = 0
    var cmdGlyph = 0
    var cmdVirtualKey = 0

    var isSecure: Bool {
        role == StepText.secureRole || subrole == StepText.secureRole
    }

    /// The key equivalent the item advertises, if any.
    var shortcut: KeyShortcut? {
        MenuCommandMapper.shortcut(
            for: MenuItemSnapshot(
                title: title, cmdChar: cmdChar, cmdModifiers: cmdModifiers, cmdGlyph: cmdGlyph,
                cmdVirtualKey: cmdVirtualKey))
    }
}

enum StepNodeReader {
    private static let identityAttributes = [kAXRoleAttribute, kAXSubroleAttribute]
    private static let menuAttributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, StepAX.identifier, StepAX.enabled, StepAX.cmdChar,
        StepAX.cmdModifiers, StepAX.cmdGlyph, StepAX.cmdVirtualKey,
    ]

    /// Role and subrole only. Used first on anything that might be a field, before another attribute is asked for.
    static func identity(of node: any AXNode) -> (role: String, subrole: String) {
        (node.string(kAXRoleAttribute) ?? "", node.string(kAXSubroleAttribute) ?? "")
    }

    /// Everything the resolver compares, in one round trip to the app when the node is live. A secure text field gets
    /// only its role, subrole, title and identifier read.
    static func facts(of node: any AXNode) -> NodeFacts {
        var facts = NodeFacts()
        (facts.role, facts.subrole) = identity(of: node)
        if facts.isSecure {
            facts.title = node.string(kAXTitleAttribute) ?? ""
            facts.identifier = node.string(StepAX.identifier) ?? ""
            return facts
        }
        if let live = node as? LiveAXNode, let values = multiple(menuAttributes, of: live.element) {
            facts.title = values[2] as? String ?? ""
            facts.identifier = values[3] as? String ?? ""
            facts.isEnabled = (values[4] as? NSNumber)?.boolValue ?? true
            facts.cmdChar = values[5] as? String ?? ""
            facts.cmdModifiers = (values[6] as? NSNumber)?.intValue ?? 0
            facts.cmdGlyph = (values[7] as? NSNumber)?.intValue ?? 0
            facts.cmdVirtualKey = (values[8] as? NSNumber)?.intValue ?? 0
            return facts
        }
        facts.title = node.string(kAXTitleAttribute) ?? ""
        facts.identifier = node.string(StepAX.identifier) ?? ""
        facts.isEnabled = node.int(StepAX.enabled).map { $0 != 0 } ?? true
        facts.cmdChar = node.string(StepAX.cmdChar) ?? ""
        facts.cmdModifiers = node.int(StepAX.cmdModifiers) ?? 0
        facts.cmdGlyph = node.int(StepAX.cmdGlyph) ?? 0
        facts.cmdVirtualKey = node.int(StepAX.cmdVirtualKey) ?? 0
        return facts
    }

    private static func multiple(_ attributes: [String], of element: AXUIElement) -> [AnyObject]? {
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element, attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard status == .success, let list = values as? [AnyObject], list.count == attributes.count else { return nil }
        return list
    }
}
