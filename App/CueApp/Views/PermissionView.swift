import Cue
import SwiftUI

/// Explains why Cue needs Accessibility access, sends the person to System Settings, and flips to a confirmation the
/// moment access arrives (the model polls, so no restart is needed).
struct PermissionView: View {
    enum Style { case compact, full }

    let permission: AccessibilityPermission
    let style: Style

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if permission.isTrusted {
                granted
            } else {
                missing
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xl)
        .animation(.smooth(duration: 0.25), value: permission.isTrusted)
    }

    private var missing: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: style == .full ? 38 : 28, weight: .light))
                .foregroundStyle(Theme.accentText)
            Text("Cue needs Accessibility access")
                .font(.system(size: style == .full ? 20 : 15, weight: .semibold))
            Text(
                "To list an app's menu commands and run them, macOS requires you to allow Cue under Accessibility. Cue reads menu names only, on this Mac, and nothing leaves it."
            )
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
            VStack(alignment: .leading, spacing: 5) {
                step("1", "Open System Settings, Privacy & Security, Accessibility.")
                step("2", "Turn on Cue in the list. Add it with the + button if it is missing.")
                step("3", "Come back. Cue notices on its own.")
            }
            .padding(.top, 2)
            HStack(spacing: Theme.Spacing.sm) {
                Button("Open System Settings") {
                    permission.requestPrompt()
                    permission.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint)
                .foregroundStyle(Theme.ink)
                .controlSize(.large)
            }
            .padding(.top, 4)
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for access")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.metaText)
            }
        }
    }

    private var granted: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: style == .full ? 38 : 28, weight: .light))
                .foregroundStyle(Theme.accentText)
            Text("Accessibility access is on")
                .font(.system(size: style == .full ? 20 : 15, weight: .semibold))
            Text("Switch to any app and press the shortcut to see its commands.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number)
                .font(.data(.caption, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
    }
}
