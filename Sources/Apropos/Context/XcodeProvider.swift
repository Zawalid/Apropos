import Foundation

/// Xcode: the current file and the workspace. The window's AXDocument is the file when an editor is focused; the
/// title ("Project - File.swift") is the fallback for the file name and the source of the workspace name.
public struct XcodeProvider: ContextProvider {
    public let bundleIDs: Set<String> = ["com.apple.dt.Xcode"]
    public let timeout: TimeInterval = 0.15

    public init() {}

    public func read(_ target: ContextTarget) -> ContextFields {
        guard let root = target.root, let window = root.activeWindow() else { return ContextFields() }
        var fields = ContextFields()
        let title = ContextText.clean(window.string(AXAttr.title))
        fields.windowTitle = title
        fields.documentPath = window.string(AXAttr.document).flatMap(ContextText.filePath)
        let parts = Self.titleParts(title)
        fields.workspace = parts.workspace
        if fields.documentPath == nil, let file = parts.file {
            // No path available: keep just the file name so the chip still shows it.
            fields.documentPath = file
        }
        fields.readSelection(from: root)
        return fields
    }

    /// Xcode titles look like "Workspace - File.swift" (separator is a dash or an em dash). A title with no
    /// separator is the workspace alone.
    static func titleParts(_ title: String?) -> (workspace: String?, file: String?) {
        guard let title else { return (nil, nil) }
        for separator in [" \u{2014} ", " - ", " \u{2013} "] {
            if let range = title.range(of: separator) {
                let workspace = String(title[..<range.lowerBound])
                let file = String(title[range.upperBound...])
                return (ContextText.clean(workspace), ContextText.clean(file))
            }
        }
        return (title, nil)
    }
}
