#if DEBUG
    import Apropos
    import SwiftUI

    // Everything a preview needs to build a real model without touching the machine: scratch stores that are never
    // flushed, a fixed Accessibility answer, a private defaults suite and a pinned fake target app. Nothing here reads
    // or writes the app's own settings or usage files, asks for Accessibility access, or looks at another app.
    // Commands, target apps and learned usage come from `DebugFixtures`, so previews and agent screenshots agree.

    @MainActor
    enum PreviewStores {
        /// A path inside a fresh temporary folder. Stores built over it never flush (see `writeDelay`), so the folder is
        /// normally never even created.
        private static func scratchURL(_ name: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("apropos-preview-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent(name)
        }

        /// Far longer than a preview lives, so a change in memory is never written out.
        private static let writeDelay = Duration.seconds(86_400)

        static func settings(_ customize: (SettingsModel) -> Void = { _ in }) -> SettingsModel {
            let store = SettingsStore(url: scratchURL("settings.json"), writeDelay: writeDelay)
            let model = SettingsModel(store: store, appliesSystemState: false)
            customize(model)
            return model
        }

        static func usageStore() -> UsageStore {
            UsageStore(url: scratchURL("usage.json"), writeDelay: writeDelay)
        }

        /// A private suite for the recent-commands list. The name is unique, and previews never record a run.
        static func defaults() -> UserDefaults {
            UserDefaults(suiteName: "apropos.preview.\(UUID().uuidString)") ?? .standard
        }

        /// A controller for the Settings pages. With `trusted` false and an `app`, the tracker follows that fake app
        /// (so the Privacy page can list its hidden commands); a trusted controller gets no target, because a trusted
        /// permission plus a target would make the menu model attach an observer to the real app.
        static func controller(
            trusted: Bool = false, app: String? = nil, customize: (SettingsModel) -> Void = { _ in }
        ) -> AppController {
            let tracker = FrontmostAppTracker(ownBundleID: "preview")
            let usageStore = usageStore()
            let controller = AppController(
                settings: settings(customize), usageStore: usageStore,
                permission: AccessibilityPermission(probe: { trusted }), tracker: tracker, defaults: defaults())
            if let app, !trusted {
                let target = DebugFixtures.targetApp(named: app)
                tracker.pin(target)
                // The fixture commands carry no bundle id, so build the id the way a real Finder command would have it.
                if let bundleID = target.bundleID, let first = DebugFixtures.commands(named: app).first {
                    usageStore.setHidden(
                        true, for: CommandID.base(bundleID: bundleID, path: first.path, title: first.title))
                }
            }
            return controller
        }
    }

    /// What the list area of a palette preview shows.
    enum PreviewMenu {
        case commands
        case loading
        case needsPermission
        case failed(String)
    }

    /// Which state of the send-to flow a palette scene shows.
    enum SendScene {
        /// The list with the generic row and the most used destinations beside the context actions.
        case rows
        /// The destination list.
        case list
        /// The Mail draft preview waiting for its Return.
        case confirm
        /// A send that failed.
        case failure
    }

    /// One palette scene. Every field has the value of an ordinary first look at Finder.
    struct PaletteOptions {
        var app = "finder"
        var menu = PreviewMenu.commands
        /// Seeds a few habits and a pin, so the list opens with Pinned and Suggested.
        var learned = true
        var query = ""
        var size = InterfaceSize.standard
        var icons = RowIconStyle.glyph
        var chips = false
        var actionsOpen = false
        /// How many Usually next rows to show (0 to 2), with sample reasons.
        var predicted = 0
        /// Runs the selected command against a runner that fails, so the footer shows the failure note.
        var failedRun = false
        /// Shows a state of the send-to flow, over a browser (or Finder, for files) with a selection.
        var send: SendScene?
        /// Shows a state of the sequence builder, over a browser with a selection.
        var sequence: SequenceScene?
        /// Makes the sample sequence fail at its second step, for the failure scene.
        var sequenceFails = false
    }

    /// The models behind one palette preview, wired the way `PanelController` wires them but over scratch stores.
    @MainActor
    final class PaletteKit {
        let model: PaletteModel
        let state = PanelState()
        let context: ContextModel
        let usage: UsageController
        let permission = AccessibilityPermission(probe: { false })
        let settings: SettingsModel
        let options: PaletteOptions
        let send: SendToCenter
        let contextActions: ContextActionCenter
        let sequences: SequenceCenter

        init(_ options: PaletteOptions) {
            self.options = options
            let settings = PreviewStores.settings {
                $0.interfaceSize = options.size
                $0.rowIcons = options.icons
            }
            self.settings = settings
            // The permission answers false and the tracker is pinned only after the menus are seeded, so the menu model
            // never starts a real read and never attaches to a running app.
            let tracker = FrontmostAppTracker(ownBundleID: "preview")
            let menus = AppMenuModel(tracker: tracker, permission: permission)
            let commands = DebugFixtures.commands(named: options.app)
            switch options.menu {
            case .commands: menus.seed(commands)
            case .loading: menus.seed(state: .loading)
            case .needsPermission: menus.seed(state: .needsPermission)
            case .failed(let message): menus.seed(state: .failed(message))
            }
            let model = PaletteModel(menus: menus, tracker: tracker)
            self.model = model
            usage = UsageController(
                store: PreviewStores.usageStore(), palette: model, defaults: PreviewStores.defaults())
            context = ContextModel(settings: settings)

            let target = DebugFixtures.targetApp(named: options.app)
            tracker.pin(target)
            if options.learned { DebugFixtures.seedUsage(usage, commands: commands) }
            let tipStore = usage.store
            model.setTipProvider { tipStore.shortcutTip(for: $0) }
            if options.chips { context.seed(Self.chipItems(for: options.app), pid: target.pid) }
            if options.predicted > 0 {
                let after = commands.dropFirst(7).first?.displayTitle ?? "that"
                let picks = Array(commands.dropFirst(4).filter(\.isEnabled).prefix(min(options.predicted, 2)))
                let rows = picks.enumerated().map { index, command in
                    let reason =
                        index == 0
                        ? "After \(after) you chose \(command.displayTitle) 9 of 12 times"
                        : "On weekday mornings you chose \(command.displayTitle) 14 of 20 times"
                    return Prediction(command: command.stableID, confidence: 0.82, reason: reason, basis: .afterCommand)
                }
                model.setPredictor { _ in rows }
            }
            // Send to: fake services, so nothing is ever created in a real app, and a snapshot of sample context.
            send = SendToCenter(
                library: .bundled(), services: AppSendServices.fake(failing: options.send == .failure),
                folders: SendFolderStore(
                    url: FileManager.default.temporaryDirectory.appendingPathComponent(
                        "apropos-preview-folders-\(UUID().uuidString).json")))
            let store = usage.store
            send.frecency = { store.frecency($0) }
            model.attachSend(send)
            contextActions = ContextActionCenter()
            contextActions.attach(to: model)
            // Sequences: the real center over fake services and a scratch store, so nothing is ever run or saved for real.
            let fakeSend = AppSendServices.fake(failing: options.sequenceFails)
            let parts = AppSequences.parts(
                functions: .builtin, actions: AppSequences.fakeActions(failing: options.sequenceFails), send: fakeSend)
            let library = ActionPackLibrary.bundled()
            let commandsStore = UserCommandStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "apropos-preview-commands-\(UUID().uuidString)", isDirectory: true))
            let sendCenter = send
            sequences = SequenceCenter(
                store: commandsStore, runner: parts.runner,
                catalogue: {
                    SequenceCatalogue(
                        contextActions: library.actions, userCommands: commandsStore.commands,
                        destinations: sendCenter.sequenceDestinations)
                })
            model.attachSequences(sequences)
            if options.send != nil || options.sequence != nil {
                DebugFixtures.seedSendUsage(store)
                let snapshot = ContextSnapshot(
                    appName: target.name, bundleID: target.bundleID, pid: target.pid, capturedAt: Date(),
                    values: DebugFixtures.sendValues(bundleID: target.bundleID))
                contextActions.update(with: snapshot)
                send.update(with: snapshot)
                sequences.update(with: snapshot)
            }
            model.query = options.query
            state.actionsOpen = options.actionsOpen
            if options.failedRun {
                model.setRunner { _ in .failure(.failed(-25204)) }
            }
        }

        /// Work that needs the run loop: the failed run that fills the footer's note.
        func settle() async {
            if let scene = options.sequence {
                await DebugSequences.apply(scene, model: model)
                if scene.focusesSymbol { state.formField = 2 }
            }
            if let scene = options.send, scene != .rows {
                let generic = model.results.first {
                    $0.command.id.hasPrefix("send:") && $0.command.title.hasSuffix("to...")
                }
                if let generic { _ = await model.run(generic.command) }
                let wanted = scene == .confirm ? "Mail draft" : (scene == .failure ? "Notes" : nil)
                if let wanted, let row = model.results.first(where: { $0.command.title == wanted }) {
                    _ = await model.run(row.command)
                }
            }
            guard options.failedRun, let command = model.selected?.command else { return }
            _ = await model.run(command)
        }

        var actions: PaletteActions {
            PaletteActions(
                run: {}, runCommand: { _ in }, perform: { _ in }, toggleActions: {}, openSettings: {}, retry: {},
                back: { [model] in _ = model.goBack() })
        }

        static func chipItems(for app: String) -> [ContextItem] {
            func item(_ kind: ContextKind, _ label: String) -> ContextItem {
                ContextItem(kind: kind, label: label, symbol: ContextItem.symbol(for: kind))
            }
            switch app {
            case "safari": return [item(.url, "github.com/zawalid/apropos"), item(.selection, "Selected text")]
            case "xcode": return [item(.document, "PaletteView.swift"), item(.branch, "main")]
            default: return [item(.folder, "Projects"), item(.selectionCount, "3 items")]
            }
        }
    }

    /// The palette exactly as the panel draws it, driven by a `PaletteKit`.
    struct PalettePreviewView: View {
        let kit: PaletteKit

        var body: some View {
            PaletteView(
                model: kit.model, state: kit.state, context: kit.context, usage: kit.usage,
                permission: kit.permission, settings: kit.settings, actions: kit.actions
            )
            .task { await kit.settle() }
        }
    }

    // MARK: Menu bar popover

    /// The popover the menu bar icon opens, on a glass card as the real popover has.
    struct MenuPopoverPreview: View {
        let app: TargetApp?
        let chips: [String]
        let recents: [UsageController.Recent]
        let hasAccess: Bool
        let pending: Int

        @State private var header = ContextHeaderModel()

        var body: some View {
            MenuPopoverView(
                header: header, recents: recents, hotKey: .default, hasAccess: hasAccess, pendingCommands: pending,
                actions: MenuPopoverActions()
            )
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.line))
            .onAppear {
                header.app = app
                header.chips = chips
            }
        }
    }

    // MARK: Menu bar menu

    /// The menu bar menu drawn in SwiftUI from the same `MenuBarContent` the real `NSMenu` is built from, so a change
    /// to what the menu lists shows up in a preview. The real menu uses system rendering; spacing here is close, not exact.
    struct MenuBarMenuPreview: View {
        let app: TargetApp?
        let chips: [String]
        let recents: [UsageController.Recent]
        let hasAccess: Bool

        @State private var header = ContextHeaderModel()

        var body: some View {
            let entries = MenuBarContent.entries(
                recents: recents, hotKey: HotKeyCombo.default.display, hasAccess: hasAccess)
            VStack(alignment: .leading, spacing: 0) {
                ContextHeaderView(model: header)
                Divider().padding(.vertical, 4)
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in row(entry) }
            }
            .padding(6)
            .frame(width: 292)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.divider))
            .onAppear {
                header.app = app
                header.chips = chips
            }
        }

        @ViewBuilder
        private func row(_ entry: MenuBarContent.Entry) -> some View {
            switch entry {
            case .separator: Divider().padding(.vertical, 4)
            case .sectionHeader(let title):
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
            case .placeholder(let title):
                Text(title).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.vertical, 3)
            case .recent(_, let title): Text(title).padding(.horizontal, 10).padding(.vertical, 3)
            case .action(_, let title, let key):
                HStack {
                    Text(title)
                    Spacer()
                    if !key.isEmpty { Text("\u{2318}\(key.uppercased())").foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 10).padding(.vertical, 3)
            }
        }

        static let sampleRecents: [UsageController.Recent] = [
            .init(
                stableID: "r1", title: "Show Path Bar", appName: "Finder", bundleID: "com.apple.finder",
                date: Date(timeIntervalSince1970: 1_800_000_000)),
            .init(
                stableID: "r2", title: "Reopen Last Closed Tab", appName: "Safari", bundleID: "com.apple.Safari",
                date: Date(timeIntervalSince1970: 1_799_990_000)),
            .init(
                stableID: "r3", title: "Clean Build Folder", appName: "Xcode", bundleID: "com.apple.dt.Xcode",
                date: Date(timeIntervalSince1970: 1_799_980_000)),
        ]
    }

    // MARK: Cells

    /// A flat stand-in for the desktop behind the glass, so the panel does not float over nothing.
    struct PreviewBackdrop: View {
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.07, green: 0.13, blue: 0.12), Color(red: 0.15, green: 0.12, blue: 0.2)]
                    : [Color(red: 0.74, green: 0.88, blue: 0.84), Color(red: 0.86, green: 0.82, blue: 0.93)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// One screen in one state. `make` builds fresh models every call, so the dark and light copies never share state.
    struct PreviewScene: Identifiable {
        let id: String
        let size: CGSize
        var backdrop = false
        let make: @MainActor () -> AnyView

        /// The scene at its natural size in `scheme`. `drawsBackdrop` is false for the renderer, which lays the image on
        /// a flat stand-in itself because offscreen glass does not blend with a SwiftUI backdrop.
        @MainActor
        func cell(_ scheme: ColorScheme, view: AnyView? = nil, drawsBackdrop: Bool = true) -> some View {
            ZStack {
                if backdrop {
                    if drawsBackdrop { PreviewBackdrop() }
                } else {
                    Theme.windowBackground
                }
                (view ?? make())
            }
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
        }
    }
#endif
