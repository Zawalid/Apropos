import Foundation

/// Settings of one recording.
public struct RecordingConfiguration: Sendable {
    public var limits: RecordingLimits
    public var privacy: ContextPrivacy
    /// Apropos's own bundle identifier: its windows are never recorded, and switching to it ends the recording.
    public var ownBundleID: String

    public init(
        limits: RecordingLimits = RecordingLimits(), privacy: ContextPrivacy = ContextPrivacy(),
        ownBundleID: String = Bundle.main.bundleIdentifier ?? "com.zawalid.apropos"
    ) {
        self.limits = limits
        self.privacy = privacy
        self.ownBundleID = ownBundleID
    }
}

/// Turns capture events into a draft. All the privacy rules of recording live here, in one place:
///
/// - A key press is reduced to a chord only if it could be a menu shortcut (command, control, or a function key) and
///   it is kept only if it matches an enabled menu item of the frontmost app; the stored locators come from the menu
///   item, not from the key. Every other key press is dropped in the same call, and plain typing leaves one flag behind
///   (text was entered), with no count, no timing and no content.
/// - Secure event input, or a password field with the focus or under the pointer, pauses everything. While paused every
///   event is dropped.
/// - Clicks that cannot be found without a position are skipped with a reason, and positions are never stored.
/// - The Apple menu, menus of recent items, other apps' menu bar icons, apps on the privacy list and Apropos's own
///   windows are never recorded.
///
/// Thread-safe: events may arrive on any thread; they are handled one at a time.
public final class RecordingEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let services: RecordingServices
    private let configuration: RecordingConfiguration
    private let log: RecorderLog
    private let permission: RecordingPermission

    private var session: RecordingSession
    private var draft = RecordingDraft()
    private var currentApp: AppIdentity?
    /// One bit: a text key was pressed since the last click, shortcut or app switch.
    private var textRunOpen = false
    /// A password field had the focus; stays set until a tick sees the focus move on.
    private var secureFieldLatched = false

    public init(
        services: RecordingServices, configuration: RecordingConfiguration = RecordingConfiguration(),
        permission: RecordingPermission = RecordingPermission(), log: RecorderLog = .standard
    ) {
        self.services = services
        self.configuration = configuration
        self.log = log
        self.permission = permission
        self.session = RecordingSession(limits: configuration.limits)
    }

    // MARK: Lifecycle

    public var state: RecordingState { lock.withLock { session.state } }
    public var currentDraft: RecordingDraft { lock.withLock { draft } }

    /// Idle to armed, if the permissions allow it.
    @discardableResult
    public func arm() -> RecordingState {
        lock.withLock {
            session.arm(permissions: permission.status())
            return session.state
        }
    }

    /// Armed to recording. Call once the event source is live.
    @discardableResult
    public func beginRecording() -> RecordingState {
        lock.withLock {
            session.start(at: services.system.now())
            if session.state == .recording {
                currentApp = services.system.frontmostApp()
                log.began()
            }
            return session.state
        }
    }

    public func sourceUnavailable() {
        lock.withLock {
            session.sourceUnavailable()
            log.ended(session.state)
        }
    }

    @discardableResult
    public func stop() -> RecordingState {
        lock.withLock {
            session.finish(.stoppedByPerson)
            log.ended(session.state)
            return session.state
        }
    }

    public func cancel() {
        lock.withLock {
            session.cancel()
            log.ended(session.state)
        }
    }

    // MARK: Events

    /// Handles one event. Returns the state afterwards, so a source can stop itself when the recording ends.
    @discardableResult
    public func handle(_ event: CaptureEvent) -> RecordingState {
        lock.withLock {
            let before = session.state
            guard before.isLive else { return before }
            session.tick(at: services.system.now())
            if session.state.isLive { process(event) }
            if session.state != before, session.state.isTerminal { log.ended(session.state) }
            return session.state
        }
    }

    private func process(_ event: CaptureEvent) {
        switch event {
        case .flagsChanged:
            return
        case .tick:
            handleTick()
        case .appActivated(let app):
            handleActivation(app)
        case .keyDown(let chord):
            handleKey(chord)
        case .mouseDown(let point):
            handleMouse(at: point)
        }
    }

    // MARK: Secure input

    /// Updates the pause state. Returns true when it is safe to look at the event.
    private func isSafeToObserve() -> Bool {
        let secure = services.system.isSecureEventInputOn() || secureFieldLatched
        let before = session.state
        session.setSecureInput(secure)
        if before == .recording, session.state == .pausedForSecureInput {
            draft.note(.passwordField)
            log.paused()
        } else if before == .pausedForSecureInput, session.state == .recording {
            log.resumed()
            reconcileFrontmostApp()
        }
        return session.state == .recording
    }

    private func latchSecureField() {
        secureFieldLatched = true
        session.setSecureInput(true)
        draft.note(.passwordField)
        log.paused()
    }

    // MARK: Handlers

    private func handleTick() {
        if secureFieldLatched, let front = services.system.frontmostApp() {
            let focus = services.hitTester.textFocus(in: front)
            if focus != .secure { secureFieldLatched = false }
        }
        guard isSafeToObserve() else { return }
        if services.system.frontmostApp()?.bundleID == configuration.ownBundleID {
            session.frontmostChanged(isApropos: true)
        }
    }

    private func handleActivation(_ app: AppIdentity) {
        if app.bundleID == configuration.ownBundleID {
            session.frontmostChanged(isApropos: true)
            return
        }
        guard isSafeToObserve() else { return }
        textRunOpen = false
        enter(app)
    }

    /// Notes a move to `app`, unless it is where the recording already was.
    private func enter(_ app: AppIdentity) {
        guard currentApp?.pid != app.pid else { return }
        currentApp = app
        if isBlocked(app.bundleID) {
            draft.note(.appOnPrivacyList)
            log.skipped(.appOnPrivacyList)
            return
        }
        draft.appendAppSwitch(bundleID: app.bundleID, name: app.name)
    }

    /// After a pause the frontmost app may have changed without a notification being handled.
    private func reconcileFrontmostApp() {
        if let front = services.system.frontmostApp(), front.bundleID != configuration.ownBundleID {
            enter(front)
        }
    }

    private func isBlocked(_ bundleID: String?) -> Bool {
        configuration.privacy.isDisabled(bundleID) || configuration.privacy.blocksSelection(bundleID)
    }

    private func skip(_ reason: SkipReason) {
        draft.note(reason)
        log.skipped(reason)
    }

    // MARK: Keys

    private func handleKey(_ chord: KeyChord) {
        guard isSafeToObserve() else { return }
        guard let front = services.system.frontmostApp() else { return }
        if front.bundleID == configuration.ownBundleID {
            session.frontmostChanged(isApropos: true)
            return
        }
        if isBlocked(front.bundleID) {
            skip(.appOnPrivacyList)
            return
        }
        if chord.isShortcutCandidate {
            textRunOpen = false
            recordShortcut(chord, in: front)
        } else if chord.keyClass == .text {
            recordTextEntry(in: front)
        }
        // Anything else (Return, arrows, Escape, a lone Shift) is dropped here.
    }

    private func recordShortcut(_ chord: KeyChord, in app: AppIdentity) {
        guard let candidate = chord.shortcut(using: services.keyLayout) else {
            skip(.shortcutNotInMenu)
            return
        }
        let matches = services.menus.menuItems(of: app).filter { $0.shortcut == candidate && $0.isEnabled }
        switch matches.count {
        case 0: skip(.shortcutNotInMenu)
        case 1: addMenuStep(matches[0], in: app, origin: .shortcut)
        default: skip(.ambiguousShortcut)
        }
    }

    private func recordTextEntry(in app: AppIdentity) {
        if textRunOpen { return }
        switch services.hitTester.textFocus(in: app) {
        case .secure:
            latchSecureField()
        case .textInput, .unknown:
            reconcileApp(app)
            guard session.state == .recording else { return }
            draft.append(.textEntered)
            textRunOpen = true
        case .other:
            break
        }
    }

    // MARK: Mouse

    private func handleMouse(at point: CGPoint) {
        guard isSafeToObserve() else { return }
        textRunOpen = false
        guard let front = services.system.frontmostApp() else { return }
        if front.bundleID == configuration.ownBundleID {
            session.frontmostChanged(isApropos: true)
            return
        }
        guard let hit = services.hitTester.hitTest(at: point) else {
            skip(.coordinateOnlyClick)
            return
        }
        if hit.bundleID == configuration.ownBundleID { return }
        if hit.isSecure {
            latchSecureField()
            return
        }
        if isBlocked(hit.bundleID) || isBlocked(front.bundleID) {
            skip(.appOnPrivacyList)
            return
        }
        switch hit.place {
        case .menuBarTitle(let barIndex):
            // Opening a menu is not a step. Opening the Apple menu is noted so the person knows it was refused.
            if barIndex == 0 || StepText.isAppleMenuTitle(hit.title) { skip(.appleMenu) }
        case .menuItem(let path, let barIndex, let ancestors, let hasSubmenu):
            recordMenuClick(
                hit, path: path, barIndex: barIndex, ancestors: ancestors, hasSubmenu: hasSubmenu, front: front)
        case .contextMenuItem:
            skip(.contextMenu)
        case .menuExtra:
            skip(.menuExtra)
        case .window:
            skip(hit.isAddressable ? .controlNotRecordedYet : .coordinateOnlyClick)
        }
    }

    private func recordMenuClick(
        _ hit: HitElement, path: [String], barIndex: Int, ancestors: [String], hasSubmenu: Bool, front: AppIdentity
    ) {
        if barIndex == 0 || path.first.map(StepText.isAppleMenuTitle) == true {
            skip(.appleMenu)
            return
        }
        if path.contains(where: StepText.isRecentMenuTitle)
            || ancestors.contains(where: StepText.isRecentMenuIdentifier)
            || StepText.isRecentMenuIdentifier(hit.identifier)
        {
            skip(.recentItems)
            return
        }
        if hit.pid != front.pid {
            skip(.menuExtra)
            return
        }
        // A submenu header only opens a submenu; a disabled item does nothing.
        if hasSubmenu || !hit.isEnabled { return }
        guard !path.isEmpty else {
            skip(.coordinateOnlyClick)
            return
        }
        if Self.isDocumentNamedWindowItem(path: path, identifier: hit.identifier) {
            skip(.windowMenuDocument)
            return
        }
        let item = StepResolver.MenuItemInfo(
            path: path, identifier: hit.identifier, shortcut: nil, isEnabled: true)
        addMenuStep(item, in: front, origin: .menuClick, advertised: services.menus.menuItems(of: front))
    }

    /// The Window menu lists open documents by name. An item there with nothing but its title to find it by would store
    /// a document name.
    private static func isDocumentNamedWindowItem(path: [String], identifier: String) -> Bool {
        guard path.count == 2, identifier.isEmpty, let menu = path.first else { return false }
        return ["window", "fenetre", "fenster", "ventana", "finestra"].contains(StepText.normalize(menu))
    }

    // MARK: Building steps

    private func reconcileApp(_ app: AppIdentity) {
        if currentApp?.pid != app.pid { enter(app) }
    }

    /// Builds the step for a menu item. `advertised` is the app's menu listing, used to learn the shortcut and
    /// identifier of an item that was clicked.
    private func addMenuStep(
        _ item: StepResolver.MenuItemInfo, in app: AppIdentity, origin: StepOrigin,
        advertised: [StepResolver.MenuItemInfo] = []
    ) {
        var info = item
        if origin == .menuClick, let known = advertised.first(where: { $0.path == item.path }) {
            info = StepResolver.MenuItemInfo(
                path: item.path, identifier: item.identifier.isEmpty ? known.identifier : item.identifier,
                shortcut: known.shortcut, isEnabled: known.isEnabled)
        }
        guard let title = info.path.last else { return }
        reconcileApp(app)
        if isBlocked(app.bundleID) { return }

        var locators: [StepLocator] = []
        if !info.identifier.isEmpty { locators.append(.identifier(info.identifier)) }
        locators.append(.roleTitle(role: StepAX.menuItem, title: title))
        locators.append(.menuPath(info.path))
        if let shortcut = info.shortcut { locators.append(.shortcut(key: shortcut.key, modifiers: shortcut.modifiers)) }

        let words = info.path.joined(separator: " > ")
        let step = UIStep(
            action: .menu, app: app.bundleID, locators: locators, description: "Choose \(words) in \(app.name)")
        guard UIStepsValidator.issues(in: UIStepsBackend(steps: [step]), privacy: configuration.privacy).isEmpty else {
            skip(.notAllowed)
            return
        }
        guard session.acceptStep() else { return }
        draft.append(.step(step, origin: origin))
        log.stepAdded(origin, total: session.stepCount)
    }
}
