import Foundation

/// Small string helpers shared by providers and the item builder.
public enum ContextText {
    public static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Cuts a selection to the safe length. Whitespace-only selections count as none.
    public static func truncatedSelection(_ text: String?) -> String? {
        guard let text, text.contains(where: { !$0.isWhitespace }) else { return nil }
        return String(text.prefix(ContextLimits.maxSelectionLength))
    }

    /// A local path from an AXDocument value (a file URL or a plain path). Remote URLs are not file paths.
    public static func filePath(_ value: String) -> String? {
        if value.hasPrefix("file://") {
            return URL(string: value)?.path.nilIfEmpty
        }
        return value.hasPrefix("/") ? value : nil
    }

    /// One line, no longer than `limit`, with an ellipsis when cut.
    public static func oneLine(_ text: String, limit: Int = ContextLimits.maxLabelLength) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "\u{2026}"
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
