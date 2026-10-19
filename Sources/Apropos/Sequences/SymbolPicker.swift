import Foundation

/// One SF Symbol the picker offers, with the words that find it besides its own name.
public struct PickerSymbol: Sendable, Hashable, Identifiable {
    public let name: String
    public let keywords: [String]
    public var id: String { name }
}

/// A named run of symbols in the picker: Actions, Files, Web...
public struct SymbolSection: Sendable, Equatable, Identifiable {
    public let title: String
    public let symbols: [PickerSymbol]
    public var id: String { title }
}

/// A step of the arrow keys inside the picker.
public enum SymbolMove: Sendable {
    case left, right, up, down
}

/// The symbols a person can choose for a command they save, and how the picker finds and walks through them. It has no
/// views in it: the grid is drawn from `sections`, and the arrow keys call `neighbour`.
public enum SymbolPicker {
    /// How many symbols a row of the grid holds. The view lays out exactly this many, so up and down land right.
    public static let columns = 12

    /// The symbol used when nothing better is known and the one that says "this is a sequence".
    public static let defaultSymbol = "square.stack.3d.up"

    // MARK: The curated list

    /// Each group is `name: keywords` lines. Names are SF Symbols that exist in SF Symbols 5 (macOS 14), so none renders
    /// as an empty square on the oldest supported system; a test checks every name resolves.
    private static let source: [(title: String, lines: [String])] = [
        (
            "Actions",
            [
                "bolt: lightning fast power quick",
                "play.fill: run start go", "pause.fill: wait stop", "stop.fill: halt end",
                "forward.fill: next skip", "backward.fill: previous back",
                "arrow.clockwise: refresh reload again", "arrow.counterclockwise: undo redo back",
                "arrow.triangle.2.circlepath: sync refresh convert", "repeat: loop again", "shuffle: random mix",
                "checkmark: done ok yes", "checkmark.circle: done ok yes complete", "xmark: close no cancel",
                "xmark.circle: close no cancel clear", "plus: add new create", "plus.circle: add new create",
                "minus: remove less", "minus.circle: remove less", "trash: delete remove bin",
                "pencil: edit write change", "wand.and.stars: magic fix clean tidy", "sparkles: magic new shine",
                "magnifyingglass: search find look",
                "arrow.up.arrow.down: sort swap reorder", "arrow.down.circle: download get",
                "arrow.up.circle: upload send", "arrow.right.circle: go next open", "flag: mark report",
                "star: favorite rate", "heart: love like favorite", "bookmark: save later", "pin: keep attach",
                "bell: notify alert reminder", "timer: wait countdown", "clock: time schedule", "alarm: wake time",
                "power: quit shutdown", "gearshape: settings preferences options", "slider.horizontal.3: adjust tune",
            ]
        ),
        (
            "Files",
            [
                "doc: file page document", "doc.text: file text document", "doc.on.doc: copy duplicate",
                "doc.on.clipboard: paste clipboard", "doc.badge.plus: new file create",
                "doc.zipper: zip archive compress", "folder: directory",
                "folder.badge.plus: new folder create", "folder.badge.minus: remove folder",
                "tray: inbox box", "tray.full: inbox full", "archivebox: archive store", "externaldrive: disk drive",
                "paperclip: attach attachment", "link: url connect",
                "square.and.pencil: compose write new", "note.text: note memo", "books.vertical: library",
                "book: read manual", "newspaper: news article", "photo: image picture",
                "photo.on.rectangle: images pictures",
                "camera: photo screenshot", "scissors: cut trim", "printer: print paper", "shippingbox: package bundle",
                "icloud: cloud sync", "icloud.and.arrow.up: upload cloud", "icloud.and.arrow.down: download cloud",
            ]
        ),
        (
            "Web",
            [
                "globe: world internet browser", "safari: browser web compass", "network: internet connect",
                "link.badge.plus: add link", "wifi: wireless internet",
                "antenna.radiowaves.left.and.right: signal broadcast",
                "cloud: online server", "arrow.down.to.line: download save",
                "qrcode: scan code", "tag: label price", "mappin.and.ellipse: place location map",
                "map: directions place", "location: gps place", "house: home start", "cart: shop buy store",
                "creditcard: pay buy card", "lock: secure private", "lock.open: unlock open", "key: password access",
                "shield: security protect", "eye: view show watch", "eye.slash: hide private",
                "server.rack: server host",
                "personalhotspot: share connect",
                "macwindow: window browser app", "square.and.arrow.up: share export",
            ]
        ),
        (
            "Text",
            [
                "textformat: font type text", "textformat.size: size font", "bold: strong heavy",
                "italic: slant emphasis",
                "underline: line under", "strikethrough: cross out", "text.alignleft: left align",
                "text.aligncenter: center align", "text.alignright: right align", "text.justify: justify align",
                "list.bullet: bullets list", "list.number: numbered list", "text.quote: quote cite",
                "character.cursor.ibeam: cursor type input", "textformat.abc: letters spelling",
                "number: digits count", "text.append: append add text",
                "paragraph: paragraph block", "quote.opening: quote", "character.book.closed: dictionary define",
                "pencil.line: write sign", "highlighter: highlight mark", "signature: sign name",
                "text.magnifyingglass: find text search", "textformat.alt: case capitals",
                "rectangle.and.pencil.and.ellipsis: rename edit",
            ]
        ),
        (
            "Dev",
            [
                "terminal: shell command line",
                "chevron.left.forwardslash.chevron.right: code html", "curlybraces: code json braces",
                "hammer: build make", "wrench.and.screwdriver: tools fix repair", "ladybug: bug debug",
                "cpu: processor chip", "memorychip: memory ram", "arrow.triangle.branch: git branch",
                "arrow.triangle.merge: git merge", "arrow.triangle.pull: git pull request",
                "point.3.connected.trianglepath.dotted: graph git network", "function: formula math code",
                "command: key shortcut cmd", "option: key alt", "shift: key capital", "keyboard: type keys shortcut",
                "swift: language apple", "doc.text.magnifyingglass: inspect log read",
                "testtube.2: test lab", "gauge: speed performance", "checklist: tasks todo tests",
                "list.bullet.rectangle: list log", "square.stack.3d.up: stack layers sequence",
                "cube: package object model", "puzzlepiece.extension: plugin extension",
                "stethoscope: health check", "externaldrive.connected.to.line.below: database server",
            ]
        ),
        (
            "Media",
            [
                "play.circle: play video", "music.note: song audio", "music.note.list: playlist songs",
                "speaker.wave.2: sound volume", "speaker.wave.3: sound loud", "speaker.slash: mute silent",
                "mic: record voice", "mic.slash: mute voice", "video: camera film", "film: movie video",
                "tv: screen television", "headphones: audio listen", "waveform: audio sound", "record.circle: record",
                "airplayaudio: cast stream", "backward.end: start rewind", "forward.end: end skip",
                "repeat.1: loop once",
                "camera.viewfinder: scan capture", "photo.stack: images gallery", "paintbrush: draw paint style",
                "paintpalette: colors design", "wand.and.rays: effects magic", "slider.vertical.3: mixer levels",
                "rectangle.on.rectangle: layers screens", "gamecontroller: game play", "theatermasks: drama arts",
            ]
        ),
        (
            "Communication",
            [
                "envelope: mail email message", "paperplane: send mail", "bubble.left: chat comment",
                "bubble.left.and.bubble.right: chat reply",
                "message: text sms chat", "phone: call telephone",
                "person: user contact", "person.2: people team", "person.3: people group team",
                "person.crop.circle: account profile", "at: mention email", "bell.badge: notification alert",
                "megaphone: announce shout", "tray.and.arrow.up: send outbox", "tray.and.arrow.down: receive inbox",
                "calendar: date event schedule", "calendar.badge.plus: new event", "text.bubble: message chat",
                "hand.wave: hello greet", "face.smiling: emoji happy", "hand.thumbsup: like approve",
                "quote.bubble: quote comment", "person.badge.plus: invite add person",
            ]
        ),
        (
            "Symbols",
            [
                "circle: round dot", "square: box", "triangle: shape", "star.fill: favorite",
                "flame: hot fire trending",
                "drop: water liquid", "leaf: nature green eco", "moon: night dark", "sun.max: day light bright",
                "cloud.sun: weather", "snowflake: cold winter", "sparkle: shine new", "crown: top best premium",
                "flag.fill: mark report", "rosette: award badge", "infinity: forever loop",
                "percent: discount ratio", "plusminus: math", "equal: math same", "dollarsign.circle: money price",
                "chart.bar: stats graph", "chart.pie: stats share",
                "chart.line.uptrend.xyaxis: growth stats", "lightbulb: idea tip", "brain.head.profile: think ai mind",
                "atom: science", "globe.europe.africa: world earth", "airplane: travel flight", "car: drive travel",
                "bicycle: ride", "figure.walk: walk move", "cup.and.saucer: coffee break", "fork.knife: food meal",
                "gift: present reward", "pawprint: animal pet", "hand.raised: stop wait",
                "target: goal aim",
            ]
        ),
    ]

    /// The curated list in groups. A symbol listed in two groups appears only in the first.
    public static let groups: [SymbolSection] = {
        var seen = Set<String>()
        return source.map { group in
            let symbols = group.lines.compactMap { line -> PickerSymbol? in
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard let name = parts.first, seen.insert(name).inserted else { return nil }
                let keywords = parts.count > 1 ? parts[1].split(separator: " ").map(String.init) : []
                return PickerSymbol(name: name, keywords: keywords)
            }
            return SymbolSection(title: group.title, symbols: symbols)
        }
    }()

    /// Every curated symbol, in group order.
    public static let all: [PickerSymbol] = groups.flatMap(\.symbols)

    private static let byName: [String: PickerSymbol] = Dictionary(
        all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

    // MARK: Finding

    /// What the grid shows. With no query: `Suggested` (when there are suggestions), then the groups. With a query: one
    /// section of matches, best first, then a `Custom` symbol when the query itself is a symbol name (`custom`).
    public static func sections(query: String, suggested: [String] = [], custom: String? = nil) -> [SymbolSection] {
        let tokens = tokens(of: query)
        if tokens.isEmpty {
            let picked = suggested.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let suggestions = picked.map { byName[$0] ?? PickerSymbol(name: $0, keywords: []) }
            let shown = Set(picked)
            var result: [SymbolSection] = []
            if !suggestions.isEmpty { result.append(SymbolSection(title: "Suggested", symbols: suggestions)) }
            for group in groups {
                let rest = group.symbols.filter { !shown.contains($0.name) }
                if !rest.isEmpty { result.append(SymbolSection(title: group.title, symbols: rest)) }
            }
            return result
        }
        let ranked = all.compactMap { symbol -> (PickerSymbol, Int)? in
            score(symbol, tokens: tokens).map { (symbol, $0) }
        }
        .sorted { $0.1 < $1.1 }.map(\.0)
        var result: [SymbolSection] = []
        if !ranked.isEmpty { result.append(SymbolSection(title: "Matches", symbols: ranked)) }
        // The name as typed comes after the matches, so the best match is what Return saves; alone when nothing matches.
        if let custom, !ranked.contains(where: { $0.name == custom }) {
            result.append(SymbolSection(title: "Custom", symbols: [PickerSymbol(name: custom, keywords: [])]))
        }
        return result
    }

    private static func tokens(of query: String) -> [String] {
        query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Lower is better; nil means it does not match. Every word typed must match the name or a keyword.
    private static func score(_ symbol: PickerSymbol, tokens: [String]) -> Int? {
        let nameParts = symbol.name.split(separator: ".").map(String.init)
        var total = 0
        for token in tokens {
            if symbol.name == token {
                total += 0
            } else if nameParts.contains(token) {
                total += 1
            } else if nameParts.contains(where: { $0.hasPrefix(token) }) {
                total += 2
            } else if symbol.keywords.contains(token) {
                total += 3
            } else if symbol.keywords.contains(where: { $0.hasPrefix(token) }) {
                total += 4
            } else if symbol.name.contains(token) {
                total += 6
            } else {
                return nil
            }
        }
        return total * 100 + symbol.name.count
    }

    // MARK: Walking

    /// The symbol an arrow key lands on, starting at `current`. Left and right walk the order; up and down keep the
    /// column across the rows of a section and across the border between two sections. `nil` when there is no
    /// symbol that way (the top row going up, the last going down). When `current` is not shown, any key lands on the
    /// first symbol.
    public static func neighbour(
        of current: String, move: SymbolMove, in sections: [SymbolSection], columns: Int = columns
    ) -> String? {
        guard columns > 0 else { return nil }
        let flat = sections.flatMap(\.symbols).map(\.name)
        guard !flat.isEmpty else { return nil }
        guard let at = flat.firstIndex(of: current) else { return flat[0] }
        switch move {
        case .left: return at > 0 ? flat[at - 1] : nil
        case .right: return at + 1 < flat.count ? flat[at + 1] : nil
        case .up, .down:
            var start = 0
            var position = (section: 0, index: 0)
            for (number, section) in sections.enumerated() {
                if at < start + section.symbols.count {
                    position = (number, at - start)
                    break
                }
                start += section.symbols.count
            }
            let column = position.index % columns
            let row = position.index / columns
            let section = sections[position.section]
            let lastRow = (section.symbols.count - 1) / columns
            if move == .up {
                if row > 0 { return section.symbols[(row - 1) * columns + column].name }
                guard position.section > 0 else { return nil }
                return Self.symbol(in: sections[position.section - 1], atLastRowColumn: column, columns: columns)
            }
            if row < lastRow {
                return section.symbols[min((row + 1) * columns + column, section.symbols.count - 1)].name
            }
            guard position.section + 1 < sections.count else { return nil }
            return sections[position.section + 1].symbols[min(column, sections[position.section + 1].symbols.count - 1)]
                .name
        }
    }

    private static func symbol(in section: SymbolSection, atLastRowColumn column: Int, columns: Int) -> String {
        let lastRow = (section.symbols.count - 1) / columns
        return section.symbols[min(lastRow * columns + column, section.symbols.count - 1)].name
    }
}
