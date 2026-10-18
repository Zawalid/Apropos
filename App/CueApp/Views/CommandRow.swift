import Cue
import SwiftUI

struct CommandRow: View {
    let ranked: RankedCommand
    let isSelected: Bool
    let appPID: pid_t?

    var body: some View {
        let command = ranked.command
        HStack(spacing: Theme.Spacing.md) {
            if let appPID {
                AppIcon(pid: appPID, size: 24)
                    .opacity(command.isEnabled ? 1 : 0.4)
            }
            VStack(alignment: .leading, spacing: 1) {
                highlightedTitle
                    .font(.system(size: 14, weight: .regular))
                    .lineLimit(1)
                Text(command.breadcrumb)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.metaText)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if command.isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .accessibilityLabel("On")
            }
            if let shortcut = command.shortcut {
                HStack(spacing: 3) {
                    ForEach(Array(shortcut.caps.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isSelected ? Theme.selection : .clear)
        }
        .foregroundStyle(command.isEnabled ? Color.primary : Color.secondary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The title with the matched characters in the accent color and a heavier weight.
    private var highlightedTitle: Text {
        let title = ranked.command.title
        guard !ranked.titlePositions.isEmpty else { return Text(title) }
        let matched = Set(ranked.titlePositions)
        var result = Text("")
        var run = ""
        var runMatched = false
        func flush() {
            guard !run.isEmpty else { return }
            result =
                result + (runMatched ? Text(run).fontWeight(.semibold).foregroundColor(Theme.accentText) : Text(run))
            run = ""
        }
        for (offset, character) in title.enumerated() {
            let isMatch = matched.contains(offset)
            if isMatch != runMatched { flush() }
            runMatched = isMatch
            run.append(character)
        }
        flush()
        return result
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.data(.caption, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 18)
            .padding(.horizontal, text.count > 2 ? 5 : 2)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.07)))
    }
}

struct StatusView: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.metaText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
