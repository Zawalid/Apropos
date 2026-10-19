import Foundation

/// A made-up but realistic world to measure ranking in: menus of a few apps, and people who use them with habits and
/// shorthand. It cannot prove the ranking is good for a real person; it shows whether a change helps when the patterns
/// we believe in are there, and it catches changes that make things worse. Deterministic for a seed.
public enum RankingSimulation {
    public struct Item: Sendable {
        public let path: [String]
        public let title: String
        public let keys: String?
        public var id: String { (path + [title]).joined(separator: ">") }
    }

    public struct Catalogue: Sendable {
        public let app: String
        public let items: [Item]
        public var commands: [Command] {
            items.map { item in
                Command(
                    id: "\(app)|\(item.id)", title: item.title, path: item.path, shortcut: nil, isEnabled: true,
                    source: .menuItem(bundleID: app),
                    stableID: CommandID.base(bundleID: app, path: item.path, title: item.title))
            }
        }
    }

    /// Menus written the way apps write them. Titles that look alike on purpose (New Window, New Tab, New Folder,
    /// New Smart Folder; Close, Close Window, Close Tab) are what makes ranking hard.
    public static let catalogues: [Catalogue] = [
        make(
            "com.apple.finder",
            [
                "Finder>About Finder", "Finder>Settings", "Finder>Empty Trash", "Finder>Hide Finder", "Finder>Hide Others",
                "Finder>Show All", "Finder>Services",
                "File>New Finder Window", "File>New Folder", "File>New Folder with Selection", "File>New Smart Folder",
                "File>New Tab", "File>Open", "File>Open With", "File>Close Window", "File>Get Info", "File>Rename",
                "File>Compress", "File>Duplicate", "File>Make Alias", "File>Quick Look", "File>Print", "File>Move to Trash",
                "File>Eject", "File>Find", "File>Tags", "File>Show Original",
                "Edit>Undo", "Edit>Redo", "Edit>Cut", "Edit>Copy", "Edit>Paste", "Edit>Paste Item", "Edit>Select All",
                "Edit>Show Clipboard", "Edit>Start Dictation", "Edit>Emoji and Symbols",
                "View>as Icons", "View>as List", "View>as Columns", "View>as Gallery", "View>Use Groups", "View>Sort By",
                "View>Show Path Bar", "View>Show Status Bar", "View>Show Preview", "View>Hide Sidebar", "View>Hide Toolbar",
                "View>Show View Options", "View>Enter Full Screen",
                "Go>Back", "Go>Forward", "Go>Enclosing Folder", "Go>Recents", "Go>Documents", "Go>Desktop",
                "Go>Downloads", "Go>Home", "Go>Computer", "Go>AirDrop", "Go>Network", "Go>Applications", "Go>Utilities",
                "Go>Go to Folder", "Go>Connect to Server",
                "Window>Minimize", "Window>Zoom", "Window>Cycle Through Windows", "Window>Merge All Windows",
                "Window>Move Tab to New Window", "Window>Bring All to Front",
            ]),
        make(
            "com.apple.Safari",
            [
                "Safari>About Safari", "Safari>Settings", "Safari>Clear History", "Safari>Hide Safari", "Safari>Quit Safari",
                "File>New Window", "File>New Private Window", "File>New Tab", "File>Open Location", "File>Close Window",
                "File>Close Tab", "File>Close Other Tabs", "File>Save As", "File>Share", "File>Export as PDF",
                "File>Print", "File>Add to Reading List", "File>Add Bookmark",
                "Edit>Undo", "Edit>Redo", "Edit>Cut", "Edit>Copy", "Edit>Paste", "Edit>Select All", "Edit>Find",
                "Edit>Find Next", "Edit>Autofill",
                "View>Show Sidebar", "View>Show Tab Bar", "View>Show Reader", "View>Zoom In", "View>Zoom Out",
                "View>Actual Size", "View>Enter Full Screen", "View>Reload Page", "View>Stop",
                "History>Back", "History>Forward", "History>Home", "History>Show All History", "History>Reopen Last Closed Tab",
                "History>Reopen All Windows from Last Session",
                "Bookmarks>Show Bookmarks", "Bookmarks>Add Bookmark", "Bookmarks>Add Bookmarks for These Tabs",
                "Develop>Show Web Inspector", "Develop>Show JavaScript Console", "Develop>Empty Caches",
                "Develop>Disable Extensions", "Develop>Show Page Source", "Develop>Responsive Design Mode",
                "Window>Minimize", "Window>Zoom", "Window>Show Previous Tab", "Window>Show Next Tab",
                "Window>Move Tab to New Window", "Window>Merge All Windows",
            ]),
        make(
            "com.apple.dt.Xcode",
            [
                "Xcode>About Xcode", "Xcode>Settings", "Xcode>Hide Xcode", "Xcode>Quit Xcode",
                "File>New File", "File>New Project", "File>New Tab", "File>New Window", "File>Open", "File>Open Quickly",
                "File>Close Tab", "File>Close Window", "File>Save", "File>Save All", "File>Duplicate", "File>Add Files",
                "File>Export", "File>Show in Finder",
                "Edit>Undo", "Edit>Redo", "Edit>Cut", "Edit>Copy", "Edit>Paste", "Edit>Select All", "Edit>Find",
                "Edit>Find and Replace", "Edit>Find in Project", "Edit>Format>Re-Indent", "Edit>Format>Shift Left",
                "Edit>Format>Shift Right", "Edit>Refactor>Rename", "Edit>Refactor>Extract Method",
                "View>Navigators>Show Project Navigator", "View>Navigators>Show Issue Navigator",
                "View>Debug Area>Show Debug Area", "View>Inspectors>Show Inspectors", "View>Show Library",
                "View>Editor>Show Assistant Editor", "View>Enter Full Screen",
                "Navigate>Jump to Definition", "Navigate>Go Back", "Navigate>Go Forward", "Navigate>Reveal in Project Navigator",
                "Navigate>Jump to Next Issue", "Navigate>Open Quickly",
                "Product>Run", "Product>Test", "Product>Build", "Product>Build For>Testing", "Product>Clean Build Folder",
                "Product>Stop", "Product>Analyze", "Product>Profile", "Product>Archive", "Product>Scheme>Edit Scheme",
                "Debug>Continue", "Debug>Step Over", "Debug>Step Into", "Debug>Step Out", "Debug>Pause",
                "Debug>Add Breakpoint", "Debug>Deactivate Breakpoints",
                "Source Control>Commit", "Source Control>Push", "Source Control>Pull", "Source Control>Discard Changes",
                "Source Control>New Branch", "Source Control>Stash Changes",
                "Window>Minimize", "Window>Zoom", "Window>Devices and Simulators", "Window>Organizer",
            ]),
        make(
            "com.apple.Notes",
            [
                "Notes>About Notes", "Notes>Settings", "Notes>Hide Notes",
                "File>New Note", "File>New Folder", "File>New Smart Folder", "File>New Tag", "File>Close", "File>Export as PDF",
                "File>Print", "File>Share", "File>Lock Note", "File>Pin Note", "File>Duplicate",
                "Edit>Undo", "Edit>Redo", "Edit>Cut", "Edit>Copy", "Edit>Paste", "Edit>Select All", "Edit>Find",
                "Edit>Attach File", "Edit>Add Link", "Edit>Check Spelling",
                "Format>Title", "Format>Heading", "Format>Subheading", "Format>Body", "Format>Monostyled",
                "Format>Bulleted List", "Format>Numbered List", "Format>Checklist", "Format>Block Quote",
                "Format>Bold", "Format>Italic", "Format>Underline", "Format>Strikethrough",
                "View>as Gallery", "View>as List", "View>Show Folders", "View>Show Attachments", "View>Zoom In", "View>Zoom Out",
                "Window>Minimize", "Window>Zoom", "Window>Notes", "Window>Show Previous Tab",
            ]),
    ]

    private static func make(_ app: String, _ lines: [String]) -> Catalogue {
        let items = lines.map { line -> Item in
            var parts = line.split(separator: ">").map(String.init)
            let title = parts.removeLast()
            return Item(path: parts, title: title, keys: nil)
        }
        return Catalogue(app: app, items: items)
    }

    /// How a person gets to a command: what they type, one character at a time, or nothing (they pick from the list).
    public enum Habit: Sendable, CaseIterable {
        /// Opens the panel and picks from the list.
        case browse
        /// Types the start of the first word.
        case prefix
        /// Types the first letters of the words ("nf" for New Folder).
        case initials
        /// Types a word from the middle of the title ("folder" for New Folder).
        case word
        /// Types their own shorthand for this command, the same each time ("nf" for New Finder Window).
        case shorthand
        /// Types a prefix with one slip: two letters swapped.
        case typo
    }

    /// What one person is like. Each command they use has a favourite way of being reached.
    public struct Person: Sendable {
        public var seed: UInt64
        public var favourites: [(app: String, id: String, weight: Double)]
        /// Favourites the person types their own shorthand for, and the shorthand.
        public var shorthand: [String: String]
        public var habitMix: [(Habit, Double)]
        /// Chance a run is an unrelated command drawn uniformly from the menu.
        public var exploration: Double
        /// The day count when favourites change: new tasks, new habits.
        public var driftAt: Int?
        /// Short chains of commands the person runs one after another, per app: after the first, the second follows.
        public var routines: [(app: String, ids: [String])] = []
        /// How often the next run is the next step of a routine.
        public var routineFollow = 0.55
    }

    public static func person(seed: UInt64, favouritesPerApp: Int = 12) -> Person {
        var rng = SeededGenerator(seed: seed)
        var favourites: [(app: String, id: String, weight: Double)] = []
        for catalogue in catalogues {
            let chosen = catalogue.items.shuffled(using: &rng).prefix(favouritesPerApp)
            for (rank, item) in chosen.enumerated() {
                // Zipf: the top few take most of the use.
                favourites.append((catalogue.app, item.id, 1.0 / Double(rank + 1)))
            }
        }
        var shorthand: [String: String] = [:]
        for fav in favourites.prefix(8) where fav.weight >= 0.2 {
            if let item = catalogues.first(where: { $0.app == fav.app })?.items.first(where: { $0.id == fav.id }) {
                // A personal abbreviation: not the first letters, the way people actually coin them.
                let words = item.title.split(separator: " ").map { String($0) }
                let letters = Array(item.title.lowercased().filter { $0.isLetter })
                let coined = words.count > 1 ? String(words.last?.prefix(3) ?? "") : String(letters.prefix(2))
                shorthand[fav.id] = coined.lowercased()
            }
        }
        var routines: [(app: String, ids: [String])] = []
        for catalogue in catalogues {
            let own = favourites.filter { $0.app == catalogue.app }.prefix(9).map(\.id)
            for chunk in stride(from: 0, to: own.count - 2, by: 3) { routines.append((catalogue.app, Array(own[chunk..<(chunk + 3)]))) }
        }
        return Person(
            seed: seed, favourites: favourites, shorthand: shorthand,
            habitMix: [
                (.browse, 0.22), (.prefix, 0.30), (.initials, 0.14), (.word, 0.10), (.shorthand, 0.16), (.typo, 0.08),
            ],
            exploration: 0.12, driftAt: nil, routines: routines, routineFollow: 0.55)
    }

    /// One run: which command, and how the person reaches it.
    public struct Intent: Sendable {
        public let app: String
        public let itemID: String
        public let habit: Habit
        /// What is typed, whole. Empty for browsing.
        public let typed: String
        /// The command run just before, in any app, if there was one.
        public let previous: (app: String, id: String)?
    }

    public static func intents(for person: Person, count: Int) -> [Intent] {
        var rng = SeededGenerator(seed: person.seed &+ 99)
        let totalWeight = person.favourites.reduce(0) { $0 + $1.weight }
        var result: [Intent] = []
        var last: (app: String, id: String)?
        for index in 0..<count {
            let drifted = person.driftAt.map { index >= $0 } ?? false
            let pool = drifted ? driftedFavourites(person) : person.favourites
            let weight = pool.reduce(0) { $0 + $1.weight }
            let (app, itemID): (String, String)
            var follow: (String, String)?
            if let last, rng.chance(person.routineFollow) {
                for routine in person.routines where routine.app == last.app {
                    if let at = routine.ids.firstIndex(of: last.id), at + 1 < routine.ids.count {
                        follow = (routine.app, routine.ids[at + 1])
                    }
                }
            }
            if let follow {
                (app, itemID) = follow
            } else if rng.chance(person.exploration) {
                let catalogue = catalogues[Int.random(in: 0..<catalogues.count, using: &rng)]
                (app, itemID) = (catalogue.app, catalogue.items[Int.random(in: 0..<catalogue.items.count, using: &rng)].id)
            } else {
                var pick = Double.random(in: 0..<max(weight, totalWeight), using: &rng)
                var chosen = pool[0]
                for fav in pool {
                    pick -= fav.weight
                    if pick <= 0 {
                        chosen = fav
                        break
                    }
                }
                (app, itemID) = (chosen.app, chosen.id)
            }
            guard let item = catalogues.first(where: { $0.app == app })?.items.first(where: { $0.id == itemID }) else {
                continue
            }
            // Only the app's own routines apply: a routine step belongs to the app it was made in.
            var habit = habit(from: person.habitMix, using: &rng)
            // A shorthand person types that shorthand for the commands they coined one for.
            if let coined = person.shorthand[itemID] {
                if rng.chance(0.7) {
                    result.append(Intent(app: app, itemID: itemID, habit: .shorthand, typed: coined, previous: last))
                    last = (app, itemID)
                    continue
                }
            } else if habit == .shorthand {
                habit = .prefix
            }
            result.append(
                Intent(
                    app: app, itemID: itemID, habit: habit, typed: typed(for: item, habit: habit, using: &rng),
                    previous: last))
            last = (app, itemID)
        }
        return result
    }

    private static func driftedFavourites(_ person: Person) -> [(app: String, id: String, weight: Double)] {
        var rng = SeededGenerator(seed: person.seed &+ 7)
        return person.favourites.map { fav in
            // The ranks of the favourites are reshuffled: last year's top command is now rare.
            (fav.app, fav.id, fav.weight * Double.random(in: 0.1...1.9, using: &rng))
        }
    }

    private static func habit(from mix: [(Habit, Double)], using rng: inout SeededGenerator) -> Habit {
        var pick = Double.random(in: 0..<mix.reduce(0) { $0 + $1.1 }, using: &rng)
        for (habit, weight) in mix {
            pick -= weight
            if pick <= 0 { return habit }
        }
        return .prefix
    }

    private static func typed(for item: Item, habit: Habit, using rng: inout SeededGenerator) -> String {
        let words = item.title.split(separator: " ").map { String($0).lowercased() }
        let first = words.first ?? item.title.lowercased()
        switch habit {
        case .browse: return ""
        case .prefix: return String(first.prefix(min(first.count, Int.random(in: 3...6, using: &rng))))
        case .initials: return words.count > 1 ? String(words.compactMap(\.first)) : String(first.prefix(3))
        case .word:
            let word = words.count > 1 ? words[Int.random(in: 1..<words.count, using: &rng)] : first
            return String(word.prefix(min(word.count, 5)))
        case .shorthand: return String(first.prefix(2))
        case .typo:
            var letters = Array(first.prefix(5))
            if letters.count >= 3 {
                let at = Int.random(in: 0..<(letters.count - 1), using: &rng)
                letters.swapAt(at, at + 1)
            }
            return String(letters)
        }
    }
}
