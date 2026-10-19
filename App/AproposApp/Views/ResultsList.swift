import Apropos
import SwiftUI

/// One line of the list: a section header or a command. Heights are fixed so the selection highlight can be placed by
/// arithmetic, which is what lets a single highlight slide between rows.
private enum ListEntry: Identifiable {
    case section(id: String, title: String, keys: [String], count: Int? = nil)
    case row(RankedCommand, index: Int, fullPath: Bool)

    var id: String {
        switch self {
        case .section(let id, _, _, _): "section-\(id)"
        case .row(let ranked, _, _): ranked.id
        }
    }

    func height(_ metrics: InterfaceMetrics) -> CGFloat {
        switch self {
        case .section: metrics.section
        case .row: metrics.rowHeight
        }
    }
}

struct ResultsList: View {
    let model: PaletteModel
    let actions: PaletteActions

    @Environment(UsageController.self) private var usage
    @Environment(\.aproposReduceMotion) private var reduceMotion
    @Environment(\.interfaceMetrics) private var metrics
    @State private var entrance = RowEntrance()
    @State private var lastMouse = NSEvent.mouseLocation

    var body: some View {
        let entries = makeEntries()
        let symbols = usage.symbols(for: model.results.map(\.command))
        let selectedID = model.selected?.id
        let placement = selectedPlacement(in: entries, selectedID: selectedID)
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    if let placement {
                        RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                            .fill(Theme.highlight)
                            .frame(height: placement.height)
                            .offset(y: placement.offset)
                            .animation(reduceMotion ? nil : Motion.selection, value: placement.offset)
                            .animation(reduceMotion ? nil : Motion.selection, value: placement.height)
                            .id("highlight-\(model.targetApp?.pid ?? 0)-\(model.query)")
                            .allowsHitTesting(false)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            switch entry {
                            case .section(_, let title, let keys, let count):
                                SectionHeader(title: title, height: metrics.section, keys: keys, count: count)
                            case .row(let ranked, let index, let fullPath):
                                CommandRow(
                                    ranked: ranked, symbol: symbols[ranked.id] ?? "command",
                                    appName: model.targetApp?.name, appPID: model.targetApp?.pid,
                                    showsFullPath: fullPath, reason: model.predictionReason(forRowID: ranked.id),
                                    alias: model.alias(for: ranked.command)
                                )
                                .rowRise(index: index, entrance: entrance)
                                .id(ranked.id)
                                .onTapGesture { actions.runCommand(ranked.command) }
                                .onContinuousHover { phase in hover(phase, id: ranked.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, Theme.listFade)
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Theme.listFade)
                }
            }
            .padding(.bottom, Theme.footerInset)
            .onChange(of: selectedID) {
                guard let selectedID else { return }
                proxy.scrollTo(selectedID)
            }
            .onChange(of: model.query) {
                if let first = model.results.first?.id { proxy.scrollTo(first, anchor: .top) }
            }
            .onChange(of: model.targetApp?.pid) { entrance.arm(for: model.targetApp?.pid) }
            .onAppear { entrance.arm(for: model.targetApp?.pid) }
        }
    }

    /// Moving the highlight with the pointer only counts when the pointer itself moved; a list that scrolls under a
    /// resting pointer must not steal the selection from the keyboard.
    private func hover(_ phase: HoverPhase, id: String) {
        guard case .active = phase else { return }
        let location = NSEvent.mouseLocation
        guard location != lastMouse else { return }
        lastMouse = location
        model.select(id: id)
    }

    private func makeEntries() -> [ListEntry] {
        let results = model.results
        let grouped = model.query.trimmingCharacters(in: .whitespaces).isEmpty
        let leading = model.leadingGroups
        let predicted = model.predictedCount
        let leadingCount = leading.pinned + predicted + leading.suggested
        // A title shared by several menus (or one that only makes sense inside its menu) shows its path.
        var titleCounts: [String: Int] = [:]
        for ranked in results { titleCounts[ranked.command.displayTitle.lowercased(), default: 0] += 1 }
        var entries: [ListEntry] = []
        var currentGroup: String?
        // The sequence draft row heads the list, ahead of the pinned rows, under its own header.
        let draftRows = grouped ? model.draftRowCount : 0
        // How many rows each menu group holds, for the number beside its header.
        var groupSizes: [String: Int] = [:]
        for ranked in results.dropFirst(draftRows + leadingCount) {
            groupSizes[ranked.command.path.first ?? "Menu", default: 0] += 1
        }
        for (position, ranked) in results.enumerated() {
            var fullPath = true
            if position < draftRows {
                if position == 0 { entries.append(.section(id: "sequence", title: "Sequence", keys: [])) }
                entries.append(.row(ranked, index: position, fullPath: false))
                continue
            }
            let index = position - draftRows
            if !grouped && index == 0 {
                entries.append(.section(id: "results", title: "Results", keys: [], count: results.count - draftRows))
            }
            if grouped {
                if index == 0 && leading.pinned > 0 {
                    entries.append(.section(id: "pinned", title: "Pinned", keys: [], count: leading.pinned))
                } else if index == leading.pinned && predicted > 0 {
                    entries.append(.section(id: "predicted", title: "Usually next", keys: ["⌘", "↩"], count: nil))
                } else if index == leading.pinned + predicted && leading.suggested > 0 {
                    entries.append(.section(id: "suggested", title: "Suggested for this moment", keys: [], count: nil))
                }
                if index >= leadingCount {
                    let group = ranked.command.path.first ?? "Menu"
                    if group != currentGroup {
                        currentGroup = group
                        entries.append(.section(id: "\(index)-\(group)", title: group, keys: [], count: groupSizes[group]))
                    }
                    fullPath =
                        CommandDisplay.isAmbiguous(title: ranked.command.title)
                        || (titleCounts[ranked.command.displayTitle.lowercased()] ?? 0) > 1
                }
            }
            entries.append(.row(ranked, index: position, fullPath: fullPath))
        }
        return entries
    }

    private func selectedPlacement(in entries: [ListEntry], selectedID: String?) -> (offset: CGFloat, height: CGFloat)?
    {
        guard let selectedID else { return nil }
        var y: CGFloat = 0
        for entry in entries {
            if case .row(let ranked, _, _) = entry, ranked.id == selectedID { return (y, entry.height(metrics)) }
            y += entry.height(metrics)
        }
        return nil
    }
}

private struct SectionHeader: View {
    let title: String
    let height: CGFloat
    /// Key caps at the trailing edge, for a group that has its own shortcut.
    var keys: [String] = []
    /// How many rows sit under the header, shown beside its name.
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.text3)
            if let count {
                Text("\(count) \(count == 1 ? "item" : "items")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.text3.opacity(0.7))
            }
            Spacer(minLength: 0)
            ForEach(keys, id: \.self) { KeyCap(text: $0, small: true) }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .frame(
            maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading
        )
        .accessibilityAddTraits(.isHeader)
    }
}
