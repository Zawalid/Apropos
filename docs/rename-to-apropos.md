# Rename: Cue to Apropos

Decided 2026-10-18. Apropos means "fitting the moment", which is the product promise. It will live at
apropos.zawalid.com for now. No trademark registry search has been done yet: do it (USPTO, EUIPO TMview) before
charging money.

The rename is one pass by one session, after the integration work in flight has landed, because it touches nearly
every file. Do it in this order and commit each step separately.

## Naming rules
- Product name in UI and docs: **Apropos**
- Swift module and package: `Apropos` (replaces `Cue`), tests `AproposTests`, app target `AproposApp`
- Probe tool: `apropos-probe`. Never ship an executable called plain `apropos`: it is a Unix command and would
  shadow it
- Bundle id: `com.zawalid.apropos` (replaces `com.zawalid.cue`)
- Debug env vars `CUE_*` become `APROPOS_*`; debug notifications `com.zawalid.cue.*` become `com.zawalid.apropos.*`
- Logger subsystem `com.zawalid.apropos`
- Hotkey signature OSType `"CUE1"` becomes `"APR1"`
- Application Support folder `Cue` becomes `Apropos`

## Steps
1. Preflight: `git status` is clean, `swift test` passes, no other session is editing. Record the baseline.
2. Settings and data migration first, with tests (below), before any rename, so nothing is ever lost.
3. Rename the Swift package, targets, folders (`Sources/Cue`, `Sources/cue-probe`, `Tests/CueTests`, `App/CueApp`),
   `Package.swift`, `App/project.yml`, scheme, imports, and regenerate the Xcode project. Use `git mv` so history
   follows.
4. Rename identifiers: bundle id, logger subsystem, notification names, env vars, hotkey signature, UserDefaults
   keys that embed the old name.
5. Rename every user-facing string: window titles, menu bar item and its accessibility label, onboarding, settings
   pages and footers, error messages, About.
6. Update scripts (`scripts/dev.sh`, `scripts/shots.sh`), the CI workflow, `.gitignore`, README, CLAUDE.md,
   CONTRIBUTING, CHANGELOG, GOAL.md, `docs/*`, and the prototype titles. Keep a short "formerly Cue" note in the
   README and CHANGELOG.
7. Build, run the app, take shots, verify (below). Then regenerate nothing by hand: the sessions' folder path is
   renamed last, by the user (see "Folder").

## Settings and data migration
Real users (starting with Walid) already have data under the old name. On first launch of the renamed app:
- If `~/Library/Application Support/Apropos` does not exist and `.../Cue` does, move or copy the whole folder
  (`settings.json`, `usage.json`, `packs/`, the settings history), then leave a `migrated-from-cue` marker file so
  it runs once. Never overwrite an existing new folder. Never delete the old one automatically.
- Copy the old UserDefaults domain `com.zawalid.cue` (hotkey combo, context privacy lists, anything else) into the
  new domain, only for keys not already set.
- Keep the settings schema version; do not bump it just for the rename.
- Put this in the core package (`Sources/Apropos/Migration`) as a testable `LegacyMigration` with an injected base
  directory and defaults suite. Tests: fresh install, old data present, both present (no overwrite), partial
  data, corrupt old file (skip and report), marker prevents a second run.
- Log what was migrated, never contents.

## Things the rename resets that code cannot fix
- **Accessibility grant:** macOS keys it to the bundle id and signature, so the user must grant it again. The
  onboarding already handles the missing-permission state; verify it shows on first launch of the new build, and
  tell the user to remove the stale "Cue" entry in System Settings, Privacy and Security, Accessibility.
- **Open at login:** the old login item stays registered under the old id. Note it in the report; the new app
  registers its own when the setting is on.
- **Debug signed binary and probe:** re-sign and re-grant for `apropos-probe`.

## Checklist
- [x] Baseline green, tree clean
- [x] `LegacyMigration` and tests committed
- [x] Package, targets, folders, imports renamed, project regenerated
- [x] Bundle id, subsystem, env vars, notifications, hotkey signature renamed
- [x] All UI strings say Apropos (grep for `\bCue\b` and `cue` finds only history notes)
- [x] Scripts, CI, docs, README, CHANGELOG, prototypes updated
- [x] No executable named `apropos` anywhere
- [x] `swift test` passes
- [ ] App built (agent mode only, never launched against real data) and launched, migration verified with a copy of real data, Accessibility re-grant flow verified
- [x] Screenshots of panel and Settings show the new name
- [ ] Report lists what was and was not verified

## Folder
The repository folder (`Cue` on the author's disk) becomes `Apropos` as the very last step, done by
the user, because moving it breaks every open session's working directory. After the move, update the paths in
`CLAUDE.md` and any session notes.
