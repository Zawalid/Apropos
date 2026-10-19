import AppKit
import Apropos
import Observation
import SwiftUI

/// Wires the pieces together: permission, app tracking, menu loading, the palette panel and the global shortcut. It is
/// the only place that knows about all of them.
@MainActor
@Observable
final class AppController {
    let permission: AccessibilityPermission
    let tracker: FrontmostAppTracker
    let menus: AppMenuModel
    let palette: PaletteModel
    let settings: SettingsModel
    let context: ContextModel
    let usage: UsageController
    let actions: ContextActionCenter
    let send: SendToCenter
    let destinationToggles: DestinationToggles
    let externalLog: ExternalActivityLog
    let panelPositions: PanelPositionStore
    let sequences: SequenceCenter
    let userCommands: UserCommandStore
    let commandHotKeys = CommandHotKeyManager()
    let itemHotKeys = MenuItemHotKeyManager()
    @ObservationIgnored private(set) lazy var external = ExternalRequestHandler(controller: self)
    private(set) var combo: HotKeyCombo
    private(set) var isHotKeyRegistered = true

    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var panel: PanelController?
    @ObservationIgnored private(set) var recording: RecordingCoordinator?
    @ObservationIgnored private var settingsController: SettingsWindowController?
    @ObservationIgnored private var statusItem: StatusItemController?
    @ObservationIgnored private let onboarding = OnboardingWindowController()
    @ObservationIgnored let sharePresenter: ShareMenuPresenter
    @ObservationIgnored let sequenceSource: SequenceCatalogueSource

    convenience init() {
        Self.runLegacyMigration()
        var settingsURL = SettingsStore.defaultURL
        var usageURL = UsageStore.defaultURL
        var commandsURL = UserCommandStore.defaultDirectory
        var sendFoldersURL = SendFolderStore.defaultURL
        #if DEBUG
            // Snapshots and experiments keep their data out of the real files.
            if let dir = ProcessInfo.processInfo.environment["APROPOS_DATA_DIR"] {
                settingsURL = URL(fileURLWithPath: dir).appendingPathComponent("settings.json")
                usageURL = URL(fileURLWithPath: dir).appendingPathComponent("usage.json")
                commandsURL = URL(fileURLWithPath: dir).appendingPathComponent("commands", isDirectory: true)
                sendFoldersURL = URL(fileURLWithPath: dir).appendingPathComponent("send-folders.json")
            }
        #endif
        self.init(
            settings: SettingsModel(store: SettingsStore(url: settingsURL)), usageStore: UsageStore(url: usageURL),
            permission: AccessibilityPermission(), tracker: FrontmostAppTracker(), defaults: .standard,
            commandsDirectory: commandsURL, sendFoldersURL: sendFoldersURL)
    }

    /// Brings data from the former name over before any store opens. Debug runs that redirect their data skip it, so
    /// experiments never read or write the real folders.
    private static func runLegacyMigration() {
        #if DEBUG
            if ProcessInfo.processInfo.environment["APROPOS_DATA_DIR"] != nil || AgentMode.isOn { return }
        #endif
        guard let domain = Bundle.main.bundleIdentifier else { return }
        let outcome = LegacyMigration(
            supportDirectory: SettingsStore.supportDirectory, folderName: SettingsStore.folderName,
            defaults: .standard, domain: domain
        ).run()
        AproposLog.app.info("\(outcome.summary, privacy: .public)")
    }

    /// The pieces are passed in so previews can build a controller over in-memory stores and a fixed permission.
    init(
        settings: SettingsModel, usageStore: UsageStore, permission: AccessibilityPermission,
        tracker: FrontmostAppTracker, defaults: UserDefaults, commandsDirectory: URL? = nil, sendFoldersURL: URL? = nil
    ) {
        // Previews pass no folder and get an empty throwaway one, so they never read the person's commands.
        self.userCommands = UserCommandStore(
            directory: commandsDirectory
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "apropos-commands-\(UUID().uuidString)", isDirectory: true))
        self.permission = permission
        self.tracker = tracker
        self.settings = settings
        let menus = AppMenuModel(tracker: tracker, permission: permission)
        menus.showAlternates = settings.showAlternates
        self.menus = menus
        let palette = PaletteModel(
            menus: menus, tracker: tracker, ranker: CommandRanker(signal: usageStore.rankingSignal()))
        self.palette = palette
        self.usage = UsageController(store: usageStore, palette: palette, defaults: defaults)
        usage.prediction.configure(from: settings.store)
        palette.sources = settings.paletteSources
        palette.menuDisabledApps = Set(settings.menuDisabledApps)
        self.combo = settings.hotKey
        // Sequences find actions, your commands and destinations through this, once everything below exists.
        let source = SequenceCatalogueSource()
        let sharePresenter = ShareMenuPresenter()
        self.sharePresenter = sharePresenter
        var sendServices = AppSendServices.live(presenter: sharePresenter)
        var actionServices = ActionServices.live
        #if DEBUG
            if AgentMode.isOn {
                sendServices = AppSendServices.agent()
                actionServices = AppSequences.fakeActions(
                    failing: ProcessInfo.processInfo.environment["APROPOS_FIXTURE_SEND_FAIL"] != nil)
            }
        #endif
        // Context actions: each finished snapshot feeds the center, which lists what applies in the palette.
        let actionLibrary = ActionPackLibrary.bundled(plus: ActionPackLibrary.userDirectory)
        let actions = ContextActionCenter(
            library: actionLibrary,
            engine: ActionEngine(
                functions: actionLibrary.functions,
                services: AppSequences.engineServices(
                    base: actionServices, functions: actionLibrary.functions, send: sendServices, source: source,
                    privacy: { ContextPrivacy.load() })))
        actions.attach(to: palette)
        // Send to: the same snapshots become payloads, and the usage store ranks the destinations.
        let send = SendToCenter(
            library: .bundled(plus: DestinationLibrary.userDirectory), services: sendServices,
            folders: SendFolderStore(
                url: sendFoldersURL
                    ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                        "apropos-send-folders-\(UUID().uuidString).json")))
        let toggles = DestinationToggles(
            url: sendFoldersURL?.deletingLastPathComponent().appendingPathComponent("send-disabled.json")
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "apropos-send-disabled-\(UUID().uuidString).json"))
        send.disabled = toggles.disabled
        self.destinationToggles = toggles
        self.panelPositions = PanelPositionStore(
            url: sendFoldersURL?.deletingLastPathComponent().appendingPathComponent("panel-position.json")
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "apropos-panel-position-\(UUID().uuidString).json"))
        self.externalLog = ExternalActivityLog(
            url: sendFoldersURL?.deletingLastPathComponent().appendingPathComponent("external-activity.json")
                ?? FileManager.default.temporaryDirectory.appendingPathComponent(
                    "apropos-external-\(UUID().uuidString).json"))
        send.frecency = { [weak usageStore] id in usageStore?.frecency(id) ?? 0 }
        send.chooseFolder = { move in await FolderChooser.choose(move: move) }
        palette.attachSend(send)
        self.send = send
        // The sequence builder: a draft in memory, run through the same engines, saved through the commands store.
        source.actions = actions
        source.send = send
        source.commands = self.userCommands
        let parts = AppSequences.parts(functions: actionLibrary.functions, actions: actionServices, send: sendServices)
        let sequences = SequenceCenter(
            store: self.userCommands, runner: parts.runner, catalogue: { source.current() },
            privacy: { [weak settings] in settings?.contextPrivacy ?? ContextPrivacy() })
        palette.attachSequences(sequences)
        self.sequences = sequences
        self.sequenceSource = source
        var service = ContextService()
        service.onSnapshot = { snapshot in
            Task { @MainActor in
                actions.update(with: snapshot)
                send.update(with: snapshot)
                sequences.update(with: snapshot)
            }
        }
        self.actions = actions
        self.context = ContextModel(settings: settings, service: service)
        #if DEBUG
            if AgentMode.isOn {
                DebugFixtures.sendHooks = DebugFixtures.SendHooks(
                    send: send, actions: actions, usage: usage, sequences: sequences)
            }
        #endif
    }

    func start() {
        // A command that asks only the first time is remembered as confirmed once a confirmed run went through.
        actions.onConfirmedRun = { [weak self] id in
            guard let self, id.rawValue.hasPrefix("user:") else { return }
            try? self.userCommands.markPanelConfirmed(id)
        }
        userCommands.reservedHotKeys = { [weak self] in self.map { [$0.combo] } ?? [] }
        userCommands.onChange = { [weak self] in self?.userCommandsChanged() }
        usage.onItemShortcutsChanged = { [weak self] in self?.itemShortcutsChanged() }
        palette.setTipProvider { [weak self] command in
            guard let self, self.settings.shortcutTips else { return nil }
            return self.usage.store.shortcutTip(for: command)
        }
        userCommands.reload()
        IntegrationHub.controller = self
        permission.startMonitoring()
        if !(AgentMode.isOn && ProcessInfo.processInfo.environment["APROPOS_FIXTURE_COMMANDS"] != nil) {
            tracker.start()
        }
        let recordingModel = RecordingModel(
            makeRecorder: { [settings] in
                Recorder(
                    engine: RecordingEngine(
                        services: RecordingServices(
                            system: LiveRecordingSystem(), hitTester: LiveHitTester(), menus: LiveMenuInspector(),
                            keyLayout: LiveKeyLayout()),
                        configuration: RecordingConfiguration(privacy: settings.contextPrivacy)),
                    source: LiveCaptureSource())
            },
            makeReview: { [userCommands, settings, sequences] draft in
                RecordingReview(
                    draft: draft, store: userCommands, privacy: { settings.contextPrivacy },
                    addToDraft: { steps, label in sequences.add(uiSteps: steps, label: label) })
            })
        recording = RecordingCoordinator(
            model: recordingModel, openDraft: { [weak self] in self?.togglePanel() },
            shortcutRecording: { [weak self] in self?.setRecording($0) })
        let panel = PanelController(
            model: palette, tracker: tracker, permission: permission, settings: settings, context: context,
            usage: usage, openSettings: { [weak self] request in
                self?.showSettings(page: request.page, intent: request.intent)
            },
            openGuide: { [weak self] in self?.showOnboarding(step: .permission) },
            startRecording: { [weak self] in self?.startRecording() }, positions: panelPositions)
        if AgentMode.isOn {
            // Automated runs stay invisible: no dock icon, status item, hotkey or welcome window.
            NSApp.setActivationPolicy(.accessory)
        } else {
            statusItem = StatusItemController(controller: self)
        }
        self.panel = panel
        palette.setUserCommandHandler { [weak self] action in self?.perform(action) ?? .failed("Not available.") }
        sharePresenter.anchor = panel.anchorView
        #if DEBUG
            if let name = ProcessInfo.processInfo.environment["APROPOS_FIXTURE_COMMANDS"] {
                let fixtures = DebugFixtures.commands(named: name)
                menus.seed(fixtures)
                if AgentMode.isOn { tracker.pin(DebugFixtures.targetApp(named: name)) }
                if ProcessInfo.processInfo.environment["APROPOS_FIXTURE_USAGE"] != nil {
                    DebugFixtures.seedUsage(usage, commands: fixtures)
                }
                if AgentMode.isOn, ProcessInfo.processInfo.environment["APROPOS_FIXTURE_PREDICTION"] != nil {
                    DebugFixtures.seedPrediction(
                        usage, commands: fixtures, app: DebugFixtures.targetApp(named: name).bundleID)
                }
            }
            if AgentMode.isOn {
                DebugSnapshot.installRemoteControl(panel: panel, model: palette)
                DebugSnapshot.installSettingsControl(controller: self)
                if let name = ProcessInfo.processInfo.environment["APROPOS_APPEARANCE"] {
                    NSApp.appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
                }
            }
        #endif
        if !AgentMode.isOn {
            let hotKey = GlobalHotKey { [weak panel] in panel?.toggle() }
            self.hotKey = hotKey
            isHotKeyRegistered = hotKey.register(combo)
            showWelcomeOnce()
        }
        NotificationCenter.default.addObserver(
            forName: .aproposSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    /// The commands changed (edited in the app or on disk): list them in the palette and keep their shortcuts in step.
    private func userCommandsChanged() {
        actions.setUserCommands(userCommands.commands)
        guard !AgentMode.isOn else { return }
        commandHotKeys.sync(userCommands.commands, reserved: [combo]) { [weak self] command in
            self?.runFromShortcut(command)
        }
        itemShortcutsChanged()
    }

    /// The shortcuts given to menu items changed: register them with the system, after the ones of your commands.
    private func itemShortcutsChanged() {
        guard !AgentMode.isOn else { return }
        let taken = userCommands.commands.filter(\.isRunnable).compactMap(\.hotkey)
        itemHotKeys.sync(
            usage.store.itemHotKeys, reservedForPanel: [combo], reservedForCommands: taken
        ) { [weak self] ids in
            self?.runItem(among: ids)
        }
    }

    /// A shortcut of a menu item was pressed: run the item of the app in front. A key shared by several apps does
    /// nothing in an app that has no item for it.
    private func runItem(among ids: [CommandID]) {
        guard let app = tracker.app, let id = ids.first(where: { $0.bundleID == app.bundleID }) else { return }
        guard let command = menus.commands.lazy.compactMap({ $0.runnable(as: id) }).first else {
            AproposLog.app.info("item shortcut: \(id.rawValue, privacy: .public) is not in the front menu")
            return
        }
        let kinds = context.senseKinds
        Task { [weak self] in
            guard let self else { return }
            let result = await self.menus.run(command)
            if case .success = result {
                self.usage.recordRun(
                    command, appName: app.name, appBundleID: app.bundleID, contextKinds: kinds, query: "")
            }
        }
    }

    /// Runs a command whose own shortcut was pressed, on the context of the app in front.
    private func runFromShortcut(_ command: UserCommand) {
        var sensing = ContextService()
        sensing.privacy = settings.contextPrivacy
        if !settings.contextSensing || context.isPaused {
            sensing = ContextService(isTrusted: { false }, makeRoot: { _ in nil })
        }
        let target = tracker.app
        Task { [actions] in
            await actions.runWithLiveContext(
                command, target: target, sensing: sensing,
                confirm: { [sequenceSource] in
                    CommandConfirmation.ask(
                        $0, reason: "You pressed its shortcut.",
                        effects: AppSequences.confirmationLines(for: $0, source: sequenceSource))
                })
        }
    }

    /// Applies the settings that live outside the views: the hotkey and the alternate-command rows.
    private func settingsChanged() {
        if menus.showAlternates != settings.showAlternates { menus.showAlternates = settings.showAlternates }
        palette.sources = settings.paletteSources
        palette.menuDisabledApps = Set(settings.menuDisabledApps)
        usage.applyPredictionSettings(settings.store)
        if !settings.contextSensing {
            actions.clear()
            send.clear()
            sequences.clear()
        }
        if settings.hotKey != combo {
            combo = settings.hotKey
            isHotKeyRegistered = hotKey?.register(combo) ?? false
            userCommandsChanged()
        }
    }

    func flush() {
        settings.flush()
        usage.flush()
    }

    func togglePanel() { panel?.toggle() }

    /// Opens the panel, optionally with a query typed in (from `apropos://search`).
    func showPanel(query: String?) {
        panel?.show()
        if let query { palette.query = query }
    }

    /// The runner for outside requests, set up from the person's choices.
    func externalRunner() -> ExternalRunner {
        var runner = ExternalRunner(store: userCommands, center: actions)
        runner.isEnabled = settings.externalControl
        runner.alwaysConfirm = settings.externalAlwaysConfirm
        return runner
    }

    /// Notes an outside request in the activity list, if the person keeps one.
    func recordExternal(
        _ action: String, command: String? = nil, result: ExternalActivityEntry.Result
    ) {
        guard settings.externalLog else { return }
        externalLog.record(action: action, command: command, result: result)
    }

    /// Links opened with the apropos scheme.
    func handleExternal(_ urls: [URL]) { external.handle(urls) }

    /// Turns a destination on or off in the panel. It stays in the library either way.
    func setDestination(_ id: ActionID, enabled: Bool) {
        destinationToggles.set(id, enabled: enabled)
        send.disabled = destinationToggles.disabled
    }

    /// Reads the destinations folder again, after one was added.
    func reloadDestinations() {
        send.reload(.bundled(plus: DestinationLibrary.userDirectory))
    }

    func setCombo(_ new: HotKeyCombo) {
        combo = new
        settings.hotKey = new
        isHotKeyRegistered = hotKey?.register(new) ?? false
        userCommandsChanged()
    }

    /// While the person is choosing a new shortcut, the current one must not fire.
    func setRecording(_ recording: Bool) {
        commandHotKeys.setPaused(recording)
        itemHotKeys.setPaused(recording)
        if recording {
            hotKey?.unregister()
        } else {
            isHotKeyRegistered = hotKey?.register(combo) ?? false
        }
    }

    /// What the panel's Command-K list does to one of your commands. Settings and the store do the real work.
    private func perform(_ action: UserCommandAction) -> UserCommandOutcome {
        switch action {
        case .edit(let id):
            showSettings(page: .commands, intent: .editCommand(id.rawValue))
            return .done(note: nil)
        case .duplicate(let id):
            do {
                let copy = try userCommands.duplicate(id)
                return .done(note: "Duplicated as \u{201C}\(copy.title)\u{201D}")
            } catch {
                return .failed("That command could not be duplicated.")
            }
        case .delete(let id):
            let title = userCommands.command(withID: id)?.title ?? "the command"
            do {
                try userCommands.delete(id)
                return .done(note: "Deleted \u{201C}\(title)\u{201D}")
            } catch {
                return .failed("That command could not be deleted.")
            }
        }
    }

    /// Starts recording what happens in the app in front, or shows the permission screen. Automated runs never record.
    func startRecording() {
        guard !AgentMode.isOn else { return }
        recording?.begin()
    }

    func showSettings(page: SettingPage? = nil, intent: SettingsIntent? = nil) {
        let controller = settingsController ?? SettingsWindowController(controller: self)
        settingsController = controller
        controller.show(page: page, intent: intent)
    }

    var settingsWindow: NSWindow? { settingsController?.currentWindow }

    /// The welcome window is for the first launch only. After that, missing access shows in the panel and the menu bar
    /// item instead of reopening a window on every start.
    private func showWelcomeOnce() {
        let key = "hasSeenWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        showOnboarding()
    }

    /// Opens the first-run guide. Without a step it starts at the welcome and leaves the permission step out when access
    /// is already granted.
    func showOnboarding(step: OnboardingStep? = nil) {
        let model = OnboardingModel(
            permission: permission, hotKey: { [weak self] in self?.combo ?? .default }, start: step,
            finish: { [weak self] in self?.onboarding.close() })
        onboarding.show(model: model, reduceMotion: settings.reduceMotion)
    }
}

extension Command {
    /// This command when `id` is its identity, or the Option-key variant that has it, made runnable as a row of its own.
    func runnable(as id: CommandID) -> Command? {
        if stableID == id { return self }
        guard let alternate = alternates.first(where: { $0.stableID == id }) else { return nil }
        return Command(
            id: self.id, title: alternate.title, path: path, shortcut: alternate.shortcut,
            isEnabled: alternate.isEnabled, isChecked: false, source: source, target: alternate.target,
            stableID: alternate.stableID)
    }
}
