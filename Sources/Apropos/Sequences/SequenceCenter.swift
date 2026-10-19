import AppKit
import Foundation
import Observation

/// What a row of the sequence draft stands for.
public enum SequenceTarget: Sendable, Hashable {
    /// The top row of the palette: "Sequence draft (3 steps)". Opens the draft level.
    case draft
    case run
    case save
    case discard
    case step(String)

    /// The identity usage and the run log would use. Draft rows are never learned, so this only keeps ids stable.
    public var commandID: CommandID {
        switch self {
        case .draft: CommandID(rawValue: "seq:draft")
        case .run: CommandID(rawValue: "seq:run")
        case .save: CommandID(rawValue: "seq:save")
        case .discard: CommandID(rawValue: "seq:discard")
        case .step(let id): CommandID(rawValue: "seq:step>\(id)")
        }
    }
}

/// Which level of the palette the draft has open.
public enum SequenceLevel: Equatable, Sendable {
    /// The steps and what can be done with them.
    case steps
    /// The form that turns the draft into a command.
    case save

    /// The breadcrumb chip: "Sequence draft" or "Save as command".
    public var title: String {
        switch self {
        case .steps: "Sequence draft"
        case .save: "Save as command"
        }
    }
}

/// A question asked before the run, in the panel's search field.
public struct SequenceAsking: Equatable, Sendable {
    public let prompt: String
    /// "Question 1 of 2".
    public let number: Int
    public let total: Int
}

/// The one confirmation a run waits for.
public struct SequencePending: Equatable, Sendable {
    public let heading: String
    public let lines: [String]
}

/// Where a run is, for the panel.
public enum SequenceRunPhase: Equatable, Sendable {
    case asking(SequenceAsking)
    case confirming(SequencePending)
    case running
    case finished(SequenceReport)
}

/// What a step row shows while and after a run.
public enum SequenceStepState: Equatable, Sendable {
    case waiting
    case running
    case done
    case failed(String)
    case skipped
}

/// What the form needs to save the draft as a command.
public struct SequenceSaveForm: Equatable, Sendable {
    public var name = ""
    public var alias = ""
    /// The chosen SF Symbol. The picker highlights it; a name typed in the symbol search that is a real symbol becomes it.
    public var symbol = SymbolPicker.defaultSymbol
    /// What is typed in the symbol search.
    public var symbolQuery = ""
    /// Symbols worth a look first, taken from the first step. Shown at the head of the picker.
    public var suggestedSymbols: [String] = []
    public var hotkey: HotKeyCombo?

    public init() {}
}

/// What the palette does after a draft row was used.
public enum SequenceDraftResult: Equatable, Sendable {
    case enteredLevel
    /// A question waits in the search field.
    case needsInput
    /// The combined confirmation waits for its Return.
    case needsConfirmation
    /// The run ended well. The panel may close.
    case finished
    /// Nothing to do (a step row was used).
    case nothing
    case discarded
    case saved
    /// The reason is in `SequenceCenter.failure`.
    case failed
}

/// What the save form says about the command that will be made, in plain words and derived from the steps.
public struct SequenceSaveSummary: Equatable, Sendable {
    /// "4 steps: New Folder, Copy path, UPPERCASE and 1 more".
    public let steps: String
    /// "Offered when files are selected": when the command appears in the panel.
    public let offered: String
}

/// What happened when a row was added to the draft.
public enum SequenceAddResult: Equatable, Sendable {
    case added(steps: Int)
    case refused(String)
}

/// The sequence builder of the palette. It holds the draft in memory, lists it as rows (a top row, then a level in the
/// same panel like the send-to destination list), runs it through the sequencer and saves it as a user command.
///
/// Rules it keeps, with tests:
/// - The draft lives in memory only and is gone at relaunch. Saving writes through `UserCommandStore`.
/// - Steps are chained by default: a step that reads text reads the result of the step before it when that step gives
///   text, else the selection. Each step can be switched to the selection, or to a question asked at run time.
/// - A run takes the context when it starts, asks its questions, shows the combined confirmation once, then runs.
///   Nothing leaves the Mac without that confirmation.
@MainActor
@Observable
public final class SequenceCenter {
    /// Bumped whenever the rows or the level change, so the palette's cached list is rebuilt.
    public private(set) var revision = 0
    public private(set) var steps: [SequenceStep] = []
    public private(set) var level: SequenceLevel?
    public private(set) var phase: SequenceRunPhase?
    public private(set) var stepStates: [String: SequenceStepState] = [:]
    /// Why something did not happen: a refused step, a refused run, a save that failed. Names steps, never values.
    /// Whether the save form shows the full symbol grid. Collapsed, it shows one line of suggestions.
    public private(set) var symbolExpanded = false
    public private(set) var failure: String?
    /// "Saved Shout and note under Your commands", until the next thing the person does.
    public private(set) var notice: String?
    public var form = SequenceSaveForm() {
        didSet { if form.symbolQuery != oldValue.symbolQuery { followSymbolQuery() } }
    }

    @ObservationIgnored private let store: UserCommandStore?
    @ObservationIgnored private let catalogue: @MainActor () -> SequenceCatalogue
    @ObservationIgnored private let runner: any SequenceStepRunner
    @ObservationIgnored private let privacy: @MainActor () -> ContextPrivacy
    @ObservationIgnored private let isSymbol: @MainActor (String) -> Bool
    @ObservationIgnored private var values = ContextValues()
    @ObservationIgnored private var target: TargetApp?
    @ObservationIgnored private var capturedAt = Date.distantPast
    @ObservationIgnored private var nextNumber = 1
    @ObservationIgnored private var useSelection: Set<String> = []
    @ObservationIgnored private var questions: [SequenceQuestion] = []
    @ObservationIgnored private var answers: [String: String] = [:]
    @ObservationIgnored private var runTask: Task<SequenceReport, Never>?
    @ObservationIgnored private var cachedRoot: [Command] = []
    @ObservationIgnored private var cachedLevel: [Command] = []

    public init(
        store: UserCommandStore?, runner: any SequenceStepRunner,
        catalogue: @escaping @MainActor () -> SequenceCatalogue,
        privacy: @escaping @MainActor () -> ContextPrivacy = { ContextPrivacy() },
        isSymbol: @escaping @MainActor (String) -> Bool = {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }
    ) {
        self.store = store
        self.runner = runner
        self.catalogue = catalogue
        self.privacy = privacy
        self.isSymbol = isSymbol
    }

    // MARK: Context

    /// Takes a fresh snapshot. An older one than already used is ignored.
    public func update(with snapshot: ContextSnapshot) {
        guard snapshot.capturedAt >= capturedAt else { return }
        capturedAt = snapshot.capturedAt
        values = snapshot.values
    }

    /// Forgets the context: sensing was turned off.
    public func clear() {
        capturedAt = .distantPast
        values = ContextValues()
    }

    /// The panel opened for `app`: forget the last snapshot and any open level or run, so a stale selection is never
    /// used. The draft stays.
    /// - Parameter keepingLevel: the panel is being reopened soon after it closed, so the draft level the person was in
    ///   stays open. The selection is still forgotten and a fresh one is read, and a waiting confirmation is dropped.
    public func beginSession(for app: TargetApp?, keepingLevel: Bool = false) {
        capturedAt = .distantPast
        values = ContextValues()
        target = app
        if !(keepingLevel && level == .steps) {
            level = nil
            symbolExpanded = false
        }
        phase = nil
        stepStates = [:]
        failure = nil
        notice = nil
        questions = []
        answers = [:]
        rebuild()
    }

    // MARK: Reading

    public var isEmpty: Bool { steps.isEmpty }
    public var hasDraft: Bool { !steps.isEmpty }

    /// The top row, when a draft exists: "Sequence draft (3 steps)".
    public var rootCommands: [Command] { cachedRoot }

    /// The rows of the open level: Run, Save and Discard, then the steps.
    public var levelCommands: [Command] { cachedLevel }

    public var isInLevel: Bool { level != nil }

    /// "Sequence draft (3 steps)".
    public var title: String { "Sequence draft (\(steps.count) step\(steps.count == 1 ? "" : "s"))" }

    /// The plan of the draft as it is now.
    public func plan() -> SequencePlan {
        SequencePlanner.plan(SequenceBackend(steps: steps), trust: .trusted, catalogue: catalogue(), privacy: privacy())
    }

    // MARK: Editing

    /// Adds what a palette row stands for. Menu items become menu steps (one step each), context
    /// actions and your commands become action steps, destinations become sends. Rows that need a choice first (the
    /// generic "Send selection to...") cannot be added.
    @discardableResult
    public func add(_ command: Command) -> SequenceAddResult {
        failure = nil
        notice = nil
        guard steps.count < SequenceLimits.maxSteps else {
            return refuse("A sequence can have at most \(SequenceLimits.maxSteps) steps.")
        }
        let result: Result<SequenceStep, SequenceAddRefusal>
        switch command.source {
        case .menuItem:
            result = menuStep(for: command)
        case .contextAction(let id):
            result = actionStep(for: command, id: id)
        case .sendTo(let target):
            result = sendStep(for: command, target: target)
        case .sequence:
            result = .failure(.init("That row is part of the draft."))
        case .app:
            result = .failure(.init("That row opens Apropos and cannot be a step."))
        }
        switch result {
        case .failure(let refusal):
            return refuse(refusal.message)
        case .success(let step):
            // One row, one step, even when the same command is added again or the step before is a menu step too: the
            // list shows, numbers, moves and deletes steps one by one, and each has an id of its own.
            steps.append(step)
            rechain()
            rebuild()
            return .added(steps: steps.count)
        }
    }

    /// Adds steps that arrive from outside the palette (the recorder) as one menu step. They are checked against the
    /// step engine's rules and the privacy list. `trusted: false` marks the step untrusted: the draft then cannot run,
    /// and saving it stores a command that waits for approval.
    @discardableResult
    public func add(uiSteps: [UIStep], label: String = "Recorded steps", trusted: Bool = true) -> SequenceAddResult {
        failure = nil
        notice = nil
        guard steps.count < SequenceLimits.maxSteps else {
            return refuse("A sequence can have at most \(SequenceLimits.maxSteps) steps.")
        }
        let backend = UIStepsBackend(steps: uiSteps)
        if let issue = UIStepsValidator.issues(in: backend, privacy: privacy()).first {
            return refuse(issue.description)
        }
        steps.append(
            SequenceStep(
                id: newID(), label: label, kind: .uiSteps(backend), trust: trusted ? .trusted : .untrusted))
        rechain()
        rebuild()
        return .added(steps: steps.count)
    }

    public func delete(stepID: String) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps.remove(at: index)
        useSelection.remove(stepID)
        afterEdit()
    }

    /// Moves a step one place up (-1) or down (+1). Out of range does nothing.
    public func move(stepID: String, by delta: Int) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }), delta != 0 else { return }
        let target = index + (delta < 0 ? -1 : 1)
        guard steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
        afterEdit()
    }

    /// Makes the step ask for its text when the sequence runs, or goes back to the chain.
    public func setAsking(_ asking: Bool, stepID: String) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        let hadQuestion = isAsking(stepID: stepID)
        steps[index].inputs.removeAll { if case .ask = $0.source { true } else { false } }
        if asking {
            steps[index].inputs.removeAll { $0.kind == .text }
            let name = plannedTitle(of: steps[index])
            steps[index].inputs.append(SequenceInput(.text, from: .ask(prompt: "Text for \(name)")))
        } else if hadQuestion {
            useSelection.remove(stepID)
            steps[index].inputs.append(SequenceInput(.text))
        }
        afterEdit()
    }

    /// Goes on with the next step when this one fails, or stops there (the default).
    public func setContinuesOnFailure(_ continues: Bool, stepID: String) {
        guard let index = steps.firstIndex(where: { $0.id == stepID }) else { return }
        steps[index].continueOnFailure = continues
        afterEdit()
    }

    public func continuesOnFailure(stepID: String) -> Bool {
        steps.first { $0.id == stepID }?.continueOnFailure ?? false
    }

    /// Reads the selection instead of the previous step's result, or goes back to the chain.
    public func setUsesSelection(_ usesSelection: Bool, stepID: String) {
        guard steps.contains(where: { $0.id == stepID }) else { return }
        if usesSelection { useSelection.insert(stepID) } else { useSelection.remove(stepID) }
        afterEdit()
    }

    public func usesSelection(stepID: String) -> Bool { useSelection.contains(stepID) }

    public func isAsking(stepID: String) -> Bool {
        steps.first { $0.id == stepID }?.inputs.contains { if case .ask = $0.source { true } else { false } } ?? false
    }

    /// Whether the step has a text input the chain, the selection or a question can fill.
    public func hasTextInput(stepID: String) -> Bool {
        steps.first { $0.id == stepID }?.inputs.contains { $0.kind == .text } ?? false
    }

    /// Whether the step before this one gives text for the chain.
    public func canChain(stepID: String) -> Bool {
        guard let index = steps.firstIndex(where: { $0.id == stepID }), index > 0 else { return false }
        return producesText(steps[index - 1])
    }

    /// Empties the draft.
    public func discard() {
        runTask?.cancel()
        steps = []
        useSelection = []
        level = nil
        phase = nil
        stepStates = [:]
        failure = nil
        notice = nil
        rebuild()
    }

    private func afterEdit() {
        rechain()
        if steps.isEmpty { level = nil }
        phase = nil
        stepStates = [:]
        failure = nil
        rebuild()
    }

    private func refuse(_ message: String) -> SequenceAddResult {
        failure = message
        revision += 1
        return .refused(message)
    }

    private struct SequenceAddRefusal: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    private func newID() -> String {
        defer { nextNumber += 1 }
        return "s\(nextNumber)"
    }

    private func menuStep(for command: Command) -> Result<SequenceStep, SequenceAddRefusal> {
        var builder = StepSequenceBuilder()
        do {
            try builder.addMenuCommand(command, appName: target?.name, privacy: privacy())
        } catch let error as StepAuthoringError {
            return .failure(.init(error.description))
        } catch {
            return .failure(.init("That menu item cannot be added."))
        }
        // Choosing a menu item of another app brings that app forward first, or its window would open behind the others.
        var backend = builder.backend
        for index in backend.steps.indices { backend.steps[index].activates = true }
        return .success(SequenceStep(id: newID(), label: command.displayTitle, kind: .uiSteps(backend)))
    }

    private func actionStep(for command: Command, id: ActionID) -> Result<SequenceStep, SequenceAddRefusal> {
        let catalogue = catalogue()
        let isUser = id.rawValue.hasPrefix("user:")
        let action: ContextAction
        if isUser {
            guard let found = catalogue.userCommands[id] else {
                return .failure(.init("That command is not available."))
            }
            if found.backend.isSequence { return .failure(.init("A sequence cannot run another sequence.")) }
            if !found.isRunnable { return .failure(.init("That command is waiting for your approval.")) }
            action = found.action
        } else {
            guard let found = catalogue.contextActions[id] else {
                return .failure(.init("That action is not available."))
            }
            action = found
        }
        let inputs = ContextRequirement.allCases.filter(action.requires.contains).compactMap {
            requirement -> SequenceInput? in
            SequenceValueKind.allCases.first { $0.requirement == requirement }.map { SequenceInput($0) }
        }
        return .success(
            SequenceStep(
                id: newID(), label: command.displayTitle, kind: isUser ? .userCommand(id) : .contextAction(id),
                inputs: inputs))
    }

    private func sendStep(for command: Command, target: SendTarget) -> Result<SequenceStep, SequenceAddRefusal> {
        guard case .destination(let id, let kind) = target else {
            return .failure(.init("Choose a destination first, then add it."))
        }
        let input: SequenceValueKind
        switch kind {
        case .text: input = .text
        case .page: input = .page
        case .files: input = .files
        case .folder: input = .folder
        }
        guard catalogue().destinations[id] != nil else {
            return .failure(.init("That destination cannot be used in a sequence."))
        }
        if let destination = catalogue().destinations[id], case .chooseFolder = destination.handler {
            return .failure(.init("Choose a folder first: a sequence cannot ask for one each time."))
        }
        return .success(
            SequenceStep(
                id: newID(), label: command.displayTitle, kind: .destination(id), inputs: [SequenceInput(input)]))
    }

    // MARK: Chaining

    /// Whether a step gives text another step can read.
    private func producesText(_ step: SequenceStep) -> Bool {
        let catalogue = catalogue()
        switch step.kind {
        case .shortcut: return true
        case .contextAction(let id):
            guard let action = catalogue.contextActions[id] else { return false }
            return Self.returnsText(action)
        case .userCommand(let id):
            guard let command = catalogue.userCommands[id] else { return false }
            return Self.returnsText(command.action)
        case .uiSteps, .destination, .openURL: return false
        }
    }

    private static func returnsText(_ action: ContextAction) -> Bool {
        guard action.output != .none else { return false }
        switch action.backend {
        case .function, .shell, .appleScript, .shortcut: return true
        case .urlScheme, .keyPress, .uiSteps, .sequence: return false
        }
    }

    /// Recomputes which text input reads the previous step's result. Questions stay as they are.
    private func rechain() {
        for index in steps.indices {
            if steps[index].output?.name.hasPrefix("from-") == true { steps[index].output = nil }
            for input in steps[index].inputs.indices {
                if case .output = steps[index].inputs[input].source { steps[index].inputs[input].source = .context }
            }
        }
        guard steps.count > 1 else { return }
        for index in 1..<steps.count where !useSelection.contains(steps[index].id) {
            let before = steps[index - 1]
            guard producesText(before),
                let input = steps[index].inputs.firstIndex(where: { $0.kind == .text && $0.source == .context })
            else { continue }
            let name = "from-\(before.id)"
            steps[index - 1].output = SequenceOutput(name: name, kind: .text)
            steps[index].inputs[input].source = .output(name)
        }
    }

    // MARK: Rows

    private func rebuild() {
        revision += 1
        guard !steps.isEmpty else {
            cachedRoot = []
            cachedLevel = []
            return
        }
        var root = Command(
            id: SequenceTarget.draft.commandID.rawValue, title: title, path: ["Sequence"], source: .sequence(.draft))
        root.symbolName = "square.stack.3d.up"
        root.keywords = ["sequence", "chain", "draft", "steps", "macro"]
        root.detail = "Review, run or save the steps you added"
        cachedRoot = [root]

        let plan = self.plan()
        var rows: [Command] = []
        func action(_ target: SequenceTarget, _ title: String, _ symbol: String, _ detail: String?) {
            var row = Command(
                id: target.commandID.rawValue, title: title, path: ["Sequence"], source: .sequence(target))
            row.symbolName = symbol
            row.detail = detail
            rows.append(row)
        }
        action(.run, "Run sequence", "play.fill", plan.requiresConfirmation ? "Asks once before it starts" : nil)
        action(.save, "Save as command...", "square.and.arrow.down", "Name it, give it an alias and a symbol")
        action(.discard, "Discard draft", "trash", nil)
        for planned in plan.steps {
            var row = Command(
                id: SequenceTarget.step(planned.step.id).commandID.rawValue,
                title: "\(planned.index + 1). \(planned.title)", path: ["Steps"],
                source: .sequence(.step(planned.step.id)))
            row.symbolName = Self.symbol(for: planned)
            row.detail = detail(for: planned, in: plan)
            rows.append(row)
        }
        cachedLevel = rows
    }

    private func detail(for planned: PlannedStep, in plan: SequencePlan) -> String {
        if let state = stepStates[planned.step.id] {
            switch state {
            case .running: return "Running"
            case .done: return "Done"
            case .skipped: return "Skipped"
            case .failed(let message): return "Stopped: \(message)"
            case .waiting: break
            }
        }
        if let problem = planned.problems.first { return "Cannot run: \(problem.message)" }
        var parts: [String] = []
        for input in planned.step.inputs {
            switch input.source {
            case .context: parts.append("uses the \(Self.contextWord(input.kind))")
            case .output(let name):
                let number = steps.firstIndex { $0.output?.name == name }.map { $0 + 1 }
                parts.append(number.map { "uses the result of step \($0)" } ?? "uses an earlier result")
            case .ask: parts.append("asks you for the text")
            }
        }
        if parts.isEmpty, let effect = planned.effects.first { return effect.line }
        if planned.step.continueOnFailure { parts.append("goes on if it fails") }
        let flow = parts.joined(separator: ", ")
        return flow.prefix(1).uppercased() + flow.dropFirst()
    }

    private static func contextWord(_ kind: SequenceValueKind) -> String {
        switch kind {
        case .text: "selected text"
        case .url: "page address"
        case .page: "page"
        case .files: "selected files"
        case .folder: "folder"
        case .document: "document"
        case .repo: "repository"
        }
    }

    private static func symbol(for planned: PlannedStep) -> String {
        switch planned.target {
        case .action(let action)?: action.symbol
        case .destination(let destination)?: destination.symbol
        case nil: "questionmark.circle"
        }
    }

    private func plannedTitle(of step: SequenceStep) -> String {
        plan().steps.first { $0.step.id == step.id }?.title ?? step.label
    }

    // MARK: Using a row

    /// Uses a row of the draft. Run may need input, then a confirmation, then runs; the rest are immediate.
    public func perform(_ command: Command) async -> SequenceDraftResult {
        guard case .sequence(let target) = command.source else { return .nothing }
        failure = nil
        notice = nil
        switch target {
        case .draft:
            level = .steps
            rebuild()
            return .enteredLevel
        case .run:
            return await beginRun()
        case .save:
            form = SequenceSaveForm()
            form.name = suggestedName()
            form.suggestedSymbols = suggestedSymbols()
            form.symbol = form.suggestedSymbols.first ?? SymbolPicker.defaultSymbol
            symbolExpanded = false
            level = .save
            rebuild()
            return .enteredLevel
        case .discard:
            discard()
            return .discarded
        case .step:
            return .nothing
        }
    }

    // MARK: The symbol picker

    /// Symbols to offer first: the one that fits the first step, then the one that says "sequence".
    public func suggestedSymbols() -> [String] {
        var result: [String] = []
        if let first = plan().steps.first { result.append(symbol(forStep: first)) }
        result.append(SymbolPicker.defaultSymbol)
        return result.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// The symbol that stands for a step: its action's or destination's own, and for menu steps what the symbol
    /// resolver makes of the menu path, the way a row of that menu item would look.
    private func symbol(forStep planned: PlannedStep) -> String {
        guard case .uiSteps(let backend) = planned.step.kind, let step = backend.steps.first else {
            return Self.symbol(for: planned)
        }
        let path = step.locators.compactMap { locator -> [String]? in
            if case .menuPath(let path) = locator { path } else { nil }
        }.first
        let title = path?.last ?? planned.step.label
        let command = Command(
            id: "seq:suggest", title: title, path: Array((path ?? []).dropLast()), source: .sequence(.draft))
        return SymbolResolver().symbol(for: command)
    }

    /// The symbols of the collapsed row: the suggestions, then common ones.
    public var quickSymbols: [String] { SymbolPicker.quickPicks(suggested: form.suggestedSymbols) }

    /// What the collapsed row draws and the arrow keys walk. The chosen symbol is in it exactly once: where the
    /// suggestions have it, or as the first tile when it came from the grid.
    public var symbolRow: [String] {
        let quick = quickSymbols
        guard !quick.contains(form.symbol) else { return quick }
        return [form.symbol] + quick.dropLast()
    }

    /// What will be saved: the steps and when the command is offered.
    public var saveSummary: SequenceSaveSummary {
        let titles = plan().steps.map(\.title)
        let shown = titles.prefix(3).joined(separator: ", ")
        let rest = titles.count - 3
        let list = rest > 0 ? "\(shown) and \(rest) more" : shown
        let count = "\(titles.count) step\(titles.count == 1 ? "" : "s")"
        return SequenceSaveSummary(steps: titles.isEmpty ? count : "\(count): \(list)", offered: offeredLine())
    }

    /// "Offered when files are selected and a folder is open", from what the steps read from the context.
    private func offeredLine() -> String {
        var needs = Set<ContextRequirement>()
        for step in steps {
            for input in step.inputs {
                if case .context = input.source { needs.insert(input.kind.requirement) }
            }
        }
        let words = ContextRequirement.allCases.filter(needs.contains).map { requirement -> String in
            switch requirement {
            case .selectedText: "text is selected"
            case .selectedFiles: "files are selected"
            case .pageURL: "a web page is open"
            case .folder: "a folder is open"
            case .gitRepo: "a git repository is open"
            case .document: "a document is open"
            }
        }
        guard !words.isEmpty else { return "Offered in every app, with or without a selection" }
        return "Offered when " + words.joined(separator: " and ")
    }

    /// Opens the full searchable grid in place of the one line.
    public func expandSymbols() {
        guard !symbolExpanded else { return }
        symbolExpanded = true
    }

    /// Back to the one line. The search is cleared and the choice kept.
    public func collapseSymbols() {
        guard symbolExpanded else { return }
        symbolExpanded = false
        form.symbolQuery = ""
    }

    /// What an arrow key did in the symbol field.
    public enum SymbolKeyResult: Sendable {
        case handled
        /// Up from the top: the keyboard goes back to the fields above, and the grid is collapsed.
        case leave
    }

    /// An arrow key in the symbol field. Collapsed: left and right walk the suggestions, down opens the grid, up leaves.
    /// Expanded: the arrows walk the grid, and up from its first row collapses it and leaves.
    @discardableResult
    public func symbolKey(_ move: SymbolMove) -> SymbolKeyResult {
        if symbolExpanded {
            if moveSymbol(move) { return .handled }
            guard move == .up else { return .handled }
            collapseSymbols()
            return .leave
        }
        switch move {
        case .left, .right:
            let shown = symbolRow
            let row = [SymbolSection(title: "Quick", symbols: shown.map { PickerSymbol(name: $0, keywords: []) })]
            if let next = SymbolPicker.neighbour(
                of: form.symbol, move: move, in: row, columns: max(shown.count, 1))
            {
                form.symbol = next
            }
            return .handled
        case .down:
            expandSymbols()
            return .handled
        case .up:
            return .leave
        }
    }

    /// What the grid shows now: the suggestions and groups, or the matches for what is typed.
    public var symbolSections: [SymbolSection] {
        SymbolPicker.sections(
            query: form.symbolQuery, suggested: form.suggestedSymbols, custom: customSymbol(for: form.symbolQuery))
    }

    /// A name typed in the search that is a real SF Symbol the curated list does not have: usable as it is.
    private func customSymbol(for query: String) -> String? {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !name.isEmpty && !name.contains(" ") && isSymbol(name) ? name : nil
    }

    /// Moves the chosen symbol one step with an arrow key. False when there is none that way (the caller may then leave
    /// the grid, for instance up from the first row).
    @discardableResult
    public func moveSymbol(_ move: SymbolMove) -> Bool {
        guard
            let next = SymbolPicker.neighbour(of: form.symbol, move: move, in: symbolSections),
            next != form.symbol
        else { return false }
        form.symbol = next
        return true
    }

    /// Typing in the search keeps the choice on something that is shown: the best match when the chosen symbol dropped
    /// out of the results.
    private func followSymbolQuery() {
        let shown = symbolSections.flatMap(\.symbols).map(\.name)
        guard !shown.isEmpty, !shown.contains(form.symbol) else { return }
        // Assigned inside didSet of `form`, so it does not run this again.
        form.symbol = shown[0]
    }

    private func suggestedName() -> String {
        let names = plan().steps.map(\.title)
        let joined = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "..." : "")
        return String(joined.prefix(UserCommandLimits.maxTitle))
    }

    // MARK: Running

    private func beginRun() async -> SequenceDraftResult {
        stepStates = [:]
        answers = [:]
        let plan = plan()
        if let refusal = plan.refusal {
            failure = refusal.message
            phase = nil
            rebuild()
            return .failed
        }
        questions = plan.questions
        if let first = questions.first {
            phase = .asking(SequenceAsking(prompt: first.prompt, number: 1, total: questions.count))
            rebuild()
            return .needsInput
        }
        return await continueRun(plan)
    }

    /// The person's answer to the question in the search field.
    public func submitAnswer(_ text: String) async -> SequenceDraftResult {
        guard case .asking(let asking)? = phase, questions.indices.contains(asking.number - 1) else { return .nothing }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            failure = "Type an answer, or press Escape to stop."
            revision += 1
            return .needsInput
        }
        failure = nil
        answers[questions[asking.number - 1].id] = text
        if asking.number < questions.count {
            let next = questions[asking.number]
            phase = .asking(SequenceAsking(prompt: next.prompt, number: asking.number + 1, total: questions.count))
            revision += 1
            return .needsInput
        }
        return await continueRun(plan())
    }

    private func continueRun(_ plan: SequencePlan) async -> SequenceDraftResult {
        if plan.requiresConfirmation {
            let confirmation = plan.confirmation
            phase = .confirming(SequencePending(heading: confirmation.heading, lines: confirmation.lines()))
            rebuild()
            return .needsConfirmation
        }
        return await execute(plan, confirmed: false)
    }

    /// The Return that confirms the combined confirmation.
    public func confirmPending() async -> SequenceDraftResult {
        guard case .confirming? = phase else { return .nothing }
        return await execute(plan(), confirmed: true)
    }

    private func execute(_ plan: SequencePlan, confirmed: Bool) async -> SequenceDraftResult {
        phase = .running
        stepStates = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.step.id, SequenceStepState.waiting) })
        rebuild()
        let sequencer = Sequencer(runner: runner)
        let invocation = SequenceInvocation(
            values: values, target: target, answers: answers, confirmed: confirmed || !plan.requiresConfirmation,
            timeout: plan.backend.suggestedTimeout)
        let task = Task { [weak self] in
            await sequencer.run(
                plan, invocation: invocation,
                onProgress: { event in
                    Task { @MainActor in self?.apply(event, plan: plan) }
                })
        }
        runTask = task
        let report = await task.value
        runTask = nil
        for result in report.results {
            stepStates[result.stepID] = Self.state(for: result.status)
        }
        phase = .finished(report)
        rebuild()
        guard let message = report.message else { return .finished }
        failure = message
        revision += 1
        return .failed
    }

    private func apply(_ event: SequenceProgress, plan: SequencePlan) {
        guard case .running? = phase else { return }
        switch event {
        case .started(let index, _):
            if plan.steps.indices.contains(index) { stepStates[plan.steps[index].step.id] = .running }
        case .finished(let result):
            stepStates[result.stepID] = Self.state(for: result.status)
        case .ended:
            break
        }
        rebuild()
    }

    private static func state(for status: SequenceStepStatus) -> SequenceStepState {
        switch status {
        case .ok: .done
        case .failed(let reason): .failed(reason.message)
        case .skipped: .skipped
        }
    }

    /// Stops a run in progress.
    public func cancelRun() { runTask?.cancel() }

    public var isRunning: Bool { if case .running? = phase { true } else { false } }

    // MARK: Saving

    /// Turns the draft into a command under Your commands. Returns false with `failure` set when it cannot.
    @discardableResult
    public func save() -> Bool {
        guard let store else {
            failure = "Saving is not available here."
            revision += 1
            return false
        }
        let name = form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let alias = form.alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbol = form.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let sequence = CommandSequence(
            title: name, aliases: alias.isEmpty ? [] : [alias],
            symbol: symbol.isEmpty ? SymbolPicker.defaultSymbol : symbol, steps: steps)
        let command = sequence.userCommand(hotkey: form.hotkey, needsConfirmation: plan().requiresConfirmation)
        do {
            try store.create(command)
        } catch let error as UserCommandError {
            failure = error.description
            revision += 1
            return false
        } catch {
            failure = "The command could not be saved."
            revision += 1
            return false
        }
        let saved = "Saved \(name) under Your commands"
        steps = []
        useSelection = []
        level = nil
        phase = nil
        stepStates = [:]
        failure = nil
        form = SequenceSaveForm()
        symbolExpanded = false
        rebuild()
        notice = saved
        return true
    }

    // MARK: Leaving

    /// Escape: stops a run, drops a question or a confirmation, leaves the save form, then the draft level. Returns false
    /// when there was nothing to leave, so the caller can close the panel.
    @discardableResult
    public func goBack() -> Bool {
        failure = nil
        // An open symbol grid closes first; the form stays.
        if level == .save, symbolExpanded {
            collapseSymbols()
            return true
        }
        if isRunning {
            cancelRun()
            return true
        }
        if phase != nil {
            phase = nil
            stepStates = [:]
            rebuild()
            return true
        }
        switch level {
        case .save?:
            level = .steps
            rebuild()
            return true
        case .steps?:
            level = nil
            rebuild()
            return true
        case nil:
            return false
        }
    }

    /// Clears the reason something did not happen and the "saved" note, once the panel has shown them long enough.
    public func clearMessages() {
        if failure != nil { failure = nil }
        if notice != nil { notice = nil }
    }

    /// Drops a waiting confirmation without leaving the level (typing is a change of mind).
    public func dropConfirmation() {
        guard case .confirming? = phase else { return }
        phase = nil
        revision += 1
    }
}
