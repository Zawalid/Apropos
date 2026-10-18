# The data layer

Everything the UI reads and writes besides the live menu. All of it lives in the `Cue` package, is unit-tested, and
stays on the Mac.

| Piece | Where | File on disk |
|---|---|---|
| Settings | `Sources/Apropos/Settings` | `settings.json` (see [settings-file.md](settings-file.md)) |
| Command identity | `Sources/Apropos/Commands/CommandID.swift` | none, it is a key |
| Option-key alternates | `Sources/Apropos/Commands/MenuSnapshot.swift` | none |
| Usage, pins, hides, aliases, symbol choices | `Sources/Apropos/Usage` | `usage.json` |
| Row symbols | `Sources/Apropos/Commands/Symbol*.swift`, `Resources/SymbolPacks` | optional `packs/*.json` |

All files sit in `~/Library/Application Support/Cue/`.

## Command identity

`Command.id` is an index path: unique inside one menu read, meaningless after the app updates. Save nothing under it.
`Command.stableID` (a `CommandID`) is the key for anything persisted:

```
com.apple.finder|file>new folder
```

Bundle id, then the normalized menu trail and title. Normalization drops trailing ellipses and update counts, ignores
case, diacritics and spacing, and neutralizes `|`, `>` and `#`. Localized titles are kept as they are, so a French menu
has French identities that are stable while the app stays French. If two commands in one app collide, the shortcut is
appended (`|⌘1`), then an ordinal (`#2`); the shortcut is otherwise not part of the identity, because users remap
shortcuts. A title with nothing usable in it (`…`) falls back to its shortcut (`key ⌘K`) or its position (`item 4`).

Known limits: toggle titles ("Show Toolbar" and "Hide Toolbar") are two identities; a command whose title changes
across app versions starts from zero; switching the app's language starts the learned ranking over for that app.

## Option-key alternates

`MenuCommandMapper.commands(from:bundleID:showAlternates:)` follows AppKit's rule: an item directly after another that
has the same key, adds Option, and whose primary does not use Option, is an alternate. A run of alternates all belong to
the first item. By default they are folded into `Command.alternates` (title, shortcut, own `stableID`, target) and get no
row. With `showAlternates: true` they stay in the list with `alternateOf` set to the primary's `stableID`.
`AppMenuModel.showAlternates` mirrors the `showAlternateCommands` setting. Alternates without a shortcut cannot be
detected from the snapshot; reading `AXMenuItemPrimaryUIElement` would catch them and has not been added.

## Usage store

JSON rather than SQLite: one small record per command ever run (a count and the last ten times), pruned after a year
idle, read once at launch, written in the background, and a person can open the file and see what Cue learned.

```json
{
  "schemaVersion": 1,
  "usage": { "com.apple.finder|file>new folder": { "runs": 12, "recent": ["2026-10-18T09:00:00Z"] } },
  "preferences": { "com.apple.finder|file>get info": { "pinnedAt": "2026-10-18T09:00:00Z", "aliases": ["gi"] } }
}
```

- Only identities and times are stored. Query text and selection contents never reach the store. Commands under any
  menu whose name contains "recent" (Open Recent, Ouvrir récent) are not recorded, since their titles are file names.
- `usage` is learned and cleared by `resetLearnedRanking()` (all apps) or `resetLearnedRanking(forBundleID:)`.
  `preferences` (pins, hidden, aliases, symbol choices) are the user's and survive a reset.
- Frecency is the Firefox scheme: bucket weights by age (100, 70, 50, 30, 10 for under 4, 14, 31, 90 days and older)
  averaged over the kept run times, multiplied by the total run count. The ranker adds a capped, logarithmic boost
  (at most 60), so usage breaks ties but never beats a clearly better text match.
- Ranking: `UsageStore.rankingSignal()` returns an immutable `UsageSignal`; `CommandRanker(signal:)` then supports
  `rank(_:query:includeHidden:)` (hidden commands omitted, pinned first on an empty query, aliases match like titles and
  an exact alias goes first), `pinned(_:)` and `suggested(_:limit:)`. Suggested is the unpinned, available, non-hidden
  commands with frecency at least 100, best first, so a fresh install suggests nothing.

## Symbols

`SymbolResolver.symbols(for: rows)` returns one SF Symbol name per row, in row order, never empty. Tiers: user override,
curated pack, standard macOS command (by shortcut, then English or French title), leading verb, keyword in the title,
top-level menu, fixed fallback. Then a distinctness pass changes a row that repeats the symbol above it to its next
candidate; the row resolved by the weaker tier moves, user overrides never move. `CommandDisplay.symbol(for:)` still
exists and gives the single-command answer.

Pack format (also in `SymbolPack.swift`): `{ schemaVersion, name, bundleIDs, commands: [{ titles?, path?, shortcut?,
symbol }] }`. `titles` are compared like identities (so `Save As…` matches `Save As`), `path` restricts an entry to a
menu trail, and a shortcut-only entry matches any command with that shortcut. Starter packs for Finder, Safari, Xcode and
Claude ship as resources; `SymbolPackLibrary.bundled(plus:)` adds every valid `*.json` in a user folder, and later packs
win. A test checks that every symbol name in the tables and packs exists on the running macOS.
