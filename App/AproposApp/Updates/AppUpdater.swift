import AppKit
import Observation
import Sparkle

/// In-app updates through Sparkle. The feed is the appcast attached to the latest GitHub release. Every update is checked
/// against the EdDSA public key in the app's Info.plist before anything is installed, and Sparkle always shows the person
/// what is new and waits for "Install Update". Checks are off until the person turns them on in Settings.
///
/// Until the project has a signing key pair (docs/updates.md), `SUPublicEDKey` holds a placeholder: the updater is then
/// not started at all and `isConfigured` is false, so a build never talks to a server it cannot verify.
@MainActor
@Observable
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    private var checksOn = false

    /// Whether this build has what Sparkle needs: a feed address and a real public key.
    let isConfigured: Bool

    /// `startingUpdater` is false in automated runs, which must never touch the update preferences or the network.
    init(startingUpdater: Bool = true) {
        isConfigured = Self.hasPublicKey
        super.init()
        guard isConfigured else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater, updaterDelegate: self, userDriverDelegate: nil)
        checksOn = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    /// Whether Apropos asks GitHub once a day if a newer version exists. Off until the person turns it on.
    var automaticallyChecks: Bool {
        get { checksOn }
        set {
            checksOn = newValue
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Asks now, whether or not the automatic check is on. Without a key it explains why nothing happens.
    func checkNow() {
        guard let controller else {
            let alert = NSAlert()
            alert.messageText = "Updates are not set up in this build"
            alert.informativeText =
                "This build has no update signing key, so it cannot check for or install updates. Download a release from GitHub instead."
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    private static var hasPublicKey: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("REPLACE")
    }

    #if DEBUG
        /// Debug builds only: point the updater at a local appcast to try an update without publishing one.
        nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
            ProcessInfo.processInfo.environment["APROPOS_FEED_URL"]
        }
    #endif
}
