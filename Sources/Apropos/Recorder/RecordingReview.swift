import Foundation
import Observation

/// What a dry look at one recorded step found, in words for a badge.
public enum StepCheck: Equatable, Sendable {
    /// Found by its strongest way of finding it.
    case found
    /// Found, but only by a weaker way: it will break when the app changes.
    case weak
    /// Not found in the app as it is now.
    case missing(String)
    /// Cannot be checked now, for example the app is not running.
    case unchecked(String)

    public var needsAttention: Bool {
        switch self {
        case .weak, .missing: true
        case .found, .unchecked: false
        }
    }
}

/// How a review ended.
public enum RecordingReviewResult: Equatable, Sendable {
    case saved(name: String)
    case addedToDraft
    case discarded
}

/// The review of a finished recording: the steps in plain words, edits, a look at whether each step still finds its
/// target, and a form that saves them as a command. It edits a copy; nothing is stored until `save()`.
@MainActor
@Observable
public final class RecordingReview {
    public private(set) var draft: RecordingDraft
    public var name = ""
    public var alias = ""
    public var hotkey: HotKeyCombo?
    public private(set) var checks: [Int: StepCheck] = [:]
    public private(set) var isChecking = false
    /// The last thing that did not work, in a sentence.
    public private(set) var problem: String?

    @ObservationIgnored private let store: UserCommandStore?
    @ObservationIgnored private let privacy: @MainActor () -> ContextPrivacy
    @ObservationIgnored private let dryRun: @Sendable (UIStepsBackend, ContextPrivacy) -> StepDryRunReport
    @ObservationIgnored private let addToDraftHandler: @MainActor ([UIStep], String) -> SequenceAddResult

    public init(
        draft: RecordingDraft, suggestedName: String = "", store: UserCommandStore?,
        privacy: @escaping @MainActor () -> ContextPrivacy = { ContextPrivacy() },
        dryRun: @escaping @Sendable (UIStepsBackend, ContextPrivacy) -> StepDryRunReport = { backend, privacy in
            StepDryRun(privacy: privacy).run(backend, environment: LiveStepEnvironment())
        },
        addToDraft: @escaping @MainActor ([UIStep], String) -> SequenceAddResult
    ) {
        self.draft = draft
        self.name = suggestedName
        self.store = store
        self.privacy = privacy
        self.dryRun = dryRun
        self.addToDraftHandler = addToDraft
    }

    // MARK: Reading

    public var items: [DraftItem] { draft.items }

    /// The notes about what was not recorded that sit after this row (or before everything, for nil).
    public func notes(after id: Int?) -> [SkippedNote] { draft.skipped.filter { $0.afterItemID == id } }

    public var stepCount: Int { draft.stepCount }
    public var textEntryCount: Int { draft.textEntryCount }

    /// Why saving is not possible yet, or nil.
    public var blocker: String? {
        if draft.stepCount == 0 { return "There are no steps left to save." }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give it a name." }
        if let issue = draft.issues(privacy: privacy()).first { return issue.description }
        return nil
    }

    public var canSave: Bool { blocker == nil && store != nil }

    // MARK: Editing

    public func delete(_ id: Int) { edit { try $0.delete(id) } }

    public func moveUp(_ id: Int) { move(id, by: -1) }
    public func moveDown(_ id: Int) { move(id, by: 1) }

    private func move(_ id: Int, by delta: Int) {
        guard let position = draft.items.firstIndex(where: { $0.id == id }) else { return }
        let target = position + delta
        guard draft.items.indices.contains(target) else { return }
        edit { try $0.move(id, to: target) }
    }

    public func rename(_ id: Int, to text: String) { edit { try $0.rename(id, to: text) } }

    /// Merges a row with the one after it when they mean the same thing.
    public func merge(_ id: Int) { edit { try $0.merge(id) } }

    /// Whether a row can merge with the next one.
    public func canMerge(_ id: Int) -> Bool {
        var copy = draft
        return (try? copy.merge(id)) != nil
    }

    public func removeTextEntries() {
        draft.removeTextEntries()
        checks = [:]
    }

    private func edit(_ change: (inout RecordingDraft) throws -> Void) {
        var copy = draft
        do {
            try change(&copy)
            draft = copy
            problem = nil
            checks = [:]
        } catch {
            problem = "\(error)"
        }
    }

    // MARK: Looking at it

    /// Looks for every step in the app as it is now, without pressing anything. The apps must be open for it to say more
    /// than "cannot check".
    public func check() {
        guard !isChecking else { return }
        let steps: UIStepsBackend
        do {
            steps = try draft.validated(privacy: privacy(), dropTextEntries: true).backend
        } catch {
            problem = "\(error)"
            return
        }
        isChecking = true
        let report = dryRun(steps, privacy())
        isChecking = false
        // The steps come out in row order without text rows and app switches; give each row its answer.
        let stepRows = draft.items.filter { $0.step != nil }
        var found: [Int: StepCheck] = [:]
        if let blocked = report.blocked {
            for row in stepRows { found[row.id] = .unchecked(blocked.message) }
        } else {
            for (row, result) in zip(stepRows, report.results) {
                if let failure = result.failure {
                    found[row.id] = failure == .appNotRunning ? .unchecked(failure.message) : .missing(failure.message)
                } else {
                    found[row.id] = result.isDegraded ? .weak : .found
                }
            }
        }
        checks = found
        problem = nil
    }

    // MARK: Ending

    /// Saves the steps as a command. A recorded command asks before its first run, like one that was imported.
    @discardableResult
    public func save() -> RecordingReviewResult? {
        guard let store else {
            problem = "Saving is not available here."
            return nil
        }
        if let blocker {
            problem = blocker
            return nil
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: " ", with: "-")
        if let combo = hotkey, let conflict = store.hotkeyConflict(combo, excluding: nil) {
            switch conflict {
            case .panel: problem = "That shortcut opens Apropos."
            case .command(let other): problem = "That shortcut already runs \(other)."
            }
            return nil
        }
        do {
            let builder = try draft.sequenceBuilder(privacy: privacy(), dropTextEntries: true)
            var saved = try builder.save(
                title: title, symbol: "cursorarrow.click.2", aliases: cleaned.isEmpty ? [] : [cleaned],
                needsConfirmation: true, in: store, privacy: privacy())
            if let hotkey {
                saved.hotkey = hotkey
                _ = try store.update(saved)
            }
            problem = nil
            return .saved(name: title)
        } catch {
            problem = "That could not be saved: \(error)"
            return nil
        }
    }

    /// Puts the steps in the sequence draft instead, to combine them with other steps first.
    @discardableResult
    public func addToDraft() -> RecordingReviewResult? {
        let steps: [UIStep]
        do {
            steps = try draft.validated(privacy: privacy(), dropTextEntries: true).backend.steps
        } catch {
            problem = "\(error)"
            return nil
        }
        switch addToDraftHandler(steps, steps.count == 1 ? "Recorded step" : "Recorded steps") {
        case .added:
            problem = nil
            return .addedToDraft
        case .refused(let reason):
            problem = reason
            return nil
        }
    }
}
