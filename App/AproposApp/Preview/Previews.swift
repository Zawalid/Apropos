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

        private static func palette(_ id: String, _ options: PaletteOptions) -> PreviewScene {
            PreviewScene(id: id, size: palette, backdrop: true) {
                AnyView(PalettePreviewView(kit: PaletteKit(options)))
            }
        }

        private static func settings(
            _ id: String, page: SettingPage, query: String = "", trusted: Bool = false, app: String? = "finder",
            customize: @escaping @MainActor (SettingsModel) -> Void = { _ in }
        ) -> PreviewScene {
            PreviewScene(id: id, size: settings) {
                let controller = PreviewStores.controller(trusted: trusted, app: app, customize: customize)
                let navigation = SettingsNavigation()
                navigation.select(page)
                return AnyView(
                    SettingsRoot(
                        controller: controller, settings: controller.settings, navigation: navigation,
                        initialQuery: query))
            }
        }

        // Palette lists

        static let paletteFinder = palette("palette-finder", PaletteOptions())
        static let paletteSafari = palette("palette-safari", PaletteOptions(app: "safari"))
        static let paletteXcode = palette("palette-xcode", PaletteOptions(app: "xcode"))
        static let paletteFresh = palette("palette-empty-search", PaletteOptions(learned: false))
        static let paletteMatches = palette("palette-search-matches", PaletteOptions(query: "new f"))

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

        // Palette appearance settings

        static let paletteCompact = palette("palette-compact", PaletteOptions(size: .compact))
        static let paletteDefault = palette("palette-default", PaletteOptions(size: .standard))
        static let paletteLarge = palette("palette-large", PaletteOptions(size: .large))
        static let paletteGlyphs = palette("palette-icons-glyph", PaletteOptions(icons: .glyph))
        static let paletteAppLogo = palette("palette-icons-app-logo", PaletteOptions(icons: .appLogo))
        static let paletteNoIcons = palette("palette-icons-none", PaletteOptions(icons: .none))

        // Menu bar menu

        static let menuBar = PreviewScene(id: "menubar-menu", size: CGSize(width: 340, height: 420), backdrop: true) {
            AnyView(
                MenuBarMenuPreview(
                    app: DebugFixtures.targetApp(named: "finder"), chips: ["Projects", "3 items"],
                    recents: MenuBarMenuPreview.sampleRecents, hasAccess: true))
        }
        static let menuBarFresh = PreviewScene(
            id: "menubar-menu-no-access", size: CGSize(width: 340, height: 360), backdrop: true
        ) {
            AnyView(MenuBarMenuPreview(app: nil, chips: [], recents: [], hasAccess: false))
        }

        // Settings

        static let settingsGeneral = settings("settings-general", page: .general)
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
            paletteFinder, paletteSafari, paletteXcode, paletteFresh, paletteMatches, paletteNoResults, paletteLoading,
            palettePermission, paletteReadFailed, paletteRunFailed, paletteActions, paletteChips, paletteCompact,
            paletteDefault, paletteLarge, paletteGlyphs, paletteAppLogo, paletteNoIcons, menuBar, menuBarFresh,
            settingsGeneral, settingsAppearance, settingsContext, settingsPrivacy, settingsPrivacyAllowed,
            settingsUpdates, settingsAbout, settingsSearch,
        ]
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
#endif
