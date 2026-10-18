import Cue
import SwiftUI

/// One 46pt row. The selection highlight is drawn by the list, not here, so it can slide between rows.
struct CommandRow: View {
    let ranked: RankedCommand
    let appName: String?
    /// False under a section header that already names the first menu.
    var showsFullPath = true

    var body: some View {
        let command = ranked.command
        HStack(spacing: Theme.Spacing.md) {
            IconTile(symbol: CommandDisplay.symbol(for: command), isEnabled: command.isEnabled)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(highlightedTitle)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.075)
                    .foregroundStyle(command.isEnabled ? Theme.text : Theme.text3)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            HStack(spacing: 4) {
                if command.isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.trailing, 4)
                        .accessibilityLabel("On")
                }
                if let shortcut = command.shortcut {
                    ForEach(Array(shortcut.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let command = ranked.command
        if showsFullPath { return command.displaySubtitle(appName: appName) }
        return command.path.dropFirst().joined(separator: " > ")
    }

    /// The display title with the matched characters in the accent color and a heavier weight.
    private var highlightedTitle: AttributedString {
        let title = ranked.command.displayTitle
        var result = AttributedString(title)
        guard !ranked.titlePositions.isEmpty else { return result }
        let matched = Set(ranked.titlePositions)
        var index = result.startIndex
        for (offset, _) in title.enumerated() {
            let next = result.index(afterCharacter: index)
            if matched.contains(offset) {
                result[index..<next].foregroundColor = Theme.accentText
                result[index..<next].font = .system(size: 15, weight: .semibold)
            }
            index = next
        }
        return result
    }
}

/// The 30pt rounded tile that carries a row's glyph.
struct IconTile: View {
    let symbol: String
    var isEnabled = true
    var accented = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(accented ? Theme.accentText : (isEnabled ? Theme.tileInk : Theme.text3))
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                    .fill(accented ? Theme.accentSoft : Theme.tile))
            .accessibilityHidden(true)
    }
}
