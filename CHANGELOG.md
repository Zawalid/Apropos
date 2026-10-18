# Changelog

All notable changes to Apropos are listed here. The format follows [Keep a Changelog](https://keepachangelog.com),
and versions follow [Semantic Versioning](https://semver.org). Entries under **Unreleased** are written by hand as
work lands.

## [Unreleased]

### Changed
- The app is now called Apropos (formerly Cue). Settings, usage and symbol packs move from `Application Support/Cue` to
  `Application Support/Apropos` once on first launch, and the old UserDefaults values are copied over. The old folder is
  left untouched. macOS treats the renamed app as new, so grant Accessibility again and remove the stale Cue entry.

### Added
- Sequences: chain steps of different kinds into one command, with the result of each step passed to the next. Add any
  runnable row to a draft from the Command-K popover (menu items, context actions, your commands, destinations); the list
  then opens with a Sequence draft row and a chip in the search field, and the draft level in the same panel lists the steps
  with delete and move by keyboard, Run and Save as command. By default a step reads the result of the step before it, so
  uppercase then send to Notes sends the capitals; a step can read the selection instead or ask you for text when it runs.
  Anything that leaves a trace outside Apropos is listed in one confirmation before the first step; a failure names the
  step and stops the run (or goes on, per step). A saved sequence is an ordinary user command, with an alias, a shortcut
  key, a link and Shortcuts. Imported sequences wait for your approval, and every value passed between steps is held to the
  action engine's injection rules. No new permission. See docs/sequences.md.
- Send to: a keyboard-first "send this to..." layer. With a selection, a page, files or a folder in front, the palette
  lists Send selection to... in the matching group, plus direct rows for the destinations you use most (counted per kind
  of thing). The row opens a destination list in the same panel, with a chip for the level and Escape to go back. Built in:
  Notes, Reminders, Things, Obsidian, Bear, a Mail draft (it never sends), copy or move into a remembered folder, and the
  system Share menu; each shows only when its app is installed. Mail drafts, moves and the Share menu show a one-line
  preview and need a confirming Return. Destinations are JSON packs in `Application Support/Apropos/destinations` that
  reuse the action engine's rules, so a selection can never become code; scripts in your own packs wait for approval.
  Apropos learns the destination ids only, never what you sent. See docs/destinations.md.
- UI steps (phase 1 of record-to-command): a command can be a list of menu picks in other apps, run through Accessibility
  without moving the pointer or taking focus. Steps find their item by identifier, role and title, menu path, shortcut,
  then position, refuse ambiguous matches, never touch the Apple menu, recent items, password fields or apps on the
  privacy list, and stop at the first failure with a named reason. Sequences are built from menu commands in code or
  by hand in JSON, rated Sturdy, Fair or Fragile, and `apropos-probe --steps` checks a file against a running app
  without performing anything. There is no recorder yet. See docs/ui-steps.md.
- Next-action prediction: Apropos learns, on this Mac, which command you usually run next and offers it under Usually
  next with a reason such as "After Run Tests you chose Commit 9 of 12 times". Command-Return runs the first one, Not now
  in the Command-K popover dismisses one, and Settings can turn it off. It learns from command names, apps and times
  only (never selections, URLs, document names or queries), in its own `sequence.json`, which Reset learned ranking
  clears and no export includes. See docs/prediction.md.
- A menu-bar app with a global shortcut (Option-Space by default, changeable in Settings) that opens a floating
  palette on the screen you are using. Escape or clicking away closes it.
- The palette lists the frontmost app's menu bar commands with their shortcuts, enabled and checked state, searches
  them with fuzzy matching, and runs the selected one with Return.
- Accessibility onboarding that explains why access is needed, opens System Settings, and picks the change up
  without a restart.
