import Foundation

/// A value held between steps. It lives in memory only and prints as a count, so a log line or a dump never carries it.
public enum SequenceValue: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    case text(String)
    case url(URL)
    case page(URL, title: String)
    case files([URL])
    case folder(URL)
    case document(URL)
    case repo(root: URL, branch: String?)

    public var kind: SequenceValueKind {
        switch self {
        case .text: .text
        case .url: .url
        case .page: .page
        case .files: .files
        case .folder: .folder
        case .document: .document
        case .repo: .repo
        }
    }

    public var description: String {
        switch self {
        case .text(let text): "SequenceValue(text, \(text.count) chars)"
        case .files(let files): "SequenceValue(files, \(files.count))"
        default: "SequenceValue(\(kind.rawValue))"
        }
    }

    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["summary": description]) }

    /// What the sensed context holds for this kind, or nil when it holds nothing.
    public static func from(context values: ContextValues, kind: SequenceValueKind) -> SequenceValue? {
        switch kind {
        case .text:
            return values.selectedText.map { .text($0) }
        case .url:
            return values.pageURL.map { .url($0) }
        case .page:
            return values.pageURL.map { .page($0, title: values.pageTitle ?? $0.host ?? "") }
        case .files:
            return values.selectedFiles.isEmpty ? nil : .files(values.selectedFiles)
        case .folder:
            return values.folderURL.map { .folder($0) }
        case .document:
            return values.documentURL.map { .document($0) }
        case .repo:
            return values.repoRoot.map { .repo(root: $0, branch: values.gitBranch) }
        }
    }

    /// Puts the value where the engine reads it. Starts from nothing: a step sees only what it declared.
    func apply(to values: inout ContextValues) {
        switch self {
        case .text(let text):
            values.selectedText = text
        case .url(let url):
            values.pageURL = url
        case .page(let url, let title):
            values.pageURL = url
            values.pageTitle = title
        case .files(let files):
            values.selectedFiles = files
        case .folder(let url):
            values.folderURL = url
        case .document(let url):
            values.documentURL = url
        case .repo(let root, let branch):
            values.repoRoot = root
            values.gitBranch = branch
        }
    }
}

/// Why a value could not be passed on. Fixed words, never the value.
public enum SequenceValueProblem: Error, Equatable, Sendable {
    case empty
    case tooLarge
    case notALink
    case notFiles
    case notAllowed

    public var message: String {
        switch self {
        case .empty: "it gave nothing to pass on"
        case .tooLarge: "what it gave is too large to pass on"
        case .notALink: "what it gave is not a web address"
        case .notFiles: "what it gave is not a list of files that exist"
        case .notAllowed: "what it gave cannot be passed on"
        }
    }
}

/// How text becomes a value another step may read. Everything a step gives, and everything the person types, goes
/// through here, so a hostile text cannot reach a backend as anything but a value: control characters are removed,
/// sizes are limited, links must be real web addresses and file lists must be real, absolute, existing paths. The
/// engine then hands values to programs and scripts only as separate arguments, standard input, environment entries,
/// script parameters or percent-encoded link parts.
public enum SequenceCoercion {
    /// The text a step produced or the person typed, as a value of `kind`. Only the four producible kinds exist here.
    public static func value(
        fromText raw: String, as kind: SequenceValueKind, fileExists: (String) -> Bool = defaultFileExists
    ) -> Result<SequenceValue, SequenceValueProblem> {
        guard raw.count <= PayloadLimits.maxTextCharacters * 2 else { return .failure(.tooLarge) }
        switch kind {
        case .text:
            let cleaned = Payload.clean(raw)
            guard cleaned.count <= PayloadLimits.maxTextCharacters else { return .failure(.tooLarge) }
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
            return .success(.text(cleaned))
        case .url, .page:
            let cleaned = Payload.clean(raw)
            guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .failure(.empty) }
            guard let url = TextTools.webURL(from: cleaned), url.absoluteString.count <= PayloadLimits.maxURLCharacters
            else { return .failure(.notALink) }
            return .success(kind == .url ? .url(url) : .page(url, title: url.host ?? url.absoluteString))
        case .files:
            let lines = raw.split(whereSeparator: \.isNewline).map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return .failure(.empty) }
            guard lines.count <= SequenceLimits.maxFilesInValue else { return .failure(.tooLarge) }
            var urls: [URL] = []
            for line in lines {
                guard line.hasPrefix("/"),
                    !line.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
                else { return .failure(.notFiles) }
                let url = URL(fileURLWithPath: line).standardizedFileURL
                // `..` is resolved by standardizing; a path that only works through one is not what was written.
                guard !line.split(separator: "/").contains(".."), fileExists(url.path) else {
                    return .failure(.notFiles)
                }
                urls.append(url)
            }
            return .success(.files(urls))
        case .folder, .document, .repo:
            return .failure(.notAllowed)
        }
    }

    public static func defaultFileExists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// Builds the actions the sequencer runs for the steps that are not an existing action: a link, a Shortcut, menu steps.
/// They are ordinary `ContextAction`s, checked by the same `ActionValidator`, so the engine's rules apply unchanged.
enum SequenceAction {
    /// Which kinds of input can fill a variable.
    static func kinds(providing variable: ActionVariable) -> [SequenceValueKind] {
        switch variable {
        case .text: [.text]
        case .files, .file, .fileName, .fileNames: [.files]
        case .directory: [.files, .folder]
        case .url: [.url, .page]
        case .title: [.page]
        case .folder: [.folder]
        case .branch, .repo: [.repo]
        case .document: [.document]
        }
    }

    /// The action for a link, a Shortcut or menu steps. Nil for the kinds that are resolved from the catalogue.
    static func synthesized(for step: SequenceStep) -> ContextAction? {
        switch step.kind {
        case .openURL(let template):
            let requires = Set(template.variables.compactMap { $0.requirements.first })
            return ContextAction(
                id: ActionID(rawValue: "seq:link"), title: "Open a link", symbol: "link", requires: requires,
                backend: .urlScheme(template), output: .none, timeout: step.effectiveTimeout)
        case .shortcut(let name):
            let takesText = step.inputs.contains { $0.kind == .text }
            let backend = ShortcutBackend(
                name: name.trimmingCharacters(in: .whitespaces), input: takesText ? .text : nil)
            return ContextAction(
                id: ActionID(rawValue: "seq:shortcut"), title: "Run a Shortcut", symbol: "wand.and.stars",
                requires: takesText ? [.selectedText] : [], backend: .shortcut(backend),
                // The result is captured when the step names an output; otherwise it is discarded.
                output: step.output == nil ? .none : .clipboard, timeout: step.effectiveTimeout)
        case .uiSteps(let backend):
            return ContextAction(
                id: ActionID(rawValue: "seq:menu"), title: "Choose menu items", symbol: "filemenu.and.selection",
                requires: [], backend: .uiSteps(backend), output: .none, timeout: step.effectiveTimeout)
        case .contextAction, .destination, .userCommand:
            return nil
        }
    }
}
