import Apropos
import SwiftUI

/// What the palette shows while Accessibility access is missing: why it is needed, one button, and a way to the guide
/// when Apropos is not in the system list. It flips to a confirmation the moment access arrives (the model polls).
struct PermissionView: View {
    let permission: AccessibilityPermission
    var onHelp: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: permission.isTrusted ? "checkmark" : "hand.raised")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(permission.isTrusted ? Theme.accentInk : Theme.Settings.tileInk)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(permission.isTrusted ? Theme.accent : Theme.Settings.tile)
                )
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(permission.isTrusted ? "Accessibility access is on" : "Allow Accessibility access")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(
                permission.isTrusted
                    ? "Switch to any app and open Apropos to see its commands."
                    : "Apropos reads the menu bar of the app you are using, so it can list and run its commands. Nothing leaves this Mac."
            )
            .font(.system(size: 13))
            .foregroundStyle(Theme.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            .fixedSize(horizontal: false, vertical: true)
            if !permission.isTrusted {
                Button("Open System Settings") {
                    permission.requestPrompt()
                    permission.openSystemSettings()
                }
                .buttonStyle(AccentButtonStyle())
                .padding(.top, 8)
                Button("Not in the list?", action: onHelp)
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text3)
                    .aproposFocusRing(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Theme.footerInset)
        .accessibilityElement(children: .contain)
    }
}
