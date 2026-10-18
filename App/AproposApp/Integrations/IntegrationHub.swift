import Foundation

/// Gives code the system starts on its own (App Intents) a way to reach the running app's controller. Set once at
/// launch; nil in previews and tests, where intents report that Apropos is not running.
@MainActor
enum IntegrationHub {
    static var controller: AppController?
}
