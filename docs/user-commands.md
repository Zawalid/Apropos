# Your own commands

A command is something you define once and run from the palette, from its own shortcut, from a link or from Shortcuts.
It uses the same engine, backends and variables as the built-in context actions (see [context-actions.md](context-actions.md)),
so the same safety rules apply.

You manage them on the Commands page of Settings: a table with an alias and a shortcut per command, a New command form,
ready-made examples, a detail sheet with approval, and Import, Export and Reveal in Finder. They are also plain files you
can edit.

## Where they live

One JSON file per command in `~/Library/Application Support/Apropos/commands/`. The folder is created the first time
something is saved; Reveal Commands Folder opens it. Edit a file while Apropos runs, then choose Reload Commands.

Before a file is replaced or removed, the old version is copied to `commands/history/<id>-<timestamp>.json` (the last 5 per
command are kept), so a change or a deletion can be undone by copying a file back. A file that cannot be used (invalid
JSON, a newer version, a definition the safety rules refuse, a duplicate id) is skipped and counted in the Reload
notification; the other commands still load.

## The file

```json
{
  "schemaVersion": 1,
  "command": {
    "id": "user:6f1c9d2e-0000-4000-8000-000000000001",
    "title": "Speak selection",
    "subtitle": "Read the selected text aloud",
    "symbol": "speaker.wave.2",
    "requires": ["selectedText"],
    "conditions": [],
    "apps": { "include": [], "exclude": ["com.1password.1password"] },
    "backend": { "type": "shell", "executable": "/usr/bin/say", "stdin": "text" },
    "output": "none",
    "confirm": false,
    "keywords": ["read", "voice"],
    "timeout": 30
  },
  "aliases": ["say"],
  "hotkey": { "keyCode": 1, "modifiers": ["control", "option"] },
  "allowFromURL": false,
  "urlConfirmed": false,
  "review": "approved"
}
```

- `id`: `user:` plus a lowercase UUID. It never changes, so usage, pins and the shortcut follow the command through edits.
  Make one with `uuidgen | tr A-Z a-z`.
- `command`: an action definition, exactly as in a context pack (backends `function`, `shell`, `appleScript`, `shortcut`,
  `urlScheme`, `keyPress`; variables `{text}`, `{files}`, `{file}`, `{directory}`, `{url}`, `{title}`, `{folder}`,
  `{branch}`, `{repo}`, `{document}`). Differences from built-in actions: `requires` may be empty (a command that only
  opens a link needs no context), and the group is always "Your commands".
- `backend` may also be `{ "type": "sequence", "sequence": { "version": 1, "steps": [...] } }`: several steps of
  different kinds with values passed between them, built in the palette and described in [sequences.md](sequences.md).
- `apps`: empty `include` means every app; otherwise only those bundle identifiers.
- `aliases`: up to 8 short names (lowercase letters, digits, `-` and `_`). Typing an alias ranks the command first. An alias
  belongs to one command.
- `hotkey`: a global shortcut that runs the command on the app in front. It needs at least one modifier and cannot be the
  panel's shortcut or another command's. It is released the moment the command is deleted, edited to another key or made
  pending. If macOS refuses a key (another app owns it) the command still works, only the shortcut is not registered.
  Commands that need context read it when the key is pressed; failures appear as a short notification.
- `allowFromURL`: off by default. See [integrations.md](integrations.md).
- `review`: `approved` (default) or `pending`. A pending command is stored but never listed, bound to a key, run from a
  link or Shortcuts, or run in any other way.

Examples:

```json
{ "schemaVersion": 1, "command": { "id": "user:...", "title": "Open the docs", "symbol": "book",
  "requires": [], "backend": { "type": "urlScheme", "url": "https://developer.apple.com/documentation" }, "output": "none" },
  "aliases": ["docs"] }
```

```json
{ "schemaVersion": 1, "command": { "id": "user:...", "title": "Look up in Dash", "symbol": "magnifyingglass",
  "requires": ["selectedText"], "backend": { "type": "urlScheme", "url": "dash://?query={text}" }, "output": "none" } }
```

## Safety

The validator refuses, at load and on every save, anything that could turn a value into code: placeholders in the
executable or in a script, a text value as a bare argument (put `--` before it, or send it on standard input), list
variables inside a longer argument, placeholders in the scheme or host of a URL. The messages say what to change.
Values reach programs only as separate arguments, standard input, environment entries (`APROPOS_TEXT` and so on),
AppleScript `argv` items or percent-encoded URL components.

## Import and export

Export writes the chosen commands (or all) to one file, `{ "schemaVersion": 1, "kind": "apropos.commands", "name": ...,
"commands": [ ... ] }`. It leaves out ids of this Mac's trust: shortcuts, `allowFromURL`, `urlConfirmed` and `review`.

Importing is two steps and nothing is stored until you say so.
1. Review: the file is checked strictly (at most 1 MB and 100 commands, every command validated, fields bounded). You are
   shown each command's title, what it runs in plain language (the program and arguments, the AppleScript text, the
   Shortcut name, the link), what it needs, and where it works. Commands that do the same as one you already have are
   flagged and skipped by default. Aliases already in use are dropped. Anything refused is listed with the reason.
2. Import: the commands you accept are stored with fresh ids. Whatever the file says about ids, shortcuts, outside access or
   approval is ignored and replaced.

Commands that run a program or an AppleScript are stored as **pending**. They do nothing until you read and approve them
(menu bar: Review Imported Commands, which shows the full definition with Approve, Later and Delete). Approving by hand
means changing `"review": "pending"` to `"approved"` in the file and choosing Reload Commands. A command whose backend you
change later keeps its approval, because you made the change yourself; a file replaced behind your back is the same trust
as any file in your own Application Support folder.

## From code

```swift
let store = UserCommandStore()                       // reads the folder
let made = try store.create(UserCommand(title: "Shout", aliases: ["up"], requires: [.selectedText],
                                        backend: .function("text.upper")))
try store.update(edited); try store.delete(made.id); let copy = try store.duplicate(made.id)
store.hotkeyConflict(combo, excluding: made.id)      // .panel, .command(title:) or nil
let review = try store.reviewFile(at: url)           // ImportReview: items, summaries, risks, rejected
store.importReviewed(review)                         // pending for scripts
try store.approve(id)                                // after the person read CommandSummary.lines(for:)
center.setUserCommands(store.commands)               // palette; pending ones are ignored
commandHotKeys.sync(store.commands, reserved: [panelCombo]) { command in ... }
```

Errors are `UserCommandError` with a `description` meant for the person editing.
