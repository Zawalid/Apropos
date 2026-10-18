import Foundation

extension ActionDefinition {
    /// A definition that carries only a backend, to turn the pack's backend JSON into an `ActionBackend` with the same
    /// conversion the action packs use.
    fileprivate init(id: ActionID, title: String, backend: BackendDefinition) {
        self.id = id
        self.title = title
        self.symbol = "paperplane"
        self.requires = []
        self.backend = backend
    }
}

/// The JSON form of a destination.
///
/// ```json
/// {
///   "id": "dest:things", "title": "Things", "symbol": "checkmark.circle", "app": "com.culturedcode.ThingsMac",
///   "accepts": ["text", "page"], "confirm": "none", "maxTextCharacters": 8000,
///   "variants": [
///     { "kinds": ["page"], "backend": { "type": "urlScheme", "url": "things:///add?title={title}&notes={url}" } },
///     { "backend": { "type": "urlScheme", "url": "things:///add?title={title}&notes={text}" } }
///   ]
/// }
/// ```
///
/// A backend is the same JSON as in an action pack (`urlScheme`, `appleScript`, `shell`, `shortcut`), with one addition:
/// `sourceLines` (a list of lines) may stand in for `source` so a script stays readable. `function` and `keyPress`
/// backends are not allowed in destinations.
struct DestinationDefinition: Decodable {
    struct VariantDefinition: Decodable {
        var kinds: [PayloadKind]?
        var backend: BackendWithLines
    }

    /// An action backend plus `sourceLines`.
    struct BackendWithLines: Decodable {
        var definition: ActionDefinition.BackendDefinition

        private struct Lines: Decodable { var sourceLines: [String]? }

        init(from decoder: Decoder) throws {
            var definition = try ActionDefinition.BackendDefinition(from: decoder)
            if let lines = try Lines(from: decoder).sourceLines {
                guard definition.source == nil else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "source and sourceLines together"))
                }
                definition.source = lines.joined(separator: "\n")
            }
            self.definition = definition
        }
    }

    var id: ActionID
    var title: String
    var subtitle: String?
    var symbol: String
    var keywords: [String]?
    var app: String?
    var accepts: [PayloadKind]
    var handler: String?
    var confirm: DestinationConfirmation?
    var preview: String?
    var maxTextCharacters: Int?
    var timeout: Double?
    var failureHint: String?
    var review: DestinationReview?
    var variants: [VariantDefinition]?
}

/// Why a destination definition was refused.
enum DestinationValidationError: Error, Equatable, CustomStringConvertible {
    case badID
    case emptyTitle
    case badSymbol
    case noAccepts
    case noVariants
    case unknownHandler(String)
    case handlerNotAllowedHere
    case backendNotAllowed(String)
    case kindNotAccepted(PayloadKind)
    case appleScriptNeedsDashDash
    case badLimit
    case badBundleID
    case invalidBackend(String)

    var description: String {
        switch self {
        case .badID: "id must look like dest:name or user:name in lowercase"
        case .emptyTitle: "title is empty or too long"
        case .badSymbol: "symbol is empty or has spaces"
        case .noAccepts: "accepts must list at least one of text, page, files, folder"
        case .noVariants: "a destination needs at least one variant"
        case .unknownHandler(let name): "no handler named \(name)"
        case .handlerNotAllowedHere: "this handler is only available to built-in destinations"
        case .backendNotAllowed(let type): "the \(type) backend is not allowed in a destination"
        case .kindNotAccepted(let kind): "a variant is for \(kind.rawValue), which the destination does not accept"
        case .appleScriptNeedsDashDash: "an AppleScript destination must pass -- as its first argument"
        case .badLimit: "maxTextCharacters must be between 1 and \(PayloadLimits.maxTextCharacters)"
        case .badBundleID: "app must be a bundle identifier"
        case .invalidBackend(let reason): reason
        }
    }
}

extension Destination {
    /// Backends a destination may use: the ones that cannot press keys or call arbitrary built-in functions.
    private static let allowedBackends: Set<String> = ["urlScheme", "appleScript", "shell", "shortcut"]

    /// Builds and validates a destination from its JSON form.
    ///
    /// Trust: bundled destinations are approved. A destination from a user pack that runs a program, a script or a
    /// Shortcut is approved only when its file says `"review": "approved"`; otherwise it is kept as pending and never
    /// offered or run. Destinations that hand content to a web address always ask for confirmation.
    init(definition: DestinationDefinition, origin: DestinationOrigin) throws {
        guard definition.id.isWellFormed, ["dest", "user"].contains(definition.id.rawValue.prefix { $0 != ":" }) else {
            throw DestinationValidationError.badID
        }
        let title = definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 60 else { throw DestinationValidationError.emptyTitle }
        guard !definition.symbol.isEmpty, !definition.symbol.contains(where: \.isWhitespace) else {
            throw DestinationValidationError.badSymbol
        }
        guard !definition.accepts.isEmpty else { throw DestinationValidationError.noAccepts }
        if let app = definition.app {
            guard !app.isEmpty, app.count <= 128,
                app.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) })
            else { throw DestinationValidationError.badBundleID }
        }
        if let limit = definition.maxTextCharacters, !(1...PayloadLimits.maxTextCharacters).contains(limit) {
            throw DestinationValidationError.badLimit
        }

        let handler: DestinationHandler
        switch definition.handler ?? "engine" {
        case "engine": handler = .engine
        case "shareMenu":
            guard origin == .bundled else { throw DestinationValidationError.handlerNotAllowedHere }
            handler = .shareMenu
        case let other: throw DestinationValidationError.unknownHandler(other)
        }

        var variants: [DestinationVariant] = []
        let accepts = Set(definition.accepts)
        for entry in definition.variants ?? [] {
            variants.append(try Self.variant(entry, destinationID: definition.id, accepts: accepts))
        }
        if handler == .engine, variants.isEmpty { throw DestinationValidationError.noVariants }

        let usesCode = variants.contains(where: \.runsCode)
        var review = DestinationReview.approved
        if origin == .user, usesCode, definition.review != .approved { review = .pending }
        var confirmation = definition.confirm ?? .none
        if variants.contains(where: \.opensWebAddress) { confirmation = .preview }

        self.init(
            id: definition.id, title: title, subtitle: definition.subtitle, symbol: definition.symbol,
            keywords: definition.keywords ?? [], appBundleID: definition.app, accepts: accepts, variants: variants,
            handler: handler, confirmation: confirmation, previewVerb: definition.preview,
            maxTextCharacters: definition.maxTextCharacters, timeout: min(max(definition.timeout ?? 15, 0.5), 120),
            failureHint: definition.failureHint, review: review, origin: origin)
    }

    private static func variant(
        _ entry: DestinationDefinition.VariantDefinition, destinationID: ActionID, accepts: Set<PayloadKind>
    ) throws -> DestinationVariant {
        let kinds = Set(entry.kinds ?? [])
        for kind in kinds where !accepts.contains(kind) { throw DestinationValidationError.kindNotAccepted(kind) }
        let backend = entry.backend.definition
        guard allowedBackends.contains(backend.type) else {
            throw DestinationValidationError.backendNotAllowed(backend.type)
        }

        var action: ContextAction
        do {
            action = try ActionDefinition(id: destinationID, title: "destination", backend: backend).makeAction()
        } catch {
            throw DestinationValidationError.invalidBackend("the backend is incomplete or unknown")
        }
        if case .appleScript(let script) = action.backend {
            // `osascript -e <source> <arguments>` reads an argument that starts with a dash as one of its own options,
            // so the first argument must be a literal `--` that ends option parsing before any value.
            guard script.arguments.isEmpty || script.arguments.first?.source == "--" else {
                throw DestinationValidationError.appleScriptNeedsDashDash
            }
        }
        // The validator wants every placeholder to be backed by a declared kind of context. Declare what the
        // placeholders use; the destination checks availability against the real payload at run time.
        var requires: Set<ContextRequirement> = []
        let probe = DestinationVariant(kinds: kinds, action: action)
        for variable in probe.variables {
            if let first = variable.requirements.first { requires.insert(first) }
        }
        action.requires = requires
        action.output = .none
        action.needsConfirmation = false
        do {
            try ActionValidator.validate(action, functions: ActionFunctionRegistry(), requireContext: false)
        } catch let error as ActionValidationError {
            throw DestinationValidationError.invalidBackend(error.description)
        }
        return DestinationVariant(kinds: kinds, action: action)
    }
}

/// All the destinations in effect: the bundled pack, then user packs. A later destination with the same id replaces an
/// earlier one. Definitions that fail validation are skipped and reported in `issues`; user destinations waiting for
/// approval are kept in `pending` and never offered.
public struct DestinationLibrary: Sendable {
    public static let currentVersion = 1

    public private(set) var destinations: [Destination] = []
    public private(set) var issues: [ActionPackIssue] = []

    public init() {}

    /// The destinations that may run.
    public var runnable: [Destination] { destinations.filter(\.isRunnable) }

    /// User destinations that run a program or script and wait for the person to approve them.
    public var pending: [Destination] { destinations.filter { !$0.isRunnable } }

    public func destination(for id: ActionID) -> Destination? { destinations.first { $0.id == id } }

    /// Adds one pack file: `{ "schemaVersion": 1, "name": "...", "destinations": [ ... ] }`.
    public mutating func add(packData data: Data, source: String, origin: DestinationOrigin) {
        struct Lossy: Decodable {
            var definition: DestinationDefinition?
            init(from decoder: Decoder) throws { definition = try? DestinationDefinition(from: decoder) }
        }
        struct Pack: Decodable {
            var schemaVersion: Int
            var name: String?
            var destinations: [Lossy]
        }
        guard data.count <= 1_000_000, let pack = try? JSONDecoder().decode(Pack.self, from: data) else {
            issues.append(ActionPackIssue(source: source, actionID: nil, reason: "not a valid destination pack"))
            return
        }
        guard pack.schemaVersion <= Self.currentVersion else {
            issues.append(ActionPackIssue(source: source, actionID: nil, reason: "written by a newer version"))
            return
        }
        for entry in pack.destinations {
            guard let definition = entry.definition else {
                issues.append(ActionPackIssue(source: source, actionID: nil, reason: "malformed definition"))
                continue
            }
            do {
                let destination = try Destination(definition: definition, origin: origin)
                if let index = destinations.firstIndex(where: { $0.id == destination.id }) {
                    destinations[index] = destination
                } else {
                    destinations.append(destination)
                }
                if !destination.isRunnable {
                    issues.append(
                        ActionPackIssue(
                            source: source, actionID: definition.id.rawValue,
                            reason: "runs code and waits for approval: set \"review\": \"approved\" after reading it"))
                }
            } catch let error as DestinationValidationError {
                issues.append(
                    ActionPackIssue(source: source, actionID: definition.id.rawValue, reason: error.description))
            } catch {
                issues.append(
                    ActionPackIssue(source: source, actionID: definition.id.rawValue, reason: "invalid definition"))
            }
        }
    }

    /// `~/Library/Application Support/Apropos/destinations`, where user packs live.
    @MainActor public static var userDirectory: URL {
        SettingsStore.supportDirectory.appendingPathComponent(
            "\(SettingsStore.folderName)/destinations", isDirectory: true)
    }

    /// The built-in destinations.
    public static func bundled() -> DestinationLibrary {
        var library = DestinationLibrary()
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "DestinationPacks") ?? []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: url) {
                library.add(packData: data, source: url.lastPathComponent, origin: .bundled)
            }
        }
        return library
    }

    /// The built-in destinations, then every `*.json` in `directory`.
    public static func bundled(plus directory: URL?) -> DestinationLibrary {
        var library = bundled()
        guard let directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return library
        }
        for name in names.filter({ $0.hasSuffix(".json") }).sorted() {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
                library.issues.append(ActionPackIssue(source: name, actionID: nil, reason: "could not be read"))
                continue
            }
            library.add(packData: data, source: name, origin: .user)
        }
        return library
    }
}
