import Foundation

/// What the planner looks things up in: the actions, the person's commands and the destinations in effect right now, and
/// whether an app is installed. A value, so a run works on one consistent picture even while packs reload.
public struct SequenceCatalogue: Sendable {
    public var contextActions: [ActionID: ContextAction]
    public var userCommands: [ActionID: UserCommand]
    public var destinations: [ActionID: Destination]
    public var isInstalled: @Sendable (String) -> Bool

    public init(
        contextActions: [ContextAction] = [], userCommands: [UserCommand] = [], destinations: [Destination] = [],
        isInstalled: @escaping @Sendable (String) -> Bool = { _ in true }
    ) {
        self.contextActions = Dictionary(contextActions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.userCommands = Dictionary(userCommands.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.destinations = Dictionary(destinations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.isInstalled = isInstalled
    }
}

/// Why a step cannot run as it is. Fixed vocabulary plus catalogue titles (never a value), so it can be shown anywhere.
public enum PlanProblem: Equatable, Sendable {
    case unknownAction
    case unknownCommand
    case unknownDestination
    /// An imported command that waits for approval.
    case commandPending(title: String)
    /// A command that is itself a sequence: sequences do not nest.
    case nestedSequence
    case appNotInstalled(bundleID: String)
    case destinationAppNotInstalled(title: String)
    case destinationPending(title: String)
    case destinationCannotTake(title: String)
    /// A destination that asks for a folder each time cannot run unattended.
    case needsFolderChoice(title: String)
    /// The step reads something its inputs do not provide.
    case needsContext(ContextRequirement)

    public var message: String {
        switch self {
        case .unknownAction: "that action is not available"
        case .unknownCommand: "that command no longer exists"
        case .unknownDestination: "that destination is not available"
        case .commandPending(let title): "\(title) is waiting for your approval"
        case .nestedSequence: "a sequence cannot run another sequence"
        case .appNotInstalled(let id): "\(id) is not installed"
        case .destinationAppNotInstalled(let title): "\(title) is not installed"
        case .destinationPending(let title): "\(title) is waiting for your approval"
        case .destinationCannotTake(let title): "\(title) cannot take this"
        case .needsFolderChoice(let title): "\(title) asks for a folder each time, which a sequence cannot do"
        case .needsContext(let requirement): "it needs \(Self.noun(requirement)) and none of its inputs provides it"
        }
    }

    private static func noun(_ requirement: ContextRequirement) -> String {
        switch requirement {
        case .selectedText: "text"
        case .selectedFiles: "files"
        case .pageURL: "a page"
        case .folder: "a folder"
        case .gitRepo: "a repository"
        case .document: "a document"
        }
    }
}

/// What a step runs through.
public enum PlannedTarget: Sendable {
    case action(ContextAction)
    case destination(Destination)
}

/// A step with what it resolved to and what is wrong with it.
public struct PlannedStep: Sendable {
    /// Position from 0.
    public let index: Int
    public let step: SequenceStep
    /// A name for rows and messages, from the catalogue: "UPPERCASE", "Send to Notes". Never a value.
    public let title: String
    public let target: PlannedTarget?
    public let problems: [PlanProblem]
    public let effects: [SequenceEffect]

    /// "Step 2 (Send to Notes)".
    public var name: String { "Step \(index + 1) (\(title))" }
}

/// Something the person is asked in the panel before the run.
public struct SequenceQuestion: Equatable, Sendable, Identifiable {
    /// `stepID.kind`, the key of its answer.
    public let id: String
    public let stepIndex: Int
    public let prompt: String
}

/// Why a plan will not run, as a whole.
public enum PlanRefusal: Equatable, Sendable {
    case invalid(SequenceIssue)
    case untrusted
    case blocked(step: Int, PlanProblem)

    public var message: String {
        switch self {
        case .invalid(let issue): issue.description
        case .untrusted: "This sequence is waiting for your approval."
        case .blocked(let step, let problem): "Step \(step + 1): \(problem.message)."
        }
    }
}

/// A sequence checked against the catalogue: every step resolved, every problem listed, every effect named, the trust
/// worked out. Nothing here runs anything.
public struct SequencePlan: Sendable {
    public let backend: SequenceBackend
    public let steps: [PlannedStep]
    public let trust: SequenceTrust
    public let issues: [SequenceIssue]

    public var effects: [SequenceEffect] { steps.flatMap(\.effects) }

    /// Anything that leaves a trace outside Apropos is confirmed once, for the whole sequence, before the first step.
    public var requiresConfirmation: Bool { !effects.isEmpty }

    /// The combined confirmation, one line per external effect, in order.
    public var confirmation: SequenceConfirmation { SequenceConfirmation(effects: effects) }

    public var questions: [SequenceQuestion] {
        steps.flatMap { planned in
            planned.step.questions.map {
                SequenceQuestion(
                    id: "\(planned.step.id).\($0.kind.rawValue)", stepIndex: planned.index, prompt: $0.prompt)
            }
        }
    }

    /// Why the whole run is refused, or nil when it may start. A step that continues on failure may have problems; the
    /// run reports it failed when it gets there.
    public var refusal: PlanRefusal? {
        if let issue = issues.first { return .invalid(issue) }
        if trust == .untrusted { return .untrusted }
        for planned in steps where !planned.step.continueOnFailure {
            if let problem = planned.problems.first { return .blocked(step: planned.index, problem) }
        }
        return nil
    }

    public var isRunnable: Bool { refusal == nil }
}

/// Resolves a sequence against the catalogue.
public enum SequencePlanner {
    /// - Parameters:
    ///   - trust: What is known about where the sequence came from (a command's review state, a draft's origin).
    ///     Steps that are untrusted themselves, and commands waiting for approval, make it untrusted whatever this says.
    public static func plan(
        _ backend: SequenceBackend, trust: SequenceTrust = .trusted, catalogue: SequenceCatalogue,
        privacy: ContextPrivacy = ContextPrivacy()
    ) -> SequencePlan {
        let issues = SequenceValidator.issues(in: backend, privacy: privacy)
        var overall = trust
        if backend.steps.contains(where: { $0.trust == .untrusted }) { overall = .untrusted }
        var planned: [PlannedStep] = []
        for (index, step) in backend.steps.enumerated() {
            let step = resolve(step, index: index, catalogue: catalogue)
            if step.problems.contains(where: { if case .commandPending = $0 { true } else { false } }) {
                overall = .untrusted
            }
            planned.append(step)
        }
        return SequencePlan(backend: backend, steps: planned, trust: overall, issues: issues)
    }

    private static func resolve(_ step: SequenceStep, index: Int, catalogue: SequenceCatalogue) -> PlannedStep {
        var problems: [PlanProblem] = []
        var target: PlannedTarget?
        var title = step.label.isEmpty ? step.summary : step.label
        let provided = Set(step.inputs.map { $0.kind.requirement })

        func checkInputs(of action: ContextAction) {
            for requirement in ContextRequirement.allCases
            where action.requires.contains(requirement) && !provided.contains(requirement) {
                problems.append(.needsContext(requirement))
            }
        }

        switch step.kind {
        case .contextAction(let id):
            if let action = catalogue.contextActions[id] {
                title = action.title
                target = .action(action)
                checkInputs(of: action)
            } else {
                problems.append(.unknownAction)
            }
        case .userCommand(let id):
            if let command = catalogue.userCommands[id] {
                title = command.title
                if !command.isRunnable { problems.append(.commandPending(title: command.title)) }
                if command.backend.isSequence { problems.append(.nestedSequence) }
                target = .action(command.action)
                checkInputs(of: command.action)
            } else {
                problems.append(.unknownCommand)
            }
        case .destination(let id):
            if let destination = catalogue.destinations[id] {
                title = destination.title
                target = .destination(destination)
                if !destination.isRunnable { problems.append(.destinationPending(title: destination.title)) }
                if let app = destination.appBundleID, !catalogue.isInstalled(app) {
                    problems.append(.destinationAppNotInstalled(title: destination.title))
                }
                if case .chooseFolder = destination.handler {
                    problems.append(.needsFolderChoice(title: destination.title))
                }
                if let kind = step.inputs.first(where: { $0.kind.payloadKind != nil })?.kind.payloadKind,
                    !destination.accepts.contains(kind)
                {
                    problems.append(.destinationCannotTake(title: destination.title))
                }
            } else {
                problems.append(.unknownDestination)
            }
        case .openURL, .shortcut, .uiSteps:
            if let action = SequenceAction.synthesized(for: step) {
                target = .action(action)
                if case .uiSteps(let backend) = step.kind {
                    for app in backend.apps where !catalogue.isInstalled(app) {
                        problems.append(.appNotInstalled(bundleID: app))
                    }
                }
            }
        }
        let effects = SequenceEffects.effects(for: step, index: index, target: target)
        return PlannedStep(
            index: index, step: step, title: title, target: target, problems: problems, effects: effects)
    }
}

extension SequenceValueKind {
    /// The kind of thing a send carries for this input, or nil for inputs a send cannot take.
    var payloadKind: PayloadKind? {
        switch self {
        case .text: .text
        case .url, .page: .page
        case .files: .files
        case .folder: .folder
        case .document, .repo: nil
        }
    }
}

extension ActionBackend {
    /// Whether this is a sequence, which cannot be a step of another sequence.
    var isSequence: Bool { false }
}
