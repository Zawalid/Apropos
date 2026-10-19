#if DEBUG
    import Apropos
    import SwiftUI

    // Every screen in every state, for Xcode's canvas. Open this file and press Option-Command-Return; edit a view, save,
    // and the matching preview redraws without launching the app. Each preview shows the screen in dark (left) and
    // light (right). The scenes are listed once in `PreviewCatalog`, which the command line renderer in
    // `App/PreviewRender` also walks to write PNGs. Sample data lives in Fixtures.swift.

    // MARK: Catalog

    @MainActor
    enum PreviewCatalog {
        static let palette = CGSize(width: 776, height: 536)
        static let settings = CGSize(width: 800, height: 560)
        static let onboarding = OnboardingView.size

        private static func palette(_ id: String, _ options: PaletteOptions) -> PreviewScene {
            PreviewScene(id: id, size: palette, backdrop: true) {
                AnyView(PalettePreviewView(kit: PaletteKit(options)))
            }
        }

        private static func settings(
            _ id: String, page: SettingPage, query: String = "", trusted: Bool = false, app: String? = "finder",
            customize: @escaping @MainActor (SettingsModel) -> Void = { _ in },
            prepare: @escaping @MainActor (AppController) -> Void = { _ in }
        ) -> PreviewScene {
            PreviewScene(id: id, size: settings) {
                let controller = PreviewStores.controller(trusted: trusted, app: app, customize: customize)
                prepare(controller)
                let navigation = SettingsNavigation()
                navigation.select(page)
                return AnyView(
                    SettingsRoot(
                        controller: controller, settings: controller.settings, navigation: navigation,
                        initialQuery: query))
            }
        }

        private static func onboarding(
            _ id: String, step: OnboardingStep, trusted: Bool = false, panelOpened: Bool = false, help: Bool = false,
            live: @escaping @MainActor () -> OnboardingLive = { .fixed(target: PreviewOnboarding.safari) }
        ) -> PreviewScene {
            PreviewScene(id: id, size: onboarding) {
                let permission = AccessibilityPermission(probe: { trusted })
                let model = OnboardingModel(
                    permission: permission, hotKey: { .default }, start: step, panelOpened: panelOpened,
                    showsHelp: help, live: live())
                return AnyView(OnboardingView(model: model))
            }
        }

        // Onboarding

        static let onboardingWelcome = onboarding("onboarding-welcome", step: .welcome)
        static let onboardingPermission = onboarding("onboarding-permission", step: .permission)
        static let onboardingPermissionHelp = onboarding("onboarding-permission-help", step: .permission, help: true)
        static let onboardingPermissionAllowed = onboarding(
            "onboarding-permission-allowed", step: .permission, trusted: true)
        static let onboardingTry = onboarding("onboarding-try", step: .tryIt, trusted: true)
        static let onboardingTryHolding = onboarding("onboarding-try-holding", step: .tryIt, trusted: true) {
            .fixed(target: PreviewOnboarding.safari, held: .option)
        }
        static let onboardingTryNothingOpen = onboarding(
            "onboarding-try-nothing-open", step: .tryIt, trusted: true
        ) {
            .fixed(target: PreviewOnboarding.finder, othersOpen: false)
        }
        static let onboardingTryNoAccess = onboarding("onboarding-try-no-access", step: .tryIt)
        static let onboardingTryDone = onboarding(
            "onboarding-try-done", step: .tryIt, trusted: true, panelOpened: true)
        static let onboardingDone = onboarding("onboarding-done", step: .done, trusted: true)

        // Palette lists

        static let paletteFinder = palette("palette-finder", PaletteOptions())
        static let paletteSafari = palette("palette-safari", PaletteOptions(app: "safari"))
        static let paletteXcode = palette("palette-xcode", PaletteOptions(app: "xcode"))
        static let paletteFresh = palette("palette-empty-search", PaletteOptions(learned: false))
        static let paletteMatches = palette("palette-search-matches", PaletteOptions(query: "new f"))
        static let paletteAproposRows = palette(
            "palette-apropos-rows", PaletteOptions(app: "safari", query: "command"))

        // Palette states

        static let paletteNoResults = palette("palette-no-results", PaletteOptions(query: "zzqx"))
        static let paletteLoading = palette("palette-loading", PaletteOptions(menu: .loading))
        static let palettePermission = palette("palette-permission", PaletteOptions(menu: .needsPermission))
        static let paletteReadFailed = palette(
            "palette-read-failed",
            PaletteOptions(
                menu: .failed("The app did not answer in time. Switch back to it and try again.")))
        static let paletteRunFailed = palette("palette-run-failed", PaletteOptions(failedRun: true))
        static let paletteActions = palette("palette-actions", PaletteOptions(actionsOpen: true))
        static let paletteChips = palette("palette-chips", PaletteOptions(chips: true))
        static let paletteUsuallyNext = palette("palette-usually-next", PaletteOptions(predicted: 2))
        static let paletteUsuallyNextOne = palette(
            "palette-usually-next-one", PaletteOptions(app: "safari", predicted: 1))
        static let paletteUsuallyNextFresh = palette(
            "palette-usually-next-fresh", PaletteOptions(learned: false, predicted: 2))

        // Send to

        static let paletteSendRows = palette("palette-send-rows", PaletteOptions(app: "safari", send: .rows))
        static let paletteSendList = palette("palette-send-list", PaletteOptions(app: "safari", send: .list))
        static let paletteSendConfirm = palette("palette-send-confirm", PaletteOptions(app: "safari", send: .confirm))
        static let paletteSendFailed = palette("palette-send-failed", PaletteOptions(app: "safari", send: .failure))
        static let paletteSendFiles = palette("palette-send-files", PaletteOptions(app: "finder", send: .list))

        // Sequences

        static let paletteSequenceRow = palette(
            "palette-sequence-row", PaletteOptions(app: "safari", sequence: .row))
        static let paletteSequenceDraft = palette(
            "palette-sequence-draft", PaletteOptions(app: "safari", sequence: .level))
        static let paletteSequenceMenus = palette(
            "palette-sequence-menus", PaletteOptions(app: "safari", sequence: .menus))
        static let paletteSequenceMissing = palette(
            "palette-sequence-missing", PaletteOptions(app: "safari", sequence: .menusMissing))
        static let paletteSequenceConfirm = palette(
            "palette-sequence-confirm", PaletteOptions(app: "safari", sequence: .confirm))
        static let paletteSequenceAsk = palette(
            "palette-sequence-ask", PaletteOptions(app: "safari", sequence: .ask))
        static let paletteSequenceFailed = palette(
            "palette-sequence-failed", PaletteOptions(app: "safari", sequence: .failure, sequenceFails: true))
        static let paletteSequenceSave = palette(
            "palette-sequence-save", PaletteOptions(app: "safari", sequence: .save))
        static let paletteSequenceSaveQuick = palette(
            "palette-sequence-save-quick", PaletteOptions(app: "safari", sequence: .saveQuick))
        static let paletteSequenceSaveSearch = palette(
            "palette-sequence-save-search", PaletteOptions(app: "safari", sequence: .saveSearch))
        static let paletteSequenceSaveCustom = palette(
            "palette-sequence-save-custom", PaletteOptions(app: "safari", sequence: .saveCustom))
        static let paletteSequenceSaveNoMatch = palette(
            "palette-sequence-save-no-match", PaletteOptions(app: "safari", sequence: .saveNoMatch))
        static let paletteSequenceSaveGrid = palette(
            "palette-sequence-save-grid", PaletteOptions(app: "safari", sequence: .saveGrid))
        static let paletteSequenceSaved = palette(
            "palette-sequence-saved", PaletteOptions(app: "safari", sequence: .saved))

        // Palette appearance settings

        static let paletteCompact = palette("palette-compact", PaletteOptions(size: .compact))
        static let paletteDefault = palette("palette-default", PaletteOptions(size: .standard))
        static let paletteLarge = palette("palette-large", PaletteOptions(size: .large))
        static let paletteGlyphs = palette("palette-icons-glyph", PaletteOptions(icons: .glyph))
        static let paletteAppLogo = palette("palette-icons-app-logo", PaletteOptions(icons: .appLogo))
        static let paletteNoIcons = palette("palette-icons-none", PaletteOptions(icons: .none))

        // Menu bar menu

        // MARK: Recording

        private struct FakePermissions: RecordingPermissionBackend {
            var accessibility: Bool
            var inputMonitoring: Bool
            func accessibilityGranted() -> Bool { accessibility }
            func inputMonitoringGranted() -> Bool { inputMonitoring }
            func requestAccessibility() {}
            func requestInputMonitoring() {}
        }

        @MainActor
        private static func recordingModel(
            _ phase: RecordingModel.Phase, accessibility: Bool = true, inputMonitoring: Bool = true,
            elapsed: TimeInterval = 0, steps: Int = 0, paused: Bool = false
        ) -> RecordingModel {
            let source = RecordingPermissionStatus(accessibility: accessibility, inputMonitoring: inputMonitoring)
            let model = RecordingModel(
                permission: RecordingPermission(
                    backend: FakePermissions(accessibility: accessibility, inputMonitoring: inputMonitoring)),
                makeRecorder: { fatalError("a preview never records") },
                makeReview: { RecordingReview(draft: $0, store: nil, addToDraft: { _, _ in .refused("preview") }) },
                openURL: { _ in })
            model.seed(phase: phase, status: source, elapsed: elapsed, stepCount: steps, pausedForSecureInput: paused)
            return model
        }

        private static func recordingBar(
            _ id: String, _ phase: RecordingModel.Phase, elapsed: TimeInterval = 0, steps: Int = 0,
            paused: Bool = false, height: CGFloat = 110
        ) -> PreviewScene {
            PreviewScene(id: id, size: CGSize(width: 520, height: height), backdrop: true) {
                AnyView(
                    RecordingBarView(
                        model: recordingModel(phase, elapsed: elapsed, steps: steps, paused: paused),
                        stopKeys: RecordingCoordinator.stopCombo.caps, actions: RecordingActions())
                        .frame(maxWidth: .infinity, maxHeight: .infinity))
            }
        }

        static let recordingLive = recordingBar("recording-live", .recording, elapsed: 42, steps: 3)
        static let recordingEnding = recordingBar("recording-ending", .recording, elapsed: 281, steps: 12)
        static let recordingPaused = recordingBar("recording-paused", .recording, elapsed: 65, steps: 4, paused: true)
        static let recordingDone = recordingBar(
            "recording-done",
            .finished(
                RecordingOutcome(
                    steps: 4,
                    message: "Recorded 4 steps, now in your draft. What you typed was not recorded.",
                    addedToDraft: true)), height: 130)
        static let recordingEmpty = recordingBar(
            "recording-empty",
            .finished(
                RecordingOutcome(
                    steps: 0,
                    message: "Nothing was recorded. Menu items you click and shortcuts you press are recorded.",
                    addedToDraft: false)), height: 120)

        private static func recordingPermission(
            _ id: String, accessibility: Bool, inputMonitoring: Bool
        ) -> PreviewScene {
            PreviewScene(id: id, size: RecordingPermissionView.size, backdrop: false) {
                AnyView(
                    RecordingPermissionView(
                        model: recordingModel(
                            .needsPermission, accessibility: accessibility, inputMonitoring: inputMonitoring),
                        actions: RecordingActions()))
            }
        }

        private static func recordingReview(
            _ id: String, name: String = "", checked: Bool = false, problem: Bool = false
        ) -> PreviewScene {
            PreviewScene(id: id, size: RecordingReviewView.size, backdrop: false) {
                let review = RecordingReview(
                    draft: .previewSample(), suggestedName: name, store: nil,
                    dryRun: { backend, _ in
                        let results = backend.steps.enumerated().map { offset, step in
                            StepDryResult(
                                step: offset + 1, stepID: step.id, matchedKind: offset == 1 ? .menuPath : .shortcut,
                                isDegraded: offset == 1, isEnabled: true, failure: offset == 2 ? .notFound : nil,
                                attempts: [])
                        }
                        return StepDryRunReport(results: results, health: .broken, blocked: nil)
                    },
                    addToDraft: { _, _ in .refused("preview") })
                if checked { review.check() }
                return AnyView(RecordingReviewView(review: review))
            }
        }

        static let recordingReview = recordingReview("recording-review")
        static let recordingReviewChecked = recordingReview("recording-review-checked", name: "Tidy Finder", checked: true)

        static let recordingPermissionNone = recordingPermission(
            "recording-permission", accessibility: false, inputMonitoring: false)
        static let recordingPermissionOne = recordingPermission(
            "recording-permission-one", accessibility: true, inputMonitoring: false)
        static let recordingPermissionAll = recordingPermission(
            "recording-permission-ready", accessibility: true, inputMonitoring: true)

        static let menuBar = PreviewScene(id: "menubar-menu", size: CGSize(width: 360, height: 460), backdrop: true) {
            AnyView(
                MenuPopoverPreview(
                    app: DebugFixtures.targetApp(named: "finder"), chips: ["Projects", "3 items"],
                    recents: MenuBarMenuPreview.sampleRecents, hasAccess: true, pending: 0))
        }
        static let menuBarFresh = PreviewScene(
            id: "menubar-menu-no-access", size: CGSize(width: 360, height: 400), backdrop: true
        ) {
            AnyView(MenuPopoverPreview(app: nil, chips: [], recents: [], hasAccess: false, pending: 2))
        }

        // Settings

        static let settingsGeneral = settings("settings-general", page: .general)
        static let settingsDestinations = settings("settings-destinations", page: .destinations)
        static let settingsPrediction = settings(
            "settings-prediction", page: .prediction, prepare: { controller in
                let app = "com.apple.dt.Xcode"
                let test = CommandID.base(bundleID: app, path: ["Product"], title: "Run Tests")
                let commit = CommandID.base(bundleID: app, path: ["Source Control"], title: "Commit")
                let engine = controller.usage.prediction
                for day in 0..<9 {
                    let at = Date().addingTimeInterval(-Double(day) * 86_400 - 3600)
                    engine.recordRun(test, title: "Run Tests", app: app, at: at)
                    engine.recordRun(commit, title: "Commit", app: app, at: at.addingTimeInterval(45))
                }
            })
        static let settingsIntegrations = settings(
            "settings-integrations", page: .integrations, prepare: { controller in
                guard
                    (try? controller.userCommands.create(
                        UserCommand(
                            title: "Shout selection", aliases: ["up"], requires: [.selectedText],
                            backend: .shell(ShellBackend(executable: "/usr/bin/say", arguments: [], standardInput: .text)),
                            output: .none, allowFromURL: true))) != nil
                else { return }
                controller.externalLog.record(action: "run", command: "Shout selection", result: .ran)
                controller.externalLog.record(action: "open", result: .ran)
            })
        static let settingsShortcuts = settings("settings-shortcuts", page: .shortcuts)
        static let settingsShortcutsItems = settings("settings-shortcuts-items", page: .shortcuts, prepare: { controller in
            let store = controller.usage.store
            let finder = CommandID(rawValue: "com.apple.finder|file>new folder")
            let tabs = CommandID(rawValue: "com.apple.safari|file>close other tabs")
            let info = CommandID(rawValue: "com.apple.finder|file>get info")
            store.listForCustomizing(finder, title: "New Folder", appName: "Finder")
            store.setAliases(["nf"], for: finder)
            store.setHotKey(HotKeyCombo(keyCode: 45, modifiers: [.control, .option]), for: finder)
            store.listForCustomizing(tabs, title: "Close Other Tabs", appName: "Safari")
            store.setAliases(["cot"], for: tabs)
            store.listForCustomizing(info, title: "Get Info", appName: "Finder")
        })
        static let settingsCommandsEmpty = settings("settings-commands-empty", page: .commands)
        static let settingsCommands = settings(
            "settings-commands", page: .commands, prepare: { controller in
                let sample: [(String, String, String, String?, HotKeyCombo?, CommandReview)] = [
                    ("Open in Terminal here", "folder", "terminal", "here", HotKeyCombo(keyCode: 17, modifiers: [.control, .option]), .approved),
                    ("Shout selection", "textformat", "shout", nil, nil, .approved),
                    ("Weekly report", "doc.text", "report", "wr", nil, .pending),
                ]
                for (title, symbol, _, alias, hotkey, review) in sample {
                    guard let template = try? ActionTemplate("{directory}") else { continue }
                    let backend = ActionBackend.shell(
                        ShellBackend(
                            executable: "/usr/bin/open", arguments: [template], standardInput: nil,
                            workingDirectory: .directory))
                    _ = try? controller.userCommands.create(
                        UserCommand(
                            title: title, symbol: symbol, aliases: alias.map { [$0] } ?? [], requires: [.folder], backend: backend,
                            hotkey: hotkey, review: review))
                }
            })
        static let settingsAppearance = settings("settings-appearance", page: .appearance)
        static let settingsContext = settings("settings-context", page: .context) {
            $0.setChip(.folder, shown: true)
            $0.setChip(.branch, shown: true)
        }
        static let settingsPrivacy = settings("settings-privacy-and-data", page: .privacyAndData) {
            $0.ignoreList = ["com.apple.keychainaccess"]
        }
        static let settingsPrivacyAllowed = settings(
            "settings-privacy-and-data-allowed", page: .privacyAndData, trusted: true, app: nil)
        static let settingsUpdates = settings("settings-updates", page: .updates)
        static let settingsAbout = settings("settings-about", page: .about)
        static let settingsSearch = settings("settings-sidebar-search", page: .general, query: "shortcut")

        /// Every scene, in the order the renderer writes them.
        static let all: [PreviewScene] = [
            paletteFinder, paletteSafari, paletteXcode, paletteFresh, paletteMatches, paletteAproposRows, paletteNoResults, paletteLoading,
            palettePermission, paletteReadFailed, paletteRunFailed, paletteActions, paletteChips, paletteUsuallyNext,
            paletteUsuallyNextOne,
            paletteUsuallyNextFresh, paletteSendRows, paletteSendList, paletteSendConfirm, paletteSendFailed,
            paletteSendFiles, paletteSequenceRow, paletteSequenceDraft, paletteSequenceMenus, paletteSequenceMissing, recordingLive, recordingEnding, recordingPaused, recordingDone, recordingEmpty, recordingReview, recordingReviewChecked, recordingPermissionNone, recordingPermissionOne, recordingPermissionAll, paletteSequenceConfirm, paletteSequenceAsk,
            paletteSequenceFailed, paletteSequenceSave, paletteSequenceSaveQuick, paletteSequenceSaveSearch,
            paletteSequenceSaveCustom, paletteSequenceSaveNoMatch, paletteSequenceSaveGrid, paletteSequenceSaved, paletteCompact,
            paletteDefault, paletteLarge, paletteGlyphs, paletteAppLogo, paletteNoIcons, menuBar, menuBarFresh,
            settingsGeneral, settingsCommands, settingsCommandsEmpty, settingsShortcuts, settingsShortcutsItems, settingsIntegrations, settingsPrediction, settingsDestinations, settingsAppearance, settingsContext, settingsPrivacy, settingsPrivacyAllowed,
            settingsUpdates, settingsAbout, settingsSearch, onboardingWelcome, onboardingPermission,
            onboardingPermissionHelp, onboardingPermissionAllowed, onboardingTry, onboardingTryHolding,
            onboardingTryNothingOpen, onboardingTryNoAccess, onboardingTryDone, onboardingDone,
        ]
    }

    /// The Mac the onboarding stage sees in previews: a front app with the commands its menus really have, read once
    /// from Safari and Finder and kept here so a preview never reads a running app.
    @MainActor
    enum PreviewOnboarding {
        static var safari: StageApp {
            StageApp(
                name: "Safari", bundleID: "com.apple.Safari",
                icon: StageSamples.icon("com.apple.Safari"), pid: 1,
                rows: [
                    StageRow(title: "New Window", subtitle: "File", symbol: "macwindow.badge.plus", caps: ["⌘", "N"]),
                    StageRow(
                        title: "New Private Window", subtitle: "File", symbol: "hand.raised",
                        caps: ["⇧", "⌘", "N"]),
                    StageRow(title: "Open Location", subtitle: "File", symbol: "link", caps: ["⌘", "L"]),
                    StageRow(title: "Close Tab", subtitle: "File", symbol: "xmark", caps: ["⌘", "W"]),
                ])
        }

        static var finder: StageApp {
            StageApp(
                name: "Finder", bundleID: "com.apple.finder",
                icon: StageSamples.icon("com.apple.finder"), pid: 2)
        }
    }

    /// A scene in dark and light, side by side. Each side owns its models, built once when the preview starts.
    struct PairedPreview: View {
        let scene: PreviewScene
        @State private var dark: AnyView
        @State private var light: AnyView

        init(_ scene: PreviewScene) {
            self.scene = scene
            _dark = State(initialValue: scene.make())
            _light = State(initialValue: scene.make())
        }

        var body: some View {
            HStack(spacing: 0) {
                scene.cell(.dark, view: dark)
                scene.cell(.light, view: light)
            }
        }
    }

    // MARK: Palette lists

    #Preview("Palette, Finder") { PairedPreview(PreviewCatalog.paletteFinder) }
    #Preview("Palette, Safari") { PairedPreview(PreviewCatalog.paletteSafari) }
    #Preview("Palette, Xcode") { PairedPreview(PreviewCatalog.paletteXcode) }
    #Preview("Palette, empty search") { PairedPreview(PreviewCatalog.paletteFresh) }
    #Preview("Palette, search with matches") { PairedPreview(PreviewCatalog.paletteMatches) }

    // MARK: Palette states

    #Preview("Palette, no results") { PairedPreview(PreviewCatalog.paletteNoResults) }
    #Preview("Palette, loading") { PairedPreview(PreviewCatalog.paletteLoading) }
    #Preview("Palette, permission missing") { PairedPreview(PreviewCatalog.palettePermission) }
    #Preview("Palette, menus could not be read") { PairedPreview(PreviewCatalog.paletteReadFailed) }
    #Preview("Palette, command failed") { PairedPreview(PreviewCatalog.paletteRunFailed) }
    #Preview("Palette, actions popover") { PairedPreview(PreviewCatalog.paletteActions) }
    #Preview("Palette, context chips on") { PairedPreview(PreviewCatalog.paletteChips) }
    #Preview("Palette, Usually next") { PairedPreview(PreviewCatalog.paletteUsuallyNext) }
    #Preview("Palette, Usually next, one row") { PairedPreview(PreviewCatalog.paletteUsuallyNextOne) }
    #Preview("Palette, Usually next, no history") { PairedPreview(PreviewCatalog.paletteUsuallyNextFresh) }

    // MARK: Send to

    #Preview("Palette, send to rows") { PairedPreview(PreviewCatalog.paletteSendRows) }
    #Preview("Palette, send to list") { PairedPreview(PreviewCatalog.paletteSendList) }
    #Preview("Palette, send to, confirm") { PairedPreview(PreviewCatalog.paletteSendConfirm) }
    #Preview("Palette, send to, failed") { PairedPreview(PreviewCatalog.paletteSendFailed) }
    #Preview("Palette, send files") { PairedPreview(PreviewCatalog.paletteSendFiles) }

    // MARK: Sequences

    #Preview("Palette, Apropos rows when searching") { PairedPreview(PreviewCatalog.paletteAproposRows) }
    #Preview("Palette, sequence draft row") { PairedPreview(PreviewCatalog.paletteSequenceRow) }
    #Preview("Palette, sequence draft level") { PairedPreview(PreviewCatalog.paletteSequenceDraft) }
    #Preview("Palette, sequence draft, menu items") { PairedPreview(PreviewCatalog.paletteSequenceMenus) }
    #Preview("Palette, sequence, confirm") { PairedPreview(PreviewCatalog.paletteSequenceConfirm) }
    #Preview("Palette, sequence, question") { PairedPreview(PreviewCatalog.paletteSequenceAsk) }
    #Preview("Palette, sequence, failed") { PairedPreview(PreviewCatalog.paletteSequenceFailed) }
    #Preview("Palette, sequence, save as command") { PairedPreview(PreviewCatalog.paletteSequenceSave) }
    #Preview("Palette, sequence, symbol row") { PairedPreview(PreviewCatalog.paletteSequenceSaveQuick) }
    #Preview("Palette, sequence, symbol search") { PairedPreview(PreviewCatalog.paletteSequenceSaveSearch) }
    #Preview("Palette, sequence, symbol typed by name") { PairedPreview(PreviewCatalog.paletteSequenceSaveCustom) }
    #Preview("Palette, sequence, symbol no match") { PairedPreview(PreviewCatalog.paletteSequenceSaveNoMatch) }
    #Preview("Palette, sequence, symbol grid") { PairedPreview(PreviewCatalog.paletteSequenceSaveGrid) }
    #Preview("Palette, sequence, saved") { PairedPreview(PreviewCatalog.paletteSequenceSaved) }

    // MARK: Interface size and row icons

    #Preview("Palette, Compact") { PairedPreview(PreviewCatalog.paletteCompact) }
    #Preview("Palette, Default") { PairedPreview(PreviewCatalog.paletteDefault) }
    #Preview("Palette, Large") { PairedPreview(PreviewCatalog.paletteLarge) }
    #Preview("Palette, glyph icons") { PairedPreview(PreviewCatalog.paletteGlyphs) }
    #Preview("Palette, app logo icons") { PairedPreview(PreviewCatalog.paletteAppLogo) }
    #Preview("Palette, no icons") { PairedPreview(PreviewCatalog.paletteNoIcons) }

    // MARK: Menu bar menu

    #Preview("Menu bar menu") { PairedPreview(PreviewCatalog.menuBar) }
    #Preview("Menu bar menu, no access") { PairedPreview(PreviewCatalog.menuBarFresh) }

    // MARK: Settings

    #Preview("Settings, General") { PairedPreview(PreviewCatalog.settingsGeneral) }
    #Preview("Settings, Appearance") { PairedPreview(PreviewCatalog.settingsAppearance) }
    #Preview("Settings, Context") { PairedPreview(PreviewCatalog.settingsContext) }
    #Preview("Settings, Privacy and data") { PairedPreview(PreviewCatalog.settingsPrivacy) }
    #Preview("Settings, Privacy and data, access allowed") { PairedPreview(PreviewCatalog.settingsPrivacyAllowed) }
    #Preview("Settings, Updates") { PairedPreview(PreviewCatalog.settingsUpdates) }
    #Preview("Settings, About") { PairedPreview(PreviewCatalog.settingsAbout) }
    #Preview("Settings, sidebar search") { PairedPreview(PreviewCatalog.settingsSearch) }

    // MARK: Onboarding

    #Preview("Onboarding, welcome") { PairedPreview(PreviewCatalog.onboardingWelcome) }
    #Preview("Onboarding, permission") { PairedPreview(PreviewCatalog.onboardingPermission) }
    #Preview("Onboarding, permission, not in the list") { PairedPreview(PreviewCatalog.onboardingPermissionHelp) }
    #Preview("Onboarding, permission, allowed") { PairedPreview(PreviewCatalog.onboardingPermissionAllowed) }
    #Preview("Onboarding, try it") { PairedPreview(PreviewCatalog.onboardingTry) }
    #Preview("Onboarding, try it, holding Option") { PairedPreview(PreviewCatalog.onboardingTryHolding) }
    #Preview("Onboarding, try it, only Finder open") { PairedPreview(PreviewCatalog.onboardingTryNothingOpen) }
    #Preview("Onboarding, try it, no access") { PairedPreview(PreviewCatalog.onboardingTryNoAccess) }
    #Preview("Onboarding, try it, worked") { PairedPreview(PreviewCatalog.onboardingTryDone) }
    #Preview("Onboarding, done") { PairedPreview(PreviewCatalog.onboardingDone) }
#endif
