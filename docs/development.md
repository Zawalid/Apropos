# Developing Cue

Run everything from the repository root.

## See changes fast

| Command | What it does |
|---|---|
| `scripts/dev.sh` | Quit the app, rebuild a Debug build, relaunch it |
| `scripts/dev.sh --watch` | Same, automatically, every time you save a file under `App/` or `Sources/` |
| `scripts/dev.sh --logs` | Build, open, then stream the app's log output |

## Accessibility access and signing

Cue reads and presses other apps' menus, which needs Accessibility access. macOS ties that grant to the app's code
signature, and an ad hoc signature changes with every build, so the grant would be lost each time. Sign Debug builds
with a stable certificate:

```bash
security find-identity -v -p codesigning        # pick a name from this list
CUE_SIGN_IDENTITY="Your Certificate Name" scripts/dev.sh
```

Grant access once in System Settings, Privacy & Security, Accessibility. If an entry looks enabled but Cue still says
it has no access, it is a stale entry from a build with a different signature: remove it with the minus button and
let Cue add itself again.

## Tests

```bash
swift test
```

Core logic (fuzzy matcher, menu mapping, ranking, palette model, hotkey and placement) is tested against fixtures in
`Tests/CueTests/Fixtures.swift`; no test touches a live app.

## Inspect a live app without the UI

```bash
swift run cue-probe com.apple.finder                       # list its commands
swift run cue-probe com.apple.finder --run "View > as List" # press one
```

The terminal needs Accessibility access for this.

## Debug-only hooks

Debug builds read `CUE_SNAPSHOT_DIR`: when set, a PNG and a text dump of the palette are written a moment after it
opens, so it can be checked without screen recording permission. They also listen for the distributed notifications
`com.zawalid.cue.debug.toggle` and `com.zawalid.cue.debug.run` (the object is a query; its best match is run), which
lets a script drive the palette without synthesizing keystrokes.

## Known limits (M0)

- Menus an app fills in lazily (parts of Xcode's) only appear once the app has built them.
- Items that are hidden alternates (for example Empty Trash with Option) are listed as separate commands.
- A menu item that opens a modal sheet can keep its app busy past the accessibility timeout; Cue treats the
  timeout as delivered.

## Agent runs are isolated

Automated checks never touch the copy you run. `scripts/shots.sh` builds to `build/agent` and runs with
`CUE_AGENT=1`, which removes the status item, the hotkey, the welcome window and activation, and makes the windows
transparent. The debug remote control only exists in that mode, so a script cannot open the panel on your screen.

`scripts/dev.sh` re-signs the app with a stable code signing certificate after each build (the first one in your
keychain, or `CUE_SIGN_IDENTITY`). macOS keys the Accessibility grant to that signature, so you grant it once and it
survives rebuilds. Without a certificate the app is ad hoc signed and the grant is lost on every build.
