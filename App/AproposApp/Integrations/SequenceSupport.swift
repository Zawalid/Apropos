import AppKit
import Apropos
import Foundation

/// Where the sequencer finds what a step may name: the actions, your commands and the destinations in effect now. The
/// controller fills the sources in once everything exists, and every run asks again, so a pack that was reloaded or a
/// command that was just saved is seen.
@MainActor
final class SequenceCatalogueSource {
    var actions: ContextActionCenter?
    var send: SendToCenter?
    var commands: UserCommandStore?
    var isInstalled: @Sendable (String) -> Bool = {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
    }

    func current() -> SequenceCatalogue {
        SequenceCatalogue(
            contextActions: actions?.library.actions ?? [], userCommands: commands?.commands ?? [],
            destinations: send?.sequenceDestinations ?? [], isInstalled: isInstalled)
    }
}

/// The sequencer of the running app: the same engines the palette and your commands use, with the send services of the
/// app (the Share menu needs the panel).
@MainActor
enum AppSequences {
    /// Everything a sequence run needs, made once.
    struct Parts {
        let services: ActionServices
        let runner: EngineStepRunner
    }

    /// The action services steps use. A sequence cannot start another, so `sequences` stays unavailable inside.
    static func parts(
        functions: ActionFunctionRegistry, actions: ActionServices, send: SendServices
    ) -> Parts {
        var inner = actions
        inner.sequences = .unavailable
        let runner = EngineStepRunner(
            engine: ActionEngine(functions: functions, services: inner), destinations: DestinationRunner(services: send)
        )
        return Parts(services: inner, runner: runner)
    }

    /// The services of the engine that runs your saved commands, with sequences connected.
    static func engineServices(
        base: ActionServices, functions: ActionFunctionRegistry, send: SendServices, source: SequenceCatalogueSource,
        privacy: @escaping @Sendable () -> ContextPrivacy
    ) -> ActionServices {
        var services = base
        services.sequences = SequenceExecutor.live(
            catalogue: { await MainActor.run { source.current() } }, functions: functions, actions: base, send: send,
            privacy: privacy)
        return services
    }

    /// The effects a sequence command will have, one line each, for the alert shown before a shortcut key runs it.
    static func confirmationLines(for command: UserCommand, source: SequenceCatalogueSource) -> [String] {
        guard let backend = command.sequenceBackend else { return [] }
        let plan = SequencePlanner.plan(backend, catalogue: source.current())
        return plan.confirmation.lines()
    }

    #if DEBUG
        /// Services that touch nothing, for previews and agent mode: no program runs, no link opens, nothing is copied,
        /// no key is pressed and no menu item is chosen in a real app.
        static func fakeActions(failing: Bool = false) -> ActionServices {
            var actions = ActionServices.live
            actions.process = { _ in
                ProcessOutput(status: failing ? 1 : 0, standardOutput: Data(), standardErrorByteCount: 0)
            }
            actions.openURL = { _ in !failing }
            actions.copyToClipboard = { _ in }
            actions.notify = { _ in }
            actions.postKey = { _ in true }
            actions.replaceSelection = { _, _ in .failed }
            actions.uiSteps = UIStepsExecutor { backend, _, _, _ in
                StepRunReport(
                    steps: [],
                    failure: failing ? StepFailure(step: 1, reason: .notFound) : nil, milliseconds: 0)
            }
            return actions
        }
    #endif
}
