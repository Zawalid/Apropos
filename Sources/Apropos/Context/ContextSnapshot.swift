import Foundation

/// What a chip in the palette represents. The order of the cases is the display order.
public enum ContextKind: String, Sendable, Equatable, CaseIterable {
    case document
    case url
    case folder
    case branch
    case selection
    case selectionCount
}

/// One piece of context, ready to render as a chip.
public struct ContextItem: Identifiable, Equatable, Sendable {
    public let kind: ContextKind
    /// Short text for the chip, already truncated for display.
    public let label: String
    /// SF Symbol name for the chip icon.
    public let symbol: String

    public var id: ContextKind { kind }

    public init(kind: ContextKind, label: String, symbol: String) {
        self.kind = kind
        self.label = label
        self.symbol = symbol
    }

    public static func symbol(for kind: ContextKind) -> String {
        switch kind {
        case .document: "doc.text"
        case .url: "link"
        case .folder: "folder"
        case .branch: "arrow.triangle.branch"
        case .selection: "text.cursor"
        case .selectionCount: "checkmark.circle"
        }
    }
}

/// The raw values providers could read. Everything is optional: a provider fills in what its app exposes.
/// Selection text is truncated to `ContextLimits.maxSelectionLength` and is never logged.
public struct ContextFields: Equatable, Sendable {
    public var windowTitle: String?
    public var documentPath: String?
    public var url: String?
    public var tabTitle: String?
    public var folderPath: String?
    public var workspace: String?
    public var gitBranch: String?
    public var selectedText: String?
    public var selectedItemCount: Int?
    public var windowCount: Int?

    public init(
        windowTitle: String? = nil, documentPath: String? = nil, url: String? = nil, tabTitle: String? = nil,
        folderPath: String? = nil, workspace: String? = nil, gitBranch: String? = nil, selectedText: String? = nil,
        selectedItemCount: Int? = nil, windowCount: Int? = nil
    ) {
        self.windowTitle = windowTitle
        self.documentPath = documentPath
        self.url = url
        self.tabTitle = tabTitle
        self.folderPath = folderPath
        self.workspace = workspace
        self.gitBranch = gitBranch
        self.selectedText = selectedText
        self.selectedItemCount = selectedItemCount
        self.windowCount = windowCount
    }

    /// Fills the gaps from `other`, keeping values already set.
    public func merging(fallback other: ContextFields) -> ContextFields {
        ContextFields(
            windowTitle: windowTitle ?? other.windowTitle,
            documentPath: documentPath ?? other.documentPath,
            url: url ?? other.url,
            tabTitle: tabTitle ?? other.tabTitle,
            folderPath: folderPath ?? other.folderPath,
            workspace: workspace ?? other.workspace,
            gitBranch: gitBranch ?? other.gitBranch,
            selectedText: selectedText ?? other.selectedText,
            selectedItemCount: selectedItemCount ?? other.selectedItemCount,
            windowCount: windowCount ?? other.windowCount)
    }
}

public enum ContextLimits {
    /// Selections longer than this are cut. Actions that need the whole text should read it themselves at run time.
    public static let maxSelectionLength = 2_000
    public static let maxLabelLength = 48
}

/// Why a snapshot has less than it could. Useful for the debug output, never an error for the panel.
public enum ContextGap: Equatable, Sendable {
    case notTrusted
    case disabledForApp
    case timedOut
}

/// The frontmost app and what Cue could learn about what the person is doing in it.
public struct ContextSnapshot: Equatable, Sendable {
    public var appName: String
    public var bundleID: String?
    public var pid: pid_t
    /// Ordered for display: document, url, folder, branch, selection, selection count.
    public var items: [ContextItem]
    public var fields: ContextFields
    /// Set when the snapshot is partial. Empty items with a gap is normal.
    public var gaps: [ContextGap]
    public var capturedAt: Date

    public init(
        appName: String, bundleID: String?, pid: pid_t = 0, items: [ContextItem] = [],
        fields: ContextFields = ContextFields(), gaps: [ContextGap] = [], capturedAt: Date = Date()
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.pid = pid
        self.items = items
        self.fields = fields
        self.gaps = gaps
        self.capturedAt = capturedAt
    }

    public func item(_ kind: ContextKind) -> ContextItem? {
        items.first { $0.kind == kind }
    }

    public var isEmpty: Bool { items.isEmpty }
}
