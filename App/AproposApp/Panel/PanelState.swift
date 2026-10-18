import Observation

/// Presentation state the views read. The panel appears and disappears at once; this only tracks the actions popover
/// and when the search field should take focus again.
@MainActor
@Observable
final class PanelState {
    /// Bumped on every open so the search field takes focus again.
    var focusToken = 0
    var actionsOpen = false
    var actionIndex = 0
    /// Which field of the save-as-command form takes the keyboard: 0 name, 1 alias, 2 symbol.
    var formField = 0
}
