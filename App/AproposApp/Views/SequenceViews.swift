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

/// The form that turns the draft into a command: a name, an optional alias and a symbol. Return saves, Escape goes
/// back to the steps, Tab moves between the fields.
struct SequenceSaveView: View {
    let center: SequenceCenter
    let state: PanelState

    private enum Field: Int, Hashable { case name, alias, symbol }
    @FocusState private var focus: Field?

    var body: some View {
        let form = Bindable(center).form
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as command")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text3)
            field("Name", text: form.name, prompt: "Name this command", field: .name)
            field("Alias", text: form.alias, prompt: "Optional, typed in the search to find it", field: .alias)
            HStack(spacing: 10) {
                field("Symbol", text: form.symbol, prompt: "An SF Symbol name", field: .symbol)
                symbolPreview
            }
            Text("It will be listed under Your commands.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { focus = Field(rawValue: state.formField) ?? .name }
        .onChange(of: state.formField) { focus = Field(rawValue: state.formField) ?? .name }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Save as command")
    }

    private var symbolPreview: some View {
        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
            .fill(Theme.tile)
            .frame(width: Theme.tileSize + 8, height: Theme.tileSize + 8)
            .overlay {
                Image(systemName: NSImage(systemSymbolName: center.form.symbol, accessibilityDescription: nil) == nil
                    ? "questionmark" : center.form.symbol)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.tileInk)
            }
            .padding(.top, 18)
            .accessibilityHidden(true)
    }

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
