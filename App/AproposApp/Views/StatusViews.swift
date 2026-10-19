import SwiftUI

/// The brand ring, open at the top right, with a small symbol inside and the pearl waiting in the gap: the picture every
/// empty, missing or failed state shares. A failure drops the pearl and takes the caution colour.
struct EmptyRing: View {
    let symbol: String
    var tint: Color = Theme.text2

    private let size: CGFloat = 76
    private let line: CGFloat = 3.5

    var body: some View {
        let isCaution = tint != Theme.text2
        ZStack {
            Circle()
                .trim(from: 0, to: 304.0 / 360.0)
                .rotation(.degrees(-12))
                .stroke(
                    isCaution ? tint.opacity(0.7) : Theme.accent.opacity(0.55),
                    style: StrokeStyle(lineWidth: line, lineCap: .round)
                )
                .frame(width: size - line, height: size - line)
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(tint)
            if !isCaution {
                Circle()
                    .fill(Color(red: 1, green: 0.54, blue: 0.3))
                    .frame(width: 10, height: 10)
                    .shadow(color: Color(red: 1, green: 0.54, blue: 0.3).opacity(0.5), radius: 5)
                    .offset(x: cos(Angle.degrees(320).radians) * (size - line) / 2, y: sin(Angle.degrees(320).radians) * (size - line) / 2)
            }
        }
        .frame(width: size, height: size)
    }
}

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
            EmptyRing(symbol: symbol, tint: tint)
                .padding(.bottom, 6)
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
