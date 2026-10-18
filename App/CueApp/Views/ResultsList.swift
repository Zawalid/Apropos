import Cue
import SwiftUI

/// One line of the list: a section header or a command. Heights are fixed so the selection highlight can be placed by
/// arithmetic, which is what lets a single highlight slide between rows.
private enum ListEntry: Identifiable {
    case section(id: String, title: String)
    case row(RankedCommand, index: Int)

    var id: String {
        switch self {
        case .section(let id, _): "section-\(id)"
        case .row(let ranked, _): ranked.id
        }
    }

    var height: CGFloat {
        switch self {
        case .section: Theme.sectionHeight
        case .row: Theme.rowHeight
        }
    }
}

struct ResultsList: View {
    let model: PaletteModel
    let actions: PaletteActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entrance = RowEntrance()
    @State private var lastMouse = NSEvent.mouseLocation

    var body: some View {
        let entries = makeEntries()
        let isGrouped = model.query.trimmingCharacters(in: .whitespaces).isEmpty
        let selectedID = model.selected?.id
        let offset = selectedOffset(in: entries, selectedID: selectedID)
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                ZStack(alignment: .top) {
                    if let offset {
                        RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                            .fill(Theme.highlight)
                            .frame(height: Theme.rowHeight)
                            .offset(y: offset)
                            .animation(reduceMotion ? nil : Motion.selection, value: offset)
                            .id("highlight-\(model.targetApp?.pid ?? 0)-\(model.query)")
                            .allowsHitTesting(false)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            switch entry {
                            case .section(_, let title):
                                SectionHeader(title: title)
                            case .row(let ranked, let index):
                                CommandRow(
                                    ranked: ranked, appName: model.targetApp?.name, showsFullPath: !isGrouped)
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
                .padding(.bottom, 96)
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 96)
                }
            }
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
        var entries: [ListEntry] = []
        var currentGroup: String?
        for (index, ranked) in results.enumerated() {
            if grouped {
                let group = ranked.command.path.first ?? "Menu"
                if group != currentGroup {
                    currentGroup = group
                    let title = group == model.targetApp?.name ? "App menu" : group
                    entries.append(.section(id: "\(index)-\(group)", title: title))
                }
            }
            entries.append(.row(ranked, index: index))
        }
        return entries
    }

    private func selectedOffset(in entries: [ListEntry], selectedID: String?) -> CGFloat? {
        guard let selectedID else { return nil }
        var y: CGFloat = 0
        for entry in entries {
            if case .row(let ranked, _) = entry, ranked.id == selectedID { return y }
            y += entry.height
        }
        return nil
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, minHeight: Theme.sectionHeight, maxHeight: Theme.sectionHeight, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
