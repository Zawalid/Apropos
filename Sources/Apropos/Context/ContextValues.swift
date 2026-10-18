import Foundation

/// What a piece of context an action can require. Combined with `ContextValues.has(_:)` to decide which actions apply.
public enum ContextRequirement: String, Sendable, CaseIterable, Codable {
    case selectedText
    case selectedFiles
    case pageURL
    case folder
    case gitRepo
    case document
}

/// The raw, typed values behind the chips, for actions to use. They live in memory only: the type prints as counts,
/// so an accidental log line or `dump` never carries a selection, a path or a URL.
public struct ContextValues: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// The whole selection, up to `ContextLimits.maxValueTextLength` characters. Never read from secure fields.
    public var selectedText: String?
    /// Absolute file URLs selected in Finder.
    public var selectedFiles: [URL]
    public var pageURL: URL?
    public var pageTitle: String?
    /// The folder of the front window, or the folder holding the open document.
    public var folderURL: URL?
    public var documentURL: URL?
    public var gitBranch: String?
    public var repoRoot: URL?

    public init(
        selectedText: String? = nil, selectedFiles: [URL] = [], pageURL: URL? = nil, pageTitle: String? = nil,
        folderURL: URL? = nil, documentURL: URL? = nil, gitBranch: String? = nil, repoRoot: URL? = nil
    ) {
        self.selectedText = selectedText
        self.selectedFiles = selectedFiles
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.folderURL = folderURL
        self.documentURL = documentURL
        self.gitBranch = gitBranch
        self.repoRoot = repoRoot
    }

    public func has(_ requirement: ContextRequirement) -> Bool {
        switch requirement {
        case .selectedText: selectedText != nil
        case .selectedFiles: !selectedFiles.isEmpty
        case .pageURL: pageURL != nil
        case .folder: folderURL != nil
        case .gitRepo: repoRoot != nil
        case .document: documentURL != nil
        }
    }

    public var present: Set<ContextRequirement> { Set(ContextRequirement.allCases.filter(has)) }

    public var isEmpty: Bool { present.isEmpty }

    public var description: String {
        "ContextValues(text: \(selectedText?.count ?? 0) chars, files: \(selectedFiles.count), "
            + "page: \(pageURL == nil ? "no" : "yes"), folder: \(folderURL == nil ? "no" : "yes"), "
            + "repo: \(repoRoot == nil ? "no" : "yes"))"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: ["summary": description]) }

    /// Builds the values from what providers read. Only absolute file paths and http(s) page URLs are kept.
    init(fields: ContextFields) {
        func fileURL(_ path: String?) -> URL? {
            guard let path, path.hasPrefix("/") else { return nil }
            return URL(fileURLWithPath: path)
        }
        selectedText = fields.fullSelection
        selectedFiles = (fields.selectedFilePaths ?? []).compactMap(fileURL)
        pageURL = fields.url.flatMap { text in
            guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
                return nil
            }
            return url
        }
        pageTitle = fields.tabTitle
        documentURL = fileURL(fields.documentPath)
        if let folder = fileURL(fields.folderPath) {
            folderURL = folder
        } else if let document = documentURL {
            folderURL = document.deletingLastPathComponent()
        } else {
            folderURL = nil
        }
        gitBranch = fields.gitBranch
        repoRoot = fileURL(fields.repoRoot)
    }
}
