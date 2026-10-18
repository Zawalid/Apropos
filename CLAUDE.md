# Apropos

Native macOS command center (Raycast-like) whose palette adapts to the frontmost app and its context.
Read [docs/design.md](docs/design.md) before making product decisions, and [docs/roadmap.md](docs/roadmap.md)
for what to build next.

## Stack
- Swift 6, SwiftUI plus AppKit, macOS 14+
- Core logic lives in a Swift package (`Sources/Apropos`), the app target is generated with XcodeGen (`App/project.yml`)
- Accessibility API for menu and UI reading, App Intents and AppleScript as action backends
- Distributed directly (not the Mac App Store, accessibility is incompatible with the sandbox), updates via Sparkle

## Rules
- Mirror the layout and tooling of the Lopper project (`/Users/walid/Personal/Projects/Lopper`): `scripts/dev.sh`,
  `docs/`, `CHANGELOG.md`, GitHub Actions CI, swift-format with the committed config
- No emojis in code. No `as any` style escapes: no force casts or force unwraps in production code
- Keep core logic in the package and unit-tested; keep views thin
- Local-first and private: nothing about the user's screen or selection leaves the Mac unless they opt in
- The panel must open instantly and animate smoothly. Treat jank as a bug
- Commit subjects are lowercase `feat:` / `fix:` / `chore:` lines, no AI attribution lines

## UI work starts in previews
Check UI changes in the Xcode previews first (`App/AproposApp/Preview/Previews.swift`, Option-Command-Return), not by
relaunching the app. Add or update a scene in `PreviewCatalog` for any screen or state you change, and look at it with
`scripts/render-previews.sh` (PNGs in `build/previews/`, no app launched). See Live previews in
[docs/development.md](docs/development.md). Only what needs the real app (hotkey, real glass, live Accessibility) waits
for the person.

## Running the app and checking it (agents read this)
The person keeps their own copy of the app running while they work. Do not disturb it.
- Never run `scripts/dev.sh`, `open` the app, `pkill` it or bring any other app to the front unless the user asked in
  the current session. `scripts/dev.sh` is for the person: it rebuilds, re-signs with a stable certificate (so the
  Accessibility grant survives) and relaunches their copy.
- To check visuals use `scripts/shots.sh`. It builds a separate copy in `build/agent` and runs it in agent mode
  (`APROPOS_AGENT=1`): no status item, hotkey, welcome window or activation, transparent windows, and the debug remote
  control is only live there. It stops only the process it started, takes a lock so two runs never overlap, and writes
  PNGs to `build/shots/`. Read those images and say which you read.
- Debug env vars (`APROPOS_APPEARANCE`, `APROPOS_FIXTURE_*`, `APROPOS_SNAPSHOT_*`, `APROPOS_DATA_DIR`) only take effect in agent mode.
  Never launch the app with them set in the person's session: a leftover value used to pin the theme and ignore the
  Settings choice.
- Anything that cannot be checked without the real app on screen (global hotkey, real glass over a real desktop,
  Accessibility on live apps) is reported as not verified, or the person is asked to try it. Do not launch the app to
  find out.
