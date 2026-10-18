import Cue
import Foundation

/// One chip under the search field: the app first, then what Cue knows about the moment.
struct ContextChip: Identifiable, Equatable {
    enum Leading: Equatable {
        case appIcon(pid_t)
        case symbol(String)
    }

    let id: String
    let leading: Leading
    let text: String
    var isApp: Bool { if case .appIcon = leading { true } else { false } }
}

/// Builds the chip row from what is known about the target app. M1 will feed it real context; until then release
/// builds show the app chip alone and debug builds can show fixtures (set CUE_FIXTURE_CONTEXT=1).
@MainActor
enum ContextChips {
    static func chips(for app: TargetApp?) -> [ContextChip] {
        guard let app else { return [] }
        var chips = [ContextChip(id: "app-\(app.pid)", leading: .appIcon(app.pid), text: app.name)]
        #if DEBUG
            if ProcessInfo.processInfo.environment["CUE_FIXTURE_CONTEXT"] != nil {
                chips += fixtures(for: app).enumerated().map { index, pair in
                    ContextChip(id: "fx-\(index)", leading: .symbol(pair.0), text: pair.1)
                }
            }
        #endif
        return chips
    }

    #if DEBUG
        private static func fixtures(for app: TargetApp) -> [(String, String)] {
            switch app.bundleID {
            case "com.apple.finder":
                return [("folder", "~/Projects/Cue"), ("cursorarrow.click", "3 items selected"), ("arrow.triangle.branch", "main")]
            case "com.apple.Safari":
                return [("globe", "linear.app/pricing"), ("textformat.size", "12 words selected"), ("rectangle.stack", "Tab 4 of 9")]
            case "com.apple.dt.Xcode":
                return [("doc.text", "PanelView.swift"), ("arrow.triangle.branch", "feat/panel"), ("desktopcomputer", "My Mac, Debug")]
            default:
                return [("doc.text", "Untitled"), ("cursorarrow.click", "Nothing selected")]
            }
        }
    #endif
}
