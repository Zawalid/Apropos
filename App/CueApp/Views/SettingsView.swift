import Cue
import SwiftUI

struct SettingsView: View {
    let controller: AppController

    var body: some View {
        Form {
            Section {
                LabeledContent("Open Cue") {
                    ShortcutRecorder(
                        combo: controller.combo,
                        onRecordingChange: { controller.setRecording($0) },
                        onChange: { controller.setCombo($0) })
                }
                if !controller.isHotKeyRegistered {
                    Label(
                        "macOS did not accept this shortcut. Another app may be using it. Choose a different one.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.cautionText)
                }
            } header: {
                Text("Shortcut")
            }
            Section {
                LabeledContent("Accessibility") {
                    if controller.permission.isTrusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accentText)
                    } else {
                        Button("Allow in System Settings") {
                            controller.permission.requestPrompt()
                            controller.permission.openSystemSettings()
                        }
                    }
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Cue reads menu names and runs menu items. Nothing about your screen leaves this Mac.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
