import Foundation

/// Why an action definition was refused. A refused definition is skipped by the pack loader and never runs.
public enum ActionValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case badID
    case emptyTitle
    case badSymbol
    case noRequirements
    case badTimeout
    case unknownFunction(String)
    case executableNotAbsolute
    case placeholderInExecutable
    case placeholderInScript
    case listVariableNotAlone
    case variableNeedsContext(ActionVariable)
    case replaceNeedsSelection
    case badShortcutName
    case urlPlaceholderBeforePath
    case urlSchemeNotAllowed(String)
    case badURLTemplate
    case emptyScript
    case optionInjection
    case tooLarge
    case invalidSteps(UIStepsValidationError)
    case invalidSequence(SequenceIssue)

    public var description: String {
        switch self {
        case .badID: "id must look like prefix:name in lowercase"
        case .emptyTitle: "title is empty"
        case .badSymbol: "symbol is empty or has spaces"
        case .noRequirements: "an action must require at least one kind of context"
        case .badTimeout: "timeout must be between 0.5 and 120 seconds"
        case .unknownFunction(let name): "no function named \(name)"
        case .executableNotAbsolute: "executable must be an absolute path"
        case .placeholderInExecutable: "executable cannot contain placeholders"
        case .placeholderInScript: "placeholders cannot appear in script text or before the script of an interpreter"
        case .listVariableNotAlone: "a list variable must be a whole argument"
        case .variableNeedsContext(let variable): "{\(variable.rawValue)} needs matching context in requires"
        case .replaceNeedsSelection: "replaceSelection needs selectedText in requires"
        case .badShortcutName: "shortcut name is empty, has placeholders or starts with a dash"
        case .urlPlaceholderBeforePath: "placeholders may not appear in the scheme or host of a URL"
        case .urlSchemeNotAllowed(let scheme): "the \(scheme) scheme is not allowed"
        case .badURLTemplate: "url template must start with a scheme"
        case .emptyScript: "script is empty"
        case .tooLarge: "a field is too large"
        case .invalidSteps(let error): error.description
        case .invalidSequence(let issue): issue.description
        case .optionInjection: "put -- before a value that is a whole argument, or send it on standard input"
        }
    }
}

/// The rules that make injection impossible by construction. Values reach a backend only as separate arguments, standard
/// input, environment entries or script parameters; the checks here keep a definition from sneaking them into program
/// text, and keep placeholders out of the one place that decides what gets run.
public enum ActionValidator {
    /// Programs that run text as code. Their script argument must be literal.
    static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish", "osascript", "python", "python3", "perl", "ruby",
        "node", "swift", "awk", "gawk", "php", "lua", "tclsh", "expect",
    ]
    /// Programs that run another program named in their arguments, which would put a value in command position.
    static let launchers: Set<String> = ["env", "xargs", "sudo", "su", "nohup", "exec", "time", "caffeinate", "open"]
    static let blockedSchemes: Set<String> = ["file", "javascript", "data", "vbscript", "about", "blob"]

    /// - Parameter requireContext: Built-in context actions must need some context; a user command may need none (open a
    ///   link, run a Shortcut), so it validates with false.
    public static func validate(
        _ action: ContextAction, functions: ActionFunctionRegistry, requireContext: Bool = true
    ) throws {
        guard action.id.isWellFormed else { throw ActionValidationError.badID }
        guard !action.title.trimmingCharacters(in: .whitespaces).isEmpty else { throw ActionValidationError.emptyTitle }
        guard !action.symbol.isEmpty, !action.symbol.contains(where: \.isWhitespace) else {
            throw ActionValidationError.badSymbol
        }
        // Steps are bound to the app they act in, which is context enough. A sequence declares its own inputs.
        if case .uiSteps = action.backend {
        } else if case .sequence = action.backend {
        } else if requireContext, action.requires.isEmpty {
            throw ActionValidationError.noRequirements
        }
        guard (0.5...120).contains(action.timeout) else { throw ActionValidationError.badTimeout }
        if action.output == .replaceSelection, !action.requires.contains(.selectedText) {
            throw ActionValidationError.replaceNeedsSelection
        }

        var used: [ActionVariable] = []
        switch action.backend {
        case .function(let name):
            guard functions[name] != nil else { throw ActionValidationError.unknownFunction(name) }
        case .shell(let shell):
            try validate(shell)
            used = shell.arguments.flatMap(\.variables) + [shell.standardInput, shell.workingDirectory].compactMap { $0 }
        case .appleScript(let script):
            guard !script.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ActionValidationError.emptyScript
            }
            try validateWholeListArguments(script.arguments)
            used = script.arguments.flatMap(\.variables)
        case .shortcut(let shortcut):
            let name = shortcut.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.hasPrefix("-"), !name.contains("{") else {
                throw ActionValidationError.badShortcutName
            }
            used = [shortcut.input].compactMap { $0 }
        case .urlScheme(let template):
            try validate(url: template)
            used = template.variables
        case .keyPress:
            break
        case .uiSteps(let steps):
            if let first = UIStepsValidator.issues(in: steps).first { throw ActionValidationError.invalidSteps(first) }
        case .sequence(let sequence):
            if let first = SequenceValidator.issues(in: sequence).first {
                throw ActionValidationError.invalidSequence(first)
            }
        }
        for variable in used {
            let provided = variable.requirements.contains { action.requires.contains($0) }
            guard provided else { throw ActionValidationError.variableNeedsContext(variable) }
        }
    }

    private static func validateWholeListArguments(_ arguments: [ActionTemplate]) throws {
        for argument in arguments where argument.variables.contains(where: \.isList) {
            guard argument.singleListVariable != nil else { throw ActionValidationError.listVariableNotAlone }
        }
    }

    /// Variables whose value can start with a dash, so a tool might read it as an option.
    static let optionRisk: Set<ActionVariable> = [.text, .title, .branch, .fileName, .fileNames]

    private static func validate(_ shell: ShellBackend) throws {
        guard shell.executable.hasPrefix("/") else { throw ActionValidationError.executableNotAbsolute }
        guard !shell.executable.contains("{") else { throw ActionValidationError.placeholderInExecutable }
        try validateWholeListArguments(shell.arguments)

        let program = (shell.executable as NSString).lastPathComponent
        let hasPlaceholders = shell.arguments.contains(where: \.hasVariables)
        if launchers.contains(program), program != "open", hasPlaceholders {
            // `env {text}` would run the value as a program.
            throw ActionValidationError.placeholderInScript
        }
        if interpreters.contains(program), hasPlaceholders {
            // Allowed only as `-c <literal script> <values...>`: the values become positional parameters.
            guard let flag = shell.arguments.first, flag.source.hasPrefix("-"), !flag.hasVariables,
                shell.arguments.count >= 2, !shell.arguments[1].hasVariables
            else { throw ActionValidationError.placeholderInScript }
        }
        // A value that is a whole argument and could start with a dash must follow `--`. Arguments after an
        // interpreter's script are positional parameters, not options.
        for (index, argument) in shell.arguments.enumerated() {
            if interpreters.contains(program), index >= 2 { continue }
            guard argument.parts.count == 1, case .variable(let variable) = argument.parts[0],
                optionRisk.contains(variable)
            else { continue }
            if index == 0 || shell.arguments[index - 1].source != "--" { throw ActionValidationError.optionInjection }
        }

    }

    private static func validate(url template: ActionTemplate) throws {
        guard case .literal(let head)? = template.parts.first, let colon = head.firstIndex(of: ":") else {
            throw ActionValidationError.badURLTemplate
        }
        let scheme = String(head[..<colon]).lowercased()
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) else {
            throw ActionValidationError.badURLTemplate
        }
        guard !blockedSchemes.contains(scheme) else { throw ActionValidationError.urlSchemeNotAllowed(scheme) }
        let afterColon = head[head.index(after: colon)...]
        if afterColon.hasPrefix("//") {
            // The destination (host) is everything up to the first path, query or fragment mark, and must be literal.
            let authority = afterColon.dropFirst(2)
            guard authority.contains(where: { "/?#".contains($0) }) else {
                throw ActionValidationError.urlPlaceholderBeforePath
            }
        } else if scheme == "http" || scheme == "https" {
            throw ActionValidationError.badURLTemplate
        }
    }
}
