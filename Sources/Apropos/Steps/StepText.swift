import Foundation

/// How titles are compared and which menus are never touched. Shared by the validator and the resolver so they agree.
public enum StepText {
    /// Case, accents, runs of spaces and the three-dots-versus-ellipsis difference do not matter: `Édition` is `edition`.
    public static func normalize(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        folded = folded.replacingOccurrences(of: "...", with: "\u{2026}")
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The Apple menu is the first item of the menu bar in every language and is always titled `Apple`. It lists the
    /// person's recent apps, documents and servers and holds their name in the Log Out item.
    public static func isAppleMenuTitle(_ title: String) -> Bool { normalize(title) == "apple" }

    /// Menus that list the person's recent documents or apps. Their items are names of the person's files, so a step
    /// never goes through them.
    private static let recentMenuTitles: Set<String> = [
        "open recent", "open recent files", "open recent documents", "recent", "recents", "recent items",
        "recent documents", "recent files", "recent places", "recently closed",
        "ouvrir recent", "ouvrir un document recent", "ouvrir un fichier recent", "elements recents",
        "documents recents", "fichiers recents",
    ]

    public static func isRecentMenuTitle(_ title: String) -> Bool { recentMenuTitles.contains(normalize(title)) }

    /// AppKit names the recent documents menu with an identifier containing `recent`.
    public static func isRecentMenuIdentifier(_ identifier: String) -> Bool {
        identifier.lowercased().contains("recent")
    }

    /// The role AppKit gives a password field, also used as its subrole.
    public static let secureRole = "AXSecureTextField"

    public static func mentionsSecureField(_ role: String) -> Bool {
        role.lowercased().contains("secure")
    }
}
