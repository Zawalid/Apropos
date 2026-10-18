import Foundation

/// The on-disk layout of the settings file and the rules for reading it. Pure functions, no I/O beyond the data given.
///
/// ```
/// { "schemaVersion": 1, "settings": { "theme": "dark", "openHotKey": { "keyCode": 49, "modifiers": ["option"] } } }
/// ```
///
/// Only values that differ from their default are written, so a default changed in a later release reaches everyone
/// who never touched the setting.
struct SettingsDocument {
    static let currentVersion = 1

    var version = SettingsDocument.currentVersion
    var values: [SettingID: SettingValue] = [:]
    /// Settings this build does not know, kept so a save does not delete them.
    var unknownSettings: [String: JSONValue] = [:]
    /// Top-level keys other than `schemaVersion` and `settings`.
    var otherKeys: [String: JSONValue] = [:]
    /// Ids whose stored value was illegal and fell back to the default.
    var repaired: [SettingID] = []

    enum ParseError: Error { case notAnObject }

    static func parse(_ data: Data) throws -> SettingsDocument {
        let top = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let object) = top else { throw ParseError.notAnObject }
        var document = SettingsDocument()
        if case .number(let version)? = object["schemaVersion"] { document.version = Int(version) }
        if case .object(let stored)? = object["settings"] {
            for (key, json) in stored {
                let id = SettingID(rawValue: key)
                guard let definition = SettingsRegistry.definition(for: id) else {
                    document.unknownSettings[key] = json
                    continue
                }
                if let value = value(from: json, for: definition.type), let valid = definition.normalized(value) {
                    document.values[id] = valid
                } else {
                    document.repaired.append(id)
                }
            }
        }
        for (key, json) in object where key != "schemaVersion" && key != "settings" { document.otherKeys[key] = json }
        document.repaired.sort { $0.rawValue < $1.rawValue }
        return document
    }

    func encoded() throws -> Data {
        var stored = unknownSettings
        for (id, value) in values {
            guard let definition = SettingsRegistry.definition(for: id), definition.defaultValue != value else { continue }
            stored[id.rawValue] = Self.json(from: value)
        }
        var top = otherKeys
        top["schemaVersion"] = .number(Double(version))
        top["settings"] = .object(stored)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.object(top)) + Data("\n".utf8)
    }

    // MARK: Value conversion

    private static let modifierNames: [(String, ModifierSet)] = [
        ("control", .control), ("option", .option), ("shift", .shift), ("command", .command),
    ]

    static func json(from value: SettingValue) -> JSONValue {
        switch value {
        case .bool(let flag): .bool(flag)
        case .string(let text): .string(text)
        case .number(let number): .number(Double(number))
        case .stringList(let list): .array(list.map(JSONValue.string))
        case .hotkey(let combo):
            .object([
                "keyCode": .number(Double(combo.keyCode)),
                "modifiers": .array(modifierNames.filter { combo.modifiers.contains($0.1) }.map { .string($0.0) }),
            ])
        }
    }

    static func value(from json: JSONValue, for type: SettingType) -> SettingValue? {
        switch (type, json) {
        case (.bool, .bool(let flag)): return .bool(flag)
        case (.string, .string(let text)), (.choice, .string(let text)): return .string(text)
        case (.number, .number(let number)): return .number(Int(number))
        case (.stringList, .array(let items)), (.multiChoice, .array(let items)):
            var list: [String] = []
            for item in items {
                guard case .string(let text) = item else { return nil }
                list.append(text)
            }
            return .stringList(list)
        case (.hotkey, .object(let object)):
            guard case .number(let code)? = object["keyCode"], case .array(let names)? = object["modifiers"],
                code >= 0, code < 256
            else { return nil }
            var modifiers = ModifierSet()
            for name in names {
                guard case .string(let text) = name, let match = modifierNames.first(where: { $0.0 == text }) else {
                    return nil
                }
                modifiers.insert(match.1)
            }
            return .hotkey(HotKeyCombo(keyCode: UInt32(code), modifiers: modifiers))
        default: return nil
        }
    }
}
