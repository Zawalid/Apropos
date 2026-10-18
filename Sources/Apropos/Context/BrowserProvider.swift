import Foundation

/// Safari, Arc, Chrome and other Chromium browsers: URL, tab title and selected text, all through Accessibility.
/// Nothing here runs AppleScript, so there is no automation prompt.
public struct BrowserProvider: ContextProvider {
    public let bundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "company.thebrowser.Browser",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]
    public let timeout: TimeInterval = 0.15

    public init() {}

    public func read(_ target: ContextTarget) -> ContextFields {
        guard let root = target.root, let window = root.activeWindow() else { return ContextFields() }
        var fields = ContextFields()
        fields.tabTitle = ContextText.clean(window.string(AXAttr.title))
        fields.windowTitle = fields.tabTitle
        fields.url = pageURL(in: window)
        fields.readSelection(from: root)
        return fields
    }

    /// Safari exposes the page URL as the window's AXDocument. Chromium browsers expose it on the web area.
    func pageURL(in window: any AXNode) -> String? {
        if let document = window.string(AXAttr.document), Self.isWebURL(document) { return document }
        let area = window.firstDescendant(maxDepth: 8, maxNodes: 300) { $0.string(AXAttr.role) == "AXWebArea" }
        if let url = area?.string(AXAttr.url), Self.isWebURL(url) { return url }
        return nil
    }

    static func isWebURL(_ text: String) -> Bool {
        text.hasPrefix("http://") || text.hasPrefix("https://")
    }
}
