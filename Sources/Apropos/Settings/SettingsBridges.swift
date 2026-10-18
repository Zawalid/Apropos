import Foundation

/// Typed views of the settings other parts of the package consume, so they never touch setting ids.
extension SettingsStore {
    /// The context privacy rules as the settings currently describe them. Master switch off disables every app
    /// by callers checking `bool(.contextSensing)` before asking for a snapshot; this only maps the lists.
    public func contextPrivacy() -> ContextPrivacy {
        let disabled = Set(stringList(.contextDisabledApps)).union(stringList(.contextIgnoreList))
        return ContextPrivacy(disabledBundleIDs: disabled)
    }

    /// The chips to show, in display order, as context kinds.
    public func visibleContextKinds() -> [ContextKind] {
        let chosen = Set(stringList(.contextChips))
        return ContextKind.allCases.filter { chosen.contains($0.rawValue) }
    }
}
