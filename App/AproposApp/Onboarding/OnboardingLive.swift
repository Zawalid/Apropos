import AppKit
import Apropos
import Observation

/// One row of a palette miniature on the onboarding stage: what the real palette would list.
struct StageRow: Identifiable, Equatable, Sendable {
    let title: String
    let subtitle: String
    let symbol: String
    let caps: [String]
    /// A context action (accent tile) rather than a menu command.
    var isAction = false

    var id: String { subtitle + "/" + title }
}

/// An app as the stage shows it: icon, name and the rows the palette would offer there.
struct StageApp: Equatable {
    let name: String
    let bundleID: String?
    let icon: NSImage?
    var pid: pid_t = 0
    /// Context shown in the palette's header for this app, for example `3 selected`.
    var context: String?
    var rows: [StageRow] = []

    static func == (lhs: StageApp, rhs: StageApp) -> Bool {
        lhs.name == rhs.name && lhs.bundleID == rhs.bundleID && lhs.pid == rhs.pid && lhs.rows == rhs.rows
            && lhs.context == rhs.context
    }
}

/// What the stage knows about the person's Mac while the guide is open: the app Apropos would open over, a few of its
/// real menu commands (read through Accessibility once access is granted), whether any app besides Finder is open, and
/// which modifier keys are held right now. Nothing here leaves the Mac or is stored.
///
/// Previews build it with `fixed`, so they never look at running apps, read menus or install event monitors.
@MainActor
@Observable
final class OnboardingLive {
    /// The app the palette would open over: the last app in front that is not Apropos.
    private(set) var target: StageApp?
    /// True when an app other than Apropos and Finder is running, so there is something worth trying it in.
    private(set) var othersOpen: Bool
    /// True while the target's menus are being read.
    private(set) var reading = false
    /// The modifiers of the shortcut held down right now.
    private(set) var held: ModifierSet = []
    private(set) var launching = false

    @ObservationIgnored private let isLive: Bool
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var readPID: pid_t?

    static let helperURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    static let helperName = "TextEdit"

    private init(isLive: Bool, target: StageApp?, othersOpen: Bool, held: ModifierSet) {
        self.isLive = isLive
        self.target = target
        self.othersOpen = othersOpen
        self.held = held
    }

    /// Follows the real Mac. The first guess at the target is the app in front when the guide opens, which is still the
    /// app the person came from, because the window activates after the model is made.
    static func live() -> OnboardingLive {
        let live = OnboardingLive(isLive: true, target: nil, othersOpen: false, held: [])
        live.adopt(NSWorkspace.shared.frontmostApplication)
        live.refreshOthers()
        return live
    }

    /// A fixed picture of the Mac, for previews.
    static func fixed(target: StageApp?, othersOpen: Bool = true, held: ModifierSet = []) -> OnboardingLive {
        OnboardingLive(isLive: false, target: target, othersOpen: othersOpen, held: held)
    }

    // MARK: Following apps

    func start() {
        guard isLive, tokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    self?.adopt(app)
                    self?.launching = false
                }
            })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refreshOthers() }
                })
        }
    }

    func stop() {
        for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        tokens.removeAll()
        stopWatchingKeys()
    }

    private func adopt(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        guard app.processIdentifier != target?.pid else { return }
        target = StageApp(
            name: app.localizedName ?? app.bundleIdentifier ?? "App", bundleID: app.bundleIdentifier, icon: app.icon,
            pid: app.processIdentifier)
        readPID = nil
    }

    private func refreshOthers() {
        let own = Bundle.main.bundleIdentifier
        othersOpen = NSWorkspace.shared.runningApplications.contains {
            $0.activationPolicy == .regular && $0.bundleIdentifier != own && $0.bundleIdentifier != "com.apple.finder"
        }
    }

    /// Opens a simple app with menus, so the step can be completed on a Mac where only Finder is open.
    func openHelper() {
        guard isLive else { return }
        launching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Self.helperURL, configuration: configuration) { _, error in
            if error != nil { Task { @MainActor [weak self] in self?.launching = false } }
        }
    }

    // MARK: Reading menus

    /// Reads a few of the target's real menu commands. Only with Accessibility access, only once per app.
    func readRows(trusted: Bool) async {
        guard isLive, trusted, let app = target, app.pid != 0, readPID != app.pid else { return }
        readPID = app.pid
        reading = true
        let pid = app.pid
        let bundleID = app.bundleID
        let name = app.name
        let rows = await Task.detached(priority: .userInitiated) { () -> [StageRow] in
            guard let menuBar = try? AXMenuReader().readMenuBar(pid: pid) else { return [] }
            let commands = MenuCommandMapper.commands(from: menuBar, bundleID: bundleID)
            return Self.pick(commands, appName: name)
        }.value
        guard target?.pid == pid else { return }
        target?.rows = rows
        reading = false
    }

    /// The commands a person would recognise first: enabled, with a shortcut, from the app's working menus.
    nonisolated static func pick(_ commands: [Command], appName: String) -> [StageRow] {
        let skipped: Set<String> = [appName, "Window", "Help"]
        let usable = commands.filter {
            $0.isEnabled && !$0.displayTitle.isEmpty && !skipped.contains($0.path.first ?? "")
        }
        let withKeys = usable.filter { $0.shortcut != nil }
        let chosen = Array((withKeys.count >= 4 ? withKeys : withKeys + usable.filter { $0.shortcut == nil }).prefix(4))
        return chosen.map {
            StageRow(
                title: $0.displayTitle, subtitle: $0.displaySubtitle(appName: appName),
                symbol: CommandDisplay.symbol(for: $0), caps: $0.shortcut?.caps ?? [])
        }
    }

    // MARK: Keys

    /// Lights the shortcut's keys as they are held. Inside the guide a local monitor sees them; with Accessibility
    /// access a global one sees them over other apps too. Only modifier state is read, never a key.
    func watchKeys(trusted: Bool) {
        guard isLive, monitors.isEmpty else { return }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                let flags = event.modifierFlags
                MainActor.assumeIsolated { self?.held = Self.modifiers(flags) }
                return event
            })
        {
            monitors.append(local)
        }
        if trusted,
            let global = NSEvent.addGlobalMonitorForEvents(
                matching: .flagsChanged,
                handler: { [weak self] event in
                    let flags = event.modifierFlags
                    MainActor.assumeIsolated { self?.held = Self.modifiers(flags) }
                })
        {
            monitors.append(global)
        }
    }

    func stopWatchingKeys() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        if isLive { held = [] }
    }

    private nonisolated static func modifiers(_ flags: NSEvent.ModifierFlags) -> ModifierSet {
        var set: ModifierSet = []
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.shift) { set.insert(.shift) }
        if flags.contains(.command) { set.insert(.command) }
        return set
    }
}

// MARK: Samples

/// The apps the welcome step shows the palette in. Real apps every Mac has, with icons read from disk and commands their
/// menus really carry, so the miniature is what the person will see.
enum StageSamples {
    static func apps() -> [StageApp] {
        [finder, safari, notes, mail]
    }

    /// The app's icon from where it is installed. Looked up by bundle id, because a path like /Applications/Safari.app is
    /// a link on recent systems and its icon would carry the alias arrow.
    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }

    static var finder: StageApp {
        StageApp(
            name: "Finder", bundleID: "com.apple.finder", icon: icon("com.apple.finder"),
            context: "3 selected",
            rows: [
                StageRow(title: "Compress 3 Items", subtitle: "File", symbol: "doc.zipper", caps: []),
                StageRow(
                    title: "Copy paths", subtitle: "3 items", symbol: "doc.on.clipboard", caps: [], isAction: true),
                StageRow(title: "New Folder", subtitle: "File", symbol: "folder.badge.plus", caps: ["⇧", "⌘", "N"]),
                StageRow(title: "Get Info", subtitle: "File", symbol: "info.circle", caps: ["⌘", "I"]),
            ])
    }

    static var safari: StageApp {
        StageApp(
            name: "Safari", bundleID: "com.apple.Safari", icon: icon("com.apple.Safari"),
            context: "developer.apple.com",
            rows: [
                StageRow(
                    title: "Copy as Markdown link", subtitle: "This page", symbol: "link", caps: [], isAction: true),
                StageRow(
                    title: "Reopen Last Closed Tab", subtitle: "History", symbol: "arrow.uturn.backward",
                    caps: ["⇧", "⌘", "T"]),
                StageRow(title: "Enter Reader", subtitle: "View", symbol: "doc.plaintext", caps: ["⇧", "⌘", "R"]),
                StageRow(title: "Add Bookmark", subtitle: "Bookmarks", symbol: "bookmark", caps: ["⌘", "D"]),
            ])
    }

    static var notes: StageApp {
        StageApp(
            name: "Notes", bundleID: "com.apple.Notes", icon: icon("com.apple.Notes"),
            context: "Trip ideas",
            rows: [
                StageRow(title: "Checklist", subtitle: "Format", symbol: "checklist", caps: ["⇧", "⌘", "L"]),
                StageRow(title: "Table", subtitle: "Format", symbol: "tablecells", caps: ["⌥", "⌘", "T"]),
                StageRow(title: "Pin Note", subtitle: "File", symbol: "pin", caps: []),
                StageRow(title: "New Note", subtitle: "File", symbol: "square.and.pencil", caps: ["⌘", "N"]),
            ])
    }

    static var mail: StageApp {
        StageApp(
            name: "Mail", bundleID: "com.apple.mail", icon: icon("com.apple.mail"),
            context: "1 message",
            rows: [
                StageRow(
                    title: "Reply All", subtitle: "Message", symbol: "arrowshape.turn.up.left.2", caps: ["⇧", "⌘", "R"]),
                StageRow(title: "Archive", subtitle: "Message", symbol: "archivebox", caps: ["⌃", "⌘", "A"]),
                StageRow(
                    title: "Send to Reminders", subtitle: "This message", symbol: "paperplane", caps: [],
                    isAction: true),
                StageRow(
                    title: "Mark as Unread", subtitle: "Message > Mark", symbol: "envelope.badge",
                    caps: ["⇧", "⌘", "U"]),
            ])
    }
}
