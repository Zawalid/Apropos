# Next-action prediction

Apropos learns which command the person usually runs next and offers it under **Usually next**, with one key and an
honest reason. Everything is local: counting tables built from a small run log, no network, no model file, nothing
that cannot be explained in a sentence.

## The run log

`~/Library/Application Support/Apropos/sequence.json`, separate from `usage.json`. Owner-only permissions (0600),
written atomically (temporary file then rename) at most every five seconds and on quit, off the main thread.

```json
{"schemaVersion":1,"events":[
  {"t":1800000000,"c":"com.apple.dt.xcode|product>test","a":"com.apple.dt.Xcode","x":["branch","document"]},
  {"t":1800000042,"c":"com.apple.terminal|shell>new tab","a":"com.apple.Terminal","p":"com.apple.dt.xcode|product>test","o":"com.apple.terminal|shell>new tab"}
]}
```

### Exactly what is stored, per event

| Key | Field | Content |
| --- | --- | --- |
| `t` | time | whole seconds since 1970 |
| `c` | command | the stable `CommandID` (bundle id, menu path, title; or a context action id such as `ctx:text.upper`) |
| `a` | app | bundle identifier of the frontmost app, only when it looks like one, else omitted (`unknown`) |
| `p` | previous | the `CommandID` that ran just before, if it was less than 10 minutes earlier |
| `x` | contextKinds | which kinds of context were present, from the fixed set `document url folder branch selection selectionCount`. Kinds only |
| `o` | offered | the `CommandID` that was shown under Usually next when the palette opened, if any |
| `k` | kind | only written for `dismiss` (the person chose Not now on a prediction); a plain run omits it |

### What is never stored

Selection text, URLs, document or file names or paths, search queries, window titles, tab titles, clipboard
contents. There is no field that could hold them: the event type has exactly the seven fields above, the initializer
sanitises each (the app must look like a bundle identifier, the kinds must be one of the six names, the command
identity must pass `PredictionPrivacy.isLoggable`), and a line in the file that would not be written today is dropped
when read. Tests assert all of this.

One residual risk is in the command identity itself: a menu item title is part of the identity, and a few menus are made
of the person's content (the Window menu lists document names, History and Bookmarks list pages, Open Recent lists
files). Commands under those menus, in English, French, German, Spanish, Italian and Portuguese, are not logged at all
(`PredictionPrivacy.contentMenus`). This is a best-effort list; a localisation it does not know would be logged as a
menu command. Identities over 200 characters or with a line break are refused.

### Lifetime

- Rotated by age (400 days) and by count (40 000 events; the oldest are dropped, in steps of 2 000 so it is not done on
  every run).
- A damaged file is copied to `sequence.json.broken-<timestamp>` and the log starts empty. A single bad line is skipped
  and the rest kept. A file from a newer schema version is read but never overwritten.
- **Reset learned ranking** clears it. It is not part of any export.

## The model

`Sources/Apropos/Prediction/PredictionModel.swift`. Counting tables, no network, no model file, nothing hidden: every
number is a count that can be quoted in a sentence.

For one moment (frontmost app, the last one or two commands run, time of day, weekday or weekend, kinds of context) it
looks up up to six small tables, from vague to specific:

1. the app (split by whether something ran in the last 10 minutes: the first command after a pause is a different question),
2. the app at this time of day (night, morning, afternoon, evening) and kind of day (weekday, weekend),
3. the app with these kinds of context present,
4. the command that ran just before, in any app,
5. that command, in this app,
6. the last two commands, in this app.

Level 4 and 5 together are the cross-app transitions: after a build in Xcode, "which command comes next in Terminal" is a
row of table 5 keyed by Terminal and the build, and the row exists because the log records the previous command whatever
app it ran in.

Each table answers "of the times we were here, which command followed", with Laplace smoothing (0.5 added to every
command and once for "something else"). The answers are blended from the vague end: a table is trusted in proportion to
its evidence, `n / (n + 2)`, and the rest of the trust falls back to the tables below it. The floor of the chain is the
existing frecency share of the command in that app, so someone with a year of `usage.json` and no log yet still gets a
(weak) guess. Counts decay exponentially with a half-life of 30 days, so a changed habit takes over within weeks. The
output is a probability, then multiplied by the feedback factor below.

Candidates are by default the commands of the frontmost app plus context actions. The palette passes the commands that
can run right now instead.

**Reasons** come from raw counts of the most specific table with at least 3 observations in which the command holds at
least 30 percent and appeared at least twice: "After Run Tests you chose Commit 9 of 12 times", "On weekdays in the
morning you chose New Note 14 of 20 times", "With text selected you chose Bold 8 of 11 times". With no such table the
reason says the command is used often (frecency) or has been run before.

**Feedback.** A run that happens while a prediction was shown counts as accepted when it is that command and as ignored
otherwise (the `o` field in the log). Not now writes a `dismiss` event. The confidence is multiplied by
`(accepted + 1) / (accepted + 0.5 * ignored + 2 * dismissed + 1)`, with the same decay. Two Not nows take a prediction
to a fifth of its confidence; accepting it again brings it back.

**Speed.** A prediction over a year of data (36 500 runs, 12 apps, 80 commands each) scored against a 600-command menu
takes about 0.04 ms in a debug build and 0.005 ms in release on the development Mac; the bound is 2 ms, tested in
`PredictionModelTests.predictsWithinTwoMillisecondsOnAYearOfData` for both the candidate-restricted and the open call.
Learning one more run is a handful of dictionary updates, so the model is updated in place after every run and built
from the log once at launch.

## In the palette

With an empty query, when the best prediction is at least 0.65 likely, the list gets a **Usually next** group right after
Pinned and before Suggested for this moment: the best prediction and, if it is at least 0.25 likely too, a runner-up
(at most two rows). Each row's subtitle is its reason in place of the menu path. Nothing is shown while a query is typed,
for a pinned command (it is already first), or for a hidden or unavailable one. Candidates are the commands that can run
right now, so a prediction is never something the app in front cannot do.

- **Run it with one key:** Command-Return runs the first Usually next row whatever is highlighted. It is free in the
  palette (Return, arrows, Tab, Page Up and Down, Command-K, Command-comma, Command-arrows and Control-N, P, J and K are
  taken). The group header shows the keys. With no prediction on screen the key does nothing. Return on the highlighted
  row still works as before, and the first row is highlighted when nothing is pinned.
- **Accepting and ignoring** are recorded in the log as the `o` field: the top prediction shown when the palette opened,
  attached to the next run if it happens within two minutes. Running that command counts as accepted, running anything
  else as ignored, closing the palette without running anything as neither.
- **Not now** is in the Command-K popover on a predicted row. It writes a `dismiss` event and the row drops out at once.
- The first time the palette opens before the context snapshot arrives, kinds of context are those of the last snapshot
  for the same app; when the snapshot changes them the group is asked for again.

## Controls

Registry entries (page: Privacy and data; the Settings pages themselves are not touched here): `predictNextCommand`
(default on) and `showPredictionReasons` (default on). Turning prediction off stops predictions and also stops recording new
runs; what is already in the log stays until it is reset, so turning it back on resumes from there. Reasons off keeps
the group and shows the usual menu path under each row.

**Reset learned ranking** clears the sequence log along with the usage counts (pins, hidden commands and aliases are kept
as before); resetting one app removes that app's runs and every mention of its commands in the rest of the log. The
registry has no button type, so the reset itself is the existing button in Settings. The settings export, the commands
export and `usage.json` never contain the log (tested).

## Evaluation

`PredictionEvaluator` replays a chronological log, trains the model on the first half, then walks the second half one
event at a time: predict, score, learn the event. It is deterministic (no clock, no randomness). Metrics over all test
events: **hit@1** and **hit@3** (the right command is the first, or among the first three, prediction), **coverage** (how
often something is shown: the best prediction passes the threshold), **wrong-when-shown** (of those, how often the first
row was not what ran). Baselines: **frecency only** (the app's most-used command by the existing frecency) and **repeat
last command** (the command most recently run in this app). The report also compares the baselines on exactly the
moments the model chose to show, prints a reliability table (does 80 percent confidence mean right 80 percent of the
time) and a threshold sweep.

```
swift run -c release apropos-probe --predict-eval                     # the person's real local log, aggregate numbers only
swift run -c release apropos-probe --predict-eval --synthetic 365     # reproduce the numbers below
```

The real-log mode never prints a command name, app or title.

### Synthetic data

`SyntheticLog` generates a person with routines: a development loop across Xcode and Terminal (build, run tests, commit,
sometimes push), writing in Notes in the morning, mail at the edges of the day, evening browsing, different weekends,
tasks that interleave (12 percent of steps), random commands (6 percent), and a habit that changes two thirds of the way
(the step after tests becomes Archive instead of Git Commit). It shows the model finds structure that is there. It does
not show that real people have this much structure, which is why the real-log mode exists.

Results, 365 days (12 213 events), seed 1, trained on the first half, threshold 0.65:

| | hit@1 | hit@3 | coverage | wrong when shown |
| --- | --- | --- | --- | --- |
| model | 69.1% | 91.7% | 51.6% | 9.7% |
| frecency only | 43.0% | 86.0% | 100% | 57.0% |
| repeat last command | 9.0% | 82.0% | 100% | 91.0% |

On the moments the model shows something it is right 90.3 percent of the time, frecency only 59.0 percent, repeat last
7.5 percent. Calibration error 0.055: confidence 0.8 to 0.9 was right 89.9 percent, 0.9 and above 96.8 percent; below 0.5
the model is slightly conservative. The same profile with heavy noise (25 percent random commands, 30 percent
interleaving, 16 249 events): hit@1 50.9 percent, coverage 22.4 percent, wrong when shown 17.8 percent, calibration
error 0.076, frecency only 36.8 percent. The model gets quieter when habits get noisy, which is the point of a threshold.

### The show threshold

Chosen from the sweep as the smallest threshold at which at most one shown prediction in ten is wrong: **0.65**
(`PredictionPolicy.showThreshold`; `chosenThresholdMatchesTheDocumentedRule` fails if the rule and the constant drift
apart). At 0.50 the wrong-when-shown rate was 16.2 percent, at 0.80 it was 6.2 percent with coverage 40 percent. A
second row joins the first when it is at least 0.25 likely. On random commands with nothing to learn the model shows
something less than 3 percent of the time (tested).

### What must be measured on real data before trusting this

Everything above is synthetic. Before the feature is trusted, run `--predict-eval` on a few weeks of Walid's own log and
check: (1) real coverage at 0.65, which will be far below the synthetic 52 percent if work is less repetitive; (2) real
wrong-when-shown and the reliability table, to see if 0.65 really means two in three; (3) that the model beats "repeat
last" and "frecency only" on the moments it shows, which is the only reason to show it; (4) whether menu commands are what
people repeat at all, or whether most sequences live in keyboard shortcuts and typing that Apropos never sees (the log
holds only what ran through Apropos, so a person who uses the palette rarely has too few events); (5) the effect of the
10 minute session window and the 30 day half-life, with `--half-life` and `--pseudo`; (6) whether Usually next is
accepted: the log records `offered` and the run, so the accept rate is computable after the first week of use.

## Tests

`SequenceLogTests` (format, rotation by age and count, corrupt and partial files, newer-version files, permissions, and
the privacy rules: only the documented keys appear in the file, no field can hold content, app and kinds are cleaned,
content menus are not logged, a tampered file cannot smuggle content in), `PredictionModelTests` (transitions, cross-app
links, second order, time of day, context kinds, decay, calibration of uncertainty, cold start, feedback, determinism,
the 2 ms bound), `PredictionEvaluationTests` (generator, evaluation determinism, baselines, calibration, threshold rule,
quiet on random data, drift recovery, no names in the report), `PalettePredictionTests` (group order, two rows, never
while searching, pinned first, Command-Return, Not now, engine end to end), `PredictionControlsTests` (settings, reset,
exports).

Checking the UI without the real app: `scripts/render-previews.sh palette-usually-next palette-usually-next-one
palette-usually-next-fresh` and `scripts/shots.sh` (the `usually-next` state seeds a routine through the real log, model
and palette path in agent mode).
