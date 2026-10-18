import ApplicationServices
import Foundation

/// A read-only view of one Accessibility element. Providers read through this so tests can use fake trees.
public protocol AXNode: Sendable {
    func string(_ attribute: String) -> String?
    func int(_ attribute: String) -> Int?
    func node(_ attribute: String) -> (any AXNode)?
    func nodes(_ attribute: String) -> [any AXNode]
    /// Number of values in an array attribute, without fetching them. Nil when the attribute is unsupported.
    func count(_ attribute: String) -> Int?
}

public enum AXAttr {
    public static let role = "AXRole"
    public static let subrole = "AXSubrole"
    public static let title = "AXTitle"
    public static let document = "AXDocument"
    public static let url = "AXURL"
    public static let focusedWindow = "AXFocusedWindow"
    public static let focusedElement = "AXFocusedUIElement"
    public static let windows = "AXWindows"
    public static let children = "AXChildren"
    public static let selectedText = "AXSelectedText"
    public static let selectedRows = "AXSelectedRows"
    public static let selectedChildren = "AXSelectedChildren"
}

extension AXNode {
    /// The window the person is working in: the focused one, else the first.
    public func activeWindow() -> (any AXNode)? {
        node(AXAttr.focusedWindow) ?? nodes(AXAttr.windows).first
    }

    /// Breadth-first search with hard limits, so a huge UI tree can never stall a read.
    public func firstDescendant(
        maxDepth: Int = 6, maxNodes: Int = 250, where matches: (any AXNode) -> Bool
    ) -> (any AXNode)? {
        var level: [any AXNode] = nodes(AXAttr.children)
        var visited = 0
        var depth = 1
        while !level.isEmpty, depth <= maxDepth {
            var next: [any AXNode] = []
            for candidate in level {
                visited += 1
                if visited > maxNodes { return nil }
                if matches(candidate) { return candidate }
                next += candidate.nodes(AXAttr.children)
            }
            level = next
            depth += 1
        }
        return nil
    }
}

/// The live implementation over `AXUIElement`.
public struct LiveAXNode: AXNode, @unchecked Sendable {
    // AXUIElement is a thread-safe CF object; it is only used for synchronous reads.
    let element: AXUIElement

    public init(element: AXUIElement) { self.element = element }

    /// The application element for a process, with a short messaging timeout so a hung app answers quickly.
    public static func application(pid: pid_t, timeout: Float = 0.2) -> LiveAXNode {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return LiveAXNode(element: app)
    }

    private func value(_ attribute: String) -> CFTypeRef? {
        var out: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute as CFString, &out)
        return status == .success ? out : nil
    }

    public func string(_ attribute: String) -> String? {
        guard let raw = value(attribute) else { return nil }
        if let text = raw as? String { return text }
        if CFGetTypeID(raw) == CFURLGetTypeID(), let url = raw as? URL { return url.absoluteString }
        return nil
    }

    public func int(_ attribute: String) -> Int? {
        (value(attribute) as? NSNumber)?.intValue
    }

    public func node(_ attribute: String) -> (any AXNode)? {
        guard let raw = value(attribute), let found = AXMenuReader.element(raw) else { return nil }
        return LiveAXNode(element: found)
    }

    public func nodes(_ attribute: String) -> [any AXNode] {
        guard let list = value(attribute) as? [AnyObject] else { return [] }
        return list.compactMap(AXMenuReader.element).map { LiveAXNode(element: $0) }
    }

    public func count(_ attribute: String) -> Int? {
        var count: CFIndex = 0
        let status = AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
        return status == .success ? count : nil
    }
}
