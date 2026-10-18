import AppKit
import SwiftUI

/// A live picture of the panel for the Appearance page. It is drawn with the panel's own tokens, tiles and key caps and
/// follows the chosen theme, size and row icons, so a change shows at once. It sits on a soft backdrop so the glass reads.
struct SettingsPalettePreview: View {
    let settings: SettingsModel

    private struct Sample {
        let symbol: String
        let title: String
        let subtitle: String
        let keys: [String]
    }

    private let samples = [
        Sample(symbol: "folder.badge.plus", title: "New Folder", subtitle: "File", keys: ["\u{21E7}", "\u{2318}", "N"]),
        Sample(symbol: "doc.on.doc", title: "Copy Path", subtitle: "Edit", keys: []),
        Sample(symbol: "eye", title: "Show Path Bar", subtitle: "View", keys: ["\u{2325}", "\u{2318}", "P"]),
        Sample(symbol: "arrow.up.right.square", title: "Open in Terminal", subtitle: "Services", keys: []),
    ]

    var body: some View {
        let metrics = settings.metrics
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.42, blue: 0.5), Color(red: 0.36, green: 0.3, blue: 0.62)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Brand.mint.opacity(0.35), .clear], center: .bottomLeading, startRadius: 0, endRadius: 320)
            )
            panel(metrics: metrics)
                .padding(.horizontal, 28)
                .padding(.vertical, 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous))
        .environment(\.interfaceMetrics, metrics)
        .environment(\.colorScheme, scheme)
        .animation(.easeOut(duration: 0.18), value: settings.interfaceSize)
        .animation(.easeOut(duration: 0.18), value: settings.rowIcons)
        .accessibilityHidden(true)
    }

    private var scheme: ColorScheme {
        switch settings.appearance {
        case .system: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        case .dark: .dark
        case .light: .light
        }
    }

    private func panel(metrics: InterfaceMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text3)
                Text("Search Finder commands")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.text3)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    AppIconImage(icon: finderIcon, size: 16)
                    Text("Finder").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Theme.chip))
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            VStack(spacing: 2) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                    row(sample, metrics: metrics, selected: index == 0)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .aproposGlass(in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    private func row(_ sample: Sample, metrics: InterfaceMetrics, selected: Bool) -> some View {
        HStack(spacing: 12) {
            switch settings.rowIcons {
            case .glyph: IconTile(symbol: sample.symbol)
            case .appLogo: AppIconImage(icon: finderIcon, size: metrics.tile)
            case .none: EmptyView()
            }
            Text(sample.title)
                .font(.system(size: metrics.title, weight: .medium))
                .foregroundStyle(Theme.text)
            Text(sample.subtitle)
                .font(.system(size: metrics.subtitle))
                .foregroundStyle(Theme.text3)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(Array(sample.keys.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(selected ? Theme.highlight : .clear))
    }

    private var finderIcon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder").map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }
}
