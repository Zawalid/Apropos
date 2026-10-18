import Foundation

/// Finder: the folder of the front window (its AXDocument is a folder URL) and how many items are selected.
public struct FinderProvider: ContextProvider {
    public let bundleIDs: Set<String> = ["com.apple.finder"]
    public let timeout: TimeInterval = 0.15
    public let filesTimeout: TimeInterval = 0.6
    private let selection: any FinderSelectionReading

    public init(selection: any FinderSelectionReading = AppleScriptFinderSelection()) {
        self.selection = selection
    }

    public func readSelectedFiles(_ target: ContextTarget, selectedCount: Int?) -> [String] {
        guard let selectedCount, selectedCount > 0 else { return [] }
        return selection.selectedPaths(timeout: filesTimeout - 0.05)
    }

    public func read(_ target: ContextTarget) -> ContextFields {
        guard let root = target.root, let window = root.activeWindow() else { return ContextFields() }
        var fields = ContextFields()
        fields.windowTitle = ContextText.clean(window.string(AXAttr.title))
        fields.folderPath = window.string(AXAttr.document).flatMap(ContextText.filePath)
        fields.selectedItemCount = selectedCount(in: window)
        return fields
    }

    /// The selection lives on the file list: an outline or table (rows) or an icon list or browser (children).
    static let listRoles: Set<String> = ["AXOutline", "AXTable", "AXList", "AXBrowser", "AXColumn"]

    func selectedCount(in window: any AXNode) -> Int? {
        let list = window.firstDescendant(maxDepth: 7, maxNodes: 300) { candidate in
            guard let role = candidate.string(AXAttr.role), Self.listRoles.contains(role) else { return false }
            return candidate.count(AXAttr.selectedRows) != nil || candidate.count(AXAttr.selectedChildren) != nil
        }
        guard let list else { return nil }
        return list.count(AXAttr.selectedRows) ?? list.count(AXAttr.selectedChildren)
    }
}

/// Reads the paths of the files selected in Finder. Accessibility exposes only names for list rows, so the real
/// implementation asks Finder itself.
public protocol FinderSelectionReading: Sendable {
    func selectedPaths(timeout: TimeInterval) -> [String]
}

/// A fixed AppleScript, run with `osascript` so it can be killed on timeout. The script has no inputs, so nothing can
/// be injected into it. The first run makes macOS ask whether Apropos may control Finder (Automation); until that is
/// allowed this returns nothing and the file actions simply do not appear.
public struct AppleScriptFinderSelection: FinderSelectionReading {
    static let script = """
        tell application "Finder"
            set picked to selection as alias list
        end tell
        set AppleScript's text item delimiters to (character id 31)
        set paths to {}
        repeat with one in picked
            set end of paths to POSIX path of one
        end repeat
        return paths as text
        """

    public init() {}

    public func selectedPaths(timeout: TimeInterval) -> [String] {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let request = ProcessRequest(
                executable: "/usr/bin/osascript", arguments: ["-e", Self.script], timeout: timeout,
                outputLimit: 200_000)
            box.set(try? await ProcessRunner.run(request))
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout + 0.1)
        guard let output = box.get(), output.status == 0 else { return [] }
        return Self.parse(output.text)
    }

    static func parse(_ text: String) -> [String] {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\u{1F}", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .newlines) }
            .filter { $0.hasPrefix("/") }
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: ProcessOutput?
        func set(_ output: ProcessOutput?) {
            lock.lock()
            value = output
            lock.unlock()
        }
        func get() -> ProcessOutput? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
