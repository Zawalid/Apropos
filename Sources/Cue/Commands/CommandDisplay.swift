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

    /// Matches "1 update" and "12 updates".
    private static func isUpdateCount(_ text: Substring) -> Bool {
        let parts = text.split(separator: " ")
        guard parts.count == 2, Int(parts[0]) != nil else { return false }
        return parts[1] == "update" || parts[1] == "updates"
    }

    /// An SF Symbol name that suggests what a command does: by a leading verb in the title, else by its top-level menu.
    public static func symbol(for command: Command) -> String {
        let title = command.displayTitle.lowercased()
        for (prefix, symbol) in verbSymbols where title == prefix || title.hasPrefix(prefix + " ") {
            return symbol
        }
        if let menu = command.path.first?.lowercased(), let symbol = menuSymbols[menu] { return symbol }
        return "command"
    }

    private static let verbSymbols: [(String, String)] = [
        ("new", "plus"), ("open", "folder"), ("close", "xmark"), ("save", "square.and.arrow.down"),
        ("export", "square.and.arrow.up"), ("share", "square.and.arrow.up"), ("print", "printer"),
        ("copy", "doc.on.doc"), ("cut", "scissors"), ("paste", "doc.on.clipboard"), ("undo", "arrow.uturn.backward"),
        ("redo", "arrow.uturn.forward"), ("find", "magnifyingglass"), ("select", "selection.pin.in.out"),
        ("delete", "trash"), ("duplicate", "plus.square.on.square"), ("rename", "pencil"), ("zoom", "plus.magnifyingglass"),
        ("reload", "arrow.clockwise"), ("refresh", "arrow.clockwise"), ("quit", "power"), ("hide", "eye.slash"),
        ("show", "eye"), ("minimize", "minus.rectangle"), ("settings", "gearshape"), ("preferences", "gearshape"),
        ("about", "info.circle"), ("get info", "info.circle"), ("bring", "square.3.layers.3d.top.filled"),
        ("send", "paperplane"), ("run", "play"), ("build", "hammer"), ("test", "checkmark.seal"),
        ("clean", "trash"), ("back", "chevron.backward"), ("forward", "chevron.forward"),
    ]

    private static let menuSymbols: [String: String] = [
        "file": "doc", "edit": "pencil", "view": "eye", "window": "macwindow", "help": "questionmark.circle",
        "format": "textformat", "go": "arrow.right.circle", "history": "clock", "bookmarks": "bookmark",
        "product": "hammer", "navigate": "location", "editor": "chevron.left.forwardslash.chevron.right",
        "insert": "plus.square", "arrange": "square.3.layers.3d", "object": "cube", "text": "textformat",
        "tab": "rectangle.stack", "develop": "wrench.and.screwdriver", "debug": "ladybug", "source control": "arrow.triangle.branch",
    ]
}
