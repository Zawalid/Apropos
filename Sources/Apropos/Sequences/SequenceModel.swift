import Foundation

// The type is called `CommandSequence` and not `Sequence`, which would hide Swift's own `Sequence` protocol inside this
// module.

/// What a value passed between steps is. The first four can be produced by a step; the rest only come from the sensed
/// context.
public enum SequenceValueKind: String, Codable, Sendable, CaseIterable {
    case text
    case url
    case page
    case files
    case folder
    case document
    case repo

    /// Whether a step can name an output of this kind.
    public var canBeProduced: Bool {
        switch self {
        case .text, .url, .page, .files: true
        case .folder, .document, .repo: false
        }
    }

    /// The word used in sentences.
    public var noun: String {
        switch self {
        case .text: "text"
        case .url: "link"
        case .page: "page"
        case .files: "files"
        case .folder: "folder"
        case .document: "document"
        case .repo: "repository"
        }
    }

    /// The context a step needs for this input to be filled from the sensed context.
    var requirement: ContextRequirement {
        switch self {
        case .text: .selectedText
        case .url, .page: .pageURL
        case .files: .selectedFiles
        case .folder: .folder
        case .document: .document
        case .repo: .gitRepo
        }
    }
}

/// Where a step's input comes from.
public enum SequenceSource: Equatable, Sendable {
    /// What Apropos senses when the run starts (taken once, so a step that changes the frontmost app does not change
    /// what later steps see).
    case context
    /// The named output of an earlier step.
    case output(String)
    /// Asked of the person in the panel before anything runs. Text only.
    case ask(prompt: String)
}

/// One input of a step. A step sees exactly the inputs it declares and nothing else from the context.
public struct SequenceInput: Equatable, Sendable, Codable {
    public var kind: SequenceValueKind
    public var source: SequenceSource

    public init(_ kind: SequenceValueKind, from source: SequenceSource = .context) {
        self.kind = kind
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case kind, from, name, prompt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(SequenceValueKind.self, forKey: .kind)
        switch try container.decodeIfPresent(String.self, forKey: .from) ?? "context" {
        case "context":
            source = .context
        case "output":
            source = .output(try container.decode(String.self, forKey: .name))
        case "ask":
            source = .ask(prompt: try container.decode(String.self, forKey: .prompt))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .from, in: container, debugDescription: "unknown input source")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch source {
        case .context:
            try container.encode("context", forKey: .from)
        case .output(let name):
            try container.encode("output", forKey: .from)
            try container.encode(name, forKey: .name)
        case .ask(let prompt):
            try container.encode("ask", forKey: .from)
            try container.encode(prompt, forKey: .prompt)
        }
    }
}

/// A value a step hands to later steps, under a name.
public struct SequenceOutput: Equatable, Sendable, Codable {
    public var name: String
    public var kind: SequenceValueKind

    public init(name: String, kind: SequenceValueKind = .text) {
        self.name = name
        self.kind = kind
    }
}

/// What a step does.
public enum SequenceStepKind: Equatable, Sendable {
    /// Menu picks in other apps (the step engine, docs/ui-steps.md). Takes and gives no values.
    case uiSteps(UIStepsBackend)
    /// A built-in or pack context action, by id (`ctx:text.upper`).
    case contextAction(ActionID)
    /// A send-to destination, by id (`dest:notes`). Takes one payload input.
    case destination(ActionID)
    /// One of the person's own commands, by id (`user:...`). A command that is itself a sequence is refused.
    case userCommand(ActionID)
    /// A link or URL scheme: a template whose values are percent-encoded.
    case openURL(ActionTemplate)
    /// An Apple Shortcut, by name. Gets its text input as its input and gives its text result.
    case shortcut(name: String)

    /// The JSON discriminator.
    public var tag: String {
        switch self {
        case .uiSteps: "uiSteps"
        case .contextAction: "contextAction"
        case .destination: "destination"
        case .userCommand: "userCommand"
        case .openURL: "openURL"
        case .shortcut: "shortcut"
        }
    }

    /// Whether the step can name an output.
    public var canProduceOutput: Bool {
        switch self {
        case .contextAction, .userCommand, .shortcut: true
        case .uiSteps, .destination, .openURL: false
        }
    }
}

public enum SequenceTrust: String, Codable, Sendable {
    case trusted
    /// Imported, or containing something imported. Stored, shown, never run until the person approves it.
    case untrusted
}

/// One step of a sequence. Plain data: written to disk, shown for review and handed to the planner.
public struct SequenceStep: Identifiable, Equatable, Sendable {
    /// Unique inside the sequence: `s1`, `s2`, ...
    public var id: String
    /// What the person saw when they added it ("UPPERCASE"). Display only; review screens use `summary` instead.
    public var label: String
    public var kind: SequenceStepKind
    public var inputs: [SequenceInput]
    public var output: SequenceOutput?
    /// Go on with the next step when this one fails. Off by default: a run stops at the first failure.
    public var continueOnFailure: Bool
    /// Seconds this step may take, 0.5 to 60. Nil: the default for its kind.
    public var timeout: TimeInterval?
    /// A step that came from outside (an import, the recorder) is untrusted until the person approves the sequence.
    public var trust: SequenceTrust

    public init(
        id: String = "", label: String = "", kind: SequenceStepKind, inputs: [SequenceInput] = [],
        output: SequenceOutput? = nil, continueOnFailure: Bool = false, timeout: TimeInterval? = nil,
        trust: SequenceTrust = .trusted
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.inputs = inputs
        self.output = output
        self.continueOnFailure = continueOnFailure
        self.timeout = timeout
        self.trust = trust
    }

    /// The seconds the step may take.
    public var effectiveTimeout: TimeInterval {
        if let timeout { return timeout }
        switch kind {
        case .uiSteps(let backend): return min(max(10, Double(backend.steps.count) * 6), SequenceLimits.maxStepTimeout)
        case .contextAction, .userCommand, .destination, .openURL, .shortcut: return SequenceLimits.defaultStepTimeout
        }
    }

    /// What the step does, worked out from its data and not from `label`.
    public var summary: String {
        switch kind {
        case .uiSteps(let backend):
            let count = backend.steps.count
            return "Choose \(count) menu item\(count == 1 ? "" : "s") in " + backend.apps.joined(separator: ", ")
        case .contextAction(let id): return "Run the action \(id.rawValue)"
        case .destination(let id): return "Send to \(id.rawValue)"
        case .userCommand(let id): return "Run your command \(id.rawValue)"
        case .openURL(let template): return "Open \(template.source)"
        case .shortcut(let name): return "Run the Shortcut \u{201C}\(name)\u{201D}"
        }
    }

    /// The inputs that are asked of the person.
    public var questions: [(kind: SequenceValueKind, prompt: String)] {
        inputs.compactMap { input in
            if case .ask(let prompt) = input.source { (input.kind, prompt) } else { nil }
        }
    }
}

extension SequenceStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, label, kind, action, destination, command, url, shortcut, ui, inputs, output, continueOnFailure
        case timeout, trust
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        switch try container.decode(String.self, forKey: .kind) {
        case "uiSteps": kind = .uiSteps(try container.decode(UIStepsBackend.self, forKey: .ui))
        case "contextAction": kind = .contextAction(try container.decode(ActionID.self, forKey: .action))
        case "destination": kind = .destination(try container.decode(ActionID.self, forKey: .destination))
        case "userCommand": kind = .userCommand(try container.decode(ActionID.self, forKey: .command))
        case "openURL": kind = .openURL(try container.decode(ActionTemplate.self, forKey: .url))
        case "shortcut": kind = .shortcut(name: try container.decode(String.self, forKey: .shortcut))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "unknown step kind")
        }
        inputs = try container.decodeIfPresent([SequenceInput].self, forKey: .inputs) ?? []
        output = try container.decodeIfPresent(SequenceOutput.self, forKey: .output)
        continueOnFailure = try container.decodeIfPresent(Bool.self, forKey: .continueOnFailure) ?? false
        timeout = try container.decodeIfPresent(Double.self, forKey: .timeout)
        trust = try container.decodeIfPresent(SequenceTrust.self, forKey: .trust) ?? .trusted
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if !label.isEmpty { try container.encode(label, forKey: .label) }
        try container.encode(kind.tag, forKey: .kind)
        switch kind {
        case .uiSteps(let backend): try container.encode(backend, forKey: .ui)
        case .contextAction(let action): try container.encode(action, forKey: .action)
        case .destination(let destination): try container.encode(destination, forKey: .destination)
        case .userCommand(let command): try container.encode(command, forKey: .command)
        case .openURL(let template): try container.encode(template, forKey: .url)
        case .shortcut(let name): try container.encode(name, forKey: .shortcut)
        }
        if !inputs.isEmpty { try container.encode(inputs, forKey: .inputs) }
        try container.encodeIfPresent(output, forKey: .output)
        if continueOnFailure { try container.encode(true, forKey: .continueOnFailure) }
        try container.encodeIfPresent(timeout, forKey: .timeout)
        if trust == .untrusted { try container.encode(trust, forKey: .trust) }
    }
}

/// The `sequence` backend of a command: an ordered list of steps run one after the other. It is what a command file
/// stores under `backend`; the title, aliases, symbol and hotkey belong to the command around it.
public struct SequenceBackend: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var steps: [SequenceStep]

    public init(version: Int = SequenceBackend.currentVersion, steps: [SequenceStep]) {
        self.version = version
        self.steps = steps.numbered()
    }

    private enum CodingKeys: String, CodingKey { case version, steps }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        steps = try container.decode([SequenceStep].self, forKey: .steps).numbered()
    }

    /// Bundle identifiers of the apps the menu steps act in, for the command's `apps` filter.
    public var uiApps: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for step in steps {
            if case .uiSteps(let backend) = step.kind {
                for app in backend.apps where seen.insert(app).inserted { result.append(app) }
            }
        }
        return result
    }

    /// How long the whole run may take: each step's time plus a second, capped by the command limit of 120.
    public var suggestedTimeout: TimeInterval {
        min(max(steps.reduce(1) { $0 + $1.effectiveTimeout }, 10), SequenceLimits.maxTotalTimeout)
    }
}

extension Array where Element == SequenceStep {
    /// Fills in the ids a hand-written file left out, as `s<position>`.
    func numbered() -> [SequenceStep] {
        enumerated().map { index, step in
            var step = step
            if step.id.isEmpty { step.id = "s\(index + 1)" }
            return step
        }
    }
}

/// A sequence as a file of its own, for export, the recorder's hand-over and drafts: a command's worth of identity
/// around the steps. Saved in the palette, it becomes an ordinary user command (see `CommandSequence.userCommand`).
public struct CommandSequence: Codable, Equatable, Sendable, Identifiable {
    public static let currentVersion = 1

    public var schemaVersion: Int
    /// `user:<lowercase uuid>`. Stable, so usage, pins and the hotkey follow the sequence through edits.
    public let id: ActionID
    public var title: String
    public var aliases: [String]
    /// An SF Symbol name.
    public var symbol: String
    public var steps: [SequenceStep]
    public var trust: SequenceTrust

    public init(
        id: ActionID = UserCommand.newID(), title: String, aliases: [String] = [],
        symbol: String = "square.stack.3d.up",
        steps: [SequenceStep], trust: SequenceTrust = .trusted
    ) {
        schemaVersion = Self.currentVersion
        self.id = id
        self.title = title
        self.aliases = aliases
        self.symbol = symbol
        self.steps = steps.numbered()
        self.trust = trust
    }

    public var backend: SequenceBackend { SequenceBackend(steps: steps) }

    /// Untrusted when the sequence says so or any of its steps does.
    public var effectiveTrust: SequenceTrust {
        trust == .untrusted || steps.contains { $0.trust == .untrusted } ? .untrusted : .trusted
    }

    /// The same sequence as it arrives from outside: every step untrusted, so nothing runs until it is approved.
    public func imported() -> CommandSequence {
        var copy = self
        copy.trust = .untrusted
        copy.steps = steps.map {
            var step = $0
            step.trust = .untrusted
            return step
        }
        return copy
    }

    /// The same sequence after the person read it and approved it.
    public func approved() -> CommandSequence {
        var copy = self
        copy.trust = .trusted
        copy.steps = steps.map {
            var step = $0
            step.trust = .trusted
            return step
        }
        return copy
    }
}

/// The limits that keep a hostile or broken file from bloating memory or running for ever.
public enum SequenceLimits {
    public static let maxSteps = 20
    public static let maxUISteps = 100
    public static let maxInputsPerStep = 4
    public static let maxNameLength = 32
    public static let maxLabelLength = 80
    public static let maxPromptLength = 200
    public static let maxShortcutName = 200
    public static let maxTemplateLength = 4_000
    public static let defaultStepTimeout: TimeInterval = 10
    public static let maxStepTimeout: TimeInterval = 60
    public static let minStepTimeout: TimeInterval = 0.5
    /// The command timeout limit of the action validator.
    public static let maxTotalTimeout: TimeInterval = 120
    public static let maxAnswerLength = 20_000
    public static let maxFilesInValue = PayloadLimits.maxFiles
}
