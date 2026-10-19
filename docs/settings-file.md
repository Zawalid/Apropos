# The settings file

Apropos keeps its settings in one readable JSON file:

```
~/Library/Application Support/Apropos/settings.json
```

Edit it while Apropos is closed, or use the Settings window. Keys are sorted, so diffs stay small. Earlier versions are
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
who never touched that setting. `SettingsRegistry` (`Sources/Apropos/Settings`) is the list of every setting, with its
page, type, default and search keywords.

| Key | Page | Type | Default |
|---|---|---|---|
| `openAtLogin` | General | bool | false |
| `showInMenuBar` | General | bool | true |
| `openHotKey` | General | hotkey | Option+Space |
| `closeOnFocusLoss` | General | bool | true |
| `resetQueryAfterSeconds` | General | number 0...3600 | 60 (0 clears every time) |
| `showAlternateCommands` | General | bool | false |
| `includeContextActions` | General | bool, list context actions in the panel | true |
| `includeUserCommands` | General | bool, list your commands and sequences | true |
| `includeSendTo` | General | bool, list Send to rows | true |
| `theme` | Appearance | `system`, `dark`, `light` | `system` |
| `interfaceSize` | Appearance | `compact`, `default`, `large` | `default` |
| `rowIcons` | Appearance | `glyph`, `appLogo`, `none` | `glyph` |
| `reduceMotion` | Appearance | bool | false |
| `contextSensing` | Context | bool, master switch | true |
| `contextDisabledApps` | Context | list of bundle ids | empty |
| `contextChips` | Appearance | subset of `document`, `url`, `folder`, `branch`, `selection`, `selectionCount` | none |
| `contextSources` | Context | subset of `document`, `url`, `folder`, `branch`, `selection`: what may be read at all | all |
| `contextSelectionBlockedApps` | Context | list of bundle ids where the selected text is never read | password managers |
| `contextIgnoreList` | Context | list of bundle ids where nothing is read | password managers |
| `predictNextCommand` | Prediction | bool | true |
| `showPredictionReasons` | Prediction | bool | true |
| `predictionSensitivity` | Prediction | `cautious`, `balanced`, `eager` | `balanced` |
| `predictionMaxRows` | Prediction | `1`, `2` | `2` |
| `predictionKeepDays` | Prediction | `30`, `90`, `365`, `0` (forever) | `365` |
| `predictionExcludedApps` | Prediction | list of bundle ids | empty |
| `externalControl` | Integrations | bool, links and Shortcuts may open Apropos and run allowed commands | true |
| `externalAlwaysConfirm` | Integrations | bool, ask before every outside run | false |
| `externalLog` | Integrations | bool, keep the last 50 outside requests | true |
| `checkForUpdates` | Updates | bool | false (opt-in) |

Value shapes: bool is `true`/`false`, choices are strings, numbers are whole numbers (clamped into their range), lists
are string arrays, a hotkey is `{ "keyCode": <virtual key code>, "modifiers": ["control", "option", "shift", "command"] }`
and needs at least one modifier. An illegal stored value falls back to the default; the rest of the file is still used.

Usage data (pins, hidden commands, aliases, run counts) is not in this file. It lives in `usage.json` beside it; see
[data-layer.md](data-layer.md).

## Safety guarantees

- Saves are atomic (write to a temporary file, then rename) and coalesced: changes within 300 ms become one write,
  and the app flushes on quit.
- Before a write replaces the file, the old one is copied into `history/settings-<UTC timestamp>.json`; only the last
  10 are kept. Restoring a version first archives the current file, so a restore can be undone.
- A file that is not valid JSON is copied to `settings.json.broken-<date>` and Apropos starts with defaults.
- A file written by a newer Apropos is used as far as it is understood, unknown settings and top-level keys are kept when
  Apropos saves, its `schemaVersion` is not lowered, and a copy is kept as `settings.json.v<N>-backup`.
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
