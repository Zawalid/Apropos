# The settings file

Cue keeps its settings in one readable JSON file:

```
~/Library/Application Support/Cue/settings.json
```

Edit it while Cue is closed, or use the Settings window. Keys are sorted, so diffs stay small. Earlier versions are
kept in `history/` next to it (the last 10), and Settings can export and import the file.

## Schema version 1

```json
{
  "schemaVersion": 1,
  "settings": {
    "theme": "dark",
    "openHotKey": { "keyCode": 49, "modifiers": ["option"] }
  }
}
```

Only values that differ from the default are written. A default changed in a later release therefore reaches everyone
who never touched that setting. `SettingsRegistry` (`Sources/Cue/Settings`) is the list of every setting, with its
page, type, default and search keywords.

| Key | Page | Type | Default |
|---|---|---|---|
| `openAtLogin` | General | bool | false |
| `showInMenuBar` | General | bool | true |
| `openHotKey` | General | hotkey | Option+Space |
| `closeOnFocusLoss` | General | bool | true |
| `resetQueryAfterSeconds` | General | number 0...3600 | 60 (0 clears every time) |
| `showAlternateCommands` | General | bool | false |
| `theme` | Appearance | `system`, `dark`, `light` | `system` |
| `interfaceSize` | Appearance | `compact`, `default`, `large` | `default` |
| `rowIcons` | Appearance | `glyph`, `appLogo`, `none` | `glyph` |
| `reduceMotion` | Appearance | bool | false |
| `contextSensing` | Context | bool, master switch | true |
| `contextDisabledApps` | Context | list of bundle ids | empty |
| `contextChips` | Context | subset of `document`, `url`, `folder`, `branch`, `selection`, `selectionCount` | all |
| `contextIgnoreList` | Privacy and data | list of bundle ids | password managers |
| `checkForUpdates` | Updates | bool | false (opt-in) |

Value shapes: bool is `true`/`false`, choices are strings, numbers are whole numbers (clamped into their range), lists
are string arrays, a hotkey is `{ "keyCode": <virtual key code>, "modifiers": ["control", "option", "shift", "command"] }`
and needs at least one modifier. An illegal stored value falls back to the default; the rest of the file is still used.

Usage data (pins, hidden commands, aliases, run counts) is not in this file. See the usage store notes in
[design.md](design.md) once added; it lives in `usage.json` beside this file.

## Safety guarantees

- Saves are atomic (write to a temporary file, then rename) and coalesced: changes within 300 ms become one write,
  and the app flushes on quit.
- Before a write replaces the file, the old one is copied into `history/settings-<UTC timestamp>.json`; only the last
  10 are kept. Restoring a version first archives the current file, so a restore can be undone.
- A file that is not valid JSON is copied to `settings.json.broken-<date>` and Cue starts with defaults.
- A file written by a newer Cue is used as far as it is understood, unknown settings and top-level keys are kept when
  Cue saves, its `schemaVersion` is not lowered, and a copy is kept as `settings.json.v<N>-backup`.
- A file that exists but cannot be read (permissions) is never overwritten.

## Using it from code

`SettingsStore` is `@MainActor` and `@Observable`. Read inside a SwiftUI body and the view tracks only that setting:

```swift
let store = SettingsStore()
store.bool(.showInMenuBar)
store.set(.string("dark"), for: .theme)
store.hotkey(.openHotKey)
```

`SettingsRegistry.definitions(on: page)` drives the pages, `SettingsRegistry.search(_:)` drives settings search.
