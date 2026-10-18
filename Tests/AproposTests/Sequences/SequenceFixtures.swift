import Foundation

@testable import Apropos

/// Small builders for sequence tests.
enum Seq {
    static func upper(_ id: String = "", output: String? = nil, input: SequenceSource = .context) -> SequenceStep {
        SequenceStep(
            id: id, label: "UPPERCASE", kind: .contextAction("ctx:text.upper"),
            inputs: [SequenceInput(.text, from: input)],
            output: output.map { SequenceOutput(name: $0) })
    }

    static func send(
        _ destination: String = "dest:notes", kind: SequenceValueKind = .text, from: SequenceSource = .context
    )
        -> SequenceStep
    {
        SequenceStep(
            label: "Send", kind: .destination(ActionID(rawValue: destination)),
            inputs: [SequenceInput(kind, from: from)])
    }

    static func link(_ template: String, kinds: [SequenceInput] = [SequenceInput(.text)]) -> SequenceStep {
        SequenceStep(label: "Link", kind: .openURL(tpl(template)), inputs: kinds)
    }

    static func tpl(_ text: String) -> ActionTemplate {
        do { return try ActionTemplate(text) } catch { fatalError("bad template in test: \(text)") }
    }

    static func menu(app: String = "com.apple.Preview", title: String = "Export as PDF") -> SequenceStep {
        SequenceStep(
            label: title,
            kind: .uiSteps(
                UIStepsBackend(steps: [
                    UIStep(
                        app: app,
                        locators: [.shortcut(key: "E", modifiers: [.command, .shift]), .menuPath(["File", title])],
                        description: "Choose File > \(title)")
                ])))
    }

    static func backend(_ steps: SequenceStep...) -> SequenceBackend { SequenceBackend(steps: steps) }
}
