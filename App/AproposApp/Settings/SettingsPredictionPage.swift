import AppKit
import Apropos
import SwiftUI

/// What Apropos learns about what you run next, what it has learned so far, and how to correct or forget it.
struct PredictionPage: View {
    let controller: AppController
    let settings: SettingsModel

    @State private var confirmingReset = false
    @State private var tick = 0
    @State private var picking = false
    @State private var apps: [ContextPage.AppEntry] = []

    private var engine: PredictionEngine { controller.usage.prediction }

    var body: some View {
        let _ = engine.log.revision
        PredictionIntro()
        SettingsSection {
            SettingToggleRow(
                id: .predictNextCommand,
                isOn: Binding(
                    get: { settings.predictNextCommand },
                    set: {
                        settings.predictNextCommand = $0
                        apply()
                    }))
            SettingToggleRow(
                id: .showPredictionReasons,
                isOn: Binding(
                    get: { settings.showPredictionReasons },
                    set: {
                        settings.showPredictionReasons = $0
                        apply()
                    })
            )
            .opacity(settings.predictNextCommand ? 1 : 0.5)
            .disabled(!settings.predictNextCommand)
        }
        learned
        habits
        tuning
        appsSection
        dataSection
        Color.clear.frame(height: 0)
            .id(tick)
            .task { apps = await ContextPage.scan(including: settings) }
            .sheet(isPresented: $picking) {
                AppPickerSheet(
                    apps: apps.filter { !settings.predictionExcludedApps.contains($0.bundleID) },
                    note: "Nothing will be learned or suggested in the app you choose."
                ) { chosen in
                    settings.predictionExcludedApps += [chosen.bundleID]
                    apply()
                    picking = false
                } onCancel: { picking = false }
            }
            .confirmationDialog(
                "Forget everything Apropos learned about what you run next?", isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button("Forget everything", role: .destructive) {
                    engine.reset()
                    tick += 1
                }
            }
    }

    private func apply() { engine.configure(from: settings.store) }

    // MARK: Learned

    private var learned: some View {
        let summary = engine.summary()
        let accuracy = engine.accuracy()
        return SettingsSection(title: "What it has learned") {
            SettingsRow(
                title: summary.runs == 0 ? "Nothing yet" : "\(summary.runs) runs in \(summary.apps) app\(summary.apps == 1 ? "" : "s")",
                detail: summary.runs == 0
                    ? "It learns as you use the panel."
                    : "Across \(summary.commands) commands on \(summary.daysOfUse) day\(summary.daysOfUse == 1 ? "" : "s")"
            ) {
                if summary.isWarmingUp && summary.runs > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: summary.warmUp).tint(Brand.mint).frame(width: 110)
                        Text("Still warming up").font(.system(size: 11.5)).foregroundStyle(Brand.text3)
                    }
                }
            }
            SettingsRow(
                title: accuracy.isEnough ? "\(Int((accuracy.rate * 100).rounded()))% right" : "Not enough to say yet",
                detail: accuracy.isEnough
                    ? "Of \(accuracy.shown) suggestions in the last 30 days, you chose the suggested command \(accuracy.chosen) times."
                    : "After about five suggestions it shows how often they were what you wanted."
            ) { EmptyView() }
        }
    }

    // MARK: Habits

    private var habits: some View {
        let list = engine.habits()
        return SettingsSection(
            title: "Your habits",
            footer: "The strongest patterns in the log. Forget one and Apropos stops suggesting it until you repeat it."
        ) {
            if list.isEmpty {
                EmptyRows(
                    title: "No habits yet",
                    detail: "They appear once you have run the same command after the same one at least three times.")
            }
            ForEach(list) { habit in
                SettingsRow(
                    title: "After \(engine.title(for: habit.previous)), \(engine.title(for: habit.command))",
                    detail: "In \(appDisplayName(habit.app)), \(habit.count) of \(habit.total) times"
                ) {
                    Button("Forget") {
                        engine.forget(habit)
                        tick += 1
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    // MARK: Tuning

    private var tuning: some View {
        SettingsSection(title: "Tuning") {
            SettingsRow(title: title(.predictionSensitivity), detail: detail(.predictionSensitivity)) {
                ValueMenu(
                    options: PredictionSensitivity.allCases.map { ($0.rawValue, $0.rawValue.capitalized) },
                    selection: Binding(
                        get: { settings.predictionSensitivity },
                        set: {
                            settings.predictionSensitivity = $0
                            apply()
                        }))
            }
            SettingsRow(title: title(.predictionMaxRows), detail: detail(.predictionMaxRows)) {
                ValueMenu(
                    options: [("1", "One"), ("2", "Two")],
                    selection: Binding(
                        get: { settings.predictionMaxRows },
                        set: {
                            settings.predictionMaxRows = $0
                            apply()
                        }))
            }
            SettingsRow(title: title(.predictionKeepDays), detail: detail(.predictionKeepDays)) {
                ValueMenu(
                    options: [("30", "30 days"), ("90", "90 days"), ("365", "A year"), ("0", "Forever")],
                    selection: Binding(
                        get: { settings.predictionKeepDays },
                        set: {
                            settings.predictionKeepDays = $0
                            apply()
                            tick += 1
                        }))
            }
        }
        .opacity(settings.predictNextCommand ? 1 : 0.5)
        .disabled(!settings.predictNextCommand)
    }

    // MARK: Apps

    private struct AppRow: Identifiable {
        let bundleID: String
        let runs: Int
        var id: String { bundleID }
    }

    private var appRows: [AppRow] {
        let inLog = engine.appsInLog().map { AppRow(bundleID: $0.app, runs: $0.runs) }
        let known = Set(inLog.map(\.bundleID))
        let extra = settings.predictionExcludedApps.filter { !known.contains($0) }.map { AppRow(bundleID: $0, runs: 0) }
        return (inLog + extra).filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
    }

    private var appsSection: some View {
        SettingsSection(
            title: "Apps",
            footer: "Turn an app off and nothing is learned or suggested in it. Forget removes what it learned there.",
            accessory: AnyView(PillButton(title: "Add app", symbol: "plus") { picking = true })
        ) {
            if appRows.isEmpty {
                EmptyRows(title: "No apps yet", detail: "Apps show up here once you have run commands in them.")
            }
            ForEach(appRows) { row in
                let name = appDisplayName(row.bundleID)
                SettingsRow(
                    title: name, detail: row.runs == 0 ? "Not learning" : "\(row.runs) runs",
                    leading: AnyView(AppIconImage(icon: icon(for: row.bundleID), size: 22))
                ) {
                    HStack(spacing: 8) {
                        if row.runs > 0 {
                            Button("Forget") {
                                engine.reset(forApp: row.bundleID)
                                tick += 1
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        AproposToggle(
                            title: "Learn in \(name)",
                            isOn: Binding(
                                get: { !settings.predictionExcludedApps.contains(row.bundleID) },
                                set: { on in
                                    var list = settings.predictionExcludedApps.filter { $0 != row.bundleID }
                                    if !on { list.append(row.bundleID) }
                                    settings.predictionExcludedApps = list
                                    apply()
                                }))
                    }
                }
            }
        }
    }

    private func icon(for bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }

    // MARK: Data

    private var dataSection: some View {
        let size = engine.log.fileSize
        return SettingsSection(title: "The log") {
            SettingsRow(
                title: "Where it lives",
                detail: (engine.log.url.path as NSString).abbreviatingWithTildeInPath
                    + (size.map { ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "")
            ) {
                HStack(spacing: 8) {
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([engine.log.url]) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Export") { export() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            SettingsRow(title: "Forget everything", detail: "Clears the log and starts over.") {
                Button("Forget") { confirmingReset = true }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func export() {
        engine.log.flush()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "apropos-prediction-log.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: engine.log.url, to: destination)
    }
}

private func title(_ id: SettingID) -> String { SettingsRegistry.definition(for: id)?.title ?? id.rawValue }

private func detail(_ id: SettingID) -> String? {
    SettingsRegistry.definition(for: id).map(\.detail).flatMap { $0.isEmpty ? nil : $0 }
}

/// What Usually next is, with a sample of the row it adds.
private struct PredictionIntro: View {
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("What you usually do next")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text(
                    "Apropos notices which command you tend to run after another, in each app and at each time of day, and puts it first under Usually next. It is a simple count kept on this Mac: command names and times only, never what you type or select."
                )
                .font(.system(size: 12.5))
                .lineSpacing(2)
                .foregroundStyle(Brand.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Image(systemName: "sparkles").font(.system(size: 14)).foregroundStyle(Theme.accentText).frame(width: 22)
                Text("Commit").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                Text("After Run Tests you chose it 9 of 12 times").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Capsule().fill(Theme.highlight))
            .frame(maxWidth: 460)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(RoundedRectangle(cornerRadius: Brand.sectionRadius, style: .continuous).fill(Brand.section))
    }
}
