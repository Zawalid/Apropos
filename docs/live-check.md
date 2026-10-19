# Live check: a walkthrough

Follow it top to bottom, about 40 minutes. Each step says what to do, what you should see, and what to tell me if it is
off. Write down only the step number and one line ("3b: the chip says Draft 0"). You need: Finder, Safari, Notes, and a
text file or note with a few words in it. Settings is Command-comma.

Before you start: quit and reopen Apropos once, so you test the current build. Grant Accessibility if asked.

---

## Part 1. The panel in Finder (5 min)
Open Finder, make a folder called `Test`, put two files in it, open it, select both files.

1. Press Option-Space.
   - See: the search field has the Apropos ring on the left and a Finder chip on the right. Under it: Usually next (maybe
     empty), a group "Selected files" with Send file to, Copy path, Copy name, Reveal in Finder, then Finder's menus with
     counts like "File 63 items".
   - Off if: the ring is missing, no counts, selected-file actions missing.
2. Type `nf`. See: New Folder first. Clear it, type `shwo`. See: Show... items (a slip still finds things). Clear it,
   type `clo`. See: Close before Close Other Tabs or longer ones.
3. Press Escape. Drag the panel by the very top strip (not the text). See: three dashed blue guides stay visible while you
   drag, it snaps to them with a tick on a trackpad, and where you let go is where it opens next time.
4. Settings, General, Position: choose Centered, close, reopen the panel. See: it is just above the middle of the screen.
   Choose Where you left it again.

## Part 2. A sequence (8 min) — the bug you hit
Still in Finder with the two files selected.

5. Open the panel, type `new folder`, press Command-K, choose Add to sequence. See: "Draft · 1" chip appears.
6. Back in the list (Escape if needed), type `copy path`, Command-K, Add to sequence. See: "Draft · 2".
7. Type `settings`, Command-K, Add to sequence (that is Finder > Settings). Then add the same Copy path again.
   See: "Draft · 4".
8. Click the Draft chip (or choose the Sequence draft row). See: Steps 4 items, numbered 1, 2, 3, 4, with the right names,
   and Copy path twice. **Off if** any step is missing or all say "1."
9. Choose Run sequence. See: "Allow these 4 things?" with steps numbered 1 to 4. Press Escape to cancel (do not run it).
10. Select a step with the arrow keys, press Backspace, repeat until none are left. See: after the last one the panel
    returns to the normal list. **Off if** it stays on an empty draft.
11. Add two steps again, choose Save as command. See: Name, Alias, Symbol on one short form; the Symbol row is one line of
    suggestions plus More. Type name `Test seq`, alias `ts`, pick a symbol, press Return.
12. Open Settings, Commands. See: Test seq with alias ts, its symbol, used 0 times.

## Part 3. Settings, page by page (15 min)
13. **Commands:** click New command. See: a form with Symbol as a small tile (click it: popover with search and grid) and
    the hint line above the buttons. Make a link command: address `https://www.google.com/search?q={text}`, name `Google it`,
    Offered: When text is selected, add it.
14. Select some words in Notes, open the panel, type `google`. See: Google it in the list. Press Return: Safari opens a
    search.
15. **Commands:** click Google it. See: a detail sheet with what it does and risks. Close. Add the example Speak the
    selection, select text, run it from the panel: it reads aloud.
16. **Destinations:** turn Bear off. Select text in Notes, open the panel, choose Send selection to... See: Bear not
    listed. Turn it on again. Click Notes, press "Send Hello from Apropos": a note appears.
17. **Shortcuts:** click the field next to Google it, press Control-Option-G. See: it shows the keys. Click a field and press
    Command-Space. See: a note that macOS uses it for Spotlight. Clear it. Select text anywhere, press Control-Option-G.
    See: Google search runs.
18. **Context:** click Read again with Notes in front. See: chips for what was read. Turn off Selected text, select text,
    open the panel. See: text actions gone. Turn it back on. Under Apps that are not read, add an app and remove it.
19. **Menu bar icon:** click it. See: Open Apropos button, two buttons Pause context / Pause learning. Click Pause context
    then check Settings, Context says Paused; click Resume.
20. **Prediction:** run a few commands, open Settings, Prediction. See: runs counted under What it has learned. (Habits
    appear after three repeats of the same pair.)
21. **Integrations:** Google it, More, allow it from outside is off by default; click Allow on a command, Copy link. In
    Terminal run `open "<the link>"`. See: a confirmation the first time. Turn Allow control from outside off, repeat:
    refused, and Recent requests says so.
22. **Privacy and data:** sizes look sensible; click Export all my data and open the folder it makes.
23. **About:** the ring sits well under the title; Copy support info pastes a short report.

## Part 4. Welcome guide and light mode (5 min)
24. Menu bar icon, the sparkle button. See: the welcome guide opens; step through it; the ring draws as you go.
25. Switch macOS to light mode. Open the panel, Settings, Appearance, About. See: nothing gray or unreadable.
26. Quit Apropos and reopen. See: every setting you changed is still there, including panel position and Draft is gone.

## What to send me
A list like: `8: only 1 step shown`, `14: Google it missing`, `17: Command-Space gave no note`. Anything that felt slow or
looked wrong, even if it is not in this list.
