import AppKit
import Foundation
import Testing

@testable import Apropos

struct SymbolResolverTests {
    private let resolver = SymbolResolver()

    private func command(
        _ title: String, path: [String] = ["File"], shortcut: KeyShortcut? = nil, bundle: String? = "com.example.app"
    ) -> Command {
        Command(id: title, title: title, path: path, shortcut: shortcut, source: .menuItem(bundleID: bundle))
    }

    private func cmd(_ key: String, _ modifiers: ModifierSet = [.command]) -> KeyShortcut {
        KeyShortcut(key: key, modifiers: modifiers)
    }

    // MARK: Tiers

    @Test func userOverrideBeatsEverything() {
        let item = command("Save", shortcut: cmd("S"), bundle: "com.apple.finder")
        let resolver = SymbolResolver(overrides: [item.stableID: "star"])
        let result = resolver.resolve(item)
        #expect(result.symbol == "star")
        #expect(result.tier == .userOverride)
    }

    @Test func packBeatsStandardCommands() {
        let item = command("New Folder", path: ["File"], shortcut: cmd("N", [.shift, .command]), bundle: "com.apple.finder")
        let result = resolver.resolve(item)
        #expect(result.symbol == "folder.badge.plus")
        #expect(result.tier == .pack)
    }

    @Test func packMatchesLocalizedTitlesAndIgnoresEllipsis() {
        #expect(resolver.symbol(for: command("Nouveau dossier", bundle: "com.apple.finder")) == "folder.badge.plus")
        #expect(
            resolver.symbol(for: command("Clear History…", path: ["History"], bundle: "com.apple.Safari")) == "trash")
        #expect(
            resolver.symbol(for: command("Coup d’œil", bundle: "com.apple.finder")) == "eye")
    }

    @Test func packPathRestrictsAnEntry() {
        let entry = SymbolPack.Entry(titles: ["Home"], path: ["Go"], symbol: "house.fill")
        let library = SymbolPackLibrary(packs: [SymbolPack(name: "T", bundleIDs: ["t"], commands: [entry])])
        let resolver = SymbolResolver(library: library)
        #expect(resolver.symbol(for: command("Home", path: ["Go"], bundle: "t")) == "house.fill")
        #expect(resolver.symbol(for: command("Home", path: ["File"], bundle: "t")) != "house.fill")
    }

    @Test func laterPacksOverrideEarlierOnes() {
        func pack(_ symbol: String) -> SymbolPack {
            SymbolPack(name: symbol, bundleIDs: ["t"], commands: [.init(titles: ["Thing"], symbol: symbol)])
        }
        let resolver = SymbolResolver(library: SymbolPackLibrary(packs: [pack("a.circle"), pack("b.circle")]))
        #expect(resolver.symbol(for: command("Thing", bundle: "t")) == "b.circle")
    }

    @Test func packOfAnotherAppDoesNotApply() {
        #expect(resolver.symbol(for: command("Build", path: ["Odd"], bundle: "com.example.other")) == "hammer")
        let xcode = resolver.resolve(command("Build", path: ["Product"], bundle: "com.apple.dt.Xcode"))
        #expect(xcode.tier == .pack)
    }

    @Test func standardShortcutWinsOverTitle() {
        let item = command("Anything At All", shortcut: cmd("P"))
        let result = resolver.resolve(item)
        #expect(result.symbol == "printer")
        #expect(result.tier == .standardCommand)
    }

    @Test func appSpecificShortcutsAreNotAssumed() {
        // Command-B is Build in Xcode and Bold in a text editor; neither is claimed by the standard table.
        #expect(resolver.symbol(for: command("Build", path: ["Product"], shortcut: cmd("B"))) == "hammer")
        #expect(resolver.symbol(for: command("Bold", path: ["Format"], shortcut: cmd("B"))) == "bold")
    }

    @Test func standardTitlesWorkInEnglishAndFrench() {
        #expect(resolver.resolve(command("Select All")).tier == .standardCommand)
        #expect(resolver.symbol(for: command("Tout sélectionner", path: ["Édition"])) == "selection.pin.in.out")
        #expect(resolver.symbol(for: command("Enregistrer sous…")) == "square.and.arrow.down.on.square")
        #expect(resolver.symbol(for: command("Coller", path: ["Édition"])) == "doc.on.clipboard")
    }

    @Test func verbRulesMatchTheLeadingWordOnly() {
        #expect(resolver.symbol(for: command("Export as PDF", path: ["Odd"])) == "square.and.arrow.up")
        #expect(resolver.symbol(for: command("Exporter en PDF", path: ["Odd"])) == "square.and.arrow.up")
        #expect(resolver.symbol(for: command("Quit Finder", path: ["Finder"])) == "power")
        #expect(resolver.resolve(command("Export as PDF", path: ["Odd"])).tier == .verb)
    }

    @Test func keywordRulesFindWordsAfterTheFirst() {
        let result = resolver.resolve(command("Project Sidebar Layout", path: ["Odd"]))
        #expect(result.symbol == "sidebar.left")
        #expect(result.tier == .keyword)
    }

    @Test func menuGroupFallback() {
        let result = resolver.resolve(command("Zork", path: ["View"]))
        #expect(result.symbol == "eye")
        #expect(result.tier == .menuGroup)
        #expect(resolver.symbol(for: command("Zork", path: ["Présentation"])) == "eye")
    }

    @Test func neverReturnsNothing() {
        let odd = [
            command("", path: []), command("…", path: ["???"]), command("🙂", path: ["🙂"], bundle: nil),
            command(String(repeating: "x", count: 500), path: ["Q"]),
        ]
        for item in odd {
            #expect(!resolver.symbol(for: item).isEmpty)
            #expect(resolver.resolve(item).candidates.count >= 2)
        }
        #expect(resolver.symbol(for: command("Zork", path: ["Odd"])) == "command")
        #expect(resolver.symbols(for: []).isEmpty)
    }

    // MARK: Distinctness

    @Test func neighboursNeverShareASymbolWhenAnAlternativeExists() {
        // All four resolve to "doc.on.doc" or close to it by verb; the menu group offers other choices.
        let items = [
            command("Copy Link", path: ["Edit"]), command("Copy Style", path: ["Edit"]),
            command("Copy Path", path: ["Edit"]), command("Copy Name", path: ["Edit"]),
        ]
        let symbols = resolver.symbols(for: items)
        #expect(symbols.count == 4)
        for pair in zip(symbols, symbols.dropFirst()) { #expect(pair.0 != pair.1, "\(symbols)") }
    }

    @Test func distinctnessLeavesUniqueRowsAlone() {
        let items = [command("Save"), command("Print"), command("Quit App", path: ["App"])]
        #expect(resolver.symbols(for: items) == items.map { resolver.symbol(for: $0) })
    }

    @Test func overridesAreNeverChangedByDistinctness() {
        let one = command("Copy Link", path: ["Edit"])
        let two = command("Copy Style", path: ["Edit"])
        let resolver = SymbolResolver(overrides: [one.stableID: "doc.on.doc", two.stableID: "doc.on.doc"])
        #expect(resolver.symbols(for: [one, two]) == ["doc.on.doc", "doc.on.doc"])
    }

    @Test func theStrongerRowKeepsItsSymbol() {
        let strong = command("Anything", path: ["Edit"], shortcut: cmd("C"))
        let weak = command("Copy Style", path: ["Edit"])
        let symbols = resolver.symbols(for: [weak, strong])
        #expect(symbols[1] == "doc.on.doc")
        #expect(symbols[0] != symbols[1])
    }

    @Test func aRowWithNoAlternativeKeepsItsSymbolEvenIfRepeated() {
        let resolver = SymbolResolver(
            library: SymbolPackLibrary(packs: []))
        let same = command("Zork", path: ["Odd"])
        let symbols = resolver.symbols(for: [same, same, same, same])
        // Fallback tier has two spares, so adjacent rows alternate rather than repeat.
        for pair in zip(symbols, symbols.dropFirst()) { #expect(pair.0 != pair.1) }
    }

    // MARK: Pack format and data validity

    @Test func bundledPacksLoadForFinderSafariXcodeAndClaude() {
        let names = Set(SymbolPackLibrary.bundled().packs.map(\.name))
        #expect(names == ["Finder", "Safari", "Xcode", "Claude"])
    }

    @Test func packDecodingDropsUnusableEntries() throws {
        let json = """
            { "schemaVersion": 1, "name": "T", "bundleIDs": ["t"], "commands": [
              { "titles": ["Ok"], "symbol": "star" },
              { "symbol": "star" },
              { "titles": ["Spaces"], "symbol": "has space" },
              { "shortcut": "⌘K", "symbol": "key" } ] }
            """
        let pack = try SymbolPack.decode(Data(json.utf8))
        #expect(pack.commands.count == 2)
    }

    @Test func shortcutOnlyPackEntryMatchesAnyTitle() {
        let pack = SymbolPack(name: "T", bundleIDs: ["t"], commands: [.init(shortcut: "⌘K", symbol: "key")])
        let resolver = SymbolResolver(library: SymbolPackLibrary(packs: [pack]))
        #expect(resolver.symbol(for: command("Whatever", shortcut: cmd("K"), bundle: "t")) == "key")
    }

    @Test func userPackDirectoryIsLoadedAndBadFilesSkipped() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("packs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"name":"Mine","bundleIDs":["mine"],"commands":[{"titles":["Go"],"symbol":"bolt"}]}"#.utf8)
            .write(to: directory.appendingPathComponent("mine.json"))
        try Data("nope".utf8).write(to: directory.appendingPathComponent("bad.json"))
        try Data(#"{"schemaVersion":9,"name":"Future","bundleIDs":["f"],"commands":[]}"#.utf8)
            .write(to: directory.appendingPathComponent("future.json"))
        let library = SymbolPackLibrary.bundled(plus: directory)
        let names = Set(library.packs.map(\.name))
        #expect(names.contains("Mine") && !names.contains("Future"))
        #expect(SymbolResolver(library: library).symbol(for: command("Go", bundle: "mine")) == "bolt")
    }

    @Test func everySymbolNameExistsOnThisMac() {
        var names = Set<String>()
        names.formUnion(StandardCommandSymbols.shortcuts.values)
        names.formUnion(StandardCommandSymbols.titles.values)
        names.formUnion(StandardCommandSymbols.verbs.values)
        names.formUnion(StandardCommandSymbols.keywords.values)
        names.formUnion(StandardCommandSymbols.groups.values)
        names.formUnion(StandardCommandSymbols.spare)
        for pack in SymbolPackLibrary.bundled().packs { names.formUnion(pack.commands.map(\.symbol)) }
        let missing = names.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "unknown SF Symbols: \(missing.sorted())")
    }

    @Test func existingBehaviourOfTheOldHelperIsKept() {
        #expect(CommandDisplay.symbol(for: command("Open Recent")) == "folder")
        #expect(CommandDisplay.symbol(for: command("Whatever", path: ["Odd"])) == "command")
    }

    @Test func usageStoreFeedsOverridesToTheResolver() async {
        let item = command("Zork", path: ["Odd"])
        let symbol = await MainActor.run { () -> String in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("u-\(UUID().uuidString)/usage.json")
            let store = UsageStore(url: url, writeDelay: .zero)
            store.setSymbolOverride("heart", for: item.stableID)
            return store.symbolResolver().symbol(for: item)
        }
        #expect(symbol == "heart")
    }
}
