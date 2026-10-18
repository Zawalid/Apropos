import Cue
import SwiftUI

struct PaletteActions {
    let run: () -> Void
    let runCommand: (Command) -> Void
    let close: () -> Void
}

/// The palette: search field on top, ranked list in the middle, status line at the bottom. All behaviour lives in
/// `PaletteModel`; this view only draws it.
struct PaletteView: View {
    let model: PaletteModel
    let state: PanelState
    let permission: AccessibilityPermission
    let actions: PaletteActions

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().overlay(Theme.hairline)
            content
            Divider().overlay(Theme.hairline)
            FooterView(model: model)
        }
        .frame(width: PanelPlacement.size.width, height: PanelPlacement.size.height)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.panelTint
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .scaleEffect(state.isPresented ? 1 : 0.965, anchor: .top)
        .opacity(state.isPresented ? 1 : 0)
        .onChange(of: state.focusToken) { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.metaText)
            TextField(placeholder, text: Bindable(model).query)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .regular))
                .focused($searchFocused)
                .autocorrectionDisabled()
            if let app = model.targetApp {
                AppChip(app: app)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg + 2)
        .frame(height: 62)
    }

    private var placeholder: String {
        if let app = model.targetApp { return "Search \(app.name) commands" }
        return "Search commands"
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .results:
            ResultsList(model: model, actions: actions)
        case .needsPermission:
            PermissionView(permission: permission, style: .compact)
        case .loading:
            StatusView(symbol: "circle.dotted", title: "Reading menus", detail: "One moment.")
        case .noApp:
            StatusView(
                symbol: "app.dashed", title: "No app in front",
                detail: "Switch to an app and open Cue again to see its commands.")
        case .noCommands(let name):
            StatusView(
                symbol: "menubar.rectangle", title: "No menu commands",
                detail: "\(name) does not expose a menu bar Cue can read.")
        case .failed(let message):
            StatusView(
                symbol: "exclamationmark.triangle", title: "Could not read menus", detail: message,
                tint: Theme.cautionText)
        case .noMatches(let query):
            StatusView(
                symbol: "magnifyingglass", title: "No matches",
                detail: query.isEmpty ? "Nothing to show." : "Nothing in this app matches \"\(query)\".")
        }
    }
}

private struct AppChip: View {
    let app: TargetApp

    var body: some View {
        HStack(spacing: 6) {
            AppIcon(pid: app.pid, size: 16)
            Text(app.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .accessibilityLabel("Commands for \(app.name)")
    }
}

struct AppIcon: View {
    let pid: pid_t
    let size: CGFloat

    var body: some View {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

private struct ResultsList: View {
    let model: PaletteModel
    let actions: PaletteActions

    var body: some View {
        let results = model.results
        let selectedID = model.selected?.id
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { ranked in
                        CommandRow(
                            ranked: ranked, isSelected: ranked.id == selectedID, appPID: model.targetApp?.pid
                        )
                        .id(ranked.id)
                        .onTapGesture { actions.runCommand(ranked.command) }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            .onChange(of: selectedID) {
                guard let selectedID else { return }
                proxy.scrollTo(selectedID)
            }
            .onChange(of: model.query) {
                if let first = results.first?.id { proxy.scrollTo(first, anchor: .top) }
            }
        }
    }
}

private struct FooterView: View {
    let model: PaletteModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let error = model.runError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.cautionText)
                    .lineLimit(1)
            } else {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.metaText)
            }
            Spacer()
            HintView(keys: ["↩"], label: "Run")
            HintView(keys: ["↑", "↓"], label: "Move")
            HintView(keys: ["esc"], label: "Close")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 38)
    }

    private var summary: String {
        let count = model.results.count
        switch model.content {
        case .results: return count == 1 ? "1 command" : "\(count) commands"
        default: return model.targetApp?.name ?? "Cue"
        }
    }
}

private struct HintView: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { KeyCap(text: $0) }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.metaText)
        }
    }
}
