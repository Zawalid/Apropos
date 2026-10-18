import Foundation

/// Works for any app that exposes the standard Accessibility attributes: window title, AXDocument, selected text on
/// the focused element and window count.
public struct GenericAccessibilityProvider: ContextProvider {
    public let bundleIDs: Set<String> = []
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 0.03) { self.timeout = timeout }

    public func read(_ target: ContextTarget) -> ContextFields {
        guard let root = target.root else { return ContextFields() }
        var fields = ContextFields()
        fields.windowCount = root.count(AXAttr.windows)
        if let window = root.activeWindow() {
            fields.windowTitle = ContextText.clean(window.string(AXAttr.title))
            fields.documentPath = window.string(AXAttr.document).flatMap(ContextText.filePath)
        }
        fields.selectedText = SelectionReader.selectedText(in: root)
        return fields
    }
}

public enum SelectionReader {
    /// Selected text of the focused element. Password fields are never read: the check happens before any value
    /// attribute is requested.
    public static func selectedText(in root: any AXNode) -> String? {
        guard let focused = root.node(AXAttr.focusedElement) else { return nil }
        if isSecure(focused) { return nil }
        return ContextText.truncatedSelection(focused.string(AXAttr.selectedText))
    }

    public static func isSecure(_ element: any AXNode) -> Bool {
        element.string(AXAttr.subrole) == "AXSecureTextField" || element.string(AXAttr.role) == "AXSecureTextField"
    }
}
