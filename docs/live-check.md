# Live check

Things that have only been checked in renders and tests, never in the running app. Try them in this order, tick what
works, and note what is off in a line each. Settings is Command-comma.

## Panel and chains
1. Open the panel in Finder with a folder selected. Do menu commands and context actions both list?
2. Add a row to a sequence draft, add a second, run it. Does each step run, and does a failure stop it?
3. Save a draft as a command. Does it appear on the Commands page, with an alias and a shortcut you can set?
4. Press Escape and Back in the draft level. Do the panel keys behave?

## Settings, General and Appearance
5. Record a new global shortcut. Does the recorder take it, and does the new key open the panel?
6. Turn "Context actions", "Your commands" and "Send to" off in turn. Does the panel list change each time?
7. Change Theme, Interface size and Row icons. Does the preview under Appearance match the real panel?

## Commands
8. Add the "Speak the selection" example. Select text, open the panel, run it.
9. Create a command with New command (link). Does it show up in the panel at once?
10. Click a command row. Does the detail sheet show what it does and its risks?
11. Import a command file. Is it pending, and can you approve it only after ticking "I have read it"?

## Destinations
12. Turn a destination off. Does it vanish from Send to in the panel? On again?
13. In a destination's details, press "Send Hello from Apropos" for Notes. Does a note appear?
14. Add a folder, then send selected files to it from the panel.
15. Create a destination with New destination (link to an app you have). Does it appear in Send to?

## Context, Prediction, Integrations, Privacy
16. On Context, press "Read again" with another app in front. Do the chips look right?
17. Turn "Selected text" off. Select text and open the panel: do text actions disappear?
18. Add an app under "Apps that are not read". Does Apropos read nothing there? Remove it again.
19. Menu bar popover: Pause context, then Resume. Does Context say "Paused"?
20. Run a few commands. Does "What it has learned" count them, and does a habit appear after three repeats?
21. Allow one command from outside, copy its link, open it in Terminal with `open`. Does it ask the first time?
22. Turn "Allow control from outside" off and repeat. Is it refused, and does Recent requests say so?
23. Privacy: do the sizes look right? Press Export all my data and open the folder it makes.

## Windows and the rest
24. Welcome guide from the popover: do all steps work, and does the ring animate?
25. About: does the ring sit right, and does Copy support info paste something sensible?
26. Quit and reopen. Is every setting you changed still there?

Light mode: repeat 7, 16 and 25 with the system in light mode.
