# Recorder plan: from a tested core to a feature people use

Written 2026-10-19. Read [recording-spike.md](recording-spike.md), [ui-steps.md](ui-steps.md) and [recorder.md](recorder.md)
first. This plan does not repeat them.

## Where it stands
- **Done in code, tested on fakes:** the step engine (phase 1), and the recorder core with its live adapters (phase 2):
  permission model, session state machine, draft with edits, validation, save through `UserCommandStore`.
- **Never run live:** the event tap delivering events, hit tests on real open menus, secure-input detection, non-US key
  layouts, replay under load. The spike found one unexplained replay failure, so retries are part of the plan.
- **UI (R1, 2026-10-19):** the permission screen, the recording bar, and three entry points (panel row, menu bar popover,
  Commands page) exist, and a finished recording is handed to the sequence draft. The review sheet (R2) does not exist yet,
  so a recording is reviewed and saved through the draft.
- **Scope decided earlier:** menus and keyboard shortcuts first; controls and typed text later; web and Electron only as
  a separate opt-in decision.

## The promise to the person
"Show Apropos once, and it does it for you." Record a few menu picks in an app, name the result, and run it from the
panel, a shortcut or a sequence. It must feel safe: nothing you type is stored, passwords pause it, and you see exactly
what it learned before you save.

## Milestones
Each ends in something you can try, and nothing starts until the one before it holds.

### R0. Live proof (about 2 days, needs you for 30 minutes)
Wire `Recorder` into the app behind a debug entry and run it for real, once, to settle the unverified list above.
- Grant the Apropos app Input Monitoring (Settings, Privacy has the row and the button).
- Try three apps: the spike fixture, Finder, Safari. Record File menu picks and two shortcuts, switch apps, type text, click
  the secure field.
- Exit: the tap delivers events, menu clicks are classified, typing leaves one note, the secure field pauses, a draft
  validates. Any surprise is written into the spike doc and fixed before R1.
- Risk: macOS does not report clicks inside an open menu the way we expect. Fallback: record the shortcut when there is
  one, and note the rest as "not recorded" (already how the draft treats it).

### R1. Start, stop, see it recording (about 3 days)
- **Entry points:** a "Record a command" row in the panel's Actions, the menu bar popover, and a Record button on the
  Commands page.
- **Permission screen:** one clear sheet that names Accessibility and Input Monitoring, says what each does for this
  feature, shows their state, and opens the right System Settings page. It never prompts by itself.
- **The recording bar:** a small floating glass pill near the top of the screen: the pearl pulsing (the brand's "now"),
  elapsed time, step count, Pause and Stop, and a global shortcut to stop. It never takes focus, so the app being
  recorded stays in front. Limits (5 minutes, 50 steps) show as a quiet countdown.
- Exit: start from any entry point, see steps count up, stop with the shortcut, no focus stolen.

### R2. Review and save (about 4 days)
- **Review sheet:** one row per step in plain words ("Choose File > Export as PDF in Preview"), a reliability badge, and
  the skipped notes in place ("A click on a button was not recorded"). Delete, move, rename, merge with the next.
- **Try it:** a dry run that resolves every step against the live app without pressing anything, marking each green or
  red, then a real replay on request.
- **Save form:** name, alias, optional shortcut, "Works in" this app only or any. It saves through the existing user
  command store, so it appears on the Commands page and in the panel at once.
- Exit: record, review, fix a row, try it, save, run the saved command from the panel.

### R3. Replay you can trust (about 1 week)
- Wait for readiness (menu open, window present) with short polling and a hard timeout per step.
- One automatic retry for the unexplained failure the spike saw, then a plain failure message that names the step.
- Never move focus away from where the person is working: replay presses menu items through Accessibility, not the mouse.
- A confirmation for any recorded command the first time it runs, like imported commands.
- Failure states for the panel: step 3 failed, app not running, menu item missing, with the next action in one line.
- Exit: a recorded command runs 50 times in a row on the fixture and Finder without a single failure, and failures read
  well.

### R4. Controls and text as values (about 2 weeks, phase 3)
- Record clicks on buttons and checkboxes (`press`), choices in pop-up menus (`select`), and values in fields (`setValue`).
- Typed text becomes a named value you choose to ask for each run, give a fixed value, or take from the selection. What
  was typed is still never stored, so the person types the example value into the review sheet.
- Postconditions ("wait until this window appears") so a replay does not rush.
- Exit: record "new note with a title" in Notes, run it with a different title each time.

### R5. Repair and confidence (about 1 to 2 weeks, phase 4)
- When a step stops matching, offer "Pick the element again": hover to highlight, click to choose, re-save that step only.
- Re-record just one step without redoing the rest.
- A confidence line on each saved command ("Found by identifier: solid", "Found by title: may break after an update").
- Exit: change a menu title in the fixture, run the command, repair it in under 30 seconds.

### R6. Sharing and packs (later)
Export and import recorded commands as part of command packs. Web and Electron stay a separate decision after R5.

## Order and timing
R0, R1, R2 and R3 are the shippable core, about 3 weeks of focused work. R4 and R5 are what make it worth paying for.
I would not start R4 until R3 passes its 50-run check on real apps.

## Design notes
- The pearl pulses only while recording is live, as the brand says: it means "now".
- The recording bar uses the same glass and rim as the panel, so it reads as part of Apropos.
- Everything the person sees is plain words: no locators, no JSON. "Found by identifier" is the most technical it gets.
- Empty and failed states use the ring illustration already in the panel.

## What I need from you
1. **Permissions on your Mac for R0:** Input Monitoring for the Apropos app, once.
2. **Thirty minutes for R0 and a few real apps** you use daily, so the test is on what you really do.
3. **A decision on one question:** record menu picks only, or also keyboard shortcuts that trigger menu items? The core
   supports both. I recommend both.

## Risks, in order
1. Clicks in open menus are not delivered or not hit-testable (R0 settles it).
2. Replay failures that cannot be explained and only retries cure (R3 measures it).
3. Apps with no accessible menus: Electron, some web apps. They will say "nothing recorded" and that is acceptable.
4. Permission fatigue: two permissions is a lot. The copy and the order matter as much as the code.
5. Trust: a command that presses things in other apps must show what it will do before its first run.
