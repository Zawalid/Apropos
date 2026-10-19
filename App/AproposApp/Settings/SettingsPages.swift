import AppKit
import Apropos
import SwiftUI

/// The name of an installed app, or the bundle identifier itself when it is not installed here.
func appDisplayName(_ bundleID: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    return bundleID
}

private func title(_ id: SettingID) -> String { SettingsRegistry.definition(for: id)?.title ?? id.rawValue }

private func detail(_ id: SettingID) -> String? {
    SettingsRegistry.definition(for: id).map(\.detail).flatMap { $0.isEmpty ? nil : $0 }
}

// MARK: General

struct GeneralPage: View {
    let controller: AppController
    let settings: SettingsModel

    private static let presets: [(value: Int, title: String)] = [
        (0, "Immediately"), (15, "After 15 seconds"), (60, "After 1 minute"), (300, "After 5 minutes"),
        (3600, "After 1 hour"),
    ]

    var body: some View {
        @Bindable var settings = settings
        SettingsSection(title: "Startup") {
            SettingToggleRow(
                id: .openAtLogin,
                isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            SettingToggleRow(id: .showInMenuBar, isOn: $settings.showInMenuBar)
        }
        SettingsSection(
            title: "Shortcut", footer: "Apropos runs alongside your launcher. Pick a shortcut it does not use."
        ) {
            SettingsRow(
                title: title(.openHotKey),
                detail: "Press it in any app to open the panel.",
                settingID: .openHotKey
            ) {
                ShortcutRecorder(
                    combo: controller.combo, onRecordingChange: { controller.setRecording($0) },
                    onChange: { controller.setCombo($0) })
            }
            .settingsAnchor(SettingID.openHotKey.rawValue)
        }
        if !controller.isHotKeyRegistered {
            Label(
                "macOS did not accept this shortcut. Another app may be using it.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 12.5))
            .foregroundStyle(Brand.danger)
            .padding(.horizontal, 16)
        }
        SettingsSection(title: "Panel") {
            SettingToggleRow(id: .closeOnFocusLoss, isOn: $settings.closeOnFocusLoss)
            SettingsRow(
                title: title(.resetQueryAfterSeconds),
                detail: "Keep what you typed if you reopen the panel within this time.",
                settingID: .resetQueryAfterSeconds
            ) {
                ValueMenu(options: options, selection: $settings.resetQuerySeconds)
            }
            .settingsAnchor(SettingID.resetQueryAfterSeconds.rawValue)
            SettingsRow(title: title(.panelPosition), detail: detail(.panelPosition), settingID: .panelPosition) {
                HStack(spacing: 8) {
                    if settings.panelPosition == PanelPlacement.Mode.remember.rawValue {
                        Button("Reset") { controller.panelPositions.forgetAll() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    ValueMenu(
                        options: PanelPlacement.Mode.allCases.map { ($0.rawValue, $0.title) },
                        selection: $settings.panelPosition)
                }
            }
            .settingsAnchor(SettingID.panelPosition.rawValue)
        }
        SettingsSection(
            title: "Include in the panel",
            footer: "The front app's menu is always listed. Suggestions from Prediction are set on their own page."
        ) {
            SettingToggleRow(id: .includeContextActions, isOn: $settings.includeContextActions)
            SettingToggleRow(id: .includeUserCommands, isOn: $settings.includeUserCommands)
            SettingToggleRow(id: .includeSendTo, isOn: $settings.includeSendTo)
            SettingToggleRow(id: .showAlternateCommands, isOn: $settings.showAlternates)
        }
        MenuOffApps(settings: settings)
    }

    /// The presets, plus the stored value when someone edited the file to something else.
    private var options: [(value: Int, title: String)] {
        let current = settings.resetQuerySeconds
        if Self.presets.contains(where: { $0.value == current }) { return Self.presets }
        return (Self.presets + [(current, "After \(current) seconds")]).sorted { $0.value < $1.value }
    }
}

// MARK: Appearance

struct AppearancePage: View {
    let settings: SettingsModel

    var body: some View {
        @Bindable var settings = settings
        SettingsSection(title: title(.theme)) {
            ChoiceCards(
                options: AppearanceMode.allCases.map { ($0, $0.title) }, selection: $settings.appearance
            ) { mode in
                switch mode {
                case .system: SplitMiniPanel()
                case .light: MiniPanel(scheme: .light)
                case .dark: MiniPanel(scheme: .dark)
                }
            }
        }
        .settingsAnchor(SettingID.theme.rawValue)
        SettingsSection(title: "Under the search field", footer: detail(.contextChips)) {
            FlowLayout(spacing: 8) {
                ForEach(SettingsRegistry.contextChipOptions, id: \.value) { option in
                    if let kind = ContextKind(rawValue: option.value) {
                        ChipToggle(
                            title: option.title,
                            isOn: Binding(
                                get: { settings.isChipShown(kind) }, set: { settings.setChip(kind, shown: $0) }))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsAnchor(SettingID.contextChips.rawValue)
        SettingsSection(title: "Panel") {
            SettingsRow(title: title(.interfaceSize), detail: detail(.interfaceSize), settingID: .interfaceSize) {
                SizePicker(selection: $settings.interfaceSize)
            }
            .settingsAnchor(SettingID.interfaceSize.rawValue)
            SettingToggleRow(id: .reduceMotion, isOn: $settings.reduceMotion)
        }
        SettingsSection(title: title(.rowIcons), footer: detail(.rowIcons)) {
            ChoiceCards(
                options: RowIconStyle.allCases.map { ($0, $0.title) }, selection: $settings.rowIcons
            ) { style in
                switch style {
                case .glyph: MiniPanel(scheme: .dark, leading: .glyph)
                case .appLogo: MiniPanel(scheme: .dark, leading: .logos)
                case .none: MiniPanel(scheme: .dark, leading: .none)
                }
            }
        }
        .settingsAnchor(SettingID.rowIcons.rawValue)
        SettingsSection(title: "Preview") {
            SettingsPalettePreview(settings: settings)
        }
    }
}

/// Three "Aa" choices of growing size.
private struct SizePicker: View {
    @Binding var selection: InterfaceSize

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InterfaceSize.allCases) { size in
                let selected = size == selection
                Button {
                    selection = size
                } label: {
                    Text("Aa")
                        .font(.system(size: size == .compact ? 11 : size == .standard ? 13 : 16, weight: .medium))
                        .foregroundStyle(selected ? Brand.text : Brand.text3)
                        .frame(width: 36, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(
                                selected ? Theme.highlight : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(size.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct AppIconImage: View {
    let icon: NSImage?
    let size: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: "app").font(.system(size: size * 0.7)).foregroundStyle(Brand.text3).frame(
                width: size, height: size)
        }
    }
}

// MARK: Privacy and data

/// A pill that toggles one kind of context: filled with the accent tint and a check when on.
private struct ChipToggle: View {
    let title: String
    @Binding var isOn: Bool

    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Brand.mint)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? Brand.text : Brand.text3)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                Capsule().fill(isOn ? Brand.mint.opacity(0.14) : (hovering ? Brand.raised : Brand.raised))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .aproposFocusRing(Capsule())
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Apps where the panel lists no menu items, for the ones whose menus only get in the way.
struct MenuOffApps: View {
    let settings: SettingsModel

    @State private var apps: [ContextPage.AppEntry] = []
    @State private var picking = false

    private var named: [ContextPage.AppEntry] {
        apps.filter { settings.menuDisabledApps.contains($0.bundleID) }
    }

    var body: some View {
        SettingsSection(
            title: "Apps without menu items",
            footer: "The panel still lists actions, your commands and Send to in these apps, just not their menu.",
            accessory: AnyView(PillButton(title: "Add app", symbol: "plus") { picking = true })
        ) {
            if named.isEmpty {
                EmptyRows(title: "Menu items show in every app", detail: "Add an app to hide its menu from the panel.")
            }
            ForEach(named) { app in
                SettingsRow(
                    title: app.name,
                    leading: AnyView(AppIconImage(icon: NSWorkspace.shared.icon(forFile: app.path), size: 22))
                ) {
                    Button {
                        settings.menuDisabledApps.removeAll { $0 == app.bundleID }
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(Brand.text3)
                    }
                    .buttonStyle(.plain)
                    .help("List this app's menu items again")
                    .accessibilityLabel("List \(app.name) menu items again")
                }
            }
        }
        .settingsAnchor(SettingID.menuDisabledApps.rawValue)
        .task { apps = await ContextPage.scan(including: settings) }
        .sheet(isPresented: $picking) {
            AppPickerSheet(
                apps: apps.filter { !settings.menuDisabledApps.contains($0.bundleID) },
                note: "The panel will not list menu items in the app you choose."
            ) { chosen in
                settings.menuDisabledApps.append(chosen.bundleID)
                picking = false
            } onCancel: { picking = false }
        }
    }
}
