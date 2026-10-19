import Apropos
import SwiftUI

/// A compact symbol field for forms: the chosen symbol in a small tile with its name, and a popover with a search box and
/// the grid of common symbols. It replaces typing a raw SF Symbol name. The list lives in the core package
/// (`SymbolPicker`), so the panel's picker and this one offer the same symbols.
struct SymbolChooser: View {
    @Binding var symbol: String
    /// The symbol used when nothing is chosen, shown as a hint.
    var fallback = SymbolPicker.defaultSymbol
    var suggested: [String] = []

    @State private var open = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: shown)
                    .font(.system(size: 15))
                    .foregroundStyle(Brand.text)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Brand.raised))
                Text(symbol.isEmpty ? "Automatic" : symbol)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.text2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Brand.text3)
            }
            .padding(.horizontal, 6)
            .padding(.trailing, 6)
            .frame(height: 38)
            .background(Capsule().fill(Brand.raised.opacity(0.6)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            SymbolGridPopover(symbol: $symbol, suggested: suggested + [fallback]) { open = false }
        }
        .accessibilityLabel("Symbol, \(symbol.isEmpty ? "automatic" : symbol)")
    }

    private var shown: String { symbol.isEmpty ? fallback : symbol }
}

private struct SymbolGridPopover: View {
    @Binding var symbol: String
    let suggested: [String]
    let onDone: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(Brand.text3)
                TextField("Search symbols", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                if !symbol.isEmpty {
                    Button("Automatic") {
                        symbol = ""
                        onDone()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Brand.text2)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Brand.raised))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                    ForEach(SymbolPicker.sections(query: query, suggested: query.isEmpty ? suggested : [])) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Brand.text3)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
                                ForEach(section.symbols) { item in
                                    let selected = item.name == symbol
                                    Button {
                                        symbol = item.name
                                        onDone()
                                    } label: {
                                        Image(systemName: item.name)
                                            .font(.system(size: 15))
                                            .foregroundStyle(selected ? Brand.mintInk : Brand.text)
                                            .frame(width: 34, height: 34)
                                            .background(Circle().fill(selected ? Brand.mint : .clear))
                                            .contentShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(item.name)
                                    .accessibilityLabel(item.name)
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 260)
        }
        .padding(14)
        .frame(width: 330)
        .tint(Brand.mint)
    }
}
