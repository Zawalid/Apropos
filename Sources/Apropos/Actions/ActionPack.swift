import Foundation

/// The JSON form of an action. Everything but `id`, `title`, `symbol`, `requires` and `backend` is optional.
///
/// ```json
/// {
///   "id": "ctx:text.upper", "title": "UPPERCASE", "subtitle": "Change the selection to capitals",
///   "symbol": "textformat.size.larger", "requires": ["selectedText"], "conditions": [],
///   "apps": { "include": [], "exclude": [] },
///   "backend": { "type": "function", "name": "text.upper" },
///   "output": "replaceSelection", "confirm": false, "keywords": ["capital"], "group": "selectedText", "timeout": 10
/// }
/// ```
///
/// Backends by `type`:
/// - `function`: `name`
/// - `shell`: `executable` (absolute), `arguments` (templates), `stdin` and `cwd` (variable names)
/// - `appleScript`: `source` (literal), `arguments` (templates, delivered as `argv`)
/// - `shortcut`: `name`, `input` (variable name)
/// - `urlScheme`: `url` (template; values are percent-encoded)
/// - `keyPress`: `keyCode`, `modifiers` (`command`, `option`, `shift`, `control`)
struct ActionDefinition: Decodable {
    struct BackendDefinition: Decodable {
        var type: String
        var name: String?
        var executable: String?
        var arguments: [ActionTemplate]?
        var stdin: ActionVariable?
        var cwd: ActionVariable?
        var source: String?
        var input: ActionVariable?
        var url: ActionTemplate?
        var keyCode: UInt32?
        var modifiers: [String]?
    }

    var id: ActionID
    var title: String
    var subtitle: String?
    var symbol: String
    var requires: [ContextRequirement]
    var conditions: [ActionCondition]?
    var apps: AppFilter?
    var backend: BackendDefinition
    var output: ActionOutput?
    var confirm: Bool?
    var keywords: [String]?
    var group: ActionGroup?
    var timeout: Double?

    enum ConversionError: Error { case unknownBackend(String), missingField(String), badModifier(String) }

    func makeAction() throws -> ContextAction {
        let built: ActionBackend
        switch backend.type {
        case "function":
            built = .function(try need(backend.name, "name"))
        case "shell":
            built = .shell(
                ShellBackend(
                    executable: try need(backend.executable, "executable"), arguments: backend.arguments ?? [],
                    standardInput: backend.stdin, workingDirectory: backend.cwd))
        case "appleScript":
            built = .appleScript(AppleScriptBackend(source: try need(backend.source, "source"), arguments: backend.arguments ?? []))
        case "shortcut":
            built = .shortcut(ShortcutBackend(name: try need(backend.name, "name"), input: backend.input))
        case "urlScheme":
            built = .urlScheme(try need(backend.url, "url"))
        case "keyPress":
            var modifiers = ModifierSet()
            for name in backend.modifiers ?? [] {
                switch name {
                case "command": modifiers.insert(.command)
                case "option": modifiers.insert(.option)
                case "shift": modifiers.insert(.shift)
                case "control": modifiers.insert(.control)
                default: throw ConversionError.badModifier(name)
                }
            }
            built = .keyPress(KeyPressBackend(keyCode: try need(backend.keyCode, "keyCode"), modifiers: modifiers))
        default:
            throw ConversionError.unknownBackend(backend.type)
        }
        return ContextAction(
            id: id, title: title, subtitle: subtitle, symbol: symbol, requires: Set(requires),
            conditions: Set(conditions ?? []), apps: apps ?? .anyApp, backend: built, output: output ?? .clipboard,
            needsConfirmation: confirm ?? false, keywords: keywords ?? [], group: group, timeout: timeout ?? 10)
    }

    private func need<T>(_ value: T?, _ field: String) throws -> T {
        guard let value else { throw ConversionError.missingField(field) }
        return value
    }
}

/// A line in the report of loading packs: which action or file was skipped and why. Never contains user text.
public struct ActionPackIssue: Sendable, Equatable {
    public let source: String
    public let actionID: String?
    public let reason: String
}

/// All the context actions in effect: the bundled pack, then user packs. A later action with the same id replaces an
/// earlier one, so a user pack can override a built-in. Definitions that fail validation are skipped and reported.
public struct ActionPackLibrary: Sendable {
    public static let currentVersion = 1

    public private(set) var actions: [ContextAction] = []
    public private(set) var issues: [ActionPackIssue] = []
    public let functions: ActionFunctionRegistry

    public init(functions: ActionFunctionRegistry = .builtin) {
        self.functions = functions
    }

    public func action(for id: ActionID) -> ContextAction? { actions.first { $0.id == id } }

    /// The actions on offer for these values in this app, in pack order.
    public func applicable(to values: ContextValues, bundleID: String?) -> [ContextAction] {
        actions.filter { $0.applies(to: values, bundleID: bundleID) }
    }

    /// Adds one pack file's actions. Returns the library for chaining.
    public mutating func add(packData data: Data, source: String) {
        struct Lossy: Decodable {
            var definition: ActionDefinition?
            var failure: String?
            init(from decoder: Decoder) throws {
                do {
                    definition = try ActionDefinition(from: decoder)
                } catch {
                    failure = "malformed definition"
                }
            }
        }
        struct Pack: Decodable {
            var schemaVersion: Int
            var name: String?
            var actions: [Lossy]
        }
        guard let pack = try? JSONDecoder().decode(Pack.self, from: data) else {
            issues.append(ActionPackIssue(source: source, actionID: nil, reason: "not a valid pack file"))
            return
        }
        guard pack.schemaVersion <= Self.currentVersion else {
            issues.append(ActionPackIssue(source: source, actionID: nil, reason: "written by a newer version"))
            return
        }
        for entry in pack.actions {
            guard let definition = entry.definition else {
                issues.append(ActionPackIssue(source: source, actionID: nil, reason: entry.failure ?? "malformed"))
                continue
            }
            do {
                let action = try definition.makeAction()
                try ActionValidator.validate(action, functions: functions)
                if let index = actions.firstIndex(where: { $0.id == action.id }) {
                    actions[index] = action
                } else {
                    actions.append(action)
                }
            } catch let error as ActionValidationError {
                issues.append(ActionPackIssue(source: source, actionID: definition.id.rawValue, reason: error.description))
            } catch {
                issues.append(ActionPackIssue(source: source, actionID: definition.id.rawValue, reason: "invalid backend"))
            }
        }
    }

    /// `~/Library/Application Support/Apropos/actions`, where user packs live.
    @MainActor public static var userDirectory: URL {
        SettingsStore.supportDirectory.appendingPathComponent("\(SettingsStore.folderName)/actions", isDirectory: true)
    }

    /// The built-in catalogue.
    public static func bundled(functions: ActionFunctionRegistry = .builtin) -> ActionPackLibrary {
        var library = ActionPackLibrary(functions: functions)
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "ActionPacks") ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: url) { library.add(packData: data, source: url.lastPathComponent) }
        }
        return library
    }

    /// The built-in catalogue, then every `*.json` in `directory` (for example `Application Support/Apropos/actions`).
    public static func bundled(plus directory: URL?, functions: ActionFunctionRegistry = .builtin) -> ActionPackLibrary {
        var library = bundled(functions: functions)
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return library
        }
        for name in names.filter({ $0.hasSuffix(".json") }).sorted() {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                library.issues.append(ActionPackIssue(source: name, actionID: nil, reason: "could not be read"))
                continue
            }
            library.add(packData: data, source: name)
        }
        return library
    }
}
