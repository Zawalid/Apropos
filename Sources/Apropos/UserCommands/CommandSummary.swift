import Foundation

/// What a command can do to the Mac, for the person reviewing it.
public enum CommandRisk: String, Sendable, Equatable, CaseIterable {
    /// Runs a program with arguments. Can do anything the person can.
    case runsProgram
    /// Runs an AppleScript. Can control other apps and run shell commands.
    case runsAppleScript
    /// Runs an Apple Shortcut, which may itself run scripts.
    case runsShortcut
    case pressesKeys
    case opensLink
    case replacesSelection
    /// Chooses menu items in other apps.
    case controlsApps

    /// Risks that make an imported command wait for approval.
    public var needsApproval: Bool { self == .runsProgram || self == .runsAppleScript }

    public var warning: String {
        switch self {
        case .runsProgram: "Runs a program on your Mac."
        case .runsAppleScript: "Runs an AppleScript, which can control other apps and run commands."
        case .runsShortcut: "Runs a Shortcut, which can do anything the Shortcut does."
        case .pressesKeys: "Presses keys in the app in front."
        case .opensLink: "Opens a link."
        case .replacesSelection: "Replaces the text you have selected."
        case .controlsApps: "Chooses menu items in other apps."
        }
    }
}

/// Plain-language descriptions of a command, for review screens and confirmation dialogs.
public enum CommandSummary {
    public static func risks(for command: UserCommand) -> [CommandRisk] {
        var risks: [CommandRisk] = []
        switch command.backend {
        case .shell: risks.append(.runsProgram)
        case .appleScript: risks.append(.runsAppleScript)
        case .shortcut: risks.append(.runsShortcut)
        case .keyPress: risks.append(.pressesKeys)
        case .urlScheme: risks.append(.opensLink)
        case .uiSteps: risks.append(.controlsApps)
        case .function: break
        }
        if command.output == .replaceSelection { risks.append(.replacesSelection) }
        return risks
    }

    /// One line per fact: what it runs, what it needs, where it works.
    public static func lines(for command: UserCommand) -> [String] {
        var lines: [String] = []
        switch command.backend {
        case .function(let name):
            lines.append("Runs the built-in function \(name).")
        case .shell(let shell):
            let arguments = shell.arguments.map(\.source).joined(separator: " ")
            lines.append("Runs \(shell.executable)" + (arguments.isEmpty ? "" : " \(clipped(arguments))"))
            if let input = shell.standardInput { lines.append("Sends {\(input.rawValue)} to its input.") }
            if let directory = shell.workingDirectory { lines.append("Runs in {\(directory.rawValue)}.") }
        case .appleScript(let script):
            let source = script.source.split(separator: "\n", omittingEmptySubsequences: false)
            lines.append("Runs an AppleScript of \(source.count) line\(source.count == 1 ? "" : "s"):")
            lines += source.prefix(8).map { "    " + clipped(String($0)) }
            if source.count > 8 { lines.append("    ...") }
            if !script.arguments.isEmpty {
                lines.append("Passes " + script.arguments.map(\.source).joined(separator: ", ") + " as parameters.")
            }
        case .shortcut(let shortcut):
            lines.append("Runs the Shortcut \u{201C}\(clipped(shortcut.name))\u{201D}.")
        case .urlScheme(let template):
            lines.append("Opens \(clipped(template.source))")
        case .keyPress(let key):
            lines.append("Presses \(key.modifiers.symbols)key code \(key.keyCode).")
        case .uiSteps(let steps):
            lines.append(
                "Runs \(steps.steps.count) step\(steps.steps.count == 1 ? "" : "s") in "
                    + steps.apps.joined(separator: ", ") + ":")
            lines += steps.steps.prefix(8).map { "    " + clipped($0.description) }
            if steps.steps.count > 8 { lines.append("    ...") }
            lines.append("Reliability: \(steps.fragility.title). \(steps.fragility.explanation)")
        }
        if !command.requires.isEmpty {
            lines.append("Needs: " + command.requires.map(\.rawValue).sorted().joined(separator: ", ") + ".")
        }
        switch command.output {
        case .clipboard: lines.append("Puts the result on the clipboard.")
        case .replaceSelection: lines.append("Replaces the selection with the result.")
        case .notify: lines.append("Shows the result in a notification.")
        case .none: break
        }
        if command.apps.include.isEmpty {
            lines.append("Works in every app.")
        } else {
            lines.append("Works in: " + command.apps.include.sorted().joined(separator: ", ") + ".")
        }
        if command.needsConfirmation { lines.append("Asks before it runs.") }
        return lines
    }

    private static func clipped(_ text: String, limit: Int = 200) -> String {
        text.count > limit ? String(text.prefix(limit)) + "..." : text
    }
}
