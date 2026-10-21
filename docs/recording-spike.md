# Record-to-command: feasibility spike

Written 2026-10-18. Decision document for the roadmap item "record an action once in any app and get a reusable
command" ([design.md](design.md), feature 4).

How to read the evidence labels used throughout:

- **Verified (here)**: run in this spike, on this Mac (macOS 26.7, Swift 6.4), output reproduced below.
- **Header**: read in the macOS SDK headers (`HIServices`, `CoreGraphics`) installed with Xcode.
- **Code**: read in this repository.
- **Known, not re-checked**: established behaviour from Apple documentation, vendor documentation or common experience
  that this spike did not re-test. Treat as a hypothesis until phase 0 below confirms it.
- **Unverified**: a guess. Listed so it can be tested.

## Decision

**Reduced-scope go.** Build record-to-command as "teach by doing, then review", not as a general macro recorder.

What to promise:

1. Record sequences of **menu picks, keyboard shortcuts that resolve to menu items, button and control presses, and
   text entry turned into parameters**, in apps that expose a reasonable Accessibility tree (native AppKit and SwiftUI,
   and mainstream apps built on them).
2. Every recording becomes a reviewable list of steps in plain words, which the person can edit, rename, delete and
   parameterise before saving. A recording is a draft, never a finished command.
3. Replay uses Accessibility actions (menu press, AXPress, set value), not synthetic mouse clicks, so it does not move
   the pointer and mostly does not steal focus.

What not to promise (see "What will not work"):

- Pixel or coordinate recording, drag and drop, canvas apps (Figma canvas), games, remote desktops.
- "Survives any app update". It survives most updates in apps that set identifiers or keep stable titles, and degrades
  with a clear repair prompt in the rest. Silent wrong behaviour is the failure to design against.
- Electron and web apps as a launch target. They are a later, opt-in phase with a visible warning.
- Password fields and anything typed into them. Never recorded, never replayed.

The cheapest honest version of the feature, "chain existing menu commands, context actions and Shortcuts into a named
command" with no recorder at all, needs none of the risky parts and should ship first (phase 1). The recorder is then a
faster way to author the same step list.

## What was run, and what is blocked

A throwaway fixture app and harness were written for this spike. They are no longer in the tree; they live in git history
at commit `d783a41` (`git show d783a41 --stat`, then `git checkout d783a41 -- scratch/recording-spike`). Nothing under
`Sources/`, `App/` or `scripts/` was touched, and nothing was launched against anyone's real apps.

| Piece | File | Notes |
|---|---|---|
| Fixture app | `fixture/main.swift` | AppKit, no nib. Menu bar (File, Edit), buttons (with and without `accessibilityIdentifier`), text field, secure field, popup, table, sheet. Accessory policy, transparent, mouse-transparent window, `orderFrontRegardless` so it never activates. Prints one JSON line per action as ground truth. French titles with `-AppleLanguages "(fr)"`. |
| Harness | `harness/main.swift` | `preflight`, `dump`, `observe` (AXObserver plus a listen-only event tap that only counts events), `replay` (ordered locator fallbacks, polling wait, timing, frontmost app before and after). Refuses any pid that is not the fixture. Never prompts for permission. |
| Runner | `run-experiments.sh`, `build.sh`, `steps-en.json` | Builds both, runs English and French, then an observe pass. Output goes to `scratch/recording-spike/build/results` (ignored by git). |

**Verified (here)**

- Both programs build. The fixture runs headless without showing anything.
- `harness preflight` in this session: `AXIsProcessTrusted: false`, Input Monitoring false, post-event access false,
  screen capture false. So **every experiment that talks to another process through Accessibility is blocked**, and the
  harness stops with a clear message instead of working around it.
- The fixture's in-process accessibility self-test (`fixture --selftest`, which needs no permission because the app
  reads itself):
  - Visible titles follow the app language: `Save` / `Enregistrer`, `Export` / `Exporter`, `Open sheet` / `Ouvrir la
    feuille`, window `Fixture` / `Banc d'essai`, menus `File` / `Fichier`, `Edit` / `Edition`, items `Export as PDF` /
    `Exporter en PDF`.
  - Menu item `identifier` values (`menu.export`) are identical in both languages.
  - AppKit appends items to the Edit menu that the app did not add (`Writing Tools`, `AutoFill`, `Start Dictation`,
    `Emoji & Symbols`; some twice in the in-process list). The positional index of anything below them changes between
    macOS versions. A menu path by index is therefore a weak fallback.
  - Controls without an identifier (the Export button) expose only role and title. A text field with a placeholder
    and no label exposes neither title nor description in the dump: an unlabeled text field is addressable only by
    identifier or by position among siblings.
  - The in-process dump showed an empty `id` for buttons whose identifier was set. That is a limit of the in-process
    proxy, not evidence that `AXIdentifier` is missing over IPC. Whether `AXIdentifier` crosses the process boundary
    for each control is **not verified** and is the first thing the blocked run answers.

**Not verified**: Electron and web behaviour, background-app replay (the fixture is an accessory app that is never
frontmost, so "no focus stolen" below is weak evidence), a human's real clicks and keys through the event tap, and the
whole prior-art section.

### Results of the first run (2026-10-18, the author's terminal granted Accessibility, Input Monitoring)

Run with `./run-experiments.sh`; output in `scratch/recording-spike/build/results` (not committed: the tree dumps
contain the person's name and recent items, see below).

**Verified (here), run 1**

| Question | Result |
|---|---|
| Does `AXIdentifier` cross the process boundary? | **Yes** for window, text field, secure field, popup, buttons, table, label and menu items (`menu.export`, even AppKit's own selector names such as `showWritingTools:` appear). A button with no identifier set shows `id=""`. |
| Is a secure field distinguishable? | **Yes**: `AXTextField` with subrole `AXSecureTextField`. The harness withheld its value. |
| Titles by language | Same element, different title: `Save` / `Enregistrer`, `Export` / `Exporter`, menu `File` / `Fichier`. Identifiers identical in both. |
| Replay on the French UI with English-title steps | Identifier steps **succeeded** (set value in 38 ms, press Save in 104 ms). Title-only steps (`Export`, `Open sheet`) **failed**, and the menu path by titles (`File > Export as PDF`) **failed**. This is the expected failure mode, now observed. |
| Does a button press produce an Accessibility notification? | **No.** During `AXPress` on Save and Export no `AXPress`-related or `AXMenuItemSelected` / `AXMenuOpened` notification arrived. Only side effects were seen: `AXValueChanged` (text field, and the status label that Save changed), `AXSelectedTextChanged`, `AXSheetCreated`, `AXFocusedWindowChanged`, `AXFocusedUIElementChanged`, `AXApplicationActivated`, `AXUIElementDestroyed`. **A recorder cannot learn that a button was clicked from AXObserver; it needs the event tap and a hit test.** |
| Does a programmatic menu press produce menu notifications? | No `AXMenuItemSelected`, `AXMenuOpened` or `AXMenuClosed` arrived. Whether a human's click on a real menu produces them is not tested. |
| `AXUIElementDestroyed` | Arrived with no readable role: the element is already gone by callback time. Do not rely on reading a destroyed element. |
| Event tap | Created (Input Monitoring granted). Counts were empty, as expected: nothing human was typing or clicking. |
| Focus | Frontmost app was Arc before and after both replays. Weak evidence, see above. |
| Menu bar of a non-frontmost accessory app | `AXMenuBar` is readable and menus are walkable while the app is not active. Menu item frames are meaningless (zero size, off screen), so menu items must be addressed by title, identifier or shortcut, never by position. |
| `AXMenu` for the fixture's Edit menu | Contains items the app never added (Writing Tools with a 13-item submenu, AutoFill, Start Dictation, Emoji & Symbols), confirming menu index paths drift with the OS. |

**Surprise 1: the whole menu bar tree includes the Apple menu**, which exposed the person's full name (the Log Out
items) and a Recent Items list of apps, documents and folders. The recorder and any stored locator must skip the Apple
menu, and **dumps of the tree are personal data**: do not paste them into issues, do not log them, do not commit them.

**Surprise 2: one English replay failed where the identical steps worked elsewhere.** In the English run, steps 0, 1, 2,
4 and 5 timed out after 3 s although the tree dump taken a moment earlier in the same run contained those elements, and
only the menu path step succeeded. In the French run (same code) the identifier steps succeeded, and in the observe
pass (English, same steps) all six succeeded. The cause is not established. Candidates: the first cold launch of a
freshly built binary, a race between the dump and the replay, or the 600-node breadth-first cap. Treat it as evidence
that replay needs retries, longer first-use waits and a real failure report. **Rerun `./run-experiments.sh` twice** to see
whether it recurs.

### Running the experiments

The harness needs Accessibility, and the tap part needs Input Monitoring. Only the person can grant them, and this
session did not try to.

1. In a terminal you do not mind granting (or use the built binary directly), run:
   ```bash
   cd scratch/recording-spike && ./build.sh
   ```
2. System Settings, Privacy and Security, Accessibility: add and enable the app you run the script from (Terminal or
   iTerm), or click `+` and add `scratch/recording-spike/build/harness` (the full path on your disk). Remove it
   afterwards. For the event tap line also add the same entry under Input Monitoring.
3. Run, from the same terminal:
   ```bash
   ./run-experiments.sh
   ```
   It starts the fixture invisibly (no window, no focus), dumps the tree in English and French, replays six steps in
   both, then observes eight seconds of programmatic activity. It takes under a minute and does not touch other apps.
4. Hand back `build/results/`. The questions each file answers are listed in "Phase 0" at the end.

The fixture window is invisible and ignores the mouse, so the run changes nothing on screen.

## 1. Capture: what can be observed

### Mechanisms

| Mechanism | Permission | Gives | Evidence |
|---|---|---|---|
| `AXObserver` notifications on an app element | Accessibility | Semantic changes: focus, value, selection, windows, menus | Header |
| `CGEventTap` listen-only, mouse | Input Monitoring (macOS 10.15+) | Every click and drag, with position and target pid | Header, known |
| `CGEventTap` listen-only, keyboard | Input Monitoring | Key down and up with key code and flags (and characters) | Header, known |
| `AXUIElementCopyElementAtPosition` | Accessibility | Which element is under a point | Known |
| `NSWorkspace` notifications | none | App launch, quit, activation, space change | Known |
| `IsSecureEventInputEnabled()` | none | Whether a password field currently has secure input | Known |

`CGEvent.h` states that taps at the session or HID level "may only receive key up and down events if access for
assistive devices is enabled", and the privacy layer introduced in macOS 10.15 splits this: passive taps need Input
Monitoring, active taps (that may swallow or alter events) need Accessibility. A recorder only needs passive taps, so
**Input Monitoring plus Accessibility** is the permission set for recording and **Accessibility alone** for replay.
Apropos already asks for Accessibility; recording adds one more prompt and one more entry in Privacy and Security,
which should appear only when the person starts their first recording. (Header for the key-event text; the 10.15
split is known, not re-checked.)

### What is visible

| User action | Visible how | Reliability |
|---|---|---|
| Menu pick with the mouse | Click lands in the menu bar or a menu. `AXMenuItemSelected` exists in the header but is documented as the notification that an item is selected (highlighted); in practice it fires on highlight, not commit, so it is not a record of invocation. The reliable signal is the mouse-up in the menu plus the element under it. | Medium. Needs tap and hit test. |
| Keyboard shortcut | Key tap gives key code and modifiers. Match them against the menu bar's key equivalents (`AXMenuItemCmdChar`, `AXMenuItemCmdModifiers`, `AXMenuItemCmdVirtualKey`, which Apropos already reads in `AXMenuReader`) to turn "Command-E" into "File > Export as PDF". | High for shortcuts that are menu items, none for shortcuts handled inside the app (editor key bindings). |
| Button or control click | Mouse-down position, then hit test to the element, then climb to the first ancestor that advertises `AXPress`. Hit test must run at mouse-down, before the UI changes. | High in native apps, low in custom-drawn ones. |
| Text entry | `AXValueChanged` on the focused element, or read the value when focus leaves. Record the resulting value, not the keystrokes. | High in native text fields, patchy in web and editors. |
| Selection in a list or table | `AXSelectedRowsChanged` | High in native tables and outlines. |
| Popup / combo choice | Value change on the popup, plus a menu event | Medium. |
| App switch | `NSWorkspace.didActivateApplicationNotification`, `AXApplicationActivated` | High. |
| Window and sheet opening | `AXWindowCreated`, `AXSheetCreated`, `AXFocusedWindowChanged` | High in native apps. A replay can use these as wait conditions. |
| Open and Save panels | The panel is hosted by a separate XPC service (`com.apple.appkit.xpc.openAndSavePanelService`) but its window is exposed under the requesting app. Typed paths and clicks are visible; the chosen file path is a value the person probably wants as a parameter. | Medium. Known, not re-checked. |
| Drag and drop | Mouse-down, drags, mouse-up are visible; the semantic meaning (item A to folder B) is not. Source and destination can be hit tested at the two ends, but replay by dragging needs synthetic pointer events. | Low. Out of scope. |
| Scrolling, hover, gestures | Visible as events, meaningless as commands. | Do not record. |
| Anything inside a canvas, game, remote desktop, video | Only pixel events. | Not recordable semantically. |

Rows about notifications were checked only for programmatic actions (see the first-run results): button presses emit
no notification, and a programmatic menu press emits no menu notification. Rows about human clicks and keys remain
unverified until someone clicks in a visible fixture.

### Apps that do not behave

| App type | Behaviour | Evidence |
|---|---|---|
| Native AppKit and SwiftUI (Finder, Notes, Xcode, System Settings) | Full tree, roles, titles, identifiers where the developer set them. SwiftUI sets `accessibilityIdentifier` only when asked and builds some controls lazily. | Known |
| Chromium and Electron (Chrome, Slack, VS Code, Notion, Figma UI) | The web accessibility tree is **off until an assistive technology announces itself**. Chromium switches it on when it sees `AXEnhancedUserInterface` or `AXManualAccessibility` set on the application element (Electron documents `AXManualAccessibility` for this). Setting `AXEnhancedUserInterface` on another app has a documented side effect of breaking window animation and window managers, so `AXManualAccessibility` is the one to try. With the tree on, controls have roles and names from ARIA and HTML, `AXDOMIdentifier` (header: `kAXDOMIdentifierAttribute`) carries the element `id`, and `AXDOMClassList` the classes. Names are the localised text. Trees are large and slow to walk. | Known, not re-checked. Header confirms `AXDOMIdentifier` exists. |
| VS Code | Editor content is only fully exposed in screen reader mode. Menus are custom, rendered in the window (not the macOS menu bar) unless the native title bar menu is used; the native macOS menu exists for the app menu only. Most commands live in the command palette, which is a web list. | Known |
| Figma | Chrome around the canvas is web and addressable once the tree is on. The canvas is WebGL and exposes nothing. Anything the person does on the canvas is invisible except as mouse events. | Known |
| Slack, Notion | Web UI, addressable with the tree on, but identifiers are generated class names that change with every release and the DOM re-renders constantly. Prefer role plus accessible name, and expect breakage. | Known |
| Java, Qt, custom toolkits | Often partial or empty trees. | Known |

Consequence: the recorder must detect "this app gave me nothing useful" (window with no children below the frame, or
only `AXGroup`s with no names) and tell the person up front, rather than record coordinates silently.

## 2. Addressing: identifying an element

### Attributes, in order of trust

| Attribute | Stable across update | Stable across language | Notes |
|---|---|---|---|
| `AXIdentifier` | Best, if the developer set it | Yes | Header: `kAXIdentifierAttribute`. Set by `accessibilityIdentifier` in AppKit and SwiftUI, used by XCUITest, so well-maintained apps often have them. Many apps have none. Whether it crosses IPC for every control type is the first thing the blocked run checks. |
| Menu item key equivalent (`AXMenuItemCmdChar` + modifiers) | Good | Yes | Not for every item. Only for menu items. |
| Role + subrole | Good | Yes | Too coarse alone. |
| `AXTitle` / `AXDescription` / `AXValue` of labels | Medium | **No**, localised | A French UI renamed `Export` to `Exporter`. |
| `AXHelp` (tooltip) | Low | No | Often more descriptive than the title for icon buttons, also localised. |
| `AXDOMIdentifier` (web) | Medium for hand-written ids, none for generated ones | Yes | Web only. |
| Hierarchy path (role and index chain) | Low | Yes | Breaks when a toolbar gains a button or the OS adds a menu item (see the Edit menu finding above). |
| Position and size | Very low | Yes | Window moves, Retina, display changes. Use only to disambiguate between siblings in the same container. |
| Element `AXUIElement` reference | None | - | Dies with the window. Never persisted. |

### Recommended locator

A step stores an **ordered list of strategies**, resolved in order, first unique match wins, and stores how the
element was found at record time so a later drift is reported as a degradation rather than a silent success:

```
1. identifier        (AXIdentifier equals)                       within window match
2. menuShortcut      (cmdChar + modifiers, menu items only)
3. roleTitle         (role, localised title, any of the known localisations)
4. roleDescription   (role, description / help)
5. path              (role chain with sibling index, last resort)
```

Rules:

- A strategy must match **exactly one** element in the scope, otherwise it is skipped, not guessed. Two matches is a
  failure of that strategy.
- Scope the search: first the window (by role, subrole and title pattern or `main`), then the container
  (toolbar, sheet, sidebar) the element sat in at record time. Search is breadth-first with the same hard limits as
  `AXNode.firstDescendant` (depth 6, 250 nodes in the existing code; recording needs a higher cap but still a cap).
- Store titles with the **language they were recorded in** (`"title": {"en": "Export", "fr": "Exporter"}` is not
  derivable automatically, so store one title plus the app's language code and let the identifier or shortcut carry
  cross-language replay). Shared packs for other languages need identifiers or shortcuts, or a per-language title map
  authored by the pack maintainer.
- Never use position as an address. Use it only as a tiebreaker among equal siblings and flag the step as fragile.
- Record a fragility score per step (identifier or shortcut: sturdy; title only: ok; path only: fragile) and show it in
  the review list.

### What breaks

| Change | Effect |
|---|---|
| Developer renames a title | Strategy 3 fails; falls back to identifier, shortcut, description. |
| App updates, menu gains or loses items | Menu paths by index fail; menus by title and shortcut survive. |
| App language differs from the recording | All title strategies fail; identifier and shortcut survive. |
| Redesigned toolbar | Hierarchy paths fail; identifiers survive. |
| Same title appears twice (two "Export" buttons) | Strategy skipped as ambiguous; needs scope or identifier. |
| Element is lazy (SwiftUI list row not yet realised, web virtual list) | Resolves only after scrolling; replay may need a "scroll into view" step. Out of scope for v1. |
| Dynamic titles ("Save 3 items", document names in the title) | Title strategy must use the stable part. Record titles with numbers and the current document name masked as a pattern. |

## 3. Replay

### Performing a step

| Step kind | Mechanism | Needs focus | Notes |
|---|---|---|---|
| Menu item | `AXUIElementPerformAction(item, kAXPressAction)` on the item found by path or shortcut. This is exactly what `AXPressTarget` does today. | Mostly no | Code: the existing handling already maps `kAXErrorCannotComplete` to "delivered", because an item that opens a modal sheet keeps the app busy past the messaging timeout. Replay must keep this rule. |
| Button, checkbox, popup item | `AXPress` | Mostly no | Disabled controls return an error. Check `AXEnabled` first. |
| Set text | `AXUIElementSetAttributeValue(el, AXValue, text)` on a text field or area | No | Replaces the whole value. For "insert at cursor", set `AXSelectedText` instead, as `LiveSelectionReplacer` does. Apps that listen to key events only (many web editors) show the new value but do not react to it. Fallback is paste, which Apropos already implements with clipboard restore. |
| Select row | Set `AXSelectedRows`, or press the row | No | Known. |
| Key press | `CGEvent` posted with `postToPid` to the target process | App must accept events while inactive | Code: the current `LiveKeyboard.post` posts to `cghidEventTap`, which goes to **whatever is frontmost**. For recorded replay it must target a pid, or the step lands in the wrong app if focus moved. |
| Wait | Poll for an element, a value, or a window to appear. Subscribe via `AXObserver` rather than poll, where the notification exists (`AXWindowCreated`, `AXSheetCreated`, `AXValueChanged`, `AXLayoutChanged`). | - | A fixed sleep is the wrong default. |

The harness replay path implements the polling variant: it re-resolves the locator every 100 ms for up to three
seconds, reports which strategy matched, the AXError, and how long the step took.

### Waiting for readiness

- Resolve the element fresh for every step. Never reuse references across steps.
- After a step that opens something (sheet, panel, new window), wait for the next step's element rather than sleeping.
- Cap each wait (default 3 s, step-configurable, global ceiling) and use `AXUIElementSetMessagingTimeout` (the code
  already uses 1.5 s for menus and 0.2 s for context reads) so a hung app cannot hang Apropos.
- Expect a postcondition when the recorder can infer one: a window appeared, a value changed, a menu item's mark
  changed. Postconditions turn "the call returned success" into "the thing happened".

### Detecting failure and recovering

| Failure | Detection | Recovery |
|---|---|---|
| Element not found | All strategies exhausted | Stop, show which step, highlight nearest candidates, offer "pick again". |
| Ambiguous | Two or more matches | Stop, ask. |
| AXError (`cannotComplete`, `invalidUIElement`, `actionUnsupported`, `apiDisabled`) | Return code | Retry once after re-resolving. `cannotComplete` after an action that opens a modal counts as delivered (existing behaviour). `apiDisabled` means the Accessibility grant was lost: report and stop. |
| Action succeeded, effect did not happen | Postcondition not met within the timeout | Report as failed, not as success. |
| Wrong app frontmost or target closed | Check pid and bundle id before each step | Abort; never act on another app. |
| Dialog the recording did not have (update prompt, permission, "are you sure") | A modal window appears that the next step cannot find | Stop and leave it for the person. |
| Destructive step | Flagged at record time (titles containing delete, remove, erase, discard, send, publish, pay, in any language is unreliable, so also flag any step whose recording was followed by a confirmation sheet) | `needsConfirmation` on the whole command, already supported by the action model. |

Replay should be **all or nothing at review time and stop-on-first-failure at run time**. Never "skip and continue",
which turns a mispress into a different command.

### Not hijacking focus

- Prefer actions that do not need focus: `AXPress` on menu items and buttons, `AXValue` sets. Known: many AppKit
  controls respond to these while their app is in the background, but some apps, and web content in particular, ignore
  or defer them until active. The harness measures frontmost app before and after each run.
- Do not call `NSRunningApplication.activate` unless a step needs it, and then record in the step that it activates. If
  a step requires the app to be frontmost, say so in the review list ("brings Safari to the front").
- Do not synthesise mouse events. They move the person's pointer and click whatever is under it if the window moved.
- Never run while the person is typing in the target. A run started from the Apropos panel is the person's explicit act,
  so that is acceptable; scheduled or triggered replay (later) needs a different rule.
- Background app: Accessibility calls to a background process work as long as the app services its run loop. App Nap
  and Electron's throttling can make `cannotComplete` more frequent. Known; measure in phase 0.
- Spaces and fullscreen: a window on another Space is addressable but cannot be shown. A step that must show a window
  has to switch Space, which is intrusive; v1 should fail with a message instead.

## 4. Permissions and privacy

### Permissions

| Need | Permission | When asked |
|---|---|---|
| Read menus, context, replay presses and value sets | Accessibility (already requested) | Existing onboarding |
| Record clicks and keys (listen-only taps) | Input Monitoring | First time the person presses Record |
| Post key events to a pid | Accessibility (post event access, `CGPreflightPostEventAccess`) | First replay that has a key step |
| Screen Recording | Not needed. Avoid: no screenshots of recorded apps. | - |

No new entitlement exists to ask for: this is outside the sandbox anyway (see design.md). Hardened runtime needs no
extra entitlement for event taps.

### What must never be recorded

The recorder is a keylogger by construction if done carelessly. The design rule: **record intent, not input.**

1. **Never store keystrokes.** Store resulting values of ordinary fields, and key presses only when they resolve to a
   menu shortcut or a fixed key (Return, Escape, Tab) in a context that is not text entry.
2. **Secure fields**: the element whose subrole or role is `AXSecureTextField` (code: already checked in
   `GenericAccessibilityProvider.isSecure` and in `ActionServices`). Check at event time, and also use
   `IsSecureEventInputEnabled()`, which tells the recorder that some app has secure input on (password fields in
   native and web views, Terminal's Secure Keyboard Entry). When it is on, **pause recording** and show "Paused:
   password field". Resume only when it is off. A paused step is stored as "wait for the person" with no content.
3. **Apps on the disabled and password manager lists** (`ContextPrivacy.disabledBundleIDs`,
   `defaultSelectionBlocked`): refuse to record in them at all.
4. **Values of fields whose name suggests secrets** (password, passcode, code, token, secret, card, CVV, IBAN, SSN) in any
   language: store the step as "type a value" with the value left out, and require a parameter at run time.
5. **Clipboard**: do not record paste contents, and do not read the clipboard while recording.
6. **Typed text in general**: default to a parameter placeholder (`{ask}` at run time) with the sample shown only in
   the review. Offer "fixed text" explicitly, off by default for values longer than a few characters.
7. **File paths and document names**: keep them out of the stored titles. Titles that contain the document name get
   masked into a pattern.
8. **No screenshots, no OCR, no network.** The recording stays in memory until the person saves, and is written only
   to the local actions folder. Logs follow the existing rule: action id and outcome, never inputs.

### Showing exactly what was recorded

A recording ends in a review sheet, before anything is stored:

- One row per step in words: "Choose File > Export as PDF in Preview", "Click Save (button)", "Type text (asks you each
  time)", with the fragility badge.
- A "Recorded values" section lists every literal string that will be stored. Nothing is stored that is not on this
  list.
- A flagged list of what was **skipped on purpose** ("1 password field was not recorded").
- Edit, delete, reorder, convert fixed text to parameter, test one step, test all.
- A "Show raw JSON" disclosure so the person can see the file that will be written.

## 5. Prior art

All of this section is **known, not re-checked** in this spike; it is from product documentation and general
experience, and should be spot-checked before it is quoted externally.

| Tool | How it records / replays | What fails in practice |
|---|---|---|
| **Keyboard Maestro** | Has "Record" that captures menu selections, key presses and mouse clicks, plus explicit actions: "Select or Show a Menu Item", "Click at Found Image", "Press a Button" (UI element by Accessibility path), "Manipulate a Window". Menu items are addressed by title path. Strong at waiting (pause until an image or button appears). | Clicks recorded as screen positions break when windows move. Menu actions break on renamed items or other languages. Image matching breaks on theme and scaling. The mature answer is not better recording but more explicit actions and conditions, plus a clear failure behaviour. |
| **Hammerspoon** | No recorder. A Lua API over `hs.eventtap` (event taps), `hs.uielement.watcher` (AXObserver) and `hs.axuielement` (attribute walk). | Everything is hand-written; the community's repeated lessons are the same as above: AXObserver notifications are inconsistent between apps, observers die when an app restarts, Electron trees need the manual accessibility flag, and trees are slow. |
| **Apple Automator "Watch Me Do"** | Records clicks and keystrokes with an event tap; replays through Accessibility where possible and raw events otherwise. | Needs Accessibility, breaks on any window move or layout change, recorded as coordinates and keys. Effectively abandoned; Apple shipped no equivalent in Shortcuts. |
| **Apple Shortcuts (macOS)** | No UI recorder. Actions come from App Intents, and "Run AppleScript" / "Run Shell Script" cover the rest. | The lesson for Apropos: when an app offers an App Intent or script action, that beats UI scripting. Prefer existing backends (`shortcut`, `appleScript`, `urlScheme`) before synthesising UI steps. |
| **AppleScript "System Events" UI scripting** | `tell process "X" to click button "Save" of window 1`. Addressing is by title and index. Script Editor's Record works only in recordable apps (Finder and a few others). | Same addressing weaknesses as above, a visible sign that title plus index is what the platform offers. Slow (each reference is an Apple event round trip). |
| **XCUITest and Xcode's UI test recorder** | Records against `accessibilityIdentifier` first, then label, producing `app.buttons["Save"]`. | The best prior art for native apps: it works because the developer owns the identifiers. Third-party apps give no such guarantee. |
| **Playwright codegen (web)** | Records locators by priority: test id, role plus accessible name, text, then CSS. | The same ordering as the locator above. Confirms the "ordered fallbacks with a visible report of which won" approach. |
| **Open source Mac recorders** (several GitHub projects built on `CGEventTap` plus `AXUIElement`) | Mostly record coordinates and keycodes for replay. | Same failure: positions break, nothing says why. Those that record element paths find that path indices drift as soon as the app updates. |
| **Sikuli and image-based tools** | Template matching on screenshots. | Needs Screen Recording, breaks on theme, scale, localisation. Contradicts the local-first posture. Not a candidate. |

Summary of what the field learned: recorders are good at **drafting** and bad at being **the final artifact**. Tools
that last pair a recorder with an editable list, explicit waits and conditions, and loud failure.

## 6. Recommendation

### Architecture

```
Recorder (main actor, only while recording)
  NSWorkspace activation         ---> app boundary
  AXObserver per app             ---> windows, sheets, focus, value, selection
  Event tap (listen-only)        ---> mouse down/up, key down (never stored raw)
  Hit test at mouse down         ---> element + ancestors
  MenuShortcutResolver           ---> key + modifiers -> menu path (reuses AXMenuReader snapshots)
  PrivacyGate                    ---> secure input, secure fields, disabled apps, secret-ish names
        |
        v  RecordedEvent (in memory only)
StepBuilder: coalesce typing, drop hover/scroll, merge menu click + item, build ordered locators, score fragility
        |
        v  [RecordedStep]
Review sheet (edit, parameterise, test, delete)  ---> saved as an action pack entry (user:...)
        |
Replayer (actor)   --- per step: resolve locator ---> perform ---> wait for postcondition
   uses the existing ActionEngine for timeout, cancellation and logging (a new backend)
```

Code to reuse unchanged: `AXMenuReader` (menus, key equivalents), `AXPressTarget` (press semantics), `AXNode` and
`LiveAXNode` (fake-able tree for tests; recorder and replayer should resolve through this protocol so locator logic
is tested with fake trees), `AccessibilityPermission`, `ContextPrivacy`, `GenericAccessibilityProvider.isSecure`,
`LiveSelectionReplacer` (value set and paste fallback), `ActionEngine` timeouts and cancellation, the validator.

New in the package: `Sources/Apropos/Recording/` with `Locator`, `LocatorResolver`, `RecordedStep`, `StepBuilder`,
`Recorder`, `Replayer`, `RecordingPrivacy`. Views thin.

Hard limits shared with the rest of the app: nothing leaves the Mac, and the recorder runs only between an explicit
Record and Stop, with a menu bar indicator that is always visible while it is on.

### Step schema, fitting the existing pack format

`ActionBackend` today has six cases (`function`, `shell`, `appleScript`, `shortcut`, `urlScheme`, `keyPress`). Add a
seventh, `uiSteps`, so a recorded command is an ordinary action: same `id`, `title`, `symbol`, `requires`, `apps`,
`confirm`, `timeout`, same library, ranking, aliases, hiding and usage. Existing `schemaVersion` 1 files stay valid;
an older Apropos skips the file with the existing "newer schemaVersion" rule if the new backend bumps it to 2.

```json
{
  "id": "user:preview.export-pdf",
  "title": "Export as PDF to Desktop",
  "symbol": "doc.richtext",
  "requires": [],
  "apps": { "include": ["com.apple.Preview"], "exclude": [] },
  "backend": {
    "type": "uiSteps",
    "app": { "bundleID": "com.apple.Preview", "language": "en" },
    "steps": [
      {
        "id": "s1", "kind": "menu",
        "locators": [
          { "by": "shortcut", "key": "e", "modifiers": ["command"] },
          { "by": "menuPath", "titles": ["File", "Export as PDF"] }
        ],
        "expect": { "windowAppears": { "role": "AXSheet" }, "timeout": 3 }
      },
      {
        "id": "s2", "kind": "setValue",
        "locators": [
          { "by": "identifier", "value": "name-field" },
          { "by": "roleTitle", "role": "AXTextField", "title": "Save As:" }
        ],
        "value": "{ask:Name}",
        "secret": false
      },
      {
        "id": "s3", "kind": "press",
        "locators": [
          { "by": "identifier", "value": "save-button" },
          { "by": "roleTitle", "role": "AXButton", "title": "Save" }
        ],
        "expect": { "windowGone": { "role": "AXSheet" }, "timeout": 5 },
        "activates": false
      }
    ],
    "onFailure": "stop"
  },
  "output": "none",
  "confirm": false,
  "timeout": 30
}
```

- `kind`: `menu`, `press`, `setValue`, `select` (row or popup item), `key` (fixed key to a pid), `wait`.
- `locators`: ordered, as in section 2. `by` is one of `identifier`, `shortcut`, `menuPath`, `roleTitle`,
  `roleDescription`, `path`. `scope` (optional) names the window or container.
- `value`: a template. Variables follow the existing safety rule: they are data, delivered to a text field, never
  interpreted. Add one new variable form, `{ask:Label}`, for "ask at run time" (a small text prompt in the palette).
  Context variables (`{text}`, `{url}`, `{file}`) come from the existing `ContextValues`, so a recorded command can use
  the selection as its input, which is where this feature meets the rest of the product.
- `secret`: true means the value is never stored and never logged; it must be supplied by `{ask}`.
- `expect`: optional postcondition (`windowAppears`, `windowGone`, `elementAppears`, `valueEquals`) with a timeout.
- `activates`: whether the step needs the app frontmost. Shown to the person.
- `onFailure`: `stop` only in v1. No skip, no continue.
- Validator additions: refuse `key` steps with printable characters from variables, refuse `setValue` on a locator that
  names a password field, refuse more than N steps (say 50), refuse steps with no locator, require `apps.include` so a
  recorded command is bound to the app it was made in.
- Per-step status for the UI is derived at run time (`strategy matched`, `time`), never stored, so logs stay free of
  inputs.

### Riskiest assumptions, ranked

1. **Apps expose enough tree to address what the person clicked.** True for native apps and mainstream AppKit-based
   tools; false for canvas, games, many Java and Qt apps, and a moving target for Electron. If this fails for the apps
   Walid cares about, the feature is a menu-only recorder. Mitigation: detect and refuse early; test on his top ten
   apps in phase 0.
2. **Titles and structure survive updates well enough.** The identifier/shortcut/title fallbacks help, but in apps
   without identifiers a rename silently removes the primary strategy. This decides how often commands need repair.
   Mitigation: a fragility score, a repair flow, and prefer menu steps (menus are far more stable than toolbars).
3. **AXPress and AXValue works for the controls that matter without foregrounding.** Known to be inconsistent in web
   and some custom controls. If it does not, the choice is to activate the app (visible, intrusive) or fail.
   Mitigation: `activates` flag, measure per app in phase 0.
4. **Capture is complete enough to reconstruct intent.** The event tap sees clicks and keys but not meaning; hit
   testing at mouse down can race with UI changes; menu invocation is inferred rather than observed. A wrong
   inference yields a recording that replays differently. Mitigation: always review, always test-run before save.
5. **Privacy: never capturing secrets.** The gate relies on secure-field detection and `IsSecureEventInputEnabled()`,
   which are good for native and web password fields and blind to a non-password field that holds a secret (a recovery
   code, a card number in a normal field). Mitigation: parameters by default for typed text, name-based redaction, no
   raw keystrokes ever stored, and an obvious indicator while recording.
6. **The extra permission.** Input Monitoring is a second scary prompt on top of Accessibility and some people will
   refuse. Mitigation: request only when Record is pressed, explain what is and is not stored, and keep the no-recorder
   path (build from menu items and Shortcuts) fully usable.
7. **Hostile or chaotic UI during replay** (modals from other apps, notifications, focus moving). The stop-on-first-
   failure rule makes this safe but annoying.
8. **Maintenance cost.** Apps change; a recorded command that rots is worse than no command. Packs maintained by us
   (v2) amortise this; personal recordings are on the person.

### What will not work

- Reliable replay in apps with no Accessibility tree. It must be refused, not faked with coordinates.
- Drag and drop and gestures.
- Recording what happens inside text editors and canvas (what was typed where, brush strokes).
- Cross-language portability of title-only locators.
- Anything that needs the Mac unlocked and the app responsive; a locked screen, a sleeping Mac or an app in a stalled
  state fails with `cannotComplete`.
- Silent self-healing. Heuristic re-matching ("this is probably the new Export button") will be right most of the time
  and wrong exactly when the cost is highest. Offer suggestions, require confirmation.
- Recording a modal macOS system prompt (permission dialogs, Touch ID). Those are protected by the system on purpose.

### Build plan

Each phase is shippable on its own and gated on its tests.

**Phase 0: finish the spike (Walid runs `run-experiments.sh`, about 10 minutes).** Answers, from the files in
`build/results/`:
- `tree-en.txt`: is `AXIdentifier` present for the controls with identifiers and absent for Export? Do menu items carry
  identifiers? What are the role/subrole/description of the text field, popup, table rows?
- `replay-en.txt`: do the six steps succeed, via which strategy, in how many ms? Does `cannotComplete` appear for the
  sheet button? Is the frontmost app unchanged?
- `replay-fr.txt`: which steps fail on the French UI and which survive (expected: titles fail, identifiers and the menu
  path by shortcut survive).
- `observe.txt`: which notifications fire for presses, value sets, sheet open, menu items? Is `AXMenuItemSelected`
  sent at all for a programmatic press? Does the event tap get created, and is the count zero with no human input?
- Real human clicks cannot be tested with the invisible window. For that, edit the fixture to drop `alphaValue = 0` and
  `ignoresMouseEvents`, and run it on a scratch Space.
- Then repeat `dump` (not replay) read-only on three real apps the person chooses (one native, one Electron, one browser)
  with `AXManualAccessibility` toggled, to rank assumption 1. Reading is passive but it is the person's apps, so ask
  first.

**Phase 1: step engine without a recorder (1 to 2 weeks).** Add the `uiSteps` backend, locators, resolver over
`AXNode`, replayer with waits and stop-on-failure, menu steps only, plus the validator. Authoring is by hand in JSON
or from the menu list ("add this menu command to a sequence"). Tests: locator resolution on fake trees (identifier
wins, ambiguity skipped, language change, menu drift), replayer failure paths, validator refusals, schema round trip.
Manual: replay on the fixture.

**Phase 2: recorder for menus and shortcuts (1 to 2 weeks).** Event tap, hit test at mouse down, shortcut to menu
path resolution, app switch boundary, review sheet with words, fragility badge and raw JSON. Privacy gate and secure
input pause with tests. Test: fixture and three native apps; assert no key characters appear in any stored file.

**Phase 3: controls and text as parameters (2 weeks).** `press`, `setValue`, `select`, `{ask}`, postconditions,
`activates`, "test this step". Tests: fixture matrix (button with and without identifier, popup, table, sheet), French
run, background replay measurements, a recorded command after the fixture's identifier is removed to exercise
degradation.

**Phase 4: repair and confidence (1 to 2 weeks).** A failed step offers "pick the element again", re-record one step,
suggested candidates with confirmation, and a "needs attention" badge on commands whose primary strategy no longer
matches (detected by a dry resolve without performing, which is safe to run in the background on open).

**Phase 5: web and Electron, opt-in (separate decision).** Set `AXManualAccessibility`, use `AXDOMIdentifier` and
role plus name, accept lower reliability, label such commands as such. Only if phase 0 shows the trees are usable for
the apps that matter.

**Out of scope for the first release:** drag and drop, canvas apps, scheduled or triggered replay (needs a different
consent and focus model), sharing recorded commands across languages (needs identifier-only or per-language titles),
packs maintained for others (v2 feature 9).

### What to do next

1. Walid runs phase 0 (steps above) and returns `build/results/`.
2. If `AXIdentifier` crosses IPC and replay works in the background in the fixture, start phase 1.
3. If menus and shortcuts alone cover most of the value for the apps in the roadmap, consider shipping phases 1 and 2
   as "Sequences" and treat phase 3 onward as optional.
