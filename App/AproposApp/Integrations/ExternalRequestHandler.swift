import AppKit
import Apropos

/// Where `apropos://` links end up. The rules (which commands may run, what a link may carry, the first-use question)
/// live in the core package's `ExternalRouter` and `ExternalRunner`; this only shows the panel and asks the person.
@MainActor
final class ExternalRequestHandler {
    private unowned let controller: AppController

    init(controller: AppController) { self.controller = controller }

    func handle(_ urls: [URL]) {
        for url in urls { handle(url) }
    }

    private func handle(_ url: URL) {
        switch ExternalRouter.parse(url) {
        case .failure(let error):
            tell(error.description)
        case .success(.open):
            controller.showPanel(query: nil)
        case .success(.search(let query)):
            controller.showPanel(query: query)
        case .success(.run(let reference, let parameters)):
            run(reference: reference, parameters: parameters)
        }
    }

    private func run(reference: String, parameters: [ActionVariable: String]) {
        let runner = ExternalRunner(store: controller.userCommands, center: controller.actions)
        switch runner.resolve(reference: reference, parameters: parameters) {
        case .failure(let rejection):
            tell(rejection.description)
        case .success(let request):
            var confirmed = !request.needsConfirmation
            if request.needsConfirmation {
                let reason =
                    request.isFirstUse
                    ? "A link or Shortcut wants to run this command for the first time. Allow it only if you started it."
                    : "This command asks for confirmation."
                confirmed = CommandConfirmation.ask(request.command, reason: reason)
                guard confirmed else { return }
            }
            let target = controller.tracker.app
            Task { _ = await runner.perform(request, confirmed: confirmed, target: target) }
        }
    }

    /// A short notification: a link has no window to report in.
    private func tell(_ message: String) {
        Task { await ActionServices.live.notify(message) }
    }
}
