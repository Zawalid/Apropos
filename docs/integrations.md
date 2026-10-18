# Running Apropos commands from outside

Two doors, one set of rules: the `apropos://` URL scheme and Shortcuts (App Intents). That includes Raycast quicklinks,
Alfred, a Terminal `open` call, a web page and any other app. Because anything can call them, they are deliberately narrow.

## The rules

1. Only **your own commands** that you marked `"allowFromURL": true` can run. Built-in context actions and menu commands
   cannot be run from outside. A command waiting for approval is never available.
2. There is no setting that turns it on for you: it is a field in the command file, off by default, and an import clears it.
3. The first time a command runs from outside, Apropos asks you, showing what the command does. Confirming records
   `"urlConfirmed": true`; changing the command's backend, or turning `allowFromURL` off, resets it. Commands marked
   `"confirm": true` ask every time.
4. A caller learns nothing about your commands: "does not exist", "not allowed" and "pending" all give the same answer.
5. The command acts only on what the caller passes. Apropos does not mix in what is selected in the app in front.
6. Values from outside are untrusted data, passed with the engine's rules: separate arguments, standard input, environment,
   AppleScript `argv`, percent-encoded URL parts. They can never become program text. Commands that replace the selection
   copy to the clipboard instead when started from outside.
7. Unknown parameters, repeated parameters, a path, port, user name or fragment in the link, control characters, and
   oversized values are rejected.

## URL scheme

| Link | Does |
|---|---|
| `apropos://open` | Shows the panel |
| `apropos://search?q=<text>` | Shows the panel with `<text>` typed (max 500 characters) |
| `apropos://run?command=<id or alias>&text=...` | Runs an allowed command |

`run` accepts `command` plus any of: `text` (up to 200,000 characters), `url` (http or https only), `title`, `file`
(absolute path) and `folder` (absolute path). A command that needs a selection gets it from `text`; one that needs a page gets
`url` and `title`.

Examples (percent-encode values):

```bash
open "apropos://run?command=up&text=hello%20world"
open "apropos://run?command=user:6f1c9d2e-0000-4000-8000-000000000001&url=https%3A%2F%2Fswift.org&title=Swift"
open "apropos://search?q=reveal"
```

A Raycast quicklink: Create Quicklink, set the link to `apropos://run?command=up&text={Selected Text}` (Raycast fills
`{Selected Text}`; it percent-encodes the value for you). Raycast stays your launcher; Apropos only does the command.
The same works in Alfred or from any script. The first run shows Apropos' confirmation, once.

## Shortcuts

In the Shortcuts app, add Apropos actions:

- **Run Apropos Command**: choose a command (the list shows only commands you allowed; search matches titles and aliases),
  optionally pass Text and a Page URL. The same confirmation and rules apply; the result dialog shows a notice when the
  command produces one.
- **Open Apropos**: shows the panel.

Intents run inside the running Apropos app. If it is not running, they say so.

## From code

`ExternalRouter.parse(url)` returns `.open`, `.search(query:)` or `.run(reference:, parameters:)`. `ExternalRunner` resolves
(`resolve(reference:parameters:)` returns an `ExternalRun` with `needsConfirmation` and `isFirstUse`, or a rejection) and
performs (`perform(_:confirmed:target:)`). The app files `App/AproposApp/Integrations/ExternalRequestHandler.swift` and
`ShortcutsIntents.swift` are thin shells over them.
