import Foundation

/// Why a sequence was refused. Messages name the step by position and never repeat its content.
public enum SequenceIssue: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case noSteps
    case tooManySteps(limit: Int)
    case tooManyMenuSteps(limit: Int)
    case duplicateStepID(step: Int)
    case badStepID(step: Int)
    case labelTooLong(step: Int)
    case badReference(step: Int)
    case badTimeout(step: Int)
    case tooManyInputs(step: Int)
    case duplicateInput(step: Int, kind: SequenceValueKind)
    case badInput(step: Int)
    case askNeedsText(step: Int)
    case badPrompt(step: Int)
    case badOutputName(step: Int)
    case duplicateOutputName(step: Int)
    case outputNotSupported(step: Int)
    case outputKindNotSupported(step: Int)
    case unknownOutput(step: Int)
    case outputKindMismatch(step: Int)
    /// A step reads the output of itself or of a later step: the only way a sequence could loop.
    case cycle(step: Int)
    case needsPayload(step: Int)
    case inputMissingForTemplate(step: Int)
    case invalidTemplate(step: Int, ActionValidationError)
    case invalidShortcutName(step: Int)
    case invalidMenuSteps(step: Int, UIStepsValidationError)
    case menuStepTakesNoValues(step: Int)

    /// The step the problem is in, counted from 1, or nil when it is about the whole sequence.
    public var step: Int? {
        switch self {
        case .unsupportedVersion, .noSteps, .tooManySteps, .tooManyMenuSteps: nil
        case .duplicateStepID(let step), .badStepID(let step), .labelTooLong(let step), .badReference(let step),
            .badTimeout(let step), .tooManyInputs(let step), .duplicateInput(let step, _), .badInput(let step),
            .askNeedsText(let step), .badPrompt(let step), .badOutputName(let step), .duplicateOutputName(let step),
            .outputNotSupported(let step), .outputKindNotSupported(let step), .unknownOutput(let step),
            .outputKindMismatch(let step), .cycle(let step), .needsPayload(let step),
            .inputMissingForTemplate(let step), .invalidTemplate(let step, _), .invalidShortcutName(let step),
            .invalidMenuSteps(let step, _), .menuStepTakesNoValues(let step):
            step
        }
    }

    public var description: String {
        let prefix = step.map { "Step \($0): " } ?? ""
        switch self {
        case .unsupportedVersion(let version):
            return "This sequence uses format \(version), which this version cannot read."
        case .noSteps: return "There are no steps."
        case .tooManySteps(let limit): return "A sequence can have at most \(limit) steps."
        case .tooManyMenuSteps(let limit): return "A sequence can choose at most \(limit) menu items in all."
        case .duplicateStepID: return prefix + "another step has the same id."
        case .badStepID: return prefix + "the id must be lowercase letters, digits, dashes and underscores."
        case .labelTooLong: return prefix + "the label is too long."
        case .badReference: return prefix + "it names an action, command or destination that cannot be one."
        case .badTimeout: return prefix + "the time limit must be between 0.5 and 60 seconds."
        case .tooManyInputs: return prefix + "it has too many inputs."
        case .duplicateInput(_, let kind): return prefix + "it takes \(kind.noun) twice."
        case .badInput: return prefix + "an input cannot come from there."
        case .askNeedsText: return prefix + "only text can be asked of you."
        case .badPrompt: return prefix + "the question is empty or too long."
        case .badOutputName: return prefix + "an output name must be lowercase letters, digits, dashes and underscores."
        case .duplicateOutputName: return prefix + "another step already gives an output with that name."
        case .outputNotSupported: return prefix + "this kind of step gives no output."
        case .outputKindNotSupported: return prefix + "that kind of value cannot be an output."
        case .unknownOutput: return prefix + "it reads an output no step gives."
        case .outputKindMismatch: return prefix + "it reads an output as another kind of value than the step gives."
        case .cycle: return prefix + "it reads an output of itself or of a later step."
        case .needsPayload: return prefix + "a send needs exactly one thing to send: text, a page, files or a folder."
        case .inputMissingForTemplate:
            return prefix + "its link or Shortcut uses a value that none of its inputs provides."
        case .invalidTemplate(_, let error): return prefix + error.description
        case .invalidShortcutName: return prefix + "the Shortcut name is empty, too long or unsafe."
        case .invalidMenuSteps(_, let error): return error.description
        case .menuStepTakesNoValues: return prefix + "menu steps take no values."
        }
    }
}

/// The structural rules a sequence must meet before it is stored or run. What needs the catalogue (does this action
/// exist, is that app installed) is the planner's job; everything here depends on the sequence alone.
public enum SequenceValidator {
    private static let nameCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Every problem, in step order. Empty means the sequence may be stored.
    public static func issues(in backend: SequenceBackend, privacy: ContextPrivacy = ContextPrivacy())
        -> [SequenceIssue]
    {
        var found: [SequenceIssue] = []
        guard backend.version <= SequenceBackend.currentVersion else { return [.unsupportedVersion(backend.version)] }
        guard !backend.steps.isEmpty else { return [.noSteps] }
        if backend.steps.count > SequenceLimits.maxSteps { found.append(.tooManySteps(limit: SequenceLimits.maxSteps)) }
        let menuSteps = backend.steps.reduce(0) {
            if case .uiSteps(let ui) = $1.kind { $0 + ui.steps.count } else { $0 }
        }
        if menuSteps > SequenceLimits.maxUISteps { found.append(.tooManyMenuSteps(limit: SequenceLimits.maxUISteps)) }

        var givers: [String: Int] = [:]
        for (offset, step) in backend.steps.enumerated() {
            if let name = step.output?.name, givers[name] == nil { givers[name] = offset + 1 }
        }
        var ids = Set<String>()
        var produced: [String: (index: Int, kind: SequenceValueKind)] = [:]
        for (offset, step) in backend.steps.enumerated() {
            let number = offset + 1
            if !ids.insert(step.id).inserted { found.append(.duplicateStepID(step: number)) }
            if step.id.isEmpty || step.id.count > SequenceLimits.maxNameLength
                || !step.id.allSatisfy(nameCharacters.contains)
            {
                found.append(.badStepID(step: number))
            }
            if step.label.count > SequenceLimits.maxLabelLength { found.append(.labelTooLong(step: number)) }
            if let timeout = step.timeout,
                !(SequenceLimits.minStepTimeout...SequenceLimits.maxStepTimeout).contains(timeout)
            {
                found.append(.badTimeout(step: number))
            }
            found += kindIssues(step, number: number, privacy: privacy)
            found += inputIssues(step, number: number, produced: produced, givers: givers)
            if let output = step.output {
                if !step.kind.canProduceOutput {
                    found.append(.outputNotSupported(step: number))
                } else if !output.kind.canBeProduced {
                    found.append(.outputKindNotSupported(step: number))
                }
                if output.name.isEmpty || output.name.count > SequenceLimits.maxNameLength
                    || !output.name.allSatisfy(nameCharacters.contains)
                {
                    found.append(.badOutputName(step: number))
                } else if produced[output.name] != nil {
                    found.append(.duplicateOutputName(step: number))
                } else {
                    produced[output.name] = (number, output.kind)
                }
            }
        }
        return found
    }

    private static func kindIssues(_ step: SequenceStep, number: Int, privacy: ContextPrivacy) -> [SequenceIssue] {
        switch step.kind {
        case .uiSteps(let backend):
            var found: [SequenceIssue] = []
            if !step.inputs.isEmpty || step.output != nil { found.append(.menuStepTakesNoValues(step: number)) }
            found += UIStepsValidator.issues(in: backend, privacy: privacy).map {
                .invalidMenuSteps(step: number, $0)
            }
            return found
        case .contextAction(let id):
            return id.isWellFormed && !id.rawValue.hasPrefix("user:") && !id.rawValue.hasPrefix("dest:")
                ? [] : [.badReference(step: number)]
        case .destination(let id):
            return id.isWellFormed && (id.rawValue.hasPrefix("dest:") || id.rawValue.hasPrefix("user:"))
                ? needsOnePayload(step, number: number) : [.badReference(step: number)]
        case .userCommand(let id):
            return id.isWellFormed && id.rawValue.hasPrefix("user:") ? [] : [.badReference(step: number)]
        case .openURL(let template):
            guard template.source.count <= SequenceLimits.maxTemplateLength else {
                return [.invalidTemplate(step: number, .tooLarge)]
            }
            return templateIssues(step, number: number)
        case .shortcut(let name):
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= SequenceLimits.maxShortcutName, !trimmed.hasPrefix("-"),
                !trimmed.contains("{")
            else { return [.invalidShortcutName(step: number)] }
            return []
        }
    }

    private static func needsOnePayload(_ step: SequenceStep, number: Int) -> [SequenceIssue] {
        let payloads = step.inputs.filter { [.text, .page, .files, .folder].contains($0.kind) }
        return payloads.count == 1 ? [] : [.needsPayload(step: number)]
    }

    private static func templateIssues(_ step: SequenceStep, number: Int) -> [SequenceIssue] {
        guard let action = SequenceAction.synthesized(for: step) else { return [] }
        var found: [SequenceIssue] = []
        let provided = Set(step.inputs.map(\.kind))
        let variables: [ActionVariable]
        switch action.backend {
        case .urlScheme(let template): variables = template.variables
        case .shortcut(let shortcut): variables = [shortcut.input].compactMap { $0 }
        default: variables = []
        }
        for variable in variables where !SequenceAction.kinds(providing: variable).contains(where: provided.contains) {
            found.append(.inputMissingForTemplate(step: number))
            break
        }
        do {
            try ActionValidator.validate(action, functions: ActionFunctionRegistry(), requireContext: false)
        } catch let error as ActionValidationError {
            found.append(.invalidTemplate(step: number, error))
        } catch {
            found.append(.badReference(step: number))
        }
        return found
    }

    private static func inputIssues(
        _ step: SequenceStep, number: Int, produced: [String: (index: Int, kind: SequenceValueKind)],
        givers: [String: Int]
    ) -> [SequenceIssue] {
        var found: [SequenceIssue] = []
        if step.inputs.count > SequenceLimits.maxInputsPerStep { found.append(.tooManyInputs(step: number)) }
        var seen = Set<SequenceValueKind>()
        for input in step.inputs {
            if !seen.insert(input.kind).inserted { found.append(.duplicateInput(step: number, kind: input.kind)) }
            switch input.source {
            case .context:
                break
            case .ask(let prompt):
                if input.kind != .text { found.append(.askNeedsText(step: number)) }
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.count > SequenceLimits.maxPromptLength {
                    found.append(.badPrompt(step: number))
                }
            case .output(let name):
                if !input.kind.canBeProduced {
                    found.append(.badInput(step: number))
                } else if let source = produced[name] {
                    if source.kind != input.kind { found.append(.outputKindMismatch(step: number)) }
                } else {
                    // Not given by an earlier step. A later or the same step makes a loop; otherwise it is unknown.
                    found.append(givers[name] != nil ? .cycle(step: number) : .unknownOutput(step: number))
                }
            }
        }
        return found
    }
}
