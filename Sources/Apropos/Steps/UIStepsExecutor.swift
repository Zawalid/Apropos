import Foundation

/// How the action engine runs a `uiSteps` backend. A value of closures, like `ActionServices` itself, so engine tests
/// can substitute a fake and never touch an app.
public struct UIStepsExecutor: Sendable {
    /// Parameters: the steps, the action id (for the log), the app the command was started in, the action's timeout.
    public var run: @Sendable (UIStepsBackend, String, TargetApp?, TimeInterval) async -> StepRunReport

    public init(run: @escaping @Sendable (UIStepsBackend, String, TargetApp?, TimeInterval) async -> StepRunReport) {
        self.run = run
    }

    /// Replays through Accessibility in the real apps. The privacy list is read from `privacy` at every run.
    public static func live(privacy: @escaping @Sendable () -> ContextPrivacy = { ContextPrivacy.load() })
        -> UIStepsExecutor
    {
        UIStepsExecutor { backend, actionID, target, timeout in
            let replayer = StepReplayer(environment: LiveStepEnvironment(), privacy: privacy)
            // Stop a little before the engine's own timeout so the failure names the step instead of just timing out.
            return await replayer.run(backend, actionID: actionID, target: target, timeout: max(timeout - 0.3, 0.3))
        }
    }

    public static let live = UIStepsExecutor.live()

    /// Runs the steps with this replayer's environment, for tests.
    public static func replaying(with replayer: StepReplayer) -> UIStepsExecutor {
        UIStepsExecutor { backend, actionID, target, timeout in
            await replayer.run(backend, actionID: actionID, target: target, timeout: timeout)
        }
    }
}
