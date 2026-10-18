import Foundation

/// Sequences as user commands: the command store, the palette, hotkeys, links and Shortcuts all see an ordinary command
/// whose backend is `sequence`.
extension CommandSequence {
    /// The sequence as a command, not yet stored.
    ///
    /// - The trust becomes the command's review state: an untrusted sequence is stored `pending` and does nothing until
    ///   the person approves it with `UserCommandStore.approve`. Per-step trust marks are not stored: review decides.
    /// - `requires` lists what the steps read from the context, so the command is offered when it can run.
    /// - Pass `needsConfirmation: plan.requiresConfirmation` so a shortcut key asks first.
    public func userCommand(
        hotkey: HotKeyCombo? = nil, needsConfirmation: Bool = false, subtitle: String? = nil
    ) -> UserCommand {
        let backend = self.backend.approved
        var requires = Set<ContextRequirement>()
        for step in backend.steps {
            for input in step.inputs {
                if case .context = input.source { requires.insert(input.kind.requirement) }
            }
        }
        return UserCommand(
            id: id, title: title, subtitle: subtitle ?? SequenceSummary.subtitle(for: backend), symbol: symbol,
            aliases: aliases, requires: requires, backend: .sequence(backend), output: .none,
            needsConfirmation: needsConfirmation, timeout: backend.suggestedTimeout, hotkey: hotkey,
            review: effectiveTrust == .trusted ? .approved : .pending)
    }

    /// The sequence behind a command, or nil when the command is not a sequence.
    public init?(command: UserCommand) {
        guard case .sequence(let backend) = command.backend else { return nil }
        self.init(
            id: command.id, title: command.title, aliases: command.aliases, symbol: command.symbol,
            steps: backend.steps,
            trust: command.review == .approved ? .trusted : .untrusted)
    }
}

extension UserCommand {
    /// The steps of the command, when it is a sequence.
    public var sequenceBackend: SequenceBackend? {
        if case .sequence(let backend) = backend { backend } else { nil }
    }
}

/// Plain-language descriptions of a sequence for review screens, from its data and not from the labels the author wrote.
public enum SequenceSummary {
    /// "3 steps".
    public static func subtitle(for backend: SequenceBackend) -> String {
        "\(backend.steps.count) step\(backend.steps.count == 1 ? "" : "s")"
    }

    public static func lines(for backend: SequenceBackend) -> [String] {
        var lines = ["Runs \(backend.steps.count) step\(backend.steps.count == 1 ? "" : "s") in order:"]
        for (index, step) in backend.steps.prefix(10).enumerated() {
            var line = "    \(index + 1). \(clipped(step.summary))"
            if let output = step.output { line += " (gives its \(output.kind.noun) to the next steps)" }
            if step.continueOnFailure { line += " (goes on if it fails)" }
            lines.append(line)
        }
        if backend.steps.count > 10 { lines.append("    ...") }
        let asks = backend.steps.reduce(0) { $0 + $1.questions.count }
        if asks > 0 { lines.append("Asks you \(asks) question\(asks == 1 ? "" : "s") before it runs.") }
        return lines
    }

    private static func clipped(_ text: String, limit: Int = 200) -> String {
        text.count > limit ? String(text.prefix(limit)) + "..." : text
    }
}
