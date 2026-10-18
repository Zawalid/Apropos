import Observation

/// Presentation state the views animate from. The panel itself is shown and hidden at once; this drives the spring.
@MainActor
@Observable
final class PanelState {
    var isPresented = false
    /// Bumped on every open so the search field takes focus again.
    var focusToken = 0
}
