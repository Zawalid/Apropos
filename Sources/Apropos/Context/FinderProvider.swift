import Foundation

/// Finder: the folder of the front window (its AXDocument is a folder URL) and how many items are selected.
public struct FinderProvider: ContextProvider {
    public let bundleIDs: Set<String> = ["com.apple.finder"]
    public let timeout: TimeInterval = 0.15

    public init() {}

    public func read(_ target: ContextTarget) -> ContextFields {
        guard let root = target.root, let window = root.activeWindow() else { return ContextFields() }
        var fields = ContextFields()
        fields.windowTitle = ContextText.clean(window.string(AXAttr.title))
        fields.folderPath = window.string(AXAttr.document).flatMap(ContextText.filePath)
        fields.selectedItemCount = selectedCount(in: window)
        return fields
    }

    /// The selection lives on the file list: an outline or table (rows) or an icon list or browser (children).
    static let listRoles: Set<String> = ["AXOutline", "AXTable", "AXList", "AXBrowser", "AXColumn"]

    func selectedCount(in window: any AXNode) -> Int? {
        let list = window.firstDescendant(maxDepth: 7, maxNodes: 300) { candidate in
            guard let role = candidate.string(AXAttr.role), Self.listRoles.contains(role) else { return false }
            return candidate.count(AXAttr.selectedRows) != nil || candidate.count(AXAttr.selectedChildren) != nil
        }
        guard let list else { return nil }
        return list.count(AXAttr.selectedRows) ?? list.count(AXAttr.selectedChildren)
    }
}
