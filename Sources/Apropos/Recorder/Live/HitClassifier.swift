import Foundation

/// A node that can say whether it is the same element as another, so its place among siblings can be found.
protocol ComparableAXNode: AXNode {
    func isSameElement(as other: any AXNode) -> Bool
}

enum HitAX {
    static let parent = "AXParent"
    static let menuBar = "AXMenuBar"
    static let menuBarItem = StepAX.menuBarItem
    static let menu = StepAX.menu
    static let menuItem = StepAX.menuItem
    static let menuExtraSubrole = "AXMenuExtra"
    static let focusedElement = AXAttr.focusedElement
    static let roleApplication = "AXApplication"
}

/// Works out what an Accessibility element is and where it sits, from the element and its parents. It reads only roles,
/// subroles, titles, identifiers and the enabled flag, never a value, and walks a bounded number of parents. It works
/// on any `AXNode`, so tests run it on fake trees and only the lookup of the element under the pointer is live.
enum HitClassifier {
    static let maxDepth = 16

    static func classify(_ element: any AXNode, pid: Int32, bundleID: String?) -> HitElement {
        let identity = StepNodeReader.identity(of: element)
        let isSecure = identity.role == StepText.secureRole || identity.subrole == StepText.secureRole
        // A password field gets only its role and subrole read: no title, no identifier.
        var hit = HitElement(
            pid: pid, bundleID: bundleID, role: identity.role, subrole: identity.subrole,
            title: isSecure ? "" : (element.string(AXAttr.title) ?? ""),
            identifier: isSecure ? "" : (element.string(StepAX.identifier) ?? ""),
            isEnabled: element.int(StepAX.enabled).map { $0 != 0 } ?? true, place: .window)
        if isSecure { return hit }
        switch identity.role {
        case HitAX.menuBarItem:
            hit.place = place(ofMenuBarItem: element, subrole: identity.subrole)
        case HitAX.menuItem:
            hit.place = placeOfMenuItem(element, title: hit.title)
        default:
            break
        }
        return hit
    }

    private static func place(ofMenuBarItem item: any AXNode, subrole: String) -> HitElement.Place {
        if subrole == HitAX.menuExtraSubrole { return .menuExtra }
        return .menuBarTitle(barIndex: index(of: item) ?? -1)
    }

    /// Walks up from a menu item through its menus to the menu bar item that opens them. Anything else at the top is a
    /// context or popup menu.
    private static func placeOfMenuItem(_ item: any AXNode, title: String) -> HitElement.Place {
        var path = [title]
        var identifiers: [String] = []
        var current: any AXNode = item
        var depth = 0
        while depth < maxDepth, let parent = current.node(HitAX.parent) {
            depth += 1
            let role = parent.string(AXAttr.role) ?? ""
            switch role {
            case HitAX.menu:
                if let identifier = parent.string(StepAX.identifier) { identifiers.append(identifier) }
            case HitAX.menuItem:
                path.insert(parent.string(AXAttr.title) ?? "", at: 0)
                if let identifier = parent.string(StepAX.identifier) { identifiers.append(identifier) }
            case HitAX.menuBarItem:
                if parent.string(AXAttr.subrole) == HitAX.menuExtraSubrole { return .menuExtra }
                path.insert(parent.string(AXAttr.title) ?? "", at: 0)
                let hasSubmenu = (item.count(AXAttr.children) ?? item.nodes(AXAttr.children).count) > 0
                return .menuItem(
                    path: path, barIndex: index(of: parent) ?? -1, ancestorIdentifiers: identifiers,
                    hasSubmenu: hasSubmenu)
            default:
                return .contextMenuItem
            }
            current = parent
        }
        return .contextMenuItem
    }

    private static func index(of item: any AXNode) -> Int? {
        guard let comparable = item as? any ComparableAXNode, let bar = item.node(HitAX.parent) else { return nil }
        return bar.nodes(AXAttr.children).firstIndex { comparable.isSameElement(as: $0) }
    }

    /// What has the keyboard focus, from its role and subrole alone.
    static func focus(of element: (any AXNode)?) -> TextFocus {
        guard let element else { return .unknown }
        let identity = StepNodeReader.identity(of: element)
        if identity.role == StepText.secureRole || identity.subrole == StepText.secureRole { return .secure }
        if identity.role.isEmpty { return .unknown }
        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        return textRoles.contains(identity.role) || identity.subrole == "AXSearchField" ? .textInput : .other
    }
}
