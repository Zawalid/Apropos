import Foundation

/// The pages of the settings window, in sidebar order.
public enum SettingPage: String, Sendable, CaseIterable, Codable {
    case general
    case appearance
    case context
    case privacyAndData
    case updates
    case about

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .context: "Context"
        case .privacyAndData: "Privacy and data"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    /// An SF Symbol for the sidebar.
    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .context: "text.viewfinder"
        case .privacyAndData: "lock.shield"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }
}

/// One selectable value of a choice setting.
public struct SettingOption: Sendable, Equatable, Hashable {
    public let value: String
    public let title: String

    public init(_ value: String, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// The kind of control a setting needs, with whatever the control must know to draw itself.
public enum SettingType: Sendable, Equatable {
    case bool
    /// Exactly one of the options.
    case choice([SettingOption])
    /// Any subset of the options, stored in the order of the options.
    case multiChoice([SettingOption])
    case string
    /// A whole number inside `range`, shown with an optional unit such as "seconds".
    case number(range: ClosedRange<Int>, unit: String?)
    case hotkey
    /// A free list of strings, for example bundle identifiers.
    case stringList
}

/// A stored setting value. Choices are strings, multi-choices and string lists are string arrays.
public enum SettingValue: Sendable, Equatable {
    case bool(Bool)
    case string(String)
    case number(Int)
    case hotkey(HotKeyCombo)
    case stringList([String])
}

/// Names a setting. The raw value is the key in the settings file and never changes once shipped.
public struct SettingID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let openAtLogin: SettingID = "openAtLogin"
    public static let showInMenuBar: SettingID = "showInMenuBar"
    public static let openHotKey: SettingID = "openHotKey"
    public static let closeOnFocusLoss: SettingID = "closeOnFocusLoss"
    public static let resetQueryAfterSeconds: SettingID = "resetQueryAfterSeconds"
    public static let showAlternateCommands: SettingID = "showAlternateCommands"
    public static let theme: SettingID = "theme"
    public static let interfaceSize: SettingID = "interfaceSize"
    public static let rowIcons: SettingID = "rowIcons"
    public static let reduceMotion: SettingID = "reduceMotion"
    public static let contextSensing: SettingID = "contextSensing"
    public static let contextDisabledApps: SettingID = "contextDisabledApps"
    public static let contextChips: SettingID = "contextChips"
    public static let contextIgnoreList: SettingID = "contextIgnoreList"
    public static let checkForUpdates: SettingID = "checkForUpdates"
}

/// Everything the settings window needs to draw and search one setting, and everything the store needs to validate it.
public struct SettingDefinition: Sendable, Identifiable {
    public let id: SettingID
    public let title: String
    /// One line shown under the title.
    public let detail: String
    /// Extra words the settings search matches besides the title.
    public let keywords: [String]
    public let page: SettingPage
    public let type: SettingType
    public let defaultValue: SettingValue

    public init(
        id: SettingID, title: String, detail: String = "", keywords: [String] = [], page: SettingPage,
        type: SettingType, defaultValue: SettingValue
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.keywords = keywords
        self.page = page
        self.type = type
        self.defaultValue = defaultValue
    }

    /// Returns `value` if it is legal for this setting's type, a repaired version if it can be, else nil.
    func normalized(_ value: SettingValue) -> SettingValue? {
        switch (type, value) {
        case (.bool, .bool): return value
        case (.string, .string): return value
        case (.choice(let options), .string(let text)):
            return options.contains { $0.value == text } ? value : nil
        case (.multiChoice(let options), .stringList(let list)):
            let chosen = Set(list)
            return .stringList(options.map(\.value).filter(chosen.contains))
        case (.number(let range, _), .number(let number)):
            return .number(min(max(number, range.lowerBound), range.upperBound))
        case (.hotkey, .hotkey(let combo)): return combo.isValid ? value : nil
        case (.stringList, .stringList(let list)):
            var seen = Set<String>()
            let cleaned = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return .stringList(cleaned)
        default: return nil
        }
    }
}

/// The list of every setting Cue has. Add a setting here and it appears in the file, the store and the search.
public enum SettingsRegistry {
    public static let all: [SettingDefinition] = general + appearance + context + privacy + updates

    public static func definition(for id: SettingID) -> SettingDefinition? { byID[id] }

    public static func definitions(on page: SettingPage) -> [SettingDefinition] { all.filter { $0.page == page } }

    /// Settings whose title, detail or keywords contain every word of `query`, case and diacritics ignored.
    public static func search(_ query: String) -> [SettingDefinition] {
        let words = query.split(separator: " ").map { fold(String($0)) }
        guard !words.isEmpty else { return [] }
        return all.filter { definition in
            let haystack = fold(([definition.title, definition.detail] + definition.keywords).joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static let byID: [SettingID: SettingDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) })

    // MARK: Option sets

    public static let themeOptions = [
        SettingOption("system", "System"), SettingOption("dark", "Dark"), SettingOption("light", "Light"),
    ]
    public static let interfaceSizeOptions = [
        SettingOption("compact", "Compact"), SettingOption("default", "Default"), SettingOption("large", "Large"),
    ]
    public static let rowIconOptions = [
        SettingOption("glyph", "Glyph"), SettingOption("appLogo", "App logo"), SettingOption("none", "None"),
    ]
    public static let contextChipOptions = [
        SettingOption("document", "Document"), SettingOption("url", "URL"), SettingOption("folder", "Folder"),
        SettingOption("branch", "Branch"), SettingOption("selection", "Selection"),
        SettingOption("selectionCount", "Selection count"),
    ]

    /// Password managers and similar apps. Cue reads nothing in them. Browsers cannot be listed here: a bank in a
    /// browser tab is the same app as any other page.
    public static let defaultIgnoreList: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
    ]

    // MARK: Definitions

    private static let general: [SettingDefinition] = [
        SettingDefinition(
            id: .openAtLogin, title: "Open at login", detail: "Start Cue when you log in.",
            keywords: ["startup", "launch", "login item", "boot"], page: .general, type: .bool,
            defaultValue: .bool(false)),
        SettingDefinition(
            id: .showInMenuBar, title: "Show in menu bar", detail: "Keep the Cue icon in the menu bar.",
            keywords: ["status item", "icon", "tray"], page: .general, type: .bool, defaultValue: .bool(true)),
        SettingDefinition(
            id: .openHotKey, title: "Open Cue", detail: "The shortcut that opens the panel.",
            keywords: ["hotkey", "shortcut", "keyboard", "global"], page: .general, type: .hotkey,
            defaultValue: .hotkey(.default)),
        SettingDefinition(
            id: .closeOnFocusLoss, title: "Close when Cue loses focus",
            detail: "Dismiss the panel when you click elsewhere.", keywords: ["dismiss", "hide", "blur", "click away"],
            page: .general, type: .bool, defaultValue: .bool(true)),
        SettingDefinition(
            id: .resetQueryAfterSeconds, title: "Reset search after",
            detail: "Clear the search field when the panel has been closed this long. 0 clears it every time.",
            keywords: ["query", "clear", "forget", "timeout"], page: .general,
            type: .number(range: 0...3600, unit: "seconds"), defaultValue: .number(60)),
        SettingDefinition(
            id: .showAlternateCommands, title: "Show alternate commands",
            detail: "List Option-key variants, such as Empty Trash Securely, as their own rows.",
            keywords: ["option", "hidden", "variants", "secure"], page: .general, type: .bool,
            defaultValue: .bool(false)),
    ]

    private static let appearance: [SettingDefinition] = [
        SettingDefinition(
            id: .theme, title: "Theme", detail: "Follow the system or force dark or light.",
            keywords: ["dark mode", "light mode", "appearance", "color"], page: .appearance,
            type: .choice(themeOptions), defaultValue: .string("system")),
        SettingDefinition(
            id: .interfaceSize, title: "Interface size", detail: "Row height and text size in the panel.",
            keywords: ["density", "compact", "large", "text size", "zoom"], page: .appearance,
            type: .choice(interfaceSizeOptions), defaultValue: .string("default")),
        SettingDefinition(
            id: .rowIcons, title: "Row icons", detail: "What the icon at the start of each row shows.",
            keywords: ["symbol", "glyph", "logo", "icon"], page: .appearance, type: .choice(rowIconOptions),
            defaultValue: .string("glyph")),
        SettingDefinition(
            id: .reduceMotion, title: "Reduce motion", detail: "Skip panel animations even if the system allows them.",
            keywords: ["animation", "accessibility", "transition"], page: .appearance, type: .bool,
            defaultValue: .bool(false)),
    ]

    private static let context: [SettingDefinition] = [
        SettingDefinition(
            id: .contextSensing, title: "Sense context", detail: "Read the frontmost app's document, URL and selection.",
            keywords: ["accessibility", "selection", "master switch", "chips"], page: .context, type: .bool,
            defaultValue: .bool(true)),
        SettingDefinition(
            id: .contextDisabledApps, title: "Apps with context off",
            detail: "Bundle identifiers of apps where Cue reads nothing but the menu.",
            keywords: ["per app", "disable", "exclude", "bundle"], page: .context, type: .stringList,
            defaultValue: .stringList([])),
        SettingDefinition(
            id: .contextChips, title: "Context chips", detail: "Which pieces of context appear above the results.",
            keywords: ["chips", "document", "url", "branch", "folder", "selection"], page: .context,
            type: .multiChoice(contextChipOptions), defaultValue: .stringList(contextChipOptions.map(\.value))),
    ]

    private static let privacy: [SettingDefinition] = [
        SettingDefinition(
            id: .contextIgnoreList, title: "Never read these apps",
            detail: "Password managers and banks. Cue reads nothing in them, not even the document title.",
            keywords: ["password", "bank", "secret", "ignore", "block", "bundle"], page: .privacyAndData,
            type: .stringList, defaultValue: .stringList(defaultIgnoreList)),
    ]

    private static let updates: [SettingDefinition] = [
        SettingDefinition(
            id: .checkForUpdates, title: "Check for updates",
            detail: "Ask the update server whether a new version exists. Off until you turn it on.",
            keywords: ["sparkle", "upgrade", "version", "network"], page: .updates, type: .bool,
            defaultValue: .bool(false))
    ]
}
