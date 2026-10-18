import Apropos
import SwiftUI

/// The glass controls floating over the bottom of the list: settings at the left, the primary action and Actions at
/// the right, and a failure note between them when a command could not run.
struct FloatingFooter: View {
    let model: PaletteModel
    let state: PanelState
    let content: PaletteContent
    let actions: PaletteActions

    var body: some View {
        HStack(spacing: 10) {
            Button(action: actions.openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14.5, weight: .regular))
                    .foregroundStyle(Theme.text2)
            }
            .buttonStyle(RoundGlassButtonStyle())
            .focusable()
            .accessibilityLabel("Open Apropos settings")
            .help("Settings")
            Spacer(minLength: 0)
            if let error = model.runError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.cautionText)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .aproposGlass(in: Capsule())
            }
            if content == .results { actionBar }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var actionBar: some View {
        HStack(spacing: 4) {
            Button(action: actions.run) {
                HStack(spacing: 6) {
                    Text("Run menu item").foregroundStyle(Theme.text.opacity(0.9))
                    KeyCap(text: "↩", small: true)
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .focusable()
            Rectangle().fill(Theme.divider).frame(width: 1, height: 18)
            Button(action: actions.toggleActions) {
                HStack(spacing: 4) {
                    Text("Actions").foregroundStyle(Theme.text2)
                    KeyCap(text: "⌘", small: true)
                    KeyCap(text: "K", small: true)
                }
            }
            .buttonStyle(CapsuleButtonStyle())
            .focusable()
        }
        .font(.system(size: 12.5))
        .padding(.horizontal, 6)
        .frame(height: Theme.footerHeight)
        .background(Theme.floatFill, in: Capsule())
        .aproposGlass(in: Capsule(), tinted: false)
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }
}

/// The Cmd+K popover.
struct ActionsPopover: View {
    let items: [PaletteAction]
    let selectedIndex: Int
    let actions: PaletteActions

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    actions.perform(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.text2)
                            .frame(width: 18)
                        Text(item.title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        ForEach(Array(item.keys.enumerated()), id: \.offset) { KeyCap(text: $0.element) }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(index == selectedIndex ? Theme.highlight : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 250)
        .aproposGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions")
    }
}
