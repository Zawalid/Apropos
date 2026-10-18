import AppIntents
import Apropos
import Foundation

/// Apropos in the Shortcuts app: run one of your commands, or open the panel.
///
/// The same rules as `apropos://run` apply, enforced by the core package's `ExternalRunner`: only approved commands that
/// are marked "allow from URL" are offered or run, the first outside run of each command asks you in Apropos, and the
/// command acts only on the values Shortcuts passes in, never on whatever is selected in the app in front.

/// Why an intent could not do its job. The text is shown by Shortcuts.
enum AproposIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning
    case refused(String)
    case declined
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notRunning: "Apropos is not running."
        case .refused(let reason): "\(reason)"
        case .declined: "You chose not to run the command."
        case .failed(let reason): "\(reason)"
        }
    }
}

/// A command as Shortcuts sees it: a title to pick, found by title or alias.
struct CommandEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Apropos Command"
    static let defaultQuery = CommandEntityQuery()

    let id: String
    let title: String
    let aliases: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)", subtitle: aliases.isEmpty ? nil : LocalizedStringResource(stringLiteral: aliases.joined(separator: ", ")))
    }

    init(_ command: UserCommand) {
        id = command.id.rawValue
        title = command.title
        aliases = command.aliases
    }
}

struct CommandEntityQuery: EntityStringQuery {
    @MainActor
    private func runner() -> ExternalRunner? {
        guard let controller = IntegrationHub.controller else { return nil }
        return ExternalRunner(store: controller.userCommands, center: controller.actions)
    }

    @MainActor
    func entities(for identifiers: [String]) async throws -> [CommandEntity] {
        guard let runner = runner() else { return [] }
        return runner.available.filter { identifiers.contains($0.id.rawValue) }.map(CommandEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [CommandEntity] {
        runner()?.search(string).map(CommandEntity.init) ?? []
    }

    @MainActor
    func suggestedEntities() async throws -> [CommandEntity] {
        runner()?.available.map(CommandEntity.init) ?? []
    }
}

struct RunAproposCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Apropos Command"
    static let description = IntentDescription(
        "Runs one of your Apropos commands. Only commands you marked as allowed from links and Shortcuts can run.")
    static let openAppWhenRun = false

    @Parameter(title: "Command") var command: CommandEntity
    @Parameter(title: "Text") var text: String?
    @Parameter(title: "Page URL") var pageURL: URL?

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$command) on \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let controller = IntegrationHub.controller else { throw AproposIntentError.notRunning }
        let runner = ExternalRunner(store: controller.userCommands, center: controller.actions)
        var parameters: [ActionVariable: String] = [:]
        if let text, !text.isEmpty { parameters[.text] = text }
        if let pageURL { parameters[.url] = pageURL.absoluteString }

        let request: ExternalRun
        switch runner.resolve(reference: command.id, parameters: parameters) {
        case .failure(let rejection): throw AproposIntentError.refused(rejection.description)
        case .success(let resolved): request = resolved
        }
        var confirmed = !request.needsConfirmation
        if request.needsConfirmation {
            let reason =
                request.isFirstUse
                ? "A Shortcut wants to run this command for the first time. Allow it only if you started it."
                : "This command asks for confirmation."
            guard CommandConfirmation.ask(request.command, reason: reason) else { throw AproposIntentError.declined }
            confirmed = true
        }
        switch await runner.perform(request, confirmed: confirmed, target: controller.tracker.app) {
        case .success(let outcome):
            return .result(dialog: IntentDialog(stringLiteral: outcome.notice ?? "Done"))
        case .failure(let error):
            throw AproposIntentError.failed(error.message)
        }
    }
}

struct OpenAproposIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Apropos"
    static let description = IntentDescription("Shows the Apropos panel for the app in front.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let controller = IntegrationHub.controller else { throw AproposIntentError.notRunning }
        controller.showPanel(query: nil)
        return .result()
    }
}

struct AproposShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAproposIntent(), phrases: ["Open \(.applicationName)"], shortTitle: "Open Apropos",
            systemImageName: "command")
    }
}
