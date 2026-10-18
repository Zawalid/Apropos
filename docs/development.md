# Developing Apropos

Run everything from the repository root.

## Live previews in Xcode

The fastest loop needs no app launch, no code signing and no Accessibility access:

```bash
cd App && xcodegen generate && open Apropos.xcodeproj
```

Open `App/AproposApp/Preview/Previews.swift`, then show the canvas with **Option-Command-Return**. Each `#Preview` is one
screen in one state, drawn in dark (left) and light (right): the palette with a Finder, Safari and Xcode list, empty
search, no results, loading, permission missing, a failed menu read and a failed command, the Cmd+K actions popover,
matched letters highlighted, context chips, the three interface sizes, the three row icon styles, the menu bar menu, and
every Settings page plus the sidebar with a search typed. Edit a view, save, and the matching preview redraws.

Previews are Debug-only (`#if DEBUG`). They build real models over scratch stores that are never flushed, a fixed
Accessibility answer and a private defaults suite, so they never read or write your settings or usage files, never need
access and never touch the copy you run. Commands and learned usage come from `DebugFixtures`; the rest is in
`Preview/Fixtures.swift`. Production views stay free of preview code: a view that needs an injectable dependency gets a
small seam (for example `AppController`'s second initializer), not a flag.

When you add a screen or a state, add a scene to `PreviewCatalog` and a one-line `#Preview` for it.

To check the same scenes without Xcode (for example from a script or an agent), render them to PNGs:

```bash
scripts/render-previews.sh                  # build, then write build/previews/<scene>-<dark|light>.png
scripts/render-previews.sh --no-build palette-finder   # reuse the build, one scene
```

This runs the `AproposPreviewRender` command line tool, a separate process that never launches the app. Offscreen images lay
the glass on a flat stand-in, so judge the glass itself in the real app.

## See changes fast

| Command | What it does |
|---|---|
| `scripts/dev.sh` | Quit the app, rebuild a Debug build, relaunch it |
| `scripts/dev.sh --watch` | Same, automatically, every time you save a file under `App/` or `Sources/` |
| `scripts/dev.sh --logs` | Build, open, then stream the app's log output |

Use previews for how a screen looks. Use `scripts/dev.sh --watch` in a spare terminal for what only the real app can show:
the global hotkey, real glass over your desktop and Accessibility on live apps. Leave it running while you work: each
save rebuilds, re-signs and relaunches the app in a few seconds.

## Accessibility access and signing

Apropos reads and presses other apps' menus, which needs Accessibility access. macOS ties that grant to the app's code
signature, and an ad hoc signature changes with every build, so the grant would be lost each time. Sign Debug builds
with a stable certificate:

```bash
security find-identity -v -p codesigning        # pick a name from this list
APROPOS_SIGN_IDENTITY="Your Certificate Name" scripts/dev.sh
```

One time, so re-signing never prompts: open Keychain Access, find the certificate's private key under My Certificates,
choose Get Info, Access Control, and select Allow all applications to access this item. Without it `codesign` asks for
your login password on every build, and `--watch` stalls on the dialog.

Grant access once in System Settings, Privacy & Security, Accessibility. If an entry looks enabled but Apropos still says
it has no access, it is a stale entry from a build with a different signature: remove it with the minus button and
let Apropos add itself again.

## Tests

```bash
swift test
```

Core logic (fuzzy matcher, menu mapping, ranking, palette model, hotkey and placement) is tested against fixtures in
`Tests/AproposTests/Fixtures.swift`; no test touches a live app.

## Inspect a live app without the UI

```bash
swift run apropos-probe com.apple.finder                       # list its commands
swift run apropos-probe com.apple.finder --run "View > as List" # press one
```

The terminal needs Accessibility access for this.

## Debug-only hooks

Debug builds read `APROPOS_SNAPSHOT_DIR`: when set, a PNG and a text dump of the palette are written a moment after it
opens, so it can be checked without screen recording permission. They also listen for the distributed notifications
`com.zawalid.apropos.debug.toggle` and `com.zawalid.apropos.debug.run` (the object is a query; its best match is run), which
lets a script drive the palette without synthesizing keystrokes.

## Known limits (M0)

- Menus an app fills in lazily (parts of Xcode's) only appear once the app has built them.
- Items that are hidden alternates (for example Empty Trash with Option) are listed as separate commands.
- A menu item that opens a modal sheet can keep its app busy past the accessibility timeout; Apropos treats the
  timeout as delivered.

## Agent runs are isolated

Automated checks never touch the copy you run. `scripts/shots.sh` builds to `build/agent` and runs with
`APROPOS_AGENT=1`, which removes the status item, the hotkey, the welcome window and activation, and makes the windows
transparent. The debug remote control only exists in that mode, so a script cannot open the panel on your screen.

`scripts/dev.sh` re-signs the app with a stable code signing certificate after each build (the first one in your
keychain, or `APROPOS_SIGN_IDENTITY`). macOS keys the Accessibility grant to that signature, so you grant it once and it
survives rebuilds. Without a certificate the app is ad hoc signed and the grant is lost on every build.
