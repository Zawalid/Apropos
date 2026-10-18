import ApplicationServices
import Foundation

extension UIStep {
    /// What the step does, worked out from its locators and not from `description`. A file written by someone else
    /// can say anything in its description, so review screens show this instead.
    public var derivedSummary: String {
        let target: String
        if let path = locators.compactMap({ locator -> [String]? in
            if case .menuPath(let titles) = locator { titles } else { nil }
        }).first {
            target = path.joined(separator: " > ")
        } else if let title = locators.compactMap({ locator -> String? in
            if case .roleTitle(_, let title) = locator { title } else { nil }
        }).first {
            target = "\u{201C}\(title)\u{201D}"
        } else if let identifier = locators.compactMap({ locator -> String? in
            if case .identifier(let value) = locator { value } else { nil }
        }).first {
            target = "the item \(identifier)"
        } else {
            target = "an item by position"
        }
        switch action {
        case .menu: return "Choose \(target) in \(app)"
        case .press: return "Press \(target) in \(app)"
        case .setValue: return "Set \(target) in \(app)"
        case .select: return "Select \(target) in \(app)"
        }
    }
}

extension ActionBackend {
    /// The steps, when this is a `uiSteps` backend.
    public var steps: UIStepsBackend? {
        if case .uiSteps(let steps) = self { steps } else { nil }
    }
}

extension ContextAction {
    /// How likely this command is to stop working, for a badge. Nil for commands that are not step sequences.
    public var stepFragility: StepFragility? { backend.steps?.fragility }
}

extension UserCommand {
    /// How likely this command is to stop working, for a badge. Nil for commands that are not step sequences.
    public var stepFragility: StepFragility? { backend.steps?.fragility }
}

/// Why a command could not be added to a sequence or saved.
public enum StepAuthoringError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Only menu commands of an app can become steps.
    case notAMenuCommand
    /// The step breaks a rule (the Apple menu, a recent items menu, the privacy list...).
    case refused(UIStepsValidationError)
    case noSteps
    case noSuchStep

    public var description: String {
        switch self {
        case .notAMenuCommand: "Only menu items can be added to a sequence."
        case .refused(let error): error.description
        case .noSteps: "Add at least one step."
        case .noSuchStep: "There is no such step."
        }
    }
}

/// Builds a sequence of steps by hand, without a recorder: add menu commands the menu reader already knows, reorder or
/// remove them, check the result and save it as a user command.
///
/// ```swift
/// var sequence = StepSequenceBuilder()
/// try sequence.addMenuCommand(exportCommand, appName: "Preview")   // identifier, shortcut and path are captured
/// try sequence.addMenuCommand(closeCommand, appName: "Preview")
/// let saved = try sequence.save(title: "Export and close", in: store)
/// print(saved.stepFragility)                                        // the badge
/// ```
public struct StepSequenceBuilder: Sendable {
    public private(set) var steps: [UIStep]

    public init(steps: [UIStep] = []) { self.steps = steps }

    // MARK: Adding

    /// Adds a step that chooses this menu command.
    ///
    /// The locators are the ones that survive best: the identifier the app set (read from the live menu item when
    /// `identifier` is nil and the command still has its Accessibility target), the role and title, the menu path, and
    /// the key equivalent. A position among siblings is added only when `includePosition` is true, because it can
    /// press a different item after an update.
    ///
    /// - Throws: `.notAMenuCommand`, or `.refused` for an item that is in the Apple menu or in a menu of recent items
    ///   (their items are the person's documents), or for an app on the privacy list.
    @discardableResult
    public mutating func addMenuCommand(
        _ command: Command, appName: String? = nil, identifier: String? = nil, includePosition: Bool = false,
        privacy: ContextPrivacy = ContextPrivacy()
    ) throws -> UIStep {
        guard case .menuItem(let bundleID?) = command.source else { throw StepAuthoringError.notAMenuCommand }
        var locators: [StepLocator] = []
        let found = identifier ?? Self.liveIdentifier(of: command)
        if let found, !found.isEmpty { locators.append(.identifier(found)) }
        locators.append(.roleTitle(role: StepAX.menuItem, title: command.title))
        locators.append(.menuPath(command.path + [command.title]))
        if let shortcut = command.shortcut {
            locators.append(.shortcut(key: shortcut.key, modifiers: shortcut.modifiers))
        }
        if includePosition, let position = Self.indexPath(of: command) { locators.append(.position(position)) }

        let words = (command.path + [command.title]).joined(separator: " > ")
        let step = UIStep(
            id: nextID(), action: .menu, app: bundleID, locators: locators,
            description: "Choose \(words)" + (appName.map { " in \($0)" } ?? ""))
        if let issue = UIStepsValidator.issues(in: UIStepsBackend(steps: [step]), privacy: privacy).first {
            throw StepAuthoringError.refused(issue)
        }
        steps.append(step)
        return step
    }

    /// Adds a step written by hand or built elsewhere. It is checked when the sequence is saved.
    public mutating func append(_ step: UIStep) {
        var step = step
        if step.id.isEmpty || steps.contains(where: { $0.id == step.id }) { step.id = nextID() }
        steps.append(step)
    }

    // MARK: Editing

    public mutating func remove(at index: Int) throws {
        guard steps.indices.contains(index) else { throw StepAuthoringError.noSuchStep }
        steps.remove(at: index)
    }

    public mutating func move(from source: Int, to destination: Int) throws {
        guard steps.indices.contains(source), steps.indices.contains(destination) else {
            throw StepAuthoringError.noSuchStep
        }
        steps.insert(steps.remove(at: source), at: destination)
    }

    /// Changes how long step `index` waits for its item.
    public mutating func setWait(_ seconds: TimeInterval?, at index: Int) throws {
        guard steps.indices.contains(index) else { throw StepAuthoringError.noSuchStep }
        steps[index].wait = seconds.map { StepWait(timeout: $0) }
    }

    // MARK: Checking and saving

    public var backend: UIStepsBackend { UIStepsBackend(steps: steps) }

    /// How likely the sequence is to stop working.
    public var fragility: StepFragility { backend.fragility }

    public func issues(privacy: ContextPrivacy = ContextPrivacy()) -> [UIStepsValidationError] {
        UIStepsValidator.issues(in: backend, privacy: privacy)
    }

    /// The sequence as a command, not yet stored. It is bound to the apps its steps act in.
    public func makeCommand(
        title: String, symbol: String = "rectangle.stack", aliases: [String] = [], needsConfirmation: Bool = false,
        privacy: ContextPrivacy = ContextPrivacy()
    ) throws -> UserCommand {
        guard !steps.isEmpty else { throw StepAuthoringError.noSteps }
        if let issue = issues(privacy: privacy).first { throw StepAuthoringError.refused(issue) }
        return UserCommand(
            title: title, symbol: symbol, aliases: aliases, apps: AppFilter(include: Set(backend.apps)), requires: [],
            backend: .uiSteps(backend), output: .none, needsConfirmation: needsConfirmation,
            timeout: Self.suggestedTimeout(forSteps: steps.count))
    }

    /// Validates, then stores the sequence as a user command through the existing store. The store checks it again.
    @MainActor
    @discardableResult
    public func save(
        title: String, symbol: String = "rectangle.stack", aliases: [String] = [], needsConfirmation: Bool = false,
        in store: UserCommandStore, privacy: ContextPrivacy = ContextPrivacy()
    ) throws -> UserCommand {
        let command = try makeCommand(
            title: title, symbol: symbol, aliases: aliases, needsConfirmation: needsConfirmation, privacy: privacy)
        return try store.create(command)
    }

    /// The steps as the JSON that goes into a command file's `backend`, for hand editing. See docs/ui-steps.md.
    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(backend), as: UTF8.self)
    }

    /// Enough time for each step to wait its default, plus the cold start allowance, within the allowed 0.5 to 120.
    public static func suggestedTimeout(forSteps count: Int) -> TimeInterval {
        min(max(10 + Double(count) * 6, 10), 120)
    }

    // MARK: Helpers

    private func nextID() -> String {
        let used = Set(steps.map(\.id))
        var number = steps.count + 1
        while used.contains("s\(number)") { number += 1 }
        return "s\(number)"
    }

    /// `Command.id` of a menu command is its index path ("2.4.1"): the menu bar item, then the item in each menu.
    static func indexPath(of command: Command) -> [Int]? {
        let parts = command.id.split(separator: ".").compactMap { Int($0) }
        return parts.count == command.id.split(separator: ".").count && parts.count >= 2 ? parts : nil
    }

    /// The identifier of the live menu item behind the command, one Accessibility read. Nil for a command without one.
    private static func liveIdentifier(of command: Command) -> String? {
        guard let target = command.target as? AXPressTarget else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(target.element, StepAX.identifier as CFString, &value)
        return status == .success ? value as? String : nil
    }
}

/// Reads a steps description from a file the way a person edits it: a bare backend (`{"version": 1, "steps": [...]}`),
/// a user command file (`{"command": {"backend": {...}}}`) or a pack (`{"actions": [{"backend": {...}}]}`, the first
/// action that has steps).
public enum UIStepsFile {
    public enum LoadError: Error, Equatable, Sendable {
        case notJSON
        case noSteps
    }

    public static func load(_ data: Data) throws -> UIStepsBackend {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(UIStepsBackend.self, from: data) { return direct }
        struct Wrapper: Decodable {
            struct Definition: Decodable {
                struct Backend: Decodable {
                    var type: String?
                    var version: Int?
                    var steps: [UIStep]?
                }
                var backend: Backend?
            }
            var command: Definition?
            var actions: [Definition]?
        }
        guard let wrapper = try? decoder.decode(Wrapper.self, from: data) else { throw LoadError.notJSON }
        let candidates = [wrapper.command].compactMap { $0 } + (wrapper.actions ?? [])
        for definition in candidates {
            if let backend = definition.backend, let steps = backend.steps {
                return UIStepsBackend(version: backend.version ?? UIStepsBackend.currentVersion, steps: steps)
            }
        }
        throw LoadError.noSteps
    }
}
