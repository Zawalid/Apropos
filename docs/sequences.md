# Sequences

A command made of steps of different kinds: change the selection with an action, send the result to Notes, open a link,
run a Shortcut, choose a menu item in another app. Each step passes what it produced to the next one. You build one in
the palette by adding rows to a draft, run it, and save it as a command that then appears under Your commands, with an
alias, its own shortcut, a link and Shortcuts like any other command ([user-commands.md](user-commands.md)).

It needs no new permission. Every step runs through an engine that already exists: the context actions
([context-actions.md](context-actions.md)), the send-to layer ([destinations.md](destinations.md)) and the step engine
([ui-steps.md](ui-steps.md)). The sequencer only decides the order and moves values between them.

```
palette rows ── Add to sequence ──► SequenceCenter (draft, in memory)
                                         │ Run                      │ Save as command
                                         ▼                          ▼
 SequencePlanner (catalogue, trust, effects) ──► Sequencer     UserCommandStore  (backend: sequence)
                                         │  per step                │ run later, from anywhere
                                         ▼                          ▼
                       EngineStepRunner ── ActionEngine / DestinationRunner / StepReplayer
```

## In the palette

- **Add to sequence** is in the Command-K popover of any row that can run: a menu item, a context action, one of your
  commands, a destination (from the destination list or a direct row). The panel stays open, so you add one row after
  another. The generic "Send selection to..." row cannot be added (it needs a choice first), and neither can a command
  that is itself a sequence.
- With a draft, the list opens with a **Sequence draft (3 steps)** row under its own header, and a chip in the search
  field says the same. Return on the row opens the draft level in the same panel, like the destination list, with a
  breadcrumb chip. Escape goes back one level: it stops a run, drops a question or a confirmation, leaves the save form,
  leaves the draft, then closes the panel.
- The draft level lists **Run sequence**, **Save as command...** and **Discard draft**, then the steps. Each step row says
  where it reads from ("Uses the selected text", "Uses the result of step 1", "Asks you for the text") and, during and after
  a run, what became of it ("Running", "Done", "Stopped: ...", "Skipped").
- On a step row: **Backspace** (with an empty search) or **Command-Backspace** deletes it, **Option-Up** and **Option-Down**
  move it. Command-K offers the same, plus *Use the selection instead* (of the previous step's result), *Ask me for the
  text* and *Keep going if it fails*.
- **Run** takes the context at that moment. If a step asks for text, the search field becomes the answer field ("Text for
  UPPERCASE"), one question at a time. If anything leaves a trace outside Apropos, one confirmation lists every effect
  and waits for a Return (below). Then it runs and marks the steps. A failure stays on screen with the draft intact;
  Return runs it again.
- **Save as command** opens a form: name (suggested from the steps), optional alias, symbol. Return saves through
  `UserCommandStore`; a bad alias or a taken name is reported and nothing is lost. The draft is then gone and a notice says
  where the command went. A shortcut key can be set through `SequenceSaveForm.hotkey`; the panel's form does not offer a
  recorder yet.
- The draft lives in memory only. Closing the panel keeps it; relaunching drops it.

### Chaining by default

A step that reads text reads the **result of the step before it** when that step gives text (a function, a program, an
AppleScript, a Shortcut, with an output other than none); otherwise it reads the selection. That is what makes
*uppercase, then send to Notes* send the capitals. Per step you can switch to the selection or to a question. Deleting or
moving a step recomputes the chain. A step whose result feeds the next one hands it over instead of delivering it (it does
not also land on the clipboard).

## The format

A sequence is a command whose backend is `sequence`. In a command file or a pack action:

```json
{
  "schemaVersion": 1,
  "command": {
    "id": "user:6f1c9d2e-0000-4000-8000-000000000002",
    "title": "Shout and note",
    "symbol": "megaphone",
    "requires": ["selectedText"],
    "backend": {
      "type": "sequence",
      "sequence": {
        "version": 1,
        "steps": [
          { "id": "s1", "label": "UPPERCASE", "kind": "contextAction", "action": "ctx:text.upper",
            "inputs": [{ "kind": "text", "from": "context" }],
            "output": { "name": "from-s1", "kind": "text" } },
          { "id": "s2", "label": "Notes", "kind": "destination", "destination": "dest:notes",
            "inputs": [{ "kind": "text", "from": "output", "name": "from-s1" }] }
        ]
      }
    },
    "output": "none",
    "confirm": false,
    "timeout": 21
  },
  "aliases": ["shout"]
}
```

Everything around `backend` is the command format of [user-commands.md](user-commands.md). The step list:

| Field | Meaning |
|---|---|
| `id` | `s1`, `s2`, ... unique; filled in when a hand-written file leaves it out |
| `label` | what you saw when you added it. Display only: review screens work out a summary from the data instead |
| `kind` | `uiSteps`, `contextAction`, `destination`, `userCommand`, `openURL`, `shortcut` (below) |
| `inputs` | up to 4, at most one per kind. A step sees exactly the inputs it declares and nothing else of the context |
| `output` | `{ "name", "kind" }`: hands the result to later steps under that name |
| `continueOnFailure` | go on with the next step if this one fails. Default false |
| `timeout` | seconds, 0.5 to 60. Default 10 (menu steps: 10 plus 6 per item, at most 60) |
| `trust` | `untrusted` for a step that came from outside; only written when set |

The standalone file form (`CommandSequence`: `schemaVersion`, `id`, `title`, `aliases`, `symbol`, `steps`, `trust`) is for
export, the recorder's hand-over and drafts. A saved sequence stores no trust of its own: the command's `review` is the
one source of truth.

### Step kinds

| `kind` | Field | Runs | Inputs | Output |
|---|---|---|---|---|
| `contextAction` | `action`: `ctx:...` or a pack id | the action through `ActionEngine` | what its `requires` need | its text, if it gives any |
| `userCommand` | `command`: `user:...` | one of your commands through `ActionEngine` | same | same |
| `destination` | `destination`: `dest:...` or `user:...` | the send-to destination through `DestinationRunner` | exactly one of `text`, `url` or `page`, `files`, `folder` | none |
| `openURL` | `url`: a template | a link or URL scheme; every `{value}` is percent-encoded | what its placeholders use | none |
| `shortcut` | `shortcut`: a name | `shortcuts run`; the text input is its input file | optional `text` | its text result |
| `uiSteps` | `ui`: the [steps format](ui-steps.md) | the menu picks | none | none |

A destination that asks for a folder each time cannot be a step (a sequence has no one to ask); a folder you copy or move
into is a destination of its own and can. A user command that is itself a sequence is refused: sequences do not nest.

### Values

Four kinds of value can be produced and passed on: `text`, `url` (a web address), `page` (an address with a title, from
its host) and `files`. Three only come from the sensed context: `folder`, `document` and `repo` (root and branch). An input
comes from one of:

- `context`: what Apropos senses when the run starts. It is taken once, so a step that changes the front app does not
  change what later steps see.
- `output`: the named output of an **earlier** step. Reading an output that no step gives is refused as unknown; one given
  by the same or a later step is refused as a cycle.
- `ask`: a prompt, answered in the panel before anything runs. Text only, at most 200 characters of prompt and 20,000 of
  answer. Runs with no one to ask (a shortcut key, a link) say so and do nothing.

Menu steps neither take nor give values in this version (typing into fields is phase 3 of [ui-steps.md](ui-steps.md)); they
take part for their order and effect.

## Safety

**Values are values.** Everything a step produces and everything you type goes through `SequenceCoercion` before another
step sees it: control characters are removed, text over 200,000 characters is refused (not cut), a blank result is a failure
(a step cannot pass nothing), an address must be a real http or https address, and a file list must be absolute, existing
paths with no `..`, at most 200. The engines then keep their own rule: a value reaches a program only as a separate argument,
standard input or an environment entry, a script only as `argv`, a Shortcut only as an input file, a link only as a
percent-encoded component. Templates are checked by the same validator as every other action: a placeholder in the scheme or
host of a link, a blocked scheme (`file`, `javascript`, `data`...) or a Shortcut name starting with `-` is refused at save,
at load and again at run time. Hostile-input tests send quotes, `$(...)`, backticks, option-like text, NULs, RTL marks, huge
text and look-alike template text through every kind of step and check what the engines received.

**Trust.** A sequence that comes from outside (an import, the recorder when asked to) is untrusted until you approve it, and
so is one with a single untrusted step, or one that names one of your commands that is itself waiting for approval. An
untrusted sequence is stored as a pending command: not listed, not bound to a key, not reachable by link or Shortcuts, not run.
`CommandRisk.runsSequence` makes an imported sequence wait like an imported program does, and the review screen
(`CommandSummary.lines`) lists the steps from their data. Approving it is `UserCommandStore.approve`. Imports assign fresh
ids, so a step that names one of the exporter's own commands will say it no longer exists.

**One confirmation, before anything runs.** A plan lists the effects of every step: a Mail draft, the Share menu, files
copied or moved, a web address (`through a web address`), a link, a Shortcut, a program, an AppleScript, menu picks in other
apps, a replaced selection, an action that asks first. If any of them asks (handing text to an app like Notes does not, as in
send-to) the whole run waits for one Return, and the confirmation shows every effect including the quiet ones, numbered by
step: `2. Open a draft in Mail`. Typing or Escape drops it. A saved sequence with such effects is stored with
`confirm: true`, so a shortcut key shows an alert with the same list, and the sequencer refuses to start without the
confirmation even if a hand-edited file says `confirm: false`.

**Availability.** The planner flags a destination whose app is not installed, a menu step in an app that is not installed, a
command that no longer exists, an action whose inputs the step does not provide, and a destination that cannot take what the
step gives. Nothing runs while a step without `continueOnFailure` has a problem, so a sequence never half-runs because its
last step was doomed. A step that continues on failure fails when its turn comes.

**Privacy.** Nothing is logged but step numbers and fixed words (`sequence step 2 failed(backend)`); a test reads the source
and fails if a log line interpolates anything else. Values print as counts. Messages name a step by position and its
catalogue title ("Step 2 (Notes)"), never what it carried. Menu steps keep every rule of [ui-steps.md](ui-steps.md) (no Apple
menu, no recent items, no password fields, nothing on the privacy list), checked again at the start of each run.

## Running

`Sequencer` runs the plan one step at a time off the main thread:

1. Refuses the whole run, before anything happens, if the plan is invalid, untrusted or blocked (`.refused`), if the
   confirmation was not given (`.needsConfirmation`) or a question is unanswered (`.needsAnswers`).
2. For each step it gathers exactly the declared inputs, runs the step with its own time limit, passes the output on after
   coercion, and records `ok`, `failed(reason)` or `skipped(reason)` with the time it took.
3. It stops at the first failure and skips the rest (`afterFailure`), unless the step says `continueOnFailure`. Steps that read
   what a failed step should have given are skipped (`inputUnavailable`); others still run.
4. The whole run has a time limit too (the command's timeout, at most 120 seconds, minus 0.3 s so the failure names the
   step). Cancelling the task, or Escape in the panel, stops the step in flight and starts no other.

Progress goes to the interface as `started(index)`, `finished(result)` and `ended(outcome)`. The report says
`completed`, `completedWithFailures`, `stopped(atStep:)`, `cancelled`, `timedOut`, or why nothing ran; `report.message` is the
sentence for a person. The step engine's own failures keep their words ("step 2 stopped: the item was not found").

Through the action engine a sequence command surfaces as `ActionError.sequenceFailed(sentence)` (stopped, cancelled, timed
out), `.confirmationRequired`, or `.unavailable(sentence)` (refused, a question with no one to ask, no sequencer connected).

## Limits

| Limit | Value |
|---|---|
| Steps per sequence | 20 |
| Menu items in all | 100 (and 50 per menu step, the step engine's limit) |
| Inputs per step | 4 |
| Name of a step, an output | 32 characters, lowercase letters, digits, `-` and `_` |
| Label of a step | 80 characters |
| Question | 200 characters; answer 20,000 |
| Text passed between steps | 200,000 characters |
| Files in a value | 200 |
| Step timeout | 0.5 to 60 seconds |
| Run timeout | 120 seconds |
| Command file | 256 KB (the user command limit) |

## From code

The recorder hands over UI steps; the Settings Commands page lists, reviews and edits sequences. Both use:

```swift
// A draft in the panel, from the recorder: checked against the step engine's rules and the privacy list.
palette.sequences?.add(uiSteps: recordedSteps, label: "Export and close", trusted: true)   // .added or .refused(reason)

// A sequence built in code, for a recorder that saves directly or an import:
var sequence = CommandSequence(title: "Export and close", steps: [
    SequenceStep(label: "Export and close", kind: .uiSteps(UIStepsBackend(steps: recordedSteps)))
])                                       // .trust is .trusted; sequence.imported() marks every step untrusted
let plan = SequencePlanner.plan(sequence.backend, trust: sequence.effectiveTrust, catalogue: catalogue)
plan.issues; plan.refusal; plan.trust; plan.effects; plan.confirmation.lines()
let command = sequence.userCommand(hotkey: nil, needsConfirmation: plan.requiresConfirmation)
try store.create(command)               // pending when untrusted: UserCommandStore.approve(id) after review

// A stored command, for a list or an editor:
command.sequenceBackend                  // SequenceBackend?, the steps
CommandSequence(command: command)        // identity and steps; trust is the review state
CommandSummary.lines(for: command)       // plain-language lines, from data
SequenceValidator.issues(in: backend)    // [SequenceIssue], each names its step
```

`SequenceCatalogue(contextActions:userCommands:destinations:isInstalled:)` is the picture of what exists right now; the app
builds it from the action library, the commands store and `SendToCenter.sequenceDestinations`
(`App/AproposApp/Integrations/SequenceSupport.swift`). `SequenceExecutor.live(...)` is what `ActionServices.sequences` is
set to, so a saved sequence runs from the palette, a shortcut key, `apropos://` and Shortcuts through the ordinary engine.
Tests replace `SequenceStepRunner` with a fake (`FakeStepRunner`) or the engine's services with recorders; nothing in the
tests touches an app.

## What is not supported

- Values between menu steps, typing text, press, set and select (phase 3 of the step engine).
- A sequence inside a sequence, loops, branches and conditions: steps run once, in order.
- Choosing a different source for an input in the panel beyond the chain, the selection and a question (a hand-edited file
  can do more).
- A recorder for the shortcut key in the save form, and editing a saved sequence in the palette (edit the file or the
  Settings page; the draft is for building).
- Running a sequence against live apps in tests: every test and every agent screenshot uses fakes.

## Where the code is

`Sources/Apropos/Sequences`: `SequenceModel` (formats, limits), `SequenceValidator`, `SequenceValues` (value kinds,
coercion, synthesized actions), `SequencePlanner` (catalogue, trust, problems), `SequenceConfirmation` (effects),
`Sequencer` (run, report, progress), `SequenceExecutor` (engine hook, `EngineStepRunner`), `SequenceCommands` (command
conversion, summaries), `SequenceCenter` (the draft). Engine hook: `ActionBackend.sequence`, `ActionServices.sequences`,
`ActionEngine.produce`, `ActionError.sequenceFailed`. Palette: `PaletteModel.attachSequences`, `CommandSource.sequence`. App:
`Integrations/SequenceSupport.swift`, `Views/SequenceViews.swift`, `Panel/DebugSequenceScenes.swift`. Tests:
`Tests/AproposTests/Sequences` (model, validation, planner and confirmation, sequencer with fake runners, engine and
injection, commands and persistence, builder flow). Previews: `palette-sequence-*` in `PreviewCatalog`, agent shots
`panel-sequence-*`.
