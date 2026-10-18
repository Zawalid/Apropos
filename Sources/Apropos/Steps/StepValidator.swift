import Foundation

/// Why a steps description was refused. Messages name the step by position and never repeat its content.
public enum UIStepsValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case unsupportedVersion(Int)
    case noSteps
    case tooManySteps(limit: Int)
    case duplicateStepID(step: Int)
    case missingAppID(step: Int)
    case badAppID(step: Int)
    case appNotAllowed(step: Int)
    case unsupportedAction(step: Int)
    case noLocators(step: Int)
    case tooManyLocators(step: Int)
    case needsCoordinate(step: Int)
    case unknownLocator(step: Int)
    case emptyLocator(step: Int)
    case appleMenu(step: Int)
    case recentItems(step: Int)
    case secureField(step: Int)
    case fieldTooLong(step: Int)
    case badTimeout(step: Int)
    case badExpectation(step: Int)
    case missingDescription(step: Int)

    /// The step the problem is in, counted from 1, or nil when it is about the whole sequence.
    public var step: Int? {
        switch self {
        case .unsupportedVersion, .noSteps, .tooManySteps: nil
        case .duplicateStepID(let step), .missingAppID(let step), .badAppID(let step), .appNotAllowed(let step),
            .unsupportedAction(let step), .noLocators(let step), .tooManyLocators(let step),
            .needsCoordinate(let step), .unknownLocator(let step), .emptyLocator(let step), .appleMenu(let step),
            .recentItems(let step), .secureField(let step), .fieldTooLong(let step), .badTimeout(let step),
            .badExpectation(let step), .missingDescription(let step):
            step
        }
    }

    public var description: String {
        let prefix = step.map { "Step \($0): " } ?? ""
        switch self {
        case .unsupportedVersion(let version):
            return "These steps use format \(version), which this version cannot read."
        case .noSteps: return "There are no steps."
        case .tooManySteps(let limit): return "A command can have at most \(limit) steps."
        case .duplicateStepID: return prefix + "another step has the same id."
        case .missingAppID: return prefix + "it does not say which app it acts in."
        case .badAppID: return prefix + "the app id is not a bundle identifier such as com.apple.finder."
        case .appNotAllowed: return prefix + "that app is on the privacy list, so no step can act in it."
        case .unsupportedAction: return prefix + "only menu steps are supported in this version."
        case .noLocators: return prefix + "it has no way to find its target."
        case .tooManyLocators: return prefix + "it has too many locators."
        case .needsCoordinate: return prefix + "a position on the screen cannot be used to find anything."
        case .unknownLocator: return prefix + "a locator is of a kind this version does not know."
        case .emptyLocator: return prefix + "a locator is empty."
        case .appleMenu: return prefix + "the Apple menu is never used: it lists your recent items and your name."
        case .recentItems: return prefix + "recent items menus are never used: their items are your documents."
        case .secureField: return prefix + "password fields are never read or filled."
        case .fieldTooLong: return prefix + "a field is too long."
        case .badTimeout: return prefix + "a wait is outside the allowed range."
        case .badExpectation: return prefix + "the expected outcome cannot be checked this way."
        case .missingDescription: return prefix + "it has no description."
        }
    }
}

/// The rules a steps description must meet before it is stored or run. The same checks run when a command is saved,
/// when a pack is loaded and again right before a run, because the privacy list can change in between.
public enum UIStepsValidator {
    public static let maxSteps = 50
    public static let maxLocatorsPerStep = 6
    public static let maxTextLength = 200
    public static let maxPathDepth = 8
    public static let maxDescriptionLength = 200
    public static let maxWait: TimeInterval = StepWait.range.upperBound

    /// Every problem, in step order. Empty means the steps may be stored and run.
    public static func issues(in backend: UIStepsBackend, privacy: ContextPrivacy = ContextPrivacy())
        -> [UIStepsValidationError]
    {
        var found: [UIStepsValidationError] = []
        if backend.version != UIStepsBackend.currentVersion { found.append(.unsupportedVersion(backend.version)) }
        if backend.steps.isEmpty { found.append(.noSteps) }
        if backend.steps.count > maxSteps { found.append(.tooManySteps(limit: maxSteps)) }
        var seen = Set<String>()
        for (offset, step) in backend.steps.prefix(maxSteps).enumerated() {
            let number = offset + 1
            if !seen.insert(step.id).inserted { found.append(.duplicateStepID(step: number)) }
            found += issues(in: step, number: number, privacy: privacy)
        }
        return found
    }

    /// Throws the first problem.
    public static func validate(_ backend: UIStepsBackend, privacy: ContextPrivacy = ContextPrivacy()) throws {
        if let first = issues(in: backend, privacy: privacy).first { throw first }
    }

    // MARK: One step

    private static func issues(in step: UIStep, number: Int, privacy: ContextPrivacy) -> [UIStepsValidationError] {
        var found: [UIStepsValidationError] = []
        if step.app.trimmingCharacters(in: .whitespaces).isEmpty {
            found.append(.missingAppID(step: number))
        } else if !isBundleID(step.app) {
            found.append(.badAppID(step: number))
        } else if privacy.isDisabled(step.app) || privacy.blocksSelection(step.app) {
            found.append(.appNotAllowed(step: number))
        }
        if !StepAction.supported.contains(step.action) { found.append(.unsupportedAction(step: number)) }
        if step.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append(.missingDescription(step: number))
        }
        if step.description.count > maxDescriptionLength { found.append(.fieldTooLong(step: number)) }
        if step.locators.isEmpty { found.append(.noLocators(step: number)) }
        if step.locators.count > maxLocatorsPerStep { found.append(.tooManyLocators(step: number)) }
        for locator in step.locators.prefix(maxLocatorsPerStep) {
            found += issues(in: locator, number: number)
        }
        if let wait = step.wait, !StepWait.range.contains(wait.timeout) { found.append(.badTimeout(step: number)) }
        if let expect = step.expect { found += issues(in: expect, number: number) }
        return found
    }

    private static func issues(in expect: StepExpectation, number: Int) -> [UIStepsValidationError] {
        var found: [UIStepsValidationError] = []
        if let timeout = expect.timeout, !StepWait.range.contains(timeout) { found.append(.badTimeout(step: number)) }
        switch expect.locator {
        case .identifier, .roleTitle:
            found += issues(in: expect.locator, number: number)
        default:
            // Only things found among the windows can be waited for; menu items are always there.
            found.append(.badExpectation(step: number))
        }
        return found
    }

    private static func issues(in locator: StepLocator, number: Int) -> [UIStepsValidationError] {
        switch locator {
        case .unsupported(let by):
            return [by == "coordinate" ? .needsCoordinate(step: number) : .unknownLocator(step: number)]
        case .identifier(let value):
            return textIssues([value], number: number)
        case .roleTitle(let role, let title):
            var found = textIssues([role, title], number: number)
            if StepText.mentionsSecureField(role) { found.append(.secureField(step: number)) }
            return found
        case .menuPath(let titles):
            var found = textIssues(titles, number: number)
            if titles.isEmpty || titles.count > maxPathDepth { found.append(.emptyLocator(step: number)) }
            if let first = titles.first, StepText.isAppleMenuTitle(first) { found.append(.appleMenu(step: number)) }
            if titles.contains(where: StepText.isRecentMenuTitle) { found.append(.recentItems(step: number)) }
            return found
        case .shortcut(let key, let modifiers):
            var found = textIssues([key], number: number)
            // A bare key is not a menu key equivalent; it would match whatever the app maps to it.
            if modifiers.isEmpty && key.count == 1 { found.append(.emptyLocator(step: number)) }
            return found
        case .position(let path):
            var found: [UIStepsValidationError] = []
            if path.count < 2 || path.count > maxPathDepth || path.contains(where: { $0 < 0 }) {
                found.append(.emptyLocator(step: number))
            }
            if path.first == 0 { found.append(.appleMenu(step: number)) }
            return found
        }
    }

    private static func textIssues(_ texts: [String], number: Int) -> [UIStepsValidationError] {
        var found: [UIStepsValidationError] = []
        if texts.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            found.append(.emptyLocator(step: number))
        }
        if texts.contains(where: { $0.count > maxTextLength }) { found.append(.fieldTooLong(step: number)) }
        return found
    }

    /// Reverse-DNS: at least one dot, letters, digits, dots, dashes and underscores.
    static func isBundleID(_ text: String) -> Bool {
        guard text.count <= maxTextLength, text.contains("."), !text.hasPrefix("."), !text.hasSuffix(".") else {
            return false
        }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }
}
