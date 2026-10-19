import Apropos
import SwiftUI

/// The chip in the search field while a draft exists: "Sequence draft, 3". Clicking it opens the draft.
struct SequenceDraftChip: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10.5, weight: .medium))
                    .accessibilityHidden(true)
                Text("Draft \u{00B7} \(count)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Theme.accentSoft))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sequence draft, \(count) step\(count == 1 ? "" : "s"). Open it.")
    }
}

/// What floats above the footer while building or running a sequence: the combined confirmation that waits for a
/// Return, the reason something did not happen, or where a saved command went. Nothing here runs anything; Return and
/// Escape are handled by the panel.
struct SequenceBanner: View {
    let model: PaletteModel

    var body: some View {
        if let pending = model.sequencePending {
            card(
                symbol: "checklist", tint: Theme.text2, title: pending.heading, lines: pending.lines,
                keys: [("\u{21A9}", "Run"), ("esc", "Cancel")])
        } else if let failure = model.sequenceFailure {
            card(
                symbol: "exclamationmark.triangle.fill", tint: Theme.cautionText, title: failure, lines: [],
                keys: [])
        } else if let notice = model.sequenceNotice {
            card(symbol: "checkmark.circle", tint: Theme.accentText, title: notice, lines: [], keys: [])
        }
    }

    private func card(
        symbol: String, tint: Color, title: String, lines: [String], keys: [(cap: String, label: String)]
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            ForEach(keys, id: \.cap) { key in
                HStack(spacing: 5) {
                    KeyCap(text: key.cap, small: true)
                    Text(key.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aproposGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// The form that turns the draft into a command: a name, an optional alias and a symbol picked from a grid. Return
/// saves, Escape goes back to the steps. Tab moves between the fields; inside the grid the arrow keys move the choice
/// (the panel handles them), and typing in the symbol search narrows it.
struct SequenceSaveView: View {
    let center: SequenceCenter
    let state: PanelState

    private enum Field: Int, Hashable { case name, alias, symbol }
    @FocusState private var focus: Field?

    var body: some View {
        let form = Bindable(center).form
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                field("Name", text: form.name, prompt: "Name this command", field: .name)
                field("Alias", text: form.alias, prompt: "Optional, typed to find it", field: .alias)
                    .frame(width: 210)
            }
            symbolPicker(search: form.symbolQuery)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { focus = Field(rawValue: state.formField) ?? .name }
        .onChange(of: state.formField) { focus = Field(rawValue: state.formField) ?? .name }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Save as command")
    }

    // MARK: Symbol

    private func symbolPicker(search: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Symbol")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text2)
                Spacer(minLength: 0)
                Text(center.form.symbol)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 10) {
                searchField(search)
                symbolPreview
            }
            grid
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func searchField(_ text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text3)
                .accessibilityHidden(true)
            TextField("Search by name or word, or type a symbol name", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .focused($focus, equals: .symbol)
                .autocorrectionDisabled()
                .accessibilityLabel("Search symbols")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focus == .symbol ? Theme.accentText.opacity(0.6) : Theme.chipEdge, lineWidth: 1))
    }

    private var symbolPreview: some View {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            .fill(Theme.tile)
            .frame(width: 32, height: 32)
            .overlay {
                Image(systemName: SymbolPreview.name(center.form.symbol))
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.tileInk)
            }
            .accessibilityHidden(true)
    }

    private var grid: some View {
        let sections = center.symbolSections
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.text3)
                            .padding(.top, 4)
                            .padding(.leading, 2)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: SymbolPicker.columns),
                            spacing: 4
                        ) {
                            ForEach(section.symbols) { symbol in
                                SymbolCell(name: symbol.name, isChosen: symbol.name == center.form.symbol) {
                                    center.form.symbol = symbol.name
                                    state.formField = 2
                                }
                                .id(symbol.name)
                            }
                        }
                    }
                    if sections.isEmpty {
                        Text("No symbol matches. Try another word.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.text3)
                            .padding(.top, 8)
                            .padding(.leading, 2)
                    }
                }
                .padding(.bottom, Theme.footerInset)
            }
            .onChange(of: center.form.symbol) { proxy.scrollTo(center.form.symbol) }
            .mask(SymbolFadeMask())
        }
        .accessibilityLabel("Symbols")
    }

    // MARK: Text fields

    private func field(_ title: String, text: Binding<String>, prompt: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text2)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .focused($focus, equals: field)
                .autocorrectionDisabled()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(focus == field ? Theme.accentText.opacity(0.6) : Theme.chipEdge, lineWidth: 1)
                )
                .accessibilityLabel(title)
        }
    }
}

/// One symbol in the grid. The chosen one has a mint ring.
struct SymbolCell: View {
    let name: String
    let isChosen: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: SymbolPreview.name(name))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isChosen ? Theme.accentText : Theme.text2)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isChosen ? Theme.accentSoft : (hovering ? Theme.chip : Color.clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: isChosen ? 2 : 0)
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

/// Fades the bottom of the grid out under the floating footer, like the result list does.
private struct SymbolFadeMask: View {
    var body: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
        }
    }
}

/// A name that is safe to draw: a symbol the system does not know shows a question mark instead of an empty square.
enum SymbolPreview {
    static func name(_ symbol: String) -> String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil ? "questionmark" : symbol
    }
}
