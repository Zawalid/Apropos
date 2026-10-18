import Foundation

/// Which apps Cue may sense. Everything stays on the Mac; this only narrows what is read.
public struct ContextPrivacy: Equatable, Sendable {
    /// Apps where Cue reads nothing beyond the app name.
    public var disabledBundleIDs: Set<String>
    /// Apps where context is read but the selected text never is.
    public var selectionBlockedBundleIDs: Set<String>

    /// Password managers and similar: their selections are secrets by nature.
    public static let defaultSelectionBlocked: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
    ]

    public init(
        disabledBundleIDs: Set<String> = [],
        selectionBlockedBundleIDs: Set<String> = ContextPrivacy.defaultSelectionBlocked
    ) {
        self.disabledBundleIDs = disabledBundleIDs
        self.selectionBlockedBundleIDs = selectionBlockedBundleIDs
    }

    public func isDisabled(_ bundleID: String?) -> Bool {
        bundleID.map(disabledBundleIDs.contains) ?? false
    }

    public func blocksSelection(_ bundleID: String?) -> Bool {
        bundleID.map(selectionBlockedBundleIDs.contains) ?? false
    }

    // Persistence: a plain string array in UserDefaults, so settings UI can bind to it.
    public static let defaultsKey = "contextDisabledApps"

    public static func load(from defaults: UserDefaults = .standard) -> ContextPrivacy {
        ContextPrivacy(disabledBundleIDs: Set(defaults.stringArray(forKey: defaultsKey) ?? []))
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(disabledBundleIDs.sorted(), forKey: Self.defaultsKey)
    }
}
