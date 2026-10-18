import Foundation

/// Runs context actions. It checks that the action applies, runs its backend off the main thread with a timeout,
/// delivers the result, and reports a `Result`. It logs the action id and whether it worked, nothing else: never the
/// inputs, the outputs or the arguments.
public struct ActionEngine: Sendable {
    public let functions: ActionFunctionRegistry
    public let services: ActionServices

    public init(functions: ActionFunctionRegistry = .builtin, services: ActionServices = .live) {
        self.functions = functions
        self.services = services
    }

    /// - Parameters:
    ///   - values: The context to run on. Taken as it is; the caller got it from a snapshot.
    ///   - target: The app the action acts on: its bundle id filters actions, its pid is where a replacement goes.
    ///   - confirmed: Pass true after the person confirmed an action with `needsConfirmation`.
    public func run(
        _ action: ContextAction, values: ContextValues, target: TargetApp?, confirmed: Bool = false
    ) async -> Result<ActionOutcome, ActionError> {
        let result = await execute(action, values: values, target: target, confirmed: confirmed)
        switch result {
        case .success:
            AproposLog.app.info("action \(action.id.rawValue, privacy: .public) succeeded")
        case .failure(let error):
            AproposLog.app.info(
                "action \(action.id.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        return result
    }

    private func execute(
        _ action: ContextAction, values: ContextValues, target: TargetApp?, confirmed: Bool
    ) async -> Result<ActionOutcome, ActionError> {
        guard action.apps.allows(target?.bundleID) else { return .failure(.notApplicable) }
        for requirement in ContextRequirement.allCases where action.requires.contains(requirement) {
            if !values.has(requirement) { return .failure(.missingContext(requirement)) }
        }
        guard action.conditions.allSatisfy({ $0.holds(for: values) }) else { return .failure(.notApplicable) }
        if action.needsConfirmation, !confirmed { return .failure(.confirmationRequired) }
        if Task.isCancelled { return .failure(.cancelled) }

        let input = ActionInput(values: values)
        let produced: String?
        do {
            produced = try await withTimeout(action.timeout) {
                try await runBackend(action, input: input, target: target)
            }
        } catch let error as ActionError {
            return .failure(error)
        } catch let error as TextToolError {
            _ = error
            return .failure(.invalidInput)
        } catch let error as ProcessRunError {
            return .failure(Self.map(error))
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.backendFailed(status: nil))
        }
        if Task.isCancelled { return .failure(.cancelled) }
        return .success(await deliver(produced, for: action, pid: target?.pid))
    }

    static func map(_ error: ProcessRunError) -> ActionError {
        switch error {
        case .launchFailed: .launchFailed
        case .timedOut: .timedOut
        case .cancelled: .cancelled
        case .outputTooLarge: .outputTooLarge
        }
    }

    /// Runs `work`, giving up with `.timedOut` after `seconds`. The work is cancelled when time runs out.
    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ActionError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ActionError.cancelled }
            return first
        }
    }

    // MARK: Backends

    private func runBackend(_ action: ContextAction, input: ActionInput, target: TargetApp?) async throws -> String? {
        switch action.backend {
        case .function(let name):
            guard let function = functions[name] else { throw ActionError.unknownFunction(name) }
            return try await function(input, services)

        case .shell(let shell):
            let arguments = try expand(shell.arguments, input: input)
            var request = ProcessRequest(
                executable: shell.executable, arguments: arguments, environment: input.environment(),
                timeout: action.timeout)
            if let variable = shell.standardInput { request.standardInput = Data(try text(variable, input).utf8) }
            if let variable = shell.workingDirectory { request.workingDirectory = try text(variable, input) }
            return try finish(try await services.process(request), action)

        case .appleScript(let script):
            let arguments = try expand(script.arguments, input: input)
            let request = ProcessRequest(
                executable: "/usr/bin/osascript", arguments: ["-e", script.source] + arguments,
                environment: input.environment(), timeout: action.timeout)
            return try finish(try await services.process(request), action)

        case .shortcut(let shortcut):
            return try await runShortcut(shortcut, input: input, timeout: action.timeout, wantsOutput: action.output != .none)

        case .urlScheme(let template):
            guard let text = template.expandScalar(input, transform: { $0.percentEncodedForURL }),
                let url = URL(string: text), let scheme = url.scheme?.lowercased(),
                !ActionValidator.blockedSchemes.contains(scheme)
            else { throw ActionError.missingContext(Self.firstRequirement(of: template)) }
            guard await services.openURL(url) else { throw ActionError.unavailable("The link could not be opened.") }
            return nil

        case .keyPress(let key):
            guard await services.postKey(key) else {
                throw ActionError.unavailable("Apropos needs Accessibility access to press keys.")
            }
            return nil

        case .uiSteps(let steps):
            let report = await services.uiSteps.run(steps, action.id.rawValue, target, action.timeout)
            if let failure = report.failure { throw ActionError.uiStepFailed(failure) }
            return nil
        }
    }

    private static func firstRequirement(of template: ActionTemplate) -> ContextRequirement {
        template.variables.first?.requirements.first ?? .selectedText
    }

    private func text(_ variable: ActionVariable, _ input: ActionInput) throws -> String {
        if let value = input.scalar(variable) { return value }
        if let list = input.list(variable) { return list.joined(separator: "\n") }
        throw ActionError.missingContext(variable.requirements.first ?? .selectedText)
    }

    private func expand(_ templates: [ActionTemplate], input: ActionInput) throws -> [String] {
        var result: [String] = []
        for template in templates {
            guard let values = template.expandArgument(input) else {
                throw ActionError.missingContext(Self.firstRequirement(of: template))
            }
            result += values
        }
        return result
    }

    private func finish(_ output: ProcessOutput, _ action: ContextAction) throws -> String? {
        guard output.status == 0 else { throw ActionError.backendFailed(status: output.status) }
        guard action.output != .none else { return nil }
        let text = output.text
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    private func runShortcut(
        _ shortcut: ShortcutBackend, input: ActionInput, timeout: TimeInterval, wantsOutput: Bool
    ) async throws -> String? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apropos-shortcut-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }

        var arguments = ["run", shortcut.name]
        if let variable = shortcut.input {
            let file = directory.appendingPathComponent("input.txt")
            try Data(try text(variable, input).utf8).write(to: file, options: .atomic)
            arguments += ["--input-path", file.path]
        }
        let outputFile = directory.appendingPathComponent("output.txt")
        if wantsOutput { arguments += ["--output-path", outputFile.path, "--output-type", "public.utf8-plain-text"] }
        let result = try await services.process(
            ProcessRequest(executable: "/usr/bin/shortcuts", arguments: arguments, timeout: timeout))
        guard result.status == 0 else { throw ActionError.backendFailed(status: result.status) }
        guard wantsOutput, let data = try? Data(contentsOf: outputFile) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Delivery

    private func deliver(_ produced: String?, for action: ContextAction, pid: pid_t?) async -> ActionOutcome {
        guard let produced else { return ActionOutcome(id: action.id, delivery: .done) }
        switch action.output {
        case .none:
            return ActionOutcome(id: action.id, delivery: .done)
        case .clipboard:
            await services.copyToClipboard(produced)
            return ActionOutcome(id: action.id, delivery: .copied)
        case .notify:
            await services.notify(produced)
            return ActionOutcome(id: action.id, delivery: .notified, notice: produced)
        case .replaceSelection:
            let replaced: ReplaceResult
            if let pid { replaced = await services.replaceSelection(produced, pid) } else { replaced = .failed }
            switch replaced {
            case .replaced: return ActionOutcome(id: action.id, delivery: .replaced)
            case .pasted: return ActionOutcome(id: action.id, delivery: .pasted)
            case .notEditable, .failed:
                await services.copyToClipboard(produced)
                return ActionOutcome(id: action.id, delivery: .copiedInstead)
            }
        }
    }
}
