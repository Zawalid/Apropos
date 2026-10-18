import SwiftUI

/// The three sizes of the palette's list, chosen in Settings, Appearance.
enum InterfaceSize: String, CaseIterable, Codable, Identifiable {
    case compact, standard, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Default"
        case .large: "Large"
        }
    }
}

/// Row, tile and type sizes for one `InterfaceSize`. Views read them from the environment instead of `Theme`.
struct InterfaceMetrics: Equatable {
    let rowHeight: CGFloat
    let tile: CGFloat
    let symbol: CGFloat
    let title: CGFloat
    let subtitle: CGFloat
    let section: CGFloat

    static func metrics(for size: InterfaceSize) -> InterfaceMetrics {
        switch size {
        case .compact:
            InterfaceMetrics(rowHeight: 34, tile: 22, symbol: 12.5, title: 13.5, subtitle: 11.5, section: 28)
        case .standard:
            InterfaceMetrics(rowHeight: 38, tile: 24, symbol: 13.5, title: 14, subtitle: 12, section: 30)
        case .large:
            InterfaceMetrics(rowHeight: 44, tile: 28, symbol: 15, title: 15, subtitle: 12.5, section: 32)
        }
    }
}

private struct InterfaceMetricsKey: EnvironmentKey {
    static let defaultValue = InterfaceMetrics.metrics(for: .standard)
}

extension EnvironmentValues {
    var interfaceMetrics: InterfaceMetrics {
        get { self[InterfaceMetricsKey.self] }
        set { self[InterfaceMetricsKey.self] = newValue }
    }
}

/// What a row's tile shows.
enum RowIconStyle: String, CaseIterable, Codable, Identifiable {
    case glyph, appLogo, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glyph: "Glyph"
        case .appLogo: "App logo"
        case .none: "None"
        }
    }
}
