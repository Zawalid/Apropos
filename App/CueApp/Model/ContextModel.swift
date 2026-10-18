import Foundation
import Cue
import Observation

/// The context items shown as chips. Refreshed each time the panel opens, off the main thread: the panel is already
/// on screen by then, and chips appear when the snapshot arrives. When sensing fails or is disabled for the app the
/// snapshot has no items, so only the app chip shows.
@MainActor
@Observable
final class ContextModel {
    private(set) var items: [ContextItem] = []
    private(set) var itemsPID: pid_t?

    @ObservationIgnored private let service: ContextService
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: ContextService = ContextService()) {
        self.service = service
    }

    func refresh(for app: TargetApp?) {
        task?.cancel()
        guard let app else {
            items = []
            itemsPID = nil
            return
        }
        // Another app's context must not linger under this app's chip; the same app keeps its chips until fresh ones arrive.
        if itemsPID != app.pid { items = [] }
        let service = self.service
        task = Task { [weak self] in
            let snapshot = await service.snapshot(for: app)
            guard !Task.isCancelled, let self else { return }
            self.itemsPID = app.pid
            self.items = snapshot.items
        }
    }
}
