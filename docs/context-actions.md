# Context actions

Menu search lists what an app already offers. Context actions are the other half: things Apropos can do with what it
senses (the selected text, the selected files, the page, the folder, the git repository), in any app, whether or not the
app has a menu item for it. This is the part of Apropos that is not a menu search.

```
ContextService (off the main thread)        ActionPackLibrary (JSON, bundled + user)
        |  ContextSnapshot.values                    |
        v                                            v
ContextActionCenter  --- applicable actions --->  palette commands (Selected text, Selected files, This page, This folder)
        |  run(command)                              ranked and suggested through UsageStore like any command
        v
ActionEngine --- backend (function, shell, AppleScript, Shortcut, URL, key press) ---> output (clipboard, replace, notice)
```

## Context values

`ContextSnapshot.values` is a `ContextValues`, the typed raw data behind the chips:

| Field | Meaning | Requirement |
|---|---|---|
| `selectedText` | Whole selection, capped at 200,000 characters | `selectedText` |
| `selectedFiles` | Absolute file URLs selected in Finder | `selectedFiles` |
| `pageURL`, `pageTitle` | The browser page (http and https only) | `pageURL` |
| `folderURL` | The Finder window's folder, or the folder holding the open document | `folder` |
| `documentURL` | The open document | `document` |
| `gitBranch`, `repoRoot` | Branch and top level of the repository containing the folder | `gitRepo` |

Rules the readers keep, with tests:
- Values live in memory only. `ContextValues` prints as counts (`description`, `debugDescription` and `dump`), so a log
  line cannot leak them. Nothing about the values is logged.
- Secure text fields are never read: the check happens before any value attribute is requested.
- Apps on the disabled list or the ignore list produce no values at all; the selection of password managers is dropped
  even when the rest of their context is read.
- Selected files come from a fixed AppleScript asked of Finder (Accessibility only exposes names for list rows), run
  with `osascript` under a 0.6 second kill timeout, and only when the Accessibility count says something is selected.
  The first run makes macOS ask whether Apropos may control Finder. Until that is allowed the file actions do not appear.

## An action

```json
{
  "id": "ctx:text.upper",
  "title": "UPPERCASE",
  "subtitle": "Change the selection to capital letters",
  "symbol": "textformat.size.larger",
  "requires": ["selectedText"],
  "conditions": [],
  "apps": { "include": [], "exclude": [] },
  "backend": { "type": "function", "name": "text.upper" },
  "output": "replaceSelection",
  "confirm": false,
  "keywords": ["capitals"],
  "group": "selectedText",
  "timeout": 10
}
```

- `id`: `prefix:name`, lowercase letters, digits and `. _ -`. Built-ins use `ctx:`, yours should use `user:`. The id is the
  command identity (`CommandID`), so pins, hides, aliases, symbol choices and usage follow the action across releases.
  Never rename a shipped id.
- `requires`: every listed context must be present, or the action is not listed. At least one is required.
- `conditions`: `selectionIsURL`, `selectionIsJSON`, `selectionIsMultiline`, for actions that make sense only for some
  selections. `apps`: bundle identifiers to include (empty means all) or exclude.
- `output`: `clipboard` (default), `replaceSelection`, `notify` (a short notice), `none` (the effect was the point).
  `replaceSelection` sets the focused element's selected text through Accessibility when it allows that; if not, and the
  element is an editable text control, it pastes with Command-V and puts the clipboard back afterwards (only if nothing
  else wrote to it meanwhile); anywhere else (a web page, a read-only view) the result goes to the clipboard and the
  outcome says `copiedInstead`.
- `confirm`: the palette asks before running (`PaletteModel.pendingConfirmation`, then `confirmPending()`).
- `group`: `selectedText`, `selectedFiles`, `page`, `folder`; inferred from `requires` when left out.
- `timeout`: seconds, 0.5 to 120. Processes are killed and functions cancelled when it runs out.

### Backends

| `type` | Fields | Notes |
|---|---|---|
| `function` | `name` | A Swift function from `ActionFunctionRegistry.builtin`. For what JSON cannot say. |
| `shell` | `executable` (absolute), `arguments`, `stdin`, `cwd` | A program with an argument list. Never a shell line. |
| `appleScript` | `source`, `arguments` | Run with `osascript -e <source> <arguments>`; values arrive as `argv` in `on run argv`. |
| `shortcut` | `name`, `input` | `shortcuts run <name>`, input and output through private temporary files. |
| `urlScheme` | `url` | Opened with the system. Every `{variable}` is percent-encoded. |
| `keyPress` | `keyCode`, `modifiers` | Posts a key event to the frontmost app. Needs Accessibility. |

Variables, written `{name}` in arguments and URLs (`{{` and `}}` are literal braces): `text`, `files` (list), `file`,
`fileName`, `fileNames` (list), `directory` (the first selected file if it is a folder, else its parent, else the front
folder), `url`, `title`, `folder`, `branch`, `repo`, `document`. A list variable must be a whole argument. An action must
`require` the context its variables come from. Scalars up to 16 KB are also in the environment as `APROPOS_TEXT`,
`APROPOS_URL` and so on.

## Safety rules

The goal is that a selection can never become code. The engine and the validator enforce it by construction, and the
tests try to break it with `$(...)`, backticks, quotes, semicolons, newlines and AppleScript fragments:

1. Values reach a backend only as separate arguments, standard input, environment entries, AppleScript `argv` items or
   percent-encoded URL components. They are never concatenated into program text. No shell is involved unless an
   action names one as its executable.
2. A definition that violates this is refused when the pack loads (and skipped, with a reason in `issues`):
   - the executable must be an absolute literal path;
   - for interpreters (`sh`, `bash`, `zsh`, `osascript`, `python`, `perl`, `ruby`, `node`, ...) placeholders are allowed
     only as `-c <literal script> <values...>`, where the values become positional parameters;
   - launchers such as `env`, `xargs` and `sudo` take no placeholders;
   - a text-like variable (`text`, `title`, `branch`, `fileName`, `fileNames`) as a whole argument must follow `--`,
     so a selection like `-rf` cannot become an option. Better: send text on standard input;
   - URL placeholders may not appear in the scheme or host, and `file:`, `javascript:`, `data:` are refused;
   - script text (AppleScript source, shell `-c` script) never contains placeholders.
3. Processes get a minimal environment (`PATH`, `HOME`, `LANG` plus the action's variables), a timeout, an output cap of
   1 MB, and are killed on cancel.
4. Logs carry the action id and `succeeded` or the error kind. They never carry inputs, outputs, arguments or paths.
   Errors have fixed messages. The usage store records the action id and times, nothing else.

## Where packs live

- Built in: `Sources/Apropos/Resources/ActionPacks/builtin.json` (bundled).
- Yours: every `*.json` in `~/Library/Application Support/Apropos/actions/`, loaded after the built-ins. An action with
  the same id replaces the earlier one, so a user pack can override a built-in. A file with a newer `schemaVersion`, a
  malformed file, or a refused definition is skipped and reported in `ActionPackLibrary.issues`; the rest still load.
  `apropos-probe --actions` prints them.

A pack file is `{ "schemaVersion": 1, "name": "...", "actions": [ ... ] }`.

## Adding an action

1. JSON only, when a program, script, Shortcut or URL does it:
   ```json
   { "id": "user:say", "title": "Speak", "symbol": "speaker.wave.2", "requires": ["selectedText"],
     "backend": { "type": "shell", "executable": "/usr/bin/say", "stdin": "text" }, "output": "none" }
   ```
   Save it in the `actions` folder. Check with `apropos-probe --actions --all`.
2. A built-in that needs Swift: write the function in `BuiltinActions.swift` (`table["name"] = { input, services in ... }`,
   returning the text to deliver or nil), put pure logic in `TextTools` or a similar type with tests, then add the entry
   to `builtin.json`. Functions reach the outside world only through `ActionServices` so tests can fake it.
3. Test it: `ActionCatalogueTests` checks the catalogue loads cleanly, every symbol exists and every function is wired;
   add a case to the applicability and run tests.

## Built-in catalogue

Selected text: UPPERCASE, lowercase, Title Case, camelCase, snake_case, kebab-case, trim, sort lines, remove duplicate
lines, join lines, count words and characters, wrap in quotes, wrap as code block, Markdown quote, URL encode and decode,
Base64 encode and decode, format and minify JSON, search the web (`x-web-search://`, the system default engine), open as
link. Selected files: copy path, copy name, reveal in Finder, open in Terminal here, compress to zip, copy SHA-256.
This page: copy URL, copy as Markdown link, copy title. This folder: open in Terminal, copy branch, copy short commit
hash, open the repository on its remote's website.

## Using it from the app

```swift
let center = ContextActionCenter(library: .bundled(plus: ActionPackLibrary.userDirectory))
center.attach(to: palette)                    // commands flow into the palette, running goes through the engine
var service = ContextService()
service.onSnapshot = { snapshot in Task { @MainActor in center.update(with: snapshot) } }
```

`PaletteModel` then lists the actions before the menu commands, only while the snapshot's app is the target, drops them
when the panel opens until a fresh snapshot arrives (so a stale selection is never acted on), and exposes `lastOutcome`
(show `outcome.notice` or "Copied"), `runError`, `pendingConfirmation`, `confirmPending()` and `cancelPending()`. Rows get
`command.symbolName`, `command.detail` and `command.keywords`.
