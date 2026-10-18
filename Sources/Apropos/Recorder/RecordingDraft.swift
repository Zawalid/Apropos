import Foundation

/// Why something the person did was not turned into a step. Each reason has one fixed sentence for the review list: it
/// names no app, title, item or key.
public enum SkipReason: String, CaseIterable, Sendable {
    /// A click on something that could only be found by where it is on the screen.
    case coordinateOnlyClick
    /// A click on a button or other control. Controls are recorded in a later version.
    case controlNotRecordedYet
    case contextMenu
    case menuExtra
    case appleMenu
    case recentItems
    /// An item of the Window menu with no identifier or shortcut: it is named after an open document.
    case windowMenuDocument
    case passwordField
    case appOnPrivacyList
    /// A command-key shortcut that is not a menu item of the app (handled inside the app, or by macOS).
    case shortcutNotInMenu
    case ambiguousShortcut
    /// The step would break a rule of the step format.
    case notAllowed

    public var explanation: String {
        switch self {
        case .coordinateOnlyClick:
            "A click on something that can only be found by its position on the screen was not recorded."
        case .controlNotRecordedYet:
            "A click on a button or control was not recorded: only menu items and shortcuts are recorded in this version."
        case .contextMenu: "A choice in a context menu was not recorded: only the menu bar is recorded."
        case .menuExtra: "A click on a menu bar icon was not recorded."
        case .appleMenu: "The Apple menu was not recorded: it lists your recent items and your name."
        case .recentItems: "A recent items menu was not recorded: its items are your documents."
        case .windowMenuDocument: "A Window menu item was not recorded: it is named after an open document."
        case .passwordField:
            "Recording paused while a password field was active. Nothing was recorded during that time."
        case .appOnPrivacyList: "Something in an app on your privacy list was not recorded."
        case .shortcutNotInMenu: "A keyboard shortcut that is not a menu item of the app was not recorded."
        case .ambiguousShortcut: "A keyboard shortcut matched more than one menu item, so it was not recorded."
        case .notAllowed: "Something was not recorded because the step format does not allow it."
        }
    }
}

/// A note that something was skipped, shown after the item it follows. Consecutive identical notes are counted.
public struct SkippedNote: Equatable, Identifiable, Sendable {
    public let id: Int
    public let reason: SkipReason
    public var count: Int
    /// The item this came after, or nil when it came before everything.
    public var afterItemID: Int?

    public var text: String {
        count > 1 ? "\(reason.explanation) (\(count) times)" : reason.explanation
    }
}

/// How a menu step was recorded.
public enum StepOrigin: String, Sendable {
    case menuClick
    case shortcut
}

/// One row of the review list.
public struct DraftItem: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case step(UIStep, origin: StepOrigin)
        /// The person moved to another app here. Becomes `activates` on the next step in that app.
        case appSwitch(bundleID: String, name: String)
        /// Text was entered here. What was typed is not recorded; turning this into a value is the next phase.
        case textEntered
    }

    public let id: Int
    public var content: Content

    /// The row in plain words.
    public var summary: String {
        switch content {
        case .step(let step, _): step.description
        case .appSwitch(_, let name): "Switch to \(name)"
        case .textEntered: "Text was entered here. What you typed is not recorded."
        }
    }

    public var step: UIStep? {
        if case .step(let step, _) = content { step } else { nil }
    }

    /// Nil for rows that are not steps.
    public var fragility: StepFragility? { step?.fragility }

    /// The kinds of locator the step has, strongest first.
    public var locatorKinds: [LocatorKind] {
        guard let step else { return [] }
        return Array(Set(step.locators.compactMap(\.kind))).sorted()
    }

    /// A short line about how it was recorded, for example "by shortcut".
    public var originNote: String? {
        guard case .step(_, let origin) = content else { return nil }
        return origin == .shortcut ? "Recorded from a keyboard shortcut" : "Recorded from a menu click"
    }
}

/// Why a draft edit or hand-off was refused.
public enum DraftError: Error, Equatable, Sendable, CustomStringConvertible {
    case noSuchItem
    case cannotMerge
    case notAStep
    case emptyName
    case nameTooLong
    /// Text entry rows that must be deleted (or turned into values, later) before the draft can be saved.
    case unresolvedText(count: Int)
    case invalid([UIStepsValidationError])

    public var description: String {
        switch self {
        case .noSuchItem: "There is no such row."
        case .cannotMerge: "Only identical steps, repeated text entry rows or app switches can be merged."
        case .notAStep: "Only steps can be renamed."
        case .emptyName: "A name cannot be empty."
        case .nameTooLong: "That name is too long."
        case .unresolvedText(let count):
            count == 1
                ? "One row records that text was entered. Delete it before saving."
                : "\(count) rows record that text was entered. Delete them before saving."
        case .invalid(let issues): issues.first.map(\.description) ?? "The steps are not valid."
        }
    }
}

/// Steps that passed the validator and are ready to be saved. The only way to get one is `RecordingDraft.validated`.
public struct ValidatedSteps: Equatable, Sendable {
    public let backend: UIStepsBackend
    public var steps: [UIStep] { backend.steps }
    public var fragility: StepFragility { backend.fragility }

    fileprivate init(backend: UIStepsBackend) { self.backend = backend }
}

/// What a recording produced, as an editable list. Holds only what a step already holds (locators, a description built
/// from them), app names, and content-free notes. It never holds a typed character, a key, a position or a recent item,
/// so dumping or logging a draft shows the same data the saved command would.
public struct RecordingDraft: Equatable, Sendable {
    public private(set) var items: [DraftItem] = []
    public private(set) var skipped: [SkippedNote] = []
    /// The name the command will be saved under. Empty until the person chooses one.
    public var title = ""
    private var nextID = 1

    public init() {}

    public var stepCount: Int { items.filter { $0.step != nil }.count }
    public var textEntryCount: Int { items.filter { $0.content == .textEntered }.count }
    public var isEmpty: Bool { items.isEmpty }

    /// The least reliable step decides.
    public var fragility: StepFragility? { items.compactMap(\.fragility).max() }

    // MARK: Recording

    @discardableResult
    mutating func append(_ content: DraftItem.Content) -> Int {
        let id = nextID
        nextID += 1
        items.append(DraftItem(id: id, content: content))
        return id
    }

    /// Replaces the last row when it is also an app switch: only where the person ended up matters.
    mutating func appendAppSwitch(bundleID: String, name: String) {
        if let last = items.last, case .appSwitch = last.content { items.removeLast() }
        append(.appSwitch(bundleID: bundleID, name: name))
    }

    mutating func note(_ reason: SkipReason) {
        let anchor = items.last?.id
        if let last = skipped.last, last.reason == reason, last.afterItemID == anchor {
            skipped[skipped.count - 1].count += 1
            return
        }
        // Bounded: a long recording cannot grow the notes without limit.
        guard skipped.count < 200 else { return }
        skipped.append(SkippedNote(id: nextID, reason: reason, count: 1, afterItemID: anchor))
        nextID += 1
    }

    // MARK: Editing

    private func index(of id: Int) throws -> Int {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw DraftError.noSuchItem }
        return index
    }

    public mutating func delete(_ id: Int) throws {
        let position = try index(of: id)
        let removed = items.remove(at: position)
        // Notes that followed the removed row now follow the row before it.
        let anchor = position > 0 ? items[position - 1].id : nil
        for offset in skipped.indices where skipped[offset].afterItemID == removed.id {
            skipped[offset].afterItemID = anchor
        }
    }

    /// Moves a row to a new position in the list.
    public mutating func move(_ id: Int, to destination: Int) throws {
        let source = try index(of: id)
        guard items.indices.contains(destination) else { throw DraftError.noSuchItem }
        items.insert(items.remove(at: source), at: destination)
    }

    /// Changes the words a step is shown with. The description is never used to find anything.
    public mutating func rename(_ id: Int, to name: String) throws {
        let position = try index(of: id)
        guard case .step(var step, let origin) = items[position].content else { throw DraftError.notAStep }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DraftError.emptyName }
        guard trimmed.count <= UIStepsValidator.maxDescriptionLength else { throw DraftError.nameTooLong }
        step.description = trimmed
        items[position].content = .step(step, origin: origin)
    }

    /// Merges a row with the one after it. Only rows that mean the same thing can merge: two identical steps become
    /// one, repeated text entry rows become one, and of two app switches the later wins.
    public mutating func merge(_ id: Int) throws {
        let position = try index(of: id)
        guard items.indices.contains(position + 1) else { throw DraftError.noSuchItem }
        let first = items[position]
        let second = items[position + 1]
        switch (first.content, second.content) {
        case (.textEntered, .textEntered):
            break
        case (.appSwitch, .appSwitch):
            items[position].content = second.content
        case (.step(let a, _), .step(let b, _)) where Self.isSameStep(a, b):
            break
        default:
            throw DraftError.cannotMerge
        }
        try delete(second.id)
    }

    private static func isSameStep(_ a: UIStep, _ b: UIStep) -> Bool {
        a.app == b.app && a.action == b.action && a.locators.count == b.locators.count
            && a.locators.allSatisfy { b.locators.contains($0) }
    }

    /// Deletes every row that records text entry.
    public mutating func removeTextEntries() {
        let ids = items.filter { $0.content == .textEntered }.map(\.id)
        for id in ids { try? delete(id) }
    }

    // MARK: Hand-off

    /// The steps in order, with each app switch folded into `activates` of the next step in that app, and fresh ids.
    private func assembledSteps() -> [UIStep] {
        var steps: [UIStep] = []
        var pendingApp: String?
        for item in items {
            switch item.content {
            case .appSwitch(let bundleID, _): pendingApp = bundleID
            case .textEntered: continue
            case .step(var step, _):
                if let app = pendingApp, app == step.app { step.activates = true }
                pendingApp = nil
                steps.append(step)
            }
        }
        return steps.enumerated().map { offset, step in
            var step = step
            step.id = "s\(offset + 1)"
            return step
        }
    }

    /// Every problem that would stop the draft being saved, in the validator's own words.
    public func issues(privacy: ContextPrivacy = ContextPrivacy()) -> [UIStepsValidationError] {
        UIStepsValidator.issues(in: UIStepsBackend(steps: assembledSteps()), privacy: privacy)
    }

    /// Checks the draft and returns the steps to save.
    ///
    /// - Parameter dropTextEntries: Leave out rows that record text entry instead of refusing them. Text entry cannot
    ///   be replayed yet, so a draft with such rows is refused unless the person agreed to drop them.
    public func validated(privacy: ContextPrivacy = ContextPrivacy(), dropTextEntries: Bool = false) throws
        -> ValidatedSteps
    {
        if !dropTextEntries, textEntryCount > 0 { throw DraftError.unresolvedText(count: textEntryCount) }
        let backend = UIStepsBackend(steps: assembledSteps())
        let found = UIStepsValidator.issues(in: backend, privacy: privacy)
        if !found.isEmpty { throw DraftError.invalid(found) }
        return ValidatedSteps(backend: backend)
    }

    /// The validated steps as a sequence builder, for the sequence session to take over.
    public func sequenceBuilder(privacy: ContextPrivacy = ContextPrivacy(), dropTextEntries: Bool = false) throws
        -> StepSequenceBuilder
    {
        StepSequenceBuilder(steps: try validated(privacy: privacy, dropTextEntries: dropTextEntries).steps)
    }

    /// Saves the draft as a user command through the existing step authoring, which validates it again.
    @MainActor
    @discardableResult
    public func save(
        as title: String? = nil, in store: UserCommandStore, privacy: ContextPrivacy = ContextPrivacy(),
        dropTextEntries: Bool = false
    ) throws -> UserCommand {
        let builder = try sequenceBuilder(privacy: privacy, dropTextEntries: dropTextEntries)
        let name = (title ?? self.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw DraftError.emptyName }
        return try builder.save(title: name, in: store, privacy: privacy)
    }
}
