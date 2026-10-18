# UI steps

A command made of steps: choose menu items in other apps through the Accessibility API, in order, stopping at the first
step that fails. It is phase 1 of record-to-command ([recording-spike.md](recording-spike.md)): the step engine, with no
recorder. A recorder will later write the same format, and until then you author steps by hand or from menu commands the
palette already knows.

To chain menu steps with other kinds of step (an action, a send, a link, a Shortcut) see [sequences.md](sequences.md).

A steps command is an ordinary command. It has the same `id`, `title`, `symbol`, `apps`, `confirm`, `timeout`, aliases,
hotkey, ranking and usage as any other, and it is stored the same way (`UserCommandStore`, a pack file, import and
export). Only its backend is new.

```
UserCommand / pack action ──► ActionBackend.uiSteps(UIStepsBackend)
                                      │ ActionEngine
                                      ▼
                       UIStepsExecutor (in ActionServices)
                                      ▼
   StepReplayer ── per step ──► StepResolver ──► LiveAXNode tree (reads only)
        │                              │
        │  press / activate / sleep    └─ the same resolver serves StepDryRun (no press, no wait)
        ▼
   StepEnvironment (LiveStepEnvironment, or a fake in tests)
```

## The format

A command file (`~/Library/Application Support/Apropos/commands/<id>.json`) or a pack action; only `backend` differs from
[user-commands.md](user-commands.md):

```json
{
  "schemaVersion": 1,
  "command": {
    "id": "user:export-and-close",
    "title": "Export as PDF and close",
    "symbol": "rectangle.stack",
    "requires": [],
    "apps": { "include": ["com.apple.Preview"], "exclude": [] },
    "backend": {
      "type": "uiSteps",
      "version": 1,
      "steps": [
        {
          "id": "s1",
          "action": "menu",
          "app": "com.apple.Preview",
          "description": "Choose File > Export as PDF",
          "locators": [
            { "by": "identifier", "value": "menu.exportPDF" },
            { "by": "roleTitle", "role": "AXMenuItem", "title": "Export as PDF" },
            { "by": "menuPath", "titles": ["File", "Export as PDF"] },
            { "by": "shortcut", "key": "E", "modifiers": ["command", "shift"] }
          ],
          "wait": { "timeout": 5 },
          "expect": { "condition": "appears", "locator": { "by": "identifier", "value": "export.sheet" }, "timeout": 4 }
        },
        {
          "action": "menu",
          "app": "com.apple.Preview",
          "description": "Choose File > Close",
          "locators": [{ "by": "shortcut", "key": "W", "modifiers": ["command"] }],
          "activates": false
        }
      ]
    },
    "output": "none",
    "confirm": false,
    "timeout": 30
  }
}
```

- `version`: 1. A different number is refused.
- `steps[].id`: unique inside the command. Optional in a hand-written file; missing ids become `s1`, `s2`, ... by position.
- `action`: `menu` is the only action that runs in this version. `press`, `setValue` and `select` are part of the format so
  files keep their meaning, and are refused for now.
- `app`: the bundle identifier of the app the step acts in. Required. A command can span apps; give `apps.include` every
  app it should be offered in.
- `description`: a sentence for the review list. It is never used to find anything, and review screens show a summary
  worked out from the locators instead, because a file from someone else can say anything in its description.
- `wait.timeout`: seconds to wait for the item to exist and be enabled, 0.2 to 30, default 3.
- `expect`: optional outcome that must be true after the press: `appears` or `gone`, for a `identifier` or `roleTitle`
  locator found among the app's windows, with its own `timeout`. If it does not hold the step fails as
  `expectationNotMet`, even though the press was delivered.
- `activates`: bring the app to the front for this step. Default false; replay never takes focus otherwise.
- `apps` is `{ "include": [...], "exclude": [...] }`; both keys are required by the pack format.
- Not part of the format: `onFailure`. A run always stops at the first failure; a key by that name is ignored.

The JSON of the steps alone, ready to paste into a `backend`, comes from `StepSequenceBuilder.json()`.

## Locators and their order

A step carries an ordered list of locators. Whatever order they are written in, they are tried strongest first:

| Order | `by` | Fields | Matches | Survives |
|---|---|---|---|---|
| 1 | `identifier` | `value` | the `AXIdentifier` the developer set | updates, other languages |
| 2 | `roleTitle` | `role`, `title` | role and visible title (case, accents and `...` versus `…` ignored) | not a renamed item, not another language |
| 3 | `menuPath` | `titles` | the menus down to the item, by title, same comparison | same as above |
| 4 | `shortcut` | `key`, `modifiers` | the item's key equivalent (`command`, `option`, `shift`, `control`) | other languages; not a remapped shortcut |
| 5 | `position` | `path` | indexes: menu bar item, then each item below | nothing: menus gain items between macOS versions |

Rules the resolver keeps:

- A locator must match **exactly one** element. Two matches mean the locator is skipped, never guessed from. If nothing
  else matches, the step fails as `ambiguous`.
- The first locator that matches uniquely wins, and the report says which kind it was. If it was not the strongest kind
  the step has, the result is flagged `isDegraded`: it worked, but its primary strategy no longer matches.
- Only leaf menu items are candidates. Submenu headers and separators never match, by any locator including `position`.
- It reads only what it compares: role, subrole, title, identifier, enabled and the key equivalent. It never reads a
  value (`AXValue`, `AXSelectedText`), and a password field gets only its role, subrole, title and identifier read.
- The search has a node budget (1500 nodes, depth 8) and a deadline, so a huge tree or a hung app cannot stall it.

English and French titles: identifiers and shortcuts are the same in every language, so a step with either replays on a
French UI. A step that has only titles fails there with `notFound`. This is by design; the repair is to add a shortcut or
an identifier, not to guess.

## Fragility

Computed from the locator kinds a step has, shown as a badge by the UI (`UserCommand.stepFragility`,
`ContextAction.stepFragility`, `UIStepsBackend.fragility`):

| Rating | When | Meaning |
|---|---|---|
| Sturdy | an `identifier` or a `shortcut` | survives renamed titles and other languages |
| Fair | `roleTitle` or `menuPath`, nothing stronger | stops working if the app renames the item or runs in another language |
| Fragile | `position` only, or nothing usable | stops working when the app's menus change |

A command is as sturdy as its weakest step. Fragility is about how likely a command is to break; whether it is broken
right now is `StepDryRun` (below).

## Privacy and safety rules

All enforced by `UIStepsValidator`, when a command is saved, when a pack loads, when an import is reviewed and again at the
start of every run (the privacy list can change in between). A command that breaks one is refused with a message naming
the step number, never its content.

- **The Apple menu is never used.** It lists recent apps, documents and servers and holds the person's name. A menu path
  starting with `Apple`, a `position` starting at index 0 and any search of the first menu bar item are refused. The
  resolver skips menu bar index 0 in every language.
- **Recent items menus are never used** (`Open Recent`, `Recent Items`, `Ouvrir récent`, `Éléments récents` and the like,
  and any menu whose identifier contains `recent`): their items are the person's documents. The resolver does not
  search inside them either.
- **Password fields are never read or filled.** A locator with a secure role is refused, a locator that resolves to a
  secure text field fails as `secureField`, and no value attribute is ever requested.
- **Apps on the privacy list are refused**, including the default password managers.
- **No pixel coordinates.** A locator of an unknown kind is kept only so the validator can name it; `x`, `y`, `point`,
  `frame`, `coordinate` and `pixel` make the whole step refused.
- **Nothing sensitive is logged.** The step engine writes through `StepLog` only: the action id, a step number, a fixed
  word (`notFound`, `ambiguous`, the locator kind) and a duration. No title, identifier, description or value is a
  parameter of any logging call; a test runs steps over a tree full of marked secrets and checks every line. Failure
  messages are fixed sentences.
- **No pointer movement.** Everything is an Accessibility action; no synthetic mouse event exists in this code.
- **No activation** unless the step says `"activates": true`.
- Importing a steps command stores it pending until the person approves it (`CommandRisk.controlsApps`).

## Limits

| Limit | Value |
|---|---|
| Steps per command | 50 |
| Locators per step | 6 |
| Length of a title, identifier or id | 200 characters |
| Length of a description | 200 characters |
| Menu path depth | 8 |
| `wait` and `expect` timeout | 0.2 to 30 seconds |
| Command `timeout` | 0.5 to 120 seconds (the existing rule; the builder suggests 10 + 6 per step) |
| Resolver search | 1500 nodes, depth 8 |
| Press retries | 2 more attempts |

## Running

`StepReplayer` runs the steps off the main thread (nothing in it is main-actor). For each step:

1. Find the app by bundle identifier (the process the command was started in wins when it matches). Not running fails as
   `appNotRunning`; the app is never launched.
2. Activate it only if the step says so.
3. **Wait until the item exists and is enabled**, polling with backoff (50 ms, growing by 1.6 up to 400 ms), up to the
   step's `wait` (default 3 s). The first step in an app Apropos has not driven yet in this launch gets 3 s more, because
   the spike saw identical steps time out on a cold start and succeed moments later.
4. Press it (`AXPress`). A press that times out counts as delivered, as it does for menu commands today: a menu item that
   opens a sheet keeps the app busy. A stale element is resolved again; other errors are retried twice, then reported with
   the error code.
5. If the step has `expect`, poll for it; if it does not hold the step fails as `expectationNotMet`.

The run has a total timeout (the action's `timeout`, minus 0.3 s so the failure names the step). Cancel the task and the
run stops: no step starts after that and a wait ends at once.

Failure reasons (`StepFailureReason`), always with the step number: `notFound`, `ambiguous`, `disabled`, `timedOut`,
`appNotRunning`, `permissionMissing`, `cancelled`, `secureField`, `notAllowed` (the validator refused it at run time),
`expectationNotMet` and `actionFailed(code)`. The run stops at the first failure; it never skips a step. Through the action
engine it surfaces as `ActionError.uiStepFailed(StepFailure)` with a message such as "Step 2 stopped: the item was not
found."

## Dry resolve and the needs-attention badge

`StepDryRun().run(backend, environment:)` finds every step's element without performing anything. It takes only the
read-only half of the environment (`StepObserving`), so it cannot press, activate or sleep; it looks once, never waits,
and is safe to run in the background. It returns per step the locator kind that would match, whether that was a fallback,
whether the item is enabled and the failure if any, plus a health:

| Health | Meaning | `needsAttention` |
|---|---|---|
| `healthy` | every step matched with its strongest locator | no |
| `degraded` | everything resolves but a weaker locator was needed: it will break next | yes |
| `broken` | some step no longer resolves, or is no longer allowed | yes |
| `unknown` | no Accessibility access, or an app is not running | no |

Menu steps do not depend on each other, so each is resolved against the app as it is now. A future step that acts on
something an earlier step opens cannot be checked this way.

From the terminal: `swift run apropos-probe --steps <file> [--wait 3]` prints, for each step, which locator would match,
and the health. It reads a steps object, a command file or a pack. It never prints a title of the live menus, never
performs anything, and says so when the terminal has no Accessibility access (exit code 2).

## Authoring without a recorder

```swift
var sequence = StepSequenceBuilder()
try sequence.addMenuCommand(exportCommand, appName: "Preview")   // a Command from the menu reader
try sequence.addMenuCommand(closeCommand, appName: "Preview")
sequence.issues()                                                 // [UIStepsValidationError], empty when fine
let saved = try await sequence.save(title: "Export and close", in: store)
saved.stepFragility                                               // .sturdy / .fair / .fragile: the badge
```

`addMenuCommand` captures, from the `Command`: the identifier (read from the live menu item through its Accessibility
target; pass `identifier:` to give one), the role and title, the menu path and the key equivalent. A `position` locator is
added only with `includePosition: true`, because after an update it can press a different item. It refuses commands that
are not menu items, items in the Apple menu or a recent items menu, and apps on the privacy list. `save` goes through
`UserCommandStore.create`, which validates again. The command is bound to the apps of its steps, needs no context, and its
output is `none`.

## What is not supported

- Recording. There is no event tap and no hit test; phase 2 writes the same format.
- `press`, `setValue`, `select`, key steps, typed text and `{ask}` parameters (phase 3).
- Anything not in the menu bar: toolbars, buttons, sheets as targets (they can only be waited for with `expect`).
- Web and Electron apps, whose menus and trees are different (phase 5).
- Pixel positions, drag and drop, gestures, apps with no Accessibility tree.
- Skipping or continuing after a failed step, scheduled or triggered runs, and healing: a failed step is reported, never
  silently replaced by a guess.
- Reading values of fields, ever.
- Cross-language portability for title-only steps. Use identifiers or shortcuts.

## Where the code is

`Sources/Apropos/Steps`: `StepModel` (schema, fragility), `StepValidator`, `StepText`, `StepResolver` and `StepNodeReader`,
`StepDryRun`, `StepReplayer`, `StepEnvironment` and `LiveStepEnvironment`, `StepLog`, `UIStepsExecutor`, `StepAuthoring`.
Engine hook: `ActionBackend.uiSteps`, `ActionServices.uiSteps`, `ActionError.uiStepFailed`. Tests: `Tests/AproposTests/Steps`
(fake trees and a fake environment with a virtual clock).
