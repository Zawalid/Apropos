import Foundation

/// What a step does to its target. Only `menu` runs in this version; the others are part of the format so a file
/// written today keeps its meaning later, and the validator refuses them until they are supported.
public enum StepAction: String, Codable, Sendable, CaseIterable {
    /// Choose a menu item.
    case menu
    case press
    case setValue
    case select

    /// The actions this version can run.
    public static let supported: Set<StepAction> = [.menu]
}

/// The kinds of locator, strongest first. A step is resolved in this order whatever order its locators are stored in,
/// so the weakest one can never shadow a stronger one.
public enum LocatorKind: String, Codable, Sendable, CaseIterable, Comparable {
    case identifier
    case roleTitle
    case menuPath
    case shortcut
    case position

    public static func < (lhs: LocatorKind, rhs: LocatorKind) -> Bool { lhs.rank < rhs.rank }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    /// Survives a change of the app's language.
    public var survivesLanguageChange: Bool { self == .identifier || self == .shortcut || self == .position }
}

/// One way to find the element a step acts on.
public enum StepLocator: Equatable, Sendable {
    /// The `AXIdentifier` the developer set. Survives language changes.
    case identifier(String)
    /// The role and the visible title, in the language the step was made in.
    case roleTitle(role: String, title: String)
    /// The titles of the menus down to the item: `["File", "Export as PDF"]`.
    case menuPath([String])
    /// The key equivalent of a menu item, for example `E` with `command`.
    case shortcut(key: String, modifiers: ModifierSet)
    /// The index of the menu bar item, then of each item below it. The weakest locator: menus gain items between
    /// macOS versions.
    case position([Int])
    /// A locator this version does not know, kept so the validator can say what it was. `coordinate` stands for any
    /// pixel position, which is never supported.
    case unsupported(String)

    public var kind: LocatorKind? {
        switch self {
        case .identifier: .identifier
        case .roleTitle: .roleTitle
        case .menuPath: .menuPath
        case .shortcut: .shortcut
        case .position: .position
        case .unsupported: nil
        }
    }
}

extension StepLocator: Codable {
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Fields that would make a locator depend on where something is drawn.
    private static let coordinateFields: [String] = ["x", "y", "point", "frame", "coordinate", "pixel"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let by = try container.decode(String.self, forKey: Key("by"))
        if Self.coordinateFields.contains(by) || Self.coordinateFields.contains(where: { container.contains(Key($0)) })
        {
            self = .unsupported("coordinate")
            return
        }
        switch by {
        case "identifier":
            self = .identifier(try container.decode(String.self, forKey: Key("value")))
        case "roleTitle":
            self = .roleTitle(
                role: try container.decode(String.self, forKey: Key("role")),
                title: try container.decode(String.self, forKey: Key("title")))
        case "menuPath":
            self = .menuPath(try container.decode([String].self, forKey: Key("titles")))
        case "shortcut":
            let names = try container.decodeIfPresent([String].self, forKey: Key("modifiers")) ?? []
            guard let modifiers = ModifierSet(names: names) else {
                throw DecodingError.dataCorruptedError(
                    forKey: Key("modifiers"), in: container, debugDescription: "unknown modifier")
            }
            self = .shortcut(key: try container.decode(String.self, forKey: Key("key")), modifiers: modifiers)
        case "position":
            self = .position(try container.decode([Int].self, forKey: Key("path")))
        default:
            self = .unsupported(by)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .identifier(let value):
            try container.encode("identifier", forKey: Key("by"))
            try container.encode(value, forKey: Key("value"))
        case .roleTitle(let role, let title):
            try container.encode("roleTitle", forKey: Key("by"))
            try container.encode(role, forKey: Key("role"))
            try container.encode(title, forKey: Key("title"))
        case .menuPath(let titles):
            try container.encode("menuPath", forKey: Key("by"))
            try container.encode(titles, forKey: Key("titles"))
        case .shortcut(let key, let modifiers):
            try container.encode("shortcut", forKey: Key("by"))
            try container.encode(key, forKey: Key("key"))
            try container.encode(modifiers.names, forKey: Key("modifiers"))
        case .position(let path):
            try container.encode("position", forKey: Key("by"))
            try container.encode(path, forKey: Key("path"))
        case .unsupported(let by):
            try container.encode(by, forKey: Key("by"))
        }
    }
}

extension ModifierSet {
    /// Names as written in JSON, in macOS display order.
    var names: [String] {
        var result: [String] = []
        if contains(.control) { result.append("control") }
        if contains(.option) { result.append("option") }
        if contains(.shift) { result.append("shift") }
        if contains(.command) { result.append("command") }
        return result
    }

    /// Nil when a name is not one of `command`, `option`, `shift`, `control`.
    init?(names: [String]) {
        var set = ModifierSet()
        for name in names {
            switch name {
            case "command": set.insert(.command)
            case "option": set.insert(.option)
            case "shift": set.insert(.shift)
            case "control": set.insert(.control)
            default: return nil
            }
        }
        self = set
    }
}

/// How long to wait for a step's element to be there before giving up. The wait polls, it is never a fixed sleep.
public struct StepWait: Codable, Equatable, Sendable {
    public static let defaultTimeout: TimeInterval = 3
    public static let range: ClosedRange<TimeInterval> = 0.2...30

    public var timeout: TimeInterval

    public init(timeout: TimeInterval) { self.timeout = timeout }
}

/// Something that must be true after a step, or the step is reported as failed even though the press was delivered.
/// The locator is looked for among the windows of the step's app.
public struct StepExpectation: Codable, Equatable, Sendable {
    public enum Condition: String, Codable, Sendable {
        case appears
        case gone
    }

    public var condition: Condition
    public var locator: StepLocator
    public var timeout: TimeInterval?

    public init(condition: Condition, locator: StepLocator, timeout: TimeInterval? = nil) {
        self.condition = condition
        self.locator = locator
        self.timeout = timeout
    }
}

/// One step of a command. Plain data: the same value is written to disk, shown for review and handed to the resolver.
public struct UIStep: Codable, Equatable, Sendable, Identifiable {
    /// Unique inside the command. Written as `s1`, `s2`, and filled in when a hand-written file leaves it out.
    public var id: String
    public var action: StepAction
    /// The bundle identifier of the app the step acts in.
    public var app: String
    /// In any order; resolved strongest first.
    public var locators: [StepLocator]
    /// What the step does, in words, for the review list and for failure reports. Never used to find anything.
    public var description: String
    public var wait: StepWait?
    public var expect: StepExpectation?
    /// Bring the app to the front for this step. Off unless the step needs it: replay never takes focus otherwise.
    public var activates: Bool

    public init(
        id: String = "", action: StepAction = .menu, app: String, locators: [StepLocator], description: String,
        wait: StepWait? = nil, expect: StepExpectation? = nil, activates: Bool = false
    ) {
        self.id = id
        self.action = action
        self.app = app
        self.locators = locators
        self.description = description
        self.wait = wait
        self.expect = expect
        self.activates = activates
    }

    private enum CodingKeys: String, CodingKey {
        case id, action, app, locators, description, wait, expect, activates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        action = try container.decode(StepAction.self, forKey: .action)
        app = try container.decodeIfPresent(String.self, forKey: .app) ?? ""
        locators = try container.decodeIfPresent([StepLocator].self, forKey: .locators) ?? []
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        wait = try container.decodeIfPresent(StepWait.self, forKey: .wait)
        expect = try container.decodeIfPresent(StepExpectation.self, forKey: .expect)
        activates = try container.decodeIfPresent(Bool.self, forKey: .activates) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(action, forKey: .action)
        try container.encode(app, forKey: .app)
        try container.encode(locators, forKey: .locators)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(wait, forKey: .wait)
        try container.encodeIfPresent(expect, forKey: .expect)
        if activates { try container.encode(true, forKey: .activates) }
    }

    /// How likely this step is to stop working, from the kinds of locator it has.
    public var fragility: StepFragility { StepFragility.rating(for: locators) }

    /// The seconds to wait for the element before failing.
    public var waitTimeout: TimeInterval { wait?.timeout ?? StepWait.defaultTimeout }
}

/// How likely a step, or a whole command, is to stop working after the app updates or in another language.
public enum StepFragility: String, Codable, Sendable, Comparable, CaseIterable {
    /// An identifier or a shortcut: both survive renamed titles and other languages.
    case sturdy
    /// Titles only. Fine until the app renames the item or runs in another language.
    case fair
    /// Position only, or no usable locator. Breaks when a menu gains an item.
    case fragile

    public static func < (lhs: StepFragility, rhs: StepFragility) -> Bool { lhs.order < rhs.order }

    private var order: Int {
        switch self {
        case .sturdy: 0
        case .fair: 1
        case .fragile: 2
        }
    }

    public static func rating(for locators: [StepLocator]) -> StepFragility {
        let kinds = Set(locators.compactMap(\.kind))
        if kinds.contains(.identifier) || kinds.contains(.shortcut) { return .sturdy }
        if kinds.contains(.roleTitle) || kinds.contains(.menuPath) { return .fair }
        return .fragile
    }

    /// The word for a badge.
    public var title: String {
        switch self {
        case .sturdy: "Sturdy"
        case .fair: "Fair"
        case .fragile: "Fragile"
        }
    }

    /// One sentence for a tooltip.
    public var explanation: String {
        switch self {
        case .sturdy: "Finds its targets by identifier or shortcut, which survive updates and other languages."
        case .fair:
            "Finds its targets by title only. It stops working if the app renames them or runs in another language."
        case .fragile: "Finds its targets by position only. It stops working when the app's menus change."
        }
    }
}

/// The `uiSteps` backend: an ordered list of steps run in order, stopping at the first failure.
public struct UIStepsBackend: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var steps: [UIStep]

    public init(version: Int = UIStepsBackend.currentVersion, steps: [UIStep]) {
        self.version = version
        self.steps = steps.numbered()
    }

    private enum CodingKeys: String, CodingKey { case version, steps }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        steps = try container.decode([UIStep].self, forKey: .steps).numbered()
    }

    /// The least reliable step decides: a command is as sturdy as its weakest step.
    public var fragility: StepFragility { steps.map(\.fragility).max() ?? .fragile }

    /// Bundle identifiers of the apps the steps act in, in first-use order.
    public var apps: [String] {
        var seen = Set<String>()
        return steps.map(\.app).filter { seen.insert($0).inserted }
    }
}

extension Array where Element == UIStep {
    /// Fills in the ids a hand-written file left out, as `s<position>`.
    func numbered() -> [UIStep] {
        enumerated().map { index, step in
            var step = step
            if step.id.isEmpty { step.id = "s\(index + 1)" }
            return step
        }
    }
}
