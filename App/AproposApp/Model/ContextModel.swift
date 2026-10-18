import Apropos
import Foundation
import Observation

/// The context items shown as chips. Refreshed each time the panel opens, off the main thread: the panel is already
/// on screen by then, and chips appear when the snapshot arrives. When sensing fails or is disabled for the app the
/// snapshot has no items, so only the app chip shows.
@MainActor
@Observable
final class ContextModel {
    private(set) var items: [ContextItem] = []
    private(set) var itemsPID: pid_t?
    /// Which kinds of context the last snapshot found, whether or not a chip shows them. Kinds only, for the run log.
    private(set) var senseKinds: [ContextKind] = []

    @ObservationIgnored private let service: ContextService
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Called on the main actor whenever new items arrive.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when the kinds of context found differ from the last snapshot, so predictions can be asked again.
    @ObservationIgnored var onKindsChange: (() -> Void)?
    @ObservationIgnored private let settings: SettingsModel

    init(settings: SettingsModel, service: ContextService = ContextService()) {
        self.settings = settings
        self.service = service
    }

    /// Shows `items` for the app with `pid` without reading anything, for previews.
    func seed(_ items: [ContextItem], pid: pid_t) {
        task?.cancel()
        self.items = items
        itemsPID = pid
    }

    func refresh(for app: TargetApp?) {
        task?.cancel()
        guard let app, settings.contextSensing else {
            items = []
            senseKinds = []
            itemsPID = nil
            onChange?()
            return
        }
        // Another app's context must not linger under this app's chip; the same app keeps its chips until fresh ones arrive.
        if itemsPID != app.pid {
            items = []
            senseKinds = []
        }
        var service = self.service
        service.privacy = settings.contextPrivacy
        let visible = Set(settings.visibleKinds)
        let sensing = service
        task = Task { [weak self] in
            let snapshot = await sensing.snapshot(for: app)
            guard !Task.isCancelled, let self else { return }
            self.itemsPID = app.pid
            let kinds = snapshot.items.map(\.kind)
            if kinds != self.senseKinds {
                self.senseKinds = kinds
                self.onKindsChange?()
            }
            self.items = snapshot.items.filter { visible.contains($0.kind) }
            self.onChange?()
        }
    }
}
