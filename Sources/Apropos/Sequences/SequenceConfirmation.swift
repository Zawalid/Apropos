import Foundation

/// What a step does outside Apropos.
public enum SequenceEffectKind: String, Sendable, Equatable {
    case mailDraft
    case shareMenu
    case moveFiles
    case copyFiles
    /// Hands the payload to another app (a note, a reminder, a to-do).
    case sendsToApp
    /// Hands the payload to a website.
    case webAddress
    case opensLink
    case runsShortcut
    case runsProgram
    case runsAppleScript
    case pressesKeys
    case menuSteps
    case replacesSelection
    /// An action that asks before it runs.
    case asksFirst
}

/// One external effect of a sequence, worded for the person who is about to allow it.
public struct SequenceEffect: Sendable, Equatable {
    /// The step it belongs to, counted from 1.
    public let step: Int
    public let kind: SequenceEffectKind
    /// "Open a draft in Mail", "Move the files to Downloads". Names destinations and apps, never a value.
    public let line: String
}

/// The one confirmation a sequence asks for, covering every step, before anything runs.
public struct SequenceConfirmation: Sendable, Equatable {
    public let effects: [SequenceEffect]

    public var isRequired: Bool { !effects.isEmpty }

    /// The question on top: "Run these 3 steps?".
    public var heading: String {
        effects.count == 1 ? "Allow this?" : "Allow these \(effects.count) things?"
    }

    /// One line per effect, numbered by step: "2. Open a draft in Mail". At most `maxLines`, then a count of the rest.
    public func lines(maxLines: Int = 8) -> [String] {
        var lines = effects.prefix(maxLines).map { "\($0.step). \($0.line)" }
        if effects.count > maxLines { lines.append("and \(effects.count - maxLines) more") }
        return lines
    }
}

enum SequenceEffects {
    static func effects(for step: SequenceStep, index: Int, target: PlannedTarget?) -> [SequenceEffect] {
        let number = index + 1
        func effect(_ kind: SequenceEffectKind, _ line: String) -> SequenceEffect {
            SequenceEffect(step: number, kind: kind, line: line)
        }
        switch step.kind {
        case .uiSteps(let backend):
            return backend.steps.map { effect(.menuSteps, $0.derivedSummary) }
        case .openURL(let template):
            return [effect(.opensLink, "Open \(linkDescription(template))")]
        case .shortcut(let name):
            return [effect(.runsShortcut, "Run the Shortcut \u{201C}\(name)\u{201D}")]
        case .destination:
            guard case .destination(let destination)? = target else { return [] }
            return [destinationEffect(destination, number: number)]
        case .contextAction, .userCommand:
            guard case .action(let action)? = target else { return [] }
            return actionEffects(action, number: number, captured: step.output != nil)
        }
    }

    private static func destinationEffect(_ destination: Destination, number: Int) -> SequenceEffect {
        let verb = destination.previewVerb ?? "Send to \(destination.title)"
        let kind: SequenceEffectKind
        var line = verb
        if destination.handler == .shareMenu {
            kind = .shareMenu
            line = "Open the Share menu"
        } else if destination.id.rawValue.hasPrefix("dest:folder.move") {
            kind = .moveFiles
            line = destination.title
        } else if destination.id.rawValue.hasPrefix("dest:folder.copy") {
            kind = .copyFiles
            line = destination.title
        } else if destination.id.rawValue == "dest:mail" {
            kind = .mailDraft
        } else if destination.opensWebAddress {
            kind = .webAddress
            line += " (through a web address)"
        } else {
            kind = .sendsToApp
        }
        return SequenceEffect(step: number, kind: kind, line: line)
    }

    /// Effects of an action step. A pure text function that lands on the clipboard has none.
    private static func actionEffects(_ action: ContextAction, number: Int, captured: Bool) -> [SequenceEffect] {
        func effect(_ kind: SequenceEffectKind, _ line: String) -> SequenceEffect {
            SequenceEffect(step: number, kind: kind, line: line)
        }
        var found: [SequenceEffect] = []
        switch action.backend {
        case .function: break
        case .shell: found.append(effect(.runsProgram, "Run a program: \(action.title)"))
        case .appleScript: found.append(effect(.runsAppleScript, "Run an AppleScript: \(action.title)"))
        case .shortcut(let shortcut):
            found.append(effect(.runsShortcut, "Run the Shortcut \u{201C}\(shortcut.name)\u{201D}"))
        case .urlScheme(let template): found.append(effect(.opensLink, "Open \(linkDescription(template))"))
        case .keyPress: found.append(effect(.pressesKeys, "Press keys in the app in front: \(action.title)"))
        case .uiSteps(let backend): found += backend.steps.map { effect(.menuSteps, $0.derivedSummary) }
        }
        // A named output is captured for the next step and never delivered.
        if action.output == .replaceSelection, !captured {
            found.append(effect(.replacesSelection, "Replace your selection"))
        }
        if found.isEmpty, action.needsConfirmation { found.append(effect(.asksFirst, action.title)) }
        return found
    }

    /// Where a link goes, worked out from its literal head so a value can never be part of it.
    static func linkDescription(_ template: ActionTemplate) -> String {
        guard case .literal(let head)? = template.parts.first, let colon = head.firstIndex(of: ":") else {
            return "a link"
        }
        let scheme = head[..<colon].lowercased()
        let rest = head[head.index(after: colon)...]
        if scheme == "http" || scheme == "https", rest.hasPrefix("//") {
            let host = rest.dropFirst(2).prefix { !"/?#".contains($0) }
            return host.isEmpty ? "a web address" : "a link to \(host)"
        }
        return "a link in the app for \(scheme)"
    }
}
