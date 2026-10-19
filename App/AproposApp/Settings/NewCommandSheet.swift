import Apropos
import SwiftUI

/// A short guided form for making a command: what it does, what it is called, when it is offered.
struct NewCommandSheet: View {
    let store: UserCommandStore
    let onDone: () -> Void

    @State private var draft = CommandDraft()
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New command")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.text)
            kindPicker
            Text(draft.kind.explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.text2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                kindFields
                field("Name", text: $draft.title, prompt: "Search Linear")
                field("Alias", text: $draft.alias, prompt: "Optional, such as lin")
                labeled("Symbol") { SymbolChooser(symbol: $draft.symbol, fallback: draft.kind.symbol) }
                labeled("Offered") {
                    ValueMenu(options: CommandDraft.Context.allCases.map { ($0, $0.title) }, selection: $draft.context)
                }
                if draft.context == .selectedText && draft.kind != .link {
                    HStack {
                        Text("Give it the selected text as input")
                            .font(.system(size: 13))
                            .foregroundStyle(Brand.text)
                        Spacer()
                        AproposToggle(title: "Give it the selected text as input", isOn: $draft.sendsSelection)
                    }
                }
            }
            if let problem {
                Text(problem)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("It appears in the panel as soon as you add it.")
                .font(.system(size: 12))
                .foregroundStyle(Brand.text3)
            HStack {
                Spacer()
                Button("Cancel", action: onDone).buttonStyle(BrandButtonStyle(kind: .plain))
                    .keyboardShortcut(.cancelAction)
                Button("Add command", action: add).buttonStyle(BrandButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .tint(Brand.mint)
    }

    private var kindPicker: some View {
        HStack(spacing: 8) {
            ForEach(CommandDraft.Kind.allCases) { kind in
                let selected = draft.kind == kind
                Button {
                    draft.kind = kind
                    problem = nil
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: kind.symbol).font(.system(size: 12.5))
                        Text(kind.title).font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(selected ? Brand.mintInk : Brand.text2)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Capsule().fill(selected ? Brand.mint : Brand.raised))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var kindFields: some View {
        switch draft.kind {
        case .link:
            field("Address", text: $draft.link, prompt: "https://linear.app/search?q={text}")
        case .shortcut:
            field("Shortcut name", text: $draft.shortcutName, prompt: "Summarize Text")
        case .program:
            field("Program", text: $draft.program, prompt: "/usr/bin/open")
            labeled("Arguments") {
                TextEditor(text: $draft.arguments)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.raised))
            }
            Text("One argument per line. Write {directory} or {file} where a path should go.")
                .font(.system(size: 11.5))
                .foregroundStyle(Brand.text3)
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        labeled(title) {
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(Brand.raised))
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Brand.text2)
                .frame(width: 104, alignment: .leading)
            content()
        }
    }

    private func add() {
        do {
            _ = try store.create(try draft.build())
            onDone()
        } catch {
            problem = "\(error)"
        }
    }
}
