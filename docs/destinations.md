# Send to

A keyboard-first "send this to..." layer, the Share Sheet done well. Whatever Apropos senses (a selection, a page, the
selected files, a folder) can go to Notes, Reminders, Things, Obsidian, Bear, a Mail draft, a folder or the system Share
menu without leaving the keyboard. The destinations you use most come to the top, separately for text, pages and files.

It is built on the context action engine ([context-actions.md](context-actions.md)) and uses its backends, validator
and safety rules unchanged. Destinations are data in packs, like actions ([user-commands.md](user-commands.md)).

```
ContextSnapshot.values --> Payload (text, page, files, folder)        DestinationLibrary (JSON packs, bundled + user)
          |                         |                                          |
          v                         v                                          v
      SendToCenter --- rows ---> PaletteModel (Send to row, recents, destination list level, confirmation)
          |  perform
          v
   DestinationRunner --- the destination's variant --> ActionEngine --> URL scheme / AppleScript / program / Shortcut
          |                                           `-> services.share (system Share menu)
          `-> usage store + run log: ids only (send:text>dest:notes)
```

## In the palette

With a selection, a page or files in front, the palette lists a **Send selection to...** row at the head of the matching
group (Selected text, Selected files, This page, This folder). Beside it come up to two **direct rows** for the
destinations you used most for that kind of thing: **Send selection to Notes**. Direct rows appear only after you used
a destination; a fresh install shows only the generic row.

- Return on a direct row sends at once, or shows the preview first (see below).
- Return on **Send selection to...** opens the destination list in the same panel. A chip in the search field says where
  you are (`< Send selection to`), the list is ranked by use and searchable, and the footer says what Return does.
- **Escape goes back one level**: it cancels a pending confirmation, then leaves the destination list, then (at the top
  level) closes the panel, as always. Clicking the chip also goes back.
- A destination whose app is not installed is not listed. A destination that cannot take this payload (for example text
  too long for a link) is listed but dimmed, with the reason.

### Confirmation

Nothing ever sends by itself, and anything that leaves the Mac or leaves a visible side effect needs a second, confirming
Return. The row shows a banner above the footer with a one-line preview and the keys:

```
Open a draft in Mail?
"Quarterly numbers look good, but the margin on the hardware line..." (112 characters)        [Return] Send   [esc] Cancel
```

Which destinations ask: the Mail draft, the Share menu, moving files, and any destination (yours included) that hands the
payload to a web address (`http` or `https` link). Typing, moving the highlight or pressing Escape drops the preview.

### Failures

A failure shows a message that names the destination (never the content), and the panel stays open at the same place with
the payload intact. Return tries again; Escape goes back and you can pick another destination.

```
Could not send to Notes. If macOS asked to let Apropos control Notes, allow it in Privacy & Security, Automation.
Nothing was lost. Return tries again, Esc goes back.
```

## Payloads

| Kind | Made from | Row says |
|---|---|---|
| `text` | the selection (up to 200,000 characters; blank selections are no payload); carries the page it came from, if any | selection |
| `page` | an http or https page URL (at most 4,096 characters) and its title (the host when there is none) | page |
| `files` | the files selected in Finder (absolute paths, at most 200) | file / 3 files |
| `folder` | Finder's folder, only in Finder and only when no file is selected | folder |

A browser selection offers both a text row and a page row. Control characters other than tab and line breaks are removed
(a NUL cannot travel in a program argument). Every payload also has a `title` for naming a note or a draft: the first
line of a selection (80 characters at most), the page title, the file name or "3 files", the folder name.

A payload prints as counts only (`Payload(text, text: 214 chars, files: 0, url: yes)`), so a log line or a dump never
carries the content.

## Built-in destinations

| Destination | Takes | What it does | Needs |
|---|---|---|---|
| Notes (`dest:notes`) | text, page | New note in the default account: the selection as the body with its source link, or a page's title and link. Plain AppleScript `make new note` | Notes installed; allow Apropos to control Notes the first time (Automation) |
| Reminders (`dest:reminders`) | text, page | New reminder in the default list: the first line as the name, the selection (and the link) as its notes | Reminders installed; Automation for Reminders |
| Things (`dest:things`) | text, page | `things:///add` to the Inbox with a title and notes (8,000 characters at most) | Things 3 installed |
| Obsidian (`dest:obsidian`) | text, page | `obsidian://new` in the last used vault, without bringing Obsidian forward; a page becomes a Markdown link (10,000 characters at most) | Obsidian installed with a vault |
| Bear (`dest:bear`) | text, page | `bear://x-callback-url/create`, without opening the note (10,000 characters at most) | Bear installed |
| Mail draft (`dest:mail`) | text, page, files | Opens a compose window with a subject, a body and the files attached. **It never sends**: the script has no send command and a test fails if one appears. Asks for confirmation | Mail installed; Automation for Mail |
| Copy or move to a folder (`dest:folder.copy.<hash>`, `dest:folder.move.<hash>`) | files, folder | `cp -R -n` or `mv -n` into a folder you chose, never overwriting. A folder chooser opens the first time; the last five folders are remembered and offered as rows (three at a time). Moving asks for confirmation | nothing |
| Share (`dest:share`) | everything | The system Share menu (`NSSharingServicePicker`) for the payload: AirDrop, Messages, Mail, anything installed. Asks for confirmation | nothing |

"Installed" means `NSWorkspace` finds the app by bundle identifier (`com.apple.Notes`, `com.apple.reminders`,
`com.culturedcode.ThingsMac`, `md.obsidian`, `net.shinyfrog.bear`, `com.apple.mail`).

## A destination

```json
{
  "id": "dest:things",
  "title": "Things",
  "subtitle": "New to-do in the Inbox",
  "symbol": "checkmark.circle",
  "app": "com.culturedcode.ThingsMac",
  "accepts": ["text", "page"],
  "keywords": ["todo", "task", "inbox"],
  "confirm": "none",
  "preview": "Add to Things",
  "maxTextCharacters": 8000,
  "timeout": 15,
  "failureHint": "Things could not open the link.",
  "variants": [
    { "kinds": ["page"], "backend": { "type": "urlScheme", "url": "things:///add?title={title}&notes={url}" } },
    { "kinds": ["text"], "backend": { "type": "urlScheme", "url": "things:///add?title={title}&notes={text}%0A%0A{url}" } },
    { "kinds": ["text"], "backend": { "type": "urlScheme", "url": "things:///add?title={title}&notes={text}" } }
  ]
}
```

- `id`: `dest:name` (built in) or `user:name`, lowercase letters, digits and `. _ -`. It is the identity usage and the run
  log follow; never rename a shipped one. Later definitions with the same id replace earlier ones.
- `accepts`: the payload kinds it takes. `app`: bundle identifier that must be installed (omit for none).
- `confirm`: `none` or `preview`. `preview`: the verb of the confirmation line ("Open a draft in Mail").
- `maxTextCharacters`: a lower text limit for destinations that cannot take long text (links).
- `handler`: `engine` (default) or `shareMenu`; the latter is for built-in destinations only.
- `variants`: tried in order; the first whose `kinds` match the payload and whose `{placeholders}` the payload can fill is
  used. A selection from a page fills `{url}`, a selection from anywhere else does not, so a variant that uses `{url}`
  put first falls through to one without it. `kinds` empty means every kind the destination accepts.
- A `backend` is the same JSON as in an action pack: `urlScheme`, `appleScript`, `shell`, `shortcut`. For readability
  `sourceLines` (a list of lines) may replace `source`. `function` and `keyPress` backends are not allowed here.
- Placeholders: `{text}`, `{title}`, `{url}`, `{files}`, `{file}`, `{fileName}`, `{fileNames}`, `{folder}`, with the same
  rules as actions (`{{` and `}}` are literal braces). `{title}` is always the payload's title.

An AppleScript destination:

```json
{ "id": "user:ulysses", "title": "Ulysses", "symbol": "doc.text", "app": "com.ulyssesapp.mac", "accepts": ["text"],
  "review": "approved",
  "variants": [ { "backend": { "type": "appleScript",
    "sourceLines": [ "on run argv", "  set theText to item 1 of argv", "  tell application \"Ulysses\" to ...", "end run" ],
    "arguments": [ "--", "{text}" ] } } ] }
```

## Adding one

1. Write a pack file: `{ "schemaVersion": 1, "name": "Mine", "destinations": [ ... ] }` and save it in
   `~/Library/Application Support/Apropos/destinations/`. It loads at launch, after the built-in ones.
2. A file with a newer `schemaVersion`, invalid JSON or a refused definition is skipped (the rest still load) and
   reported in `DestinationLibrary.issues`.
3. A destination that runs a program, an AppleScript or a Shortcut stays **pending**, unlisted and never run, until you
   have read it and added `"review": "approved"` to it. A destination that only opens a link needs no review.
4. For a new built-in: add it to `Sources/Apropos/Resources/DestinationPacks/builtin.json`, then a test in
   `BuiltinDestinationTests` with the fake runner (`SendRecorder`) that checks exactly which program, arguments or link
   the engine was asked to run.

## Safety rules

The point is that a selection can never become code. The destination layer reuses the engine and adds its own checks;
`SendToInjectionTests` sends quotes, newlines, AppleScript and shell metacharacters, `$(...)`, `{text}` lookalikes,
`%00`, leading dashes, emoji, right-to-left marks and 200,000 characters through every backend type and inspects exactly
what the engine was asked to run.

1. Payload text reaches a program only as a separate argument, standard input, an environment entry (16 KB or less), an
   AppleScript `argv` item or a percent-encoded URL component. Never string interpolation into script or program text.
2. An AppleScript destination must pass a literal `--` as its first argument. `osascript` reads a leading dash in a value
   after the script as one of its own options (`-s`, `-e`), so the `--` ends option parsing before any value.
3. Scripts are literal; the engine expands placeholders only in `arguments`. The action validator refuses placeholders in
   the executable, in an interpreter's script, in a link's scheme or host, a text value that could start with a dash as a
   bare argument, and `file:`, `javascript:` and `data:` links.
4. Folder destinations carry the folder as a literal in the argument list (braces escaped) with a trailing slash, so
   a missing folder is an error rather than a new file, and use `-n` so nothing is overwritten.
5. A pack destination that runs code needs your approval (above), and one that hands content to a web address always asks
   for a confirming Return.
6. Backends in destinations are limited to `urlScheme`, `appleScript`, `shell`, `shortcut`.
7. Nothing is sent without a Return; the Mail script has no send command.

## Privacy

- Payloads live in memory only, for as long as the panel needs them, and are dropped when the panel opens again.
- The usage store and the run log learn **ids only**: `send:text>dest:notes` (kind and destination) and a time. No text, URL,
  title, file name or path. A folder destination's id carries a 4-byte hash of its path, never the path. The run log
  additionally records the kinds of context that were present, as for any command.
- Logs carry the destination id and `succeeded` or an error kind. Error messages name the destination, never the content.
- Send-to rows are not added to the menu bar's recent commands list.
- Reset learned ranking forgets which destinations you used. The remembered folders are a separate small file
  (`send-folders.json`, local, never exported).
- Nothing leaves the Mac except through the destination you chose and confirmed; Apropos adds no network access.

## Learning and ranking

Each row has the identity `send:<kind>` (the generic row) or `send:<kind>><destination id>` (a destination), which the
usage store, pins, hiding and the prediction run log use like any command. Because the kind is part of the id,
destinations are ranked separately for text, pages and files: using Notes for text does not promote it for files. The
destination list is ordered by use then by the library's order; the top two used destinations also appear as direct rows.

## From code

```swift
let send = SendToCenter(library: .bundled(plus: DestinationLibrary.userDirectory), services: .live,
                        folders: SendFolderStore(url: SendFolderStore.defaultURL))
send.frecency = { usageStore.frecency($0) }
send.chooseFolder = { move in await FolderChooser.choose(move: move) }
palette.attachSend(send)                      // rows, destination list and confirmation flow into the palette
service.onSnapshot = { send.update(with: $0) }
```

`DestinationRunner(services:).send(destination, payload:, confirmed:)` is the whole of sending; tests pass a fake
`SendServices` (see `SendRecorder` in `Tests/AproposTests/SendToSupport.swift`) so no note, reminder, draft or file is ever
created while developing.

## What is verified

Unit tests (fake runner, no app touched): payload derivation and limits, pack loading and validation, trust rules,
injection with hostile payloads for AppleScript, links and programs, each built-in destination's exact arguments or link,
the Mail script never sending, confirmation, failure and retry, ranking per kind, folder remembering, learning ids. Previews
and agent screenshots (`palette-send-*`) show the list, the confirmation and the error state. The three AppleScripts compile
(`osacompile`) and the Notes HTML escaping was run on hostile text without touching Notes.

Not verified without the real apps: that each app accepts what is sent (Notes, Reminders and Mail scripts, the Things,
Obsidian and Bear links, Mail attachments), the Automation permission prompts, the system Share menu, the folder chooser,
and the panel's behaviour when those take focus.
