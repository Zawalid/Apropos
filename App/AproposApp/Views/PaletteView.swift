import Apropos
import SwiftUI

struct PaletteActions {
    let run: () -> Void
    let runCommand: (Command) -> Void
    let perform: (PaletteAction) -> Void
    let toggleActions: () -> Void
    let openSettings: () -> Void
    let retry: () -> Void
    var openGuide: () -> Void = {}
}

/// The palette: a glass panel with the search field and context chips on top, the ranked list below, and a floating
/// footer. All behaviour lives in `PaletteModel`; this view only draws it.
struct PaletteView: View {
    let model: PaletteModel
    let state: PanelState
    let context: ContextModel
    let usage: UsageController
    let permission: AccessibilityPermission
    let settings: SettingsModel
    let actions: PaletteActions

    @FocusState private var searchFocused: Bool
    @Environment(\.aproposReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                SearchHeader(model: model, context: context, searchFocused: $searchFocused)
                PaletteContentView(model: model, permission: permission, actions: actions)
            }
            FloatingFooter(
                model: model, state: state, content: PaletteContentView.resolve(model), actions: actions)
            if state.actionsOpen {
                ActionsPopover(
                    items: PaletteAction.available(
                        for: model.selected?.command, appName: model.targetApp?.name,
                        isPinned: model.selected.map { usage.isPinned($0.command) } ?? false),
                    selectedIndex: state.actionIndex, actions: actions
                )
                .padding(.trailing, 14)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(
                    reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(width: PanelPlacement.size.width, height: PanelPlacement.size.height)
        .aproposGlass(in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .tint(Theme.accentText)
        .environment(\.interfaceMetrics, settings.metrics)
        .environment(settings)
        .environment(usage)
        .providesReduceMotion(settings.reduceMotion)
        .onChange(of: state.focusToken) { searchFocused = true }
        .onAppear { searchFocused = true }
    }
}

private struct SearchHeader: View {
    let model: PaletteModel
    let context: ContextModel
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        let chips = ContextChips.chips(
            for: model.targetApp, items: context.itemsPID == model.targetApp?.pid ? context.items : [])
        let appChip = chips.first(where: \.isApp)
        let others = chips.filter { !$0.isApp }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.text2)
                    .accessibilityHidden(true)
                TextField(placeholder, text: Bindable(model).query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .tracking(-0.18)
                    .foregroundStyle(Theme.text)
                    .focused(searchFocused)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search commands")
                if let appChip {
                    ContextChipView(chip: appChip)
                        .accessibilityLabel("Commands for \(appChip.text)")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, others.isEmpty ? 12 : 10)
            if !others.isEmpty {
                ChipRow(chips: others)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
            }
        }
    }

    private var placeholder: String {
        if let app = model.targetApp { return "Search \(app.name) commands" }
        return "Search or type a command"
    }
}

/// The optional row of context chips under the search field. Empty by default; the person turns pieces on in Settings.
private struct ChipRow: View {
    let chips: [ContextChip]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                ContextChipView(chip: chip).chipRise(index: index)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current context")
    }
}

private struct ContextChipView: View {
    let chip: ContextChip

    var body: some View {
        HStack(spacing: 6) {
            switch chip.leading {
            case .appIcon(let pid): AppIcon(pid: pid, size: 14)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 10.5, weight: .medium))
                    .accessibilityHidden(true)
            }
            Text(chip.text)
                .font(.system(size: 12, weight: chip.isApp ? .medium : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(chip.isApp ? Theme.text : Theme.text2)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Capsule().fill(Theme.chip))
        .fixedSize()
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
                .foregroundStyle(Theme.text2)
                .frame(width: size, height: size)
        }
    }
}

/// Chooses what fills the area under the header.
private struct PaletteContentView: View {
    let model: PaletteModel
    let permission: AccessibilityPermission
    let actions: PaletteActions

    static func resolve(_ model: PaletteModel) -> PaletteContent {
        #if DEBUG
            if let forced = DebugPreviewState.forced { return forced }
        #endif
        return model.content
    }

    var body: some View {
        switch Self.resolve(model) {
        case .results:
            ResultsList(model: model, actions: actions)
        case .needsPermission:
            PermissionView(permission: permission, onHelp: actions.openGuide)
        case .loading:
            LoadingRows()
        case .noApp:
            StatusView(
                symbol: "app.dashed", title: "No app in front",
                detail: "Switch to an app and open Apropos again to see its commands.")
        case .noCommands(let name):
            StatusView(
                symbol: "menubar.rectangle", title: "No menu commands",
                detail: "\(name) does not expose a menu bar Apropos can read.")
        case .failed(let message):
            StatusView(
                symbol: "exclamationmark.triangle", title: "Could not read menus", detail: message,
                tint: Theme.cautionText, actionTitle: "Try again", action: actions.retry)
        case .noMatches(let query):
            StatusView(
                symbol: "magnifyingglass",
                title: query.isEmpty ? "Nothing to show" : "No commands for \"\(query)\"",
                detail: query.isEmpty
                    ? "This app has no commands to list."
                    : "Nothing in \(model.targetApp?.name ?? "this app") matches. Try fewer letters.")
        }
    }
}

#if DEBUG
    /// Debug builds only: APROPOS_PREVIEW_STATE=permission|loading|failed|empty|nocommands forces a state so each can be
    /// looked at without breaking the real conditions.
    enum DebugPreviewState {
        static var forced: PaletteContent? {
            switch ProcessInfo.processInfo.environment["APROPOS_PREVIEW_STATE"] {
            case "permission": .needsPermission
            case "loading": .loading
            case "failed": .failed("The app did not answer in time. Switch back to it and try again.")
            case "empty": .noMatches(query: "zzq")
            case "nocommands": .noCommands(appName: "Preview")
            default: nil
            }
        }
    }
#endif
