import Foundation

/// One line of the run log: what ran, in which app, after what, in which kinds of context. Nothing else.
///
/// The type is the privacy boundary. It has no field that could hold a selection, a URL, a document or file name, a
/// query or a window title, and the initializer cleans what it is given: the app is a bundle identifier or "unknown",
/// the context kinds are only the fixed `ContextKind` names, and the command identity must pass
/// `PredictionPrivacy.isLoggable`. See docs/prediction.md for the field list.
public struct RunEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The person ran the command.
        case run
        /// The person chose Not now on a predicted command; no command ran.
        case dismiss
    }

    public let kind: Kind
    /// Whole seconds since 1970.
    public let time: TimeInterval
    public let command: CommandID
    /// Bundle identifier of the frontmost app when it happened, or `PredictionPrivacy.unknownApp`.
    public let app: String
    /// The command run just before, when it was within the session window.
    public let previous: CommandID?
    /// Which kinds of context were present, sorted. Kinds only, never their values.
    public let contextKinds: [String]
    /// The top prediction on screen when the palette opened, if any. A run of that command counts as accepted, a run of
    /// anything else as ignored.
    public let offered: CommandID?

    public var date: Date { Date(timeIntervalSince1970: time) }

    public init?(
        kind: Kind = .run, at date: Date, command: CommandID, app: String?, previous: CommandID? = nil,
        contextKinds: [ContextKind] = [], offered: CommandID? = nil
    ) {
        self.init(
            kind: kind, time: date.timeIntervalSince1970, command: command, app: app, previous: previous,
            kindNames: contextKinds.map(\.rawValue), offered: offered)
    }

    init?(
        kind: Kind, time: TimeInterval, command: CommandID, app: String?, previous: CommandID?, kindNames: [String],
        offered: CommandID?
    ) {
        guard time.isFinite, time > 0, PredictionPrivacy.isLoggable(command) else { return nil }
        self.kind = kind
        self.time = time.rounded(.down)
        self.command = command
        self.app = PredictionPrivacy.cleanApp(app)
        self.previous = previous.flatMap { PredictionPrivacy.isLoggable($0) ? $0 : nil }
        self.contextKinds = PredictionPrivacy.cleanKinds(kindNames)
        self.offered = offered.flatMap { PredictionPrivacy.isLoggable($0) ? $0 : nil }
    }

    // MARK: Coding

    /// Short keys keep a year of events small. Every key that can appear in the file is listed here.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind = "k"
        case time = "t"
        case command = "c"
        case app = "a"
        case previous = "p"
        case contextKinds = "x"
        case offered = "o"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .run
        let time = try container.decode(Int.self, forKey: .time)
        let command = try container.decode(String.self, forKey: .command)
        let app = try container.decodeIfPresent(String.self, forKey: .app)
        let previous = try container.decodeIfPresent(String.self, forKey: .previous)
        let kinds = try container.decodeIfPresent([String].self, forKey: .contextKinds) ?? []
        let offered = try container.decodeIfPresent(String.self, forKey: .offered)
        // A line that would not be written today is not trusted when read either.
        guard
            let event = RunEvent(
                kind: kind, time: TimeInterval(time), command: CommandID(rawValue: command), app: app,
                previous: previous.map { CommandID(rawValue: $0) }, kindNames: kinds,
                offered: offered.map { CommandID(rawValue: $0) })
        else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "event not allowed in the run log"))
        }
        self = event
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if kind != .run { try container.encode(kind, forKey: .kind) }
        try container.encode(Int(time), forKey: .time)
        try container.encode(command.rawValue, forKey: .command)
        if app != PredictionPrivacy.unknownApp { try container.encode(app, forKey: .app) }
        try container.encodeIfPresent(previous?.rawValue, forKey: .previous)
        if !contextKinds.isEmpty { try container.encode(contextKinds, forKey: .contextKinds) }
        try container.encodeIfPresent(offered?.rawValue, forKey: .offered)
    }
}

/// What may enter the run log. Everything here is a rule about identity strings, because the identity is the only free
/// text the log holds.
public enum PredictionPrivacy {
    public static let unknownApp = "unknown"
    static let maxIdentityLength = 200

    /// Menus whose items are made of the person's content: window lists carry document names, History and Bookmarks
    /// carry page titles, Recent menus carry file names. Matched on the normalized, accent-free name, in the languages
    /// the app is likely to meet. A best-effort list on top of the structural rules; commands under these menus are
    /// not logged at all.
    static let contentMenus: Set<String> = [
        "window", "fenetre", "fenster", "ventana", "finestra", "janela",
        "history", "historique", "verlauf", "historial", "cronologia", "historico",
        "bookmarks", "signets", "lesezeichen", "marcadores", "segnalibri", "favorites", "favoris", "favoriten",
        "favoritos", "preferiti", "marque-pages", "reading list", "liste de lecture",
    ]
    static let contentMenuFragments = ["recent", "recemment", "zuletzt", "reciente", "recenti"]

    /// True when a command identity may be written to the run log.
    public static func isLoggable(_ id: CommandID) -> Bool {
        let raw = id.rawValue
        guard !raw.isEmpty, raw.count <= maxIdentityLength, !raw.contains(where: \.isNewline) else { return false }
        guard let separator = raw.firstIndex(of: "|") else { return true }
        let trail = raw[raw.index(after: separator)...]
        for part in trail.split(separator: ">", omittingEmptySubsequences: true).dropLast() {
            // The last part is the item; the parts before it are menu names. A shortcut or ordinal suffix is on the item.
            let name = CommandID.normalize(String(part))
            if contentMenus.contains(name) { return false }
            if contentMenuFragments.contains(where: { name.contains($0) }) { return false }
        }
        return true
    }

    /// A bundle identifier as is, anything else (empty, too long, containing spaces or slashes) as "unknown".
    static func cleanApp(_ app: String?) -> String {
        guard let app, !app.isEmpty, app.count <= 128 else { return unknownApp }
        let allowed = app.unicodeScalars.allSatisfy {
            ($0.value < 128) && (CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_")
        }
        return allowed ? app : unknownApp
    }

    /// Only the fixed context kind names survive, sorted and without duplicates.
    static func cleanKinds(_ names: [String]) -> [String] {
        let known = Set(ContextKind.allCases.map(\.rawValue))
        return Array(Set(names.filter { known.contains($0) })).sorted()
    }
}
