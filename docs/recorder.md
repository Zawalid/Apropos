# Recorder (phase 2 of record-to-command)

The capture core that turns what a person does into a reviewable list of UI steps: menu picks and keyboard shortcuts that
are menu items, with app switches as boundaries. It has no UI and nothing in the app starts it yet. It builds on the step
engine ([ui-steps.md](ui-steps.md)) and the decisions in [recording-spike.md](recording-spike.md); a recording is a
**draft**, never a finished command.

Code: `Sources/Apropos/Recorder`. Tests: `Tests/AproposTests/Recorder` (fakes only, no live tap anywhere).

```
LiveCaptureSource (listen-only CGEvent tap + app activation + 0.5 s tick)      <- the only part that touches the system
        │  CaptureEvent: mouseDown(point) | keyDown(KeyChord) | flagsChanged | appActivated | tick
        ▼
RecordingEngine ── RecordingSession (state machine, limits)
        │   ├─ RecordingSystem      clock, frontmost app, secure event input
        │   ├─ ElementHitTester     element under the pointer, text focus     (LiveHitTester / HitClassifier)
        │   ├─ MenuInspecting       an app's menu items with their shortcuts  (StepResolver.menuItems)
        │   └─ KeyLayout            key code -> printed key, to compare with a menu shortcut
        ▼
RecordingDraft  items (step | app switch | text entered), skipped notes, edits
        ▼
draft.validated() -> ValidatedSteps -> sequenceBuilder() / save(in: UserCommandStore)
```

## Permissions

| Permission | Why | Read with | Request with |
|---|---|---|---|
| Accessibility | find the menu item under the pointer, read an app's menus | `AXIsProcessTrusted()` | `AXIsProcessTrustedWithOptions` prompt |
| Input Monitoring | be told a click or key happened (listen-only tap) | `CGPreflightListenEventAccess()` | `CGRequestListenEventAccess()` |

`RecordingPermission.status()` only reads. `request(_:)` is a separate call for a button the person pressed; nothing
prompts by itself. The wording a UI shows is in `RecordingPermissionKind` (`title`, `whatItAllows`, `whyRecording`,
`settingsURL`) and `RecordingPermissionCopy` (`headline`, `summary`, `neverStored`, `missing(_:)`), so a screen and a
test agree on the sentences. `apropos-probe --record-state` prints all of it and creates nothing.

## What is and is not recorded

Recorded, as `UIStep` with `action: menu` (the only action the step engine runs today):

- A click on a **leaf menu bar item** of the frontmost app.
- A **keyboard shortcut** that matches exactly one enabled menu item of the frontmost app. The stored locators come from
  the menu item (identifier, role and title, menu path, advertised shortcut), not from the key that was pressed.
- An **app switch**, as a row "Switch to Notes". When the draft is handed off it becomes `activates: true` on the next
  step in that app, so no new action kind is needed. A switch with no later step in that app disappears.
- **Typing**, as one row "Text was entered here. What you typed is not recorded." Phase 3 turns it into a value. Until
  then a draft with such a row cannot be saved unless the person deletes it or agrees to drop it
  (`validated(dropTextEntries:)`).

Never recorded, each with a content-free note in the review list (`SkipReason`, fixed sentences that name nothing):

| What | Note |
|---|---|
| a click that could only be found by position, or on nothing addressable | coordinate-only click |
| a click on a button or other control | controls are recorded in a later version |
| a context menu or popup menu choice | only the menu bar is recorded |
| a menu bar icon (status item) | menu bar icon |
| the Apple menu, in any language (bar index 0, title `Apple`, or a path starting there) | Apple menu |
| `Open Recent` and other recent items menus (by title or identifier), at any depth | recent items |
| a Window menu item with no identifier or shortcut (it is named after an open document) | Window menu item |
| anything while secure input is on or a password field has the focus or is under the pointer | recording paused |
| anything in an app on the privacy list (`ContextPrivacy`, including password managers) | privacy list |
| a shortcut that is not a menu item, or matches two items | shortcut not recorded |
| Apropos's own windows | nothing; switching to Apropos ends the recording |

Opening a menu, opening a submenu and clicking a disabled item are not steps and leave no note.

## Keys: how characters are kept out

The rule is **record intent, not input**. It is enforced by construction, not by a filter on stored data:

1. `LiveCaptureSource` reads a key event's **key code and modifier flags only**. It never asks for the characters
   (`keyboardGetUnicodeString` and friends); a test reads the sources and fails if any file mentions them, or `NSEvent`
   monitors, or the pasteboard, or the network, or screen capture.
2. A `KeyChord` carries key code and modifiers. It describes and reflects as the words "key event", so a log line or a
   `dump` cannot show it.
3. A chord is a **shortcut candidate** only with Command, Control, or a function key. Anything else (letters, digits,
   Shift or Option typing, Return, arrows, Escape) is never compared with menus and never stored.
4. A candidate is turned into a printed key in memory (`KeyLayout`, only to compare with the menu item's advertised key)
   and used for one lookup. If it matches an enabled item, the item's own data goes into the step. If not, the chord is
   gone and a "not a menu item" note is added. Nothing is buffered between events.
5. Plain typing leaves **one bit**: a text run is open. The first text key of a run adds the placeholder row (after
   asking whether the focused element is a text input or the app would not say); further keys do nothing. There is no
   count, no length, no timing. A click, a shortcut or an app switch closes the run.
6. Property tests type 600 random chords (five seeds) through a layout where every key code prints its own private-use
   character, then search the draft, its JSON, its `String(describing:)`/`reflecting:`/`dump`, the notes, the engine
   state, the log lines and each chord's description for any of those characters. They also type a passphrase and check
   only the placeholder remains.

Logs go through `RecorderLog`: a fixed word and a number ("recorder step added via shortcut, 3 steps"). No app, title,
identifier, key or position is a parameter of any log call. A test runs a recording over secret-named items and checks
every line.

## Hit testing and step building

On a left mouse down the engine asks `ElementHitTester` for the element under the pointer **before** the UI changes. The
point is used for that one call and never stored. `HitClassifier` (pure, tested on fake trees) turns an element and its
parents into a `HitElement`: role, subrole, title, identifier, enabled, and a `Place`: `menuBarTitle`, `menuItem` (the
path of titles down from the bar, the bar index, identifiers of the menus above, whether it opens a submenu),
`contextMenuItem`, `menuExtra`, or `window`. A password field is read for its role and subrole only. No value attribute
is ever requested.

The step for a menu item has the locators `StepSequenceBuilder.addMenuCommand` builds: `identifier` (when the app set
one), `roleTitle` (`AXMenuItem` and the title), `menuPath`, and `shortcut` (when the item advertises one). A clicked
item's shortcut and identifier are filled in from the app's own menu listing. No `position` locator is added. The
description is "Choose File > Export as PDF in Preview". Every step is checked with `UIStepsValidator` as it is built;
one it would refuse is skipped with a note.

## Session

`RecordingSession` is a value type: `idle`, `armed`, `recording`, `pausedForSecureInput`, `finished(reason)`,
`cancelled`, `failed(reason)`. Terminal states stay terminal. `arm` fails with the missing permissions named. Hard
limits (`RecordingLimits`): 300 seconds and 50 steps (the step engine's maximum), at most 1800 seconds and 50 steps even
if asked for more. Reaching a limit finishes the recording, it is never extended. Switching to Apropos
(`appActivated`, or the frontmost app seen on a tick or a key) finishes it with `switchedToApropos`. Ticks every half
second keep limits, secure input and the Apropos check working while the person does nothing.

Secure input (`IsSecureEventInputEnabled()`) or a latched password field pauses everything: events are dropped before
any hit test or menu read. A password field latches when it is under a click or has the focus on a text key, and
releases when a tick sees the focus elsewhere. After a pause the frontmost app is reconciled, so an app switch during
the pause is not lost.

## The draft

`RecordingDraft`: `items` (`DraftItem`: `id`, `summary` in plain words, `fragility`, `locatorKinds`, `originNote`),
`skipped` (`SkippedNote`: reason, count, the item it follows), `title`.

| Operation | Behaviour |
|---|---|
| `delete(id)` | removes a row; its notes follow the row before it |
| `move(id, to:)` | reorders |
| `rename(id, to:)` | changes the step's description only (1 to 200 characters); it is never used to find anything |
| `merge(id)` | merges a row with the next only when they mean the same thing: identical steps, two text rows, two app switches (the later wins). Anything else throws `cannotMerge` |
| `removeTextEntries()` | deletes all text rows |
| `issues(privacy:)` | the validator's findings on the steps as they would be saved |
| `validated(privacy:dropTextEntries:)` | `ValidatedSteps` (renumbered `s1...`, app switches folded into `activates`) or `DraftError` |
| `sequenceBuilder(...)` | a `StepSequenceBuilder` for the sequence session to take over |
| `save(as:in:)` | main actor; validates, then `UserCommandStore.create` through the existing authoring |

A draft holds only what a step already holds (locators, a description built from them), app names, and fixed-sentence
notes. Dumps of a draft are still personal data (they contain menu titles), so do not paste or commit them.

## API for the next phases

```swift
let services = RecordingServices(
    system: LiveRecordingSystem(), hitTester: LiveHitTester(), menus: LiveMenuInspector(), keyLayout: LiveKeyLayout())
let engine = RecordingEngine(services: services, configuration: RecordingConfiguration(privacy: privacy))
let recorder = Recorder(engine: engine, source: LiveCaptureSource())

if RecordingPermission().status().canRecord {
    recorder.begin()                 // .recording, or .failed(reason); never prompts
    // ... the person works; recorder.state / recorder.draft are readable at any time
    var draft = recorder.finish()    // also runs on its own when a limit is hit or Apropos is switched to
    try draft.rename(draft.items[0].id, to: "Export the report")
    draft.title = "Export report"
    try draft.save(in: userCommandStore)          // or: let steps = try draft.sequenceBuilder()
}
```

- `LiveKeyLayout()` must be created on the main actor (macOS requires keyboard layout calls there); it reads the table
  once.
- **Phase 3** (controls and text as values) extends `HitElement.Place.window` handling in
  `RecordingEngine.handleMouse` (it currently skips with `controlNotRecordedYet`), replaces the `textEntered` row with a
  value-bearing row, and relaxes `StepAction.supported`. `DraftItem.Content` is the place to add cases.
- **The recording UI** observes `Recorder.state` and `draft`; show `RecordingState.failed` with
  `RecordingFailure.description`, notes with `SkippedNote.text`, and the badge from `DraftItem.fragility`. The engine is
  thread-safe (events arrive on the tap thread); read `state` and `draft` from any thread, then publish to the main
  actor.
- **The sequence session** takes `draft.sequenceBuilder()` or `draft.validated().steps`.

## Trying it by hand later (Walid)

Nothing here has been run against a real app: it was developed only with fakes. To see it work:

1. Check the two permissions without prompting, from the terminal you will use:
   ```bash
   swift run apropos-probe --record-state
   ```
2. Allow that terminal under Privacy & Security > Accessibility **and** Input Monitoring.
3. Use the spike fixture so no real app is involved (check it out of history first: see docs/recording-spike.md). It is
   invisible by default; in a scratch copy of
   `scratch/recording-spike/fixture/main.swift` set `window.alphaValue = 1`, `ignoresMouseEvents = false` and
   `app.setActivationPolicy(.regular)` so its menu bar shows, build it with `scratch/recording-spike/build.sh`, and run
   it on a scratch Space.
4. In the fixture, with it in front, run (this is the **only** command that creates a live tap; it listens for N seconds,
   default 20, at most 120):
   ```bash
   swift run apropos-probe --record-live 30
   ```
   and choose File > Export as PDF, press Command-S, switch to another app and back, type something in the text field.
   It prints each row in words with its badge, the skipped notes and whether the draft is valid. The output names the
   menu items you chose: do not paste it anywhere.
5. Things worth checking by eye: typing leaves exactly one "Text was entered" row; the secure field pauses recording
   (try the fixture's secure field); a click on the Export button is noted, not recorded; the Apple menu is noted.

## Known limits and what is unverified

- **Verified**: logic against fakes (`swift test`), the classifier on fake trees with parents, the probe's
  `--record-state` output, and that the live adapters compile (including in the app target). **Not verified**: the live
  tap delivering events, `AXUIElementCopyElementAtPosition` returning menu items for clicks in an open menu, parent
  chains of real menus, `LiveKeyLayout` on non-US layouts, the tap callback under load, secure input detection in
  real password fields. No live tap or hit test was run.
- A menu pick made by pressing on the menu title and releasing on the item (one drag) is not captured: only the
  mouse down is observed, and it lands on the title. Click-to-open then click-the-item works.
- Menu titles that contain a document or person's name outside the Window menu and recent items menus (some apps list
  open documents elsewhere) are stored as titles, like any menu step. Prefer steps with an identifier or shortcut.
- A keyboard layout change during a recording is not noticed.
- Electron and web apps: their menus are often not in the macOS menu bar; expect "nothing recorded" there.
- Clicks inside a menu opened by a keyboard shortcut that opens a sheet are not followed by the recorder; sheets are
  phase 3.
- Only left clicks are observed; right clicks, drags, scrolling and gestures are not.
