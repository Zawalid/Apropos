import Foundation

/// How a command reads in the palette. The real title stays on `Command` (it is what gets run); these helpers only
/// shape what is drawn.
extension Command {
    /// The title without trailing ellipses or noise such as ", 1 update", which apps append to menu items.
    public var displayTitle: String { CommandDisplay.cleanTitle(title) }

    /// The menu trail as one quiet line, for example `File > New Session`. Items of the app's own menu read as
    /// `App menu` rather than repeating the app name.
    public func displaySubtitle(appName: String?) -> String {
        guard !path.isEmpty else { return "" }
        var trail = path
        if let appName, trail.first == appName { trail[0] = "App menu" }
        return trail.joined(separator: " > ")
    }
}

public enum CommandDisplay {
    public static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            if let comma = title.lastIndex(of: ","), isUpdateCount(title[title.index(after: comma)...]) {
                title.removeSubrange(comma...)
                changed = true
            }
            for ellipsis in ["\u{2026}", "..."] where title.hasSuffix(ellipsis) {
                title.removeLast(ellipsis.count)
                changed = true
            }
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != title {
                title = trimmed
                changed = true
            }
        }
        return title.isEmpty ? raw : title
    }

    /// Whether a title cannot be understood without its menu: it starts in lower case ("as Columns") or is a bare
    /// generic word that many menus reuse.
    public static func isAmbiguous(title: String) -> Bool {
        let clean = cleanTitle(title)
        guard let first = clean.first else { return false }
        if first.isLowercase { return true }
        return genericTitles.contains(clean.lowercased())
    }

    private static let genericTitles: Set<String> = [
        "show", "hide", "next", "previous", "reset", "clear", "options", "more", "all", "other", "default", "custom",
        "bigger", "smaller", "larger", "actual size", "zoom", "toggle", "new", "open", "close", "add", "remove",
    ]

    /// Matches "1 update" and "12 updates".
    private static func isUpdateCount(_ text: Substring) -> Bool {
        let parts = text.split(separator: " ")
        guard parts.count == 2, Int(parts[0]) != nil else { return false }
        return parts[1] == "update" || parts[1] == "updates"
    }
}
