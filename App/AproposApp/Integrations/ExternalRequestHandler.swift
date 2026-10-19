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
            guard controller.settings.externalControl else { return turnedOff("open") }
            controller.recordExternal("open", result: .ran)
            controller.showPanel(query: nil)
        case .success(.search(let query)):
            guard controller.settings.externalControl else { return turnedOff("search") }
            controller.recordExternal("search", result: .ran)
            controller.showPanel(query: query)
        case .success(.run(let reference, let parameters)):
            run(reference: reference, parameters: parameters)
        }
    }

    private func run(reference: String, parameters: [ActionVariable: String]) {
        let runner = controller.externalRunner()
        switch runner.resolve(reference: reference, parameters: parameters) {
        case .failure(let rejection):
            controller.recordExternal("run", result: rejection == .turnedOff ? .turnedOff : .refused)
            tell(rejection.description)
        case .success(let request):
            var confirmed = !request.needsConfirmation
            if request.needsConfirmation {
                let reason =
                    request.isFirstUse
                    ? "A link or Shortcut wants to run this command for the first time. Allow it only if you started it."
                    : "This command asks for confirmation."
                confirmed = CommandConfirmation.ask(request.command, reason: reason)
                guard confirmed else {
                    controller.recordExternal("run", command: request.command.title, result: .declined)
                    return
                }
            }
            let target = controller.tracker.app
            let title = request.command.title
            Task { [controller] in
                switch await runner.perform(request, confirmed: confirmed, target: target) {
                case .success: controller.recordExternal("run", command: title, result: .ran)
                case .failure: controller.recordExternal("run", command: title, result: .failed)
                }
            }
        }
    }

    private func turnedOff(_ action: String) {
        controller.recordExternal(action, result: .turnedOff)
        tell(ExternalRejection.turnedOff.description)
    }

    /// A short notification: a link has no window to report in.
    private func tell(_ message: String) {
        Task { await ActionServices.live.notify(message) }
    }
}
