# Changelog

All notable changes to Apropos are listed here. The format follows [Keep a Changelog](https://keepachangelog.com),
and versions follow [Semantic Versioning](https://semver.org). Entries under **Unreleased** are written by hand as
work lands.

## [Unreleased]

### Added (shortcut tips)
- When you run a menu item from the panel five times or more and it has a keyboard shortcut, the footer shows "Run 8 times
  from here. Try" with the keys while that row is highlighted. Command-K has "Stop reminding me of the keys" for one item,
  and General has a Shortcut tips switch. Nothing leaves your Mac.

### Changed (sequence draft)
- Each step of the draft shows the icon of the app it acts in, so a sequence across Finder, Notes and Mail reads at a
  glance. A step that reads the selection, files or page now says "Needs selected files, none are selected" when the app in
  front has none, and the Run sequence row names the first such step.

### Added (aliases and shortcuts for menu items)
- Any menu item of any app can have its own alias and its own global shortcut. In the panel press Command-K on an item and
  choose Alias and shortcut; Settings opens on Shortcuts, Menu items, with the alias field ready. The alias finds the item
  first when you type it. The shortcut runs the item in its app while that app is in front, so one key can serve items of
  different apps. A key another of your commands, the panel or macOS already uses is refused or flagged.
- A row that has an alias shows it as a small pill before its keys, tinted while you are typing exactly that alias.

### Added (settings, onboarding and the menu bar)
- A new Settings window: a floating glass sidebar and rounded sections, with pages for General, Appearance, Commands,
  Destinations, Context, Prediction, Integrations, Privacy and data, Updates and About. Appearance shows theme and row icons
  as small pictures and a live preview of the panel. General chooses which sources the panel includes: context actions, your
  commands, Send to and alternate commands.
- Commands page: a table with an alias and a shortcut per command, a guided New command form (link, Shortcut or program),
  ready-made examples, a detail sheet that says what a command does and what it can do to your Mac, and approval only after
  you tick that you have read it. Rows show how often a command was used.
- Destinations page: real app icons, a switch per destination, saved folders, a detail sheet with a test send, and a guided
  New destination form.
- Context page: a live "read right now" card, a switch for each kind of context (document, web address, folder and files,
  git branch, selected text), and an exceptions list of apps that are not read or only without the selection. Pause context
  for an hour from the menu bar.
- Prediction page: what it has learned, an accuracy line, your strongest habits with Forget, sensitivity, rows and how long to
  keep the log, per-app learning, and Pause learning for an hour from the menu bar.
- Integrations page: copyable links, which commands may run from outside and whether each asked yet, a link builder, setup
  recipes, a master switch, "always ask", and a list of recent outside requests (never the values).
- Privacy and data page: what Apropos keeps with sizes and Reveal and Forget for each, permissions with reasons, the network
  state, Export all my data, and Forget everything it learned.
- Updates shows the bundled changelog and says honestly that automatic updates arrive with the first public release. About
  shows the hero ring, grouped diagnostics and Copy support info.
- A new onboarding built around the logo ring, which is drawn as you set up. A menu bar popover replaces the plain menu on
  click: the app in front and what is read from it, a big Open button, recent commands and a row of controls. Command-comma
  opens Settings.

### Fixed
- Sequence draft: deleting the last step now returns to the command list (with what you had typed) instead of leaving an
  empty draft open.
- Sequence draft: every menu item you add is now a step of its own. Before, menu items added one after another were folded
  into a single step: the Steps list showed "1 item", the confirmation numbered every line "1." and the draft could fail
  with "Step 2: another step has the same id". The list, the numbers, delete, move, run and save now work step by step,
  including the same command added twice.
- A command's output could be cut short when its process exited at the moment its last chunk was being read. Output is now
  read to the end before the result is reported.

### Changed
- Saving a sequence as a command now picks its symbol from a searchable grid of common SF Symbols, with a suggestion from the
  first step, instead of asking for a raw symbol name. Arrow keys walk the grid, Tab moves between Name, Alias and Symbol.
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
