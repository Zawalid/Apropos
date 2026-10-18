import Apropos
import SwiftUI

/// The chip in the search field while the destination list is open: "Send selection to". Clicking it goes back.
struct BreadcrumbChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Capsule().fill(Theme.chip))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to commands from \(title)")
    }
}

/// What floats above the footer while sending: the one-line preview that waits for a confirming Return, or the reason a
/// send did not happen. Nothing here sends anything; Return and Escape are handled by the panel.
struct SendBanner: View {
    let model: PaletteModel

    var body: some View {
        if let pending = model.sendPending {
            Banner(
                symbol: "paperplane", tint: Theme.text2, title: "Send to \(pending.destinationTitle)?",
                detail: pending.line, keys: [("\u{21A9}", "Send"), ("esc", "Cancel")])
        } else if let failure = model.sendFailure {
            Banner(
                symbol: "exclamationmark.triangle.fill", tint: Theme.cautionText, title: failure,
                detail: "Nothing was lost. Return tries again, Esc goes back.", keys: [])
        }
    }
}

private struct Banner: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let keys: [(cap: String, label: String)]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
