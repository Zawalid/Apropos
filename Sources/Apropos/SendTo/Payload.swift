import Foundation

/// What kind of thing is being sent. One context can offer several (a selection inside a browser is text and a page).
public enum PayloadKind: String, Sendable, CaseIterable, Codable, Hashable {
    case text
    case page
    case files
    case folder

    /// The palette group the Send to row sits in, the same one the matching context actions use.
    public var group: ActionGroup {
        switch self {
        case .text: .selectedText
        case .page: .page
        case .files: .selectedFiles
        case .folder: .folder
        }
    }

    /// The word used in rows: "Send selection to...".
    public var noun: String {
        switch self {
        case .text: "selection"
        case .page: "page"
        case .files: "files"
        case .folder: "folder"
        }
    }
}

/// Hard limits on what can be sent. A destination may set a lower limit of its own for text.
public enum PayloadLimits {
    public static let maxTextCharacters = 200_000
    public static let maxFiles = 200
    public static let maxTitleCharacters = 300
    public static let maxURLCharacters = 4_096
}

/// What the person asked to send, derived from the sensed context. It lives in memory only and prints as counts, so a
/// log line or a dump never carries the content. Control characters (a NUL cannot travel in a program argument) are
/// removed on the way in.
public struct Payload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let kind: PayloadKind
    /// The selection (`.text`).
    public let text: String?
    /// The page (`.page`), or the page the selection came from (`.text`), when there is one.
    public let url: URL?
    /// The page title (`.page`) or a title made from the content: the first line of a selection, the first file name.
    public let title: String
    public let files: [URL]
    /// The folder (`.folder`).
    public let folder: URL?
    /// Where the context came from, for the Share menu and previews. Never logged.
    public let sourceBundleID: String?

    private init(
        kind: PayloadKind, text: String? = nil, url: URL? = nil, title: String, files: [URL] = [],
        folder: URL? = nil, sourceBundleID: String?
    ) {
        self.kind = kind
        self.text = text
        self.url = url
        self.title = title
        self.files = files
        self.folder = folder
        self.sourceBundleID = sourceBundleID
    }

    // MARK: Building

    /// The payloads the context offers, in the order their rows are listed: files, text, page, folder. A folder is
    /// offered only in Finder and only when no file is selected, because every editor has a folder and it would be noise.
    public static func candidates(from values: ContextValues, bundleID: String?) -> [Payload] {
        var result: [Payload] = []
        if let files = files(values.selectedFiles, bundleID: bundleID) { result.append(files) }
        if let text = text(values.selectedText, source: values.pageURL, bundleID: bundleID) { result.append(text) }
        if let page = page(url: values.pageURL, title: values.pageTitle, bundleID: bundleID) { result.append(page) }
        if values.selectedFiles.isEmpty, bundleID == "com.apple.finder", let folder = folder(values.folderURL) {
            result.append(folder)
        }
        return result
    }

    public static func text(_ raw: String?, source: URL? = nil, bundleID: String? = nil) -> Payload? {
        guard let raw else { return nil }
        let cleaned = clean(String(raw.prefix(PayloadLimits.maxTextCharacters)))
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Payload(
            kind: .text, text: cleaned, url: acceptableURL(source), title: derivedTitle(from: cleaned),
            sourceBundleID: bundleID)
    }

    public static func page(url: URL?, title: String?, bundleID: String? = nil) -> Payload? {
        guard let url = acceptableURL(url) else { return nil }
        let cleanedTitle = title.map(cleanLine) ?? ""
        let shown = cleanedTitle.isEmpty ? (url.host ?? url.absoluteString) : cleanedTitle
        return Payload(
            kind: .page, url: url, title: String(shown.prefix(PayloadLimits.maxTitleCharacters)),
            sourceBundleID: bundleID)
    }

    public static func files(_ urls: [URL], bundleID: String? = nil) -> Payload? {
        let absolute = urls.filter { $0.isFileURL && $0.path.hasPrefix("/") }
        guard !absolute.isEmpty, absolute.count <= PayloadLimits.maxFiles else { return nil }
        let title = absolute.count == 1 ? absolute[0].lastPathComponent : "\(absolute.count) files"
        return Payload(
            kind: .files, title: String(cleanLine(title).prefix(PayloadLimits.maxTitleCharacters)), files: absolute,
            sourceBundleID: bundleID)
    }

    public static func folder(_ url: URL?, bundleID: String? = nil) -> Payload? {
        guard let url, url.isFileURL, url.path.hasPrefix("/") else { return nil }
        let name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return Payload(
            kind: .folder, title: String(cleanLine(name).prefix(PayloadLimits.maxTitleCharacters)), folder: url,
            sourceBundleID: bundleID)
    }

    private static func acceptableURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            url.absoluteString.count <= PayloadLimits.maxURLCharacters
        else { return nil }
        return url
    }

    // MARK: Cleaning

    /// Removes control characters other than tab, newline and carriage return. They have no meaning in a note and a NUL
    /// would cut a program argument short.
    static func clean(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            scalar == "\t" || scalar == "\n" || scalar == "\r" || !(scalar.properties.generalCategory == .control)
        }))
    }

    /// One line: control characters out, runs of whitespace collapsed.
    static func cleanLine(_ text: String) -> String {
        clean(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The first non-empty line of a selection, at most 80 characters.
    static func derivedTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).lazy.map { cleanLine(String($0)) }.first { !$0.isEmpty } ?? ""
        guard !firstLine.isEmpty else { return "Note" }
        guard firstLine.count > 80 else { return firstLine }
        return String(firstLine.prefix(79)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    // MARK: Using

    /// The payload as context values for the engine. `selectedText` carries the text (`.text` only), `pageURL` the page
    /// or the selection's source, `pageTitle` the title (so `{title}` is always something to name a note by),
    /// `selectedFiles` the files and `folderURL` the folder.
    public var contextValues: ContextValues {
        switch kind {
        case .text:
            ContextValues(selectedText: text, pageURL: url, pageTitle: title)
        case .page:
            ContextValues(pageURL: url, pageTitle: title)
        case .files:
            ContextValues(selectedFiles: files, pageTitle: title)
        case .folder:
            ContextValues(pageTitle: title, folderURL: folder)
        }
    }

    /// "selection", "page", "3 files", "folder".
    public var noun: String {
        kind == .files && files.count > 1 ? "\(files.count) files" : (kind == .files ? "file" : kind.noun)
    }

    /// The characters in the text, or 0.
    public var textLength: Int { text?.count ?? 0 }

    /// A short description for a confirmation line: what is about to be sent, in a few words. It shows part of the
    /// content because the person is about to send it and should see it; it is never written anywhere.
    public var previewLine: String {
        switch kind {
        case .text:
            let count = textLength
            return "\"\(title)\" (\(count) character\(count == 1 ? "" : "s"))"
        case .page:
            let host = url?.host ?? ""
            return host.isEmpty || title == host ? "\"\(title)\"" : "\"\(title)\" (\(host))"
        case .files:
            guard files.count > 1 else { return "\"\(title)\"" }
            let names = files.prefix(2).map(\.lastPathComponent).joined(separator: ", ")
            return "\(files.count) files (\(names)\(files.count > 2 ? ", ..." : ""))"
        case .folder:
            return "folder \"\(title)\""
        }
    }

    public var description: String {
        "Payload(\(kind.rawValue), text: \(textLength) chars, files: \(files.count), "
            + "url: \(url == nil ? "no" : "yes"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["summary": description]) }
}
