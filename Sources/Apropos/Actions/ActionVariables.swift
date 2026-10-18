import Foundation

/// A named value an action can pass to its backend. Backends receive values as separate arguments, standard input,
/// environment entries or AppleScript parameters; they are never pasted into program text.
public enum ActionVariable: String, Sendable, CaseIterable, Codable {
    /// The selected text.
    case text
    /// Every selected file, as absolute paths. List variable.
    case files
    /// The first selected file's path.
    case file
    /// The first selected file's name.
    case fileName
    /// Every selected file's name. List variable.
    case fileNames
    /// The folder to work in: the first selected file if it is a folder, else its parent, else the front folder.
    case directory
    case url
    case title
    case folder
    case branch
    case repo
    case document

    public var isList: Bool { self == .files || self == .fileNames }

    /// The context an action must declare to use this variable. `directory` is satisfied by either option.
    var requirements: [ContextRequirement] {
        switch self {
        case .text: [.selectedText]
        case .files, .file, .fileName, .fileNames: [.selectedFiles]
        case .directory: [.selectedFiles, .folder]
        case .url, .title: [.pageURL]
        case .folder: [.folder]
        case .branch, .repo: [.gitRepo]
        case .document: [.document]
        }
    }

    /// The name of the environment entry that carries this variable, for scripts that prefer environment access.
    public var environmentName: String { "APROPOS_" + rawValue.uppercased() }
}

/// What an action runs on: the context values with the variables derived from them.
public struct ActionInput: Sendable {
    public let values: ContextValues

    public init(values: ContextValues) { self.values = values }

    public func scalar(_ variable: ActionVariable) -> String? {
        switch variable {
        case .text: values.selectedText
        case .file: values.selectedFiles.first?.path
        case .fileName: values.selectedFiles.first?.lastPathComponent
        case .directory: directory()
        case .url: values.pageURL?.absoluteString
        case .title: values.pageTitle
        case .folder: values.folderURL?.path
        case .branch: values.gitBranch
        case .repo: values.repoRoot?.path
        case .document: values.documentURL?.path
        case .files, .fileNames: nil
        }
    }

    public func list(_ variable: ActionVariable) -> [String]? {
        switch variable {
        case .files: values.selectedFiles.isEmpty ? nil : values.selectedFiles.map(\.path)
        case .fileNames: values.selectedFiles.isEmpty ? nil : values.selectedFiles.map(\.lastPathComponent)
        default: nil
        }
    }

    private func directory() -> String? {
        if let first = values.selectedFiles.first {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return first.path
            }
            return first.deletingLastPathComponent().path
        }
        return values.folderURL?.path
    }

    /// Small variables as environment entries. Large or list values are left out: use standard input or arguments.
    public func environment() -> [String: String] {
        var result: [String: String] = [:]
        for variable in ActionVariable.allCases where !variable.isList {
            if let value = scalar(variable), value.utf8.count <= 16_384 { result[variable.environmentName] = value }
        }
        return result
    }
}

/// A string with `{variable}` placeholders. `{{` and `}}` are literal braces.
public struct ActionTemplate: Sendable, Equatable, Codable {
    public enum Part: Sendable, Equatable {
        case literal(String)
        case variable(ActionVariable)
    }

    public enum ParseError: Error, Equatable {
        case unknownVariable(String)
        case unbalancedBrace
    }

    public let source: String
    public let parts: [Part]

    public init(_ source: String) throws {
        self.source = source
        var parts: [Part] = []
        var literal = ""
        var index = source.startIndex
        func flush() {
            if !literal.isEmpty { parts.append(.literal(literal)) }
            literal = ""
        }
        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            if character == "{" {
                if next < source.endIndex, source[next] == "{" {
                    literal.append("{")
                    index = source.index(after: next)
                    continue
                }
                guard let close = source[next...].firstIndex(of: "}") else { throw ParseError.unbalancedBrace }
                let name = String(source[next..<close])
                guard let variable = ActionVariable(rawValue: name) else { throw ParseError.unknownVariable(name) }
                flush()
                parts.append(.variable(variable))
                index = source.index(after: close)
            } else if character == "}" {
                guard next < source.endIndex, source[next] == "}" else { throw ParseError.unbalancedBrace }
                literal.append("}")
                index = source.index(after: next)
            } else {
                literal.append(character)
                index = next
            }
        }
        flush()
        self.parts = parts
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        try self.init(text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(source)
    }

    public var variables: [ActionVariable] {
        parts.compactMap { if case .variable(let variable) = $0 { variable } else { nil } }
    }

    public var hasVariables: Bool { !variables.isEmpty }

    /// True when the whole template is one list variable, the only place a list may appear.
    var singleListVariable: ActionVariable? {
        if parts.count == 1, case .variable(let variable) = parts[0], variable.isList { return variable }
        return nil
    }

    /// One argument becomes one entry, or many for a list variable. Nil when a value is missing.
    func expandArgument(_ input: ActionInput) -> [String]? {
        if let list = singleListVariable { return input.list(list) }
        return expandScalar(input).map { [$0] }
    }

    /// Concatenates literals and values, with `transform` applied to each value (not to the literals).
    func expandScalar(_ input: ActionInput, transform: (String) -> String = { $0 }) -> String? {
        var result = ""
        for part in parts {
            switch part {
            case .literal(let text): result += text
            case .variable(let variable):
                guard let value = input.scalar(variable) else { return nil }
                result += transform(value)
            }
        }
        return result
    }
}

extension String {
    /// Percent-encodes everything except RFC 3986 unreserved characters, so a value can never end a URL component.
    var percentEncodedForURL: String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }
}
