import SwiftUI

/// A centered message for the palette's non-list states.
struct StatusView: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = Theme.text2
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.tile))
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Theme.footerInset)
        .accessibilityElement(children: .contain)
    }
}

/// Placeholder rows shown while an app's menus are being read. Static on purpose: nothing moves in this state.
struct LoadingRows: View {
    private let titleWidths: [CGFloat] = [180, 140, 220, 120, 160]
    @Environment(\.interfaceMetrics) private var metrics

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(titleWidths.enumerated()), id: \.offset) { _, width in
                HStack(spacing: Theme.Spacing.md) {
                    RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                        .fill(Theme.tile)
                        .frame(width: 24, height: 24)
                    Capsule().fill(Theme.tile).frame(width: width, height: 10)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: metrics.rowHeight)
                .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reading menus")
    }
}
