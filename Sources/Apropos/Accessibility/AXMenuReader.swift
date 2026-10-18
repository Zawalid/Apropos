import ApplicationServices
import Foundation

public enum MenuReadError: Error, Sendable, Equatable {
    case notTrusted
    case noMenuBar
    case unresponsive
    case failed(Int32)

    public var message: String {
        switch self {
        case .notTrusted: "Apropos needs Accessibility access to read menus."
        case .noMenuBar: "This app has no menu bar."
        case .unresponsive: "The app did not answer in time."
        case .failed(let code): "The app's menus could not be read (error \(code))."
        }
    }
}

public enum CommandRunError: Error, Sendable, Equatable {
    case disabled
    case unavailable
    case failed(Int32)

    public var message: String {
        switch self {
        case .disabled: "That command is not available right now."
        case .unavailable: "That command no longer exists. The app's menu changed."
        case .failed(let code): "The app refused the command (error \(code))."
        }
    }
}

/// Presses a menu item through the Accessibility API.
public struct AXPressTarget: CommandTarget, @unchecked Sendable {
    // AXUIElement is a thread-safe CF object; it is only ever used for synchronous calls.
    let element: AXUIElement

    public func perform() throws {
        let status = AXUIElementPerformAction(element, kAXPressAction as CFString)
        switch status {
        case .success:
            return
        case .cannotComplete:
            // A menu item that opens a modal sheet keeps the app busy past the messaging timeout even though the
            // action was delivered. Treat the timeout as delivered.
            return
        case .invalidUIElement:
            throw CommandRunError.unavailable
        default:
            throw CommandRunError.failed(status.rawValue)
        }
    }
}

/// Reads an app's whole menu bar through the Accessibility API into plain snapshots.
public struct AXMenuReader: Sendable {
    static let attributes: [String] = [
        kAXTitleAttribute,
        kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute,
        kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdGlyphAttribute,
        kAXMenuItemCmdVirtualKeyAttribute,
        kAXMenuItemMarkCharAttribute,
        kAXChildrenAttribute,
    ]

    static let maxDepth = 6

    public init() {}

    public func readMenuBar(pid: pid_t) throws -> [MenuItemSnapshot] {
        guard AXIsProcessTrusted() else { throw MenuReadError.notTrusted }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.5)

        var barValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &barValue)
        switch status {
        case .success: break
        case .noValue, .attributeUnsupported: throw MenuReadError.noMenuBar
        case .cannotComplete: throw MenuReadError.unresponsive
        case .apiDisabled: throw MenuReadError.notTrusted
        default: throw MenuReadError.failed(status.rawValue)
        }
        guard let barValue, let bar = Self.element(barValue) else { throw MenuReadError.noMenuBar }

        return children(of: bar).compactMap { barItem in
            let attributes = read(barItem)
            // A menu bar item holds one AXMenu whose children are the items.
            let menuItems = attributes.children.flatMap { child -> [AXUIElement] in
                children(of: child)
            }
            let items = menuItems.compactMap { snapshot(of: $0, depth: 1) }
            return MenuItemSnapshot(title: attributes.title, isEnabled: attributes.enabled, children: items)
        }
    }

    /// The one place a CF reference becomes an `AXUIElement`. Swift refuses a conditional cast to a CF type, so the type
    /// id is checked first and anything that is not an accessibility element returns nil instead of being reinterpreted.
    static func element(_ value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private struct Attributes {
        var title = ""
        var enabled = true
        var cmdChar = ""
        var cmdModifiers = 0
        var cmdGlyph = 0
        var cmdVirtualKey = 0
        var markChar = ""
        var children: [AXUIElement] = []
    }

    private func snapshot(of element: AXUIElement, depth: Int) -> MenuItemSnapshot? {
        let attributes = read(element)
        var submenu: [MenuItemSnapshot] = []
        if depth < Self.maxDepth {
            for menu in attributes.children {
                submenu += children(of: menu).compactMap { snapshot(of: $0, depth: depth + 1) }
            }
        }
        return MenuItemSnapshot(
            title: attributes.title,
            isEnabled: attributes.enabled,
            cmdChar: attributes.cmdChar,
            cmdModifiers: attributes.cmdModifiers,
            cmdGlyph: attributes.cmdGlyph,
            cmdVirtualKey: attributes.cmdVirtualKey,
            markChar: attributes.markChar,
            children: submenu,
            target: AXPressTarget(element: element))
    }

    /// All the attributes of one element in a single round trip to the app.
    private func read(_ element: AXUIElement) -> Attributes {
        var result = Attributes()
        var values: CFArray?
        let status = AXUIElementCopyMultipleAttributeValues(
            element, Self.attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard status == .success, let list = values as? [AnyObject], list.count == Self.attributes.count else {
            return result
        }
        result.title = list[0] as? String ?? ""
        result.enabled = (list[1] as? Bool) ?? true
        result.cmdChar = list[2] as? String ?? ""
        result.cmdModifiers = (list[3] as? Int) ?? 0
        result.cmdGlyph = (list[4] as? Int) ?? 0
        result.cmdVirtualKey = (list[5] as? Int) ?? 0
        result.markChar = list[6] as? String ?? ""
        result.children = (list[7] as? [AnyObject] ?? []).compactMap(Self.element)
        return result
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        guard status == .success, let list = value as? [AnyObject] else { return [] }
        return list.compactMap(Self.element)
    }
}
