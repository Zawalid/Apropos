import Foundation

/// Turns raw fields into the ordered chips. Labels are short and never carry more than the person needs to
/// recognise the context: a URL chip shows the host, a selection chip shows its first line.
public enum ContextItemBuilder {
    public static func items(from fields: ContextFields) -> [ContextItem] {
        var items: [ContextItem] = []

        if let label = documentLabel(fields) {
            items.append(make(.document, label))
        }
        if let url = fields.url, let label = urlLabel(url) {
            items.append(make(.url, label))
        }
        if let folder = fields.folderPath {
            let name = (folder as NSString).lastPathComponent
            items.append(make(.folder, name.isEmpty ? folder : name))
        }
        if let branch = fields.gitBranch {
            items.append(make(.branch, branch))
        }
        if let text = fields.selectedText {
            items.append(make(.selection, ContextText.oneLine(text)))
        }
        if let count = fields.selectedItemCount, count > 0 {
            items.append(make(.selectionCount, count == 1 ? "1 selected" : "\(count) selected"))
        }
        return items.filter { !$0.label.isEmpty }
    }

    private static func make(_ kind: ContextKind, _ label: String) -> ContextItem {
        ContextItem(kind: kind, label: ContextText.oneLine(label), symbol: ContextItem.symbol(for: kind))
    }

    private static func documentLabel(_ fields: ContextFields) -> String? {
        if let path = fields.documentPath { return (path as NSString).lastPathComponent }
        if fields.url != nil { return fields.tabTitle }
        // A window title that only repeats the folder name adds nothing.
        guard let title = fields.windowTitle else { return nil }
        if let folder = fields.folderPath, (folder as NSString).lastPathComponent == title { return nil }
        return title
    }

    /// Host plus a short path, no query or fragment (those often carry tokens).
    static func urlLabel(_ text: String) -> String? {
        guard let components = URLComponents(string: text), let host = components.host else { return nil }
        let shortHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let path = components.path == "/" ? "" : components.path
        return shortHost + path
    }
}
