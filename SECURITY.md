# Security

Apropos asks for powerful permissions. With Accessibility it can read and press controls in other apps, and with Input
Monitoring (only when you record a command) it is told when you click or press a key. This page says what it does with
that power, what it refuses to do, and how to report a problem.

## Reporting a vulnerability

Please do not open a public issue. Use GitHub's private vulnerability reporting: open the **Security** tab of this
repository and choose **Report a vulnerability**. Include the steps, the Apropos version or commit, and your macOS
version. You can expect a first reply within a week. Credit is given in the fix unless you prefer not to be named.

Supported versions: there is no release yet. Fixes go to `main`, and after the first release only the latest release
receives them while Apropos is pre-1.0.

## What counts as a security issue

- Anything that sends data about your screen, selection, documents, typing or commands off your Mac. Apropos is not
  supposed to make network connections.
- Text you did not type becoming code: a selection, page title, file name or link parameter that ends up executed as a
  program, a script or part of a shell command.
- A command running when it was not approved, or an outside caller (a link, Shortcuts, another app) running something
  the owner never allowed.
- Recording, reading or storing what it promises not to: typed characters, password fields, secure input, apps on the
  privacy list.
- A step pressing a different control than the one recorded, or pressing something it is built to refuse (the Apple
  menu, recent items, password fields).
- A release or build artifact that does not match the source it claims to come from.

## Threat model

### What Apropos reads, and when

| Source | How | When |
|---|---|---|
| The menu bar of the frontmost app | Accessibility API | when the panel opens or the app changes |
| Selected text, selected files, the web address and document of the front window, the folder, the git branch | Accessibility API, Finder, `git` | when the panel opens, per kind and per app as you allow in Settings, Context |
| Which apps are running and which is in front | `NSWorkspace` | continuously, as a name and bundle id only |
| Clicks and key codes while recording | a listen-only event tap (Input Monitoring) | only between pressing Record and stopping, and never while secure input is on or a password field has focus |

Apps on the privacy list, password managers among them, are not read or recorded. Password fields are read for their role
only, never their value. The recorder reads a key event's key code and modifiers, never its characters. A test reads the
recorder's sources and fails if they mention reading characters, the pasteboard, the network or screen capture.

### What Apropos keeps

Plain JSON files in `~/Library/Application Support/Apropos/`: settings, your commands, usage counts and pins, and the
order in which commands ran. They hold command names, app bundle ids and times. They never hold query text, selection
contents, addresses or document names (Open Recent menus are not recorded because their titles are file names). Each file
can be opened and read. Settings, Privacy and data shows sizes and has Forget for each, and Export all my data.

The files are not encrypted. They are protected by your macOS account and disk encryption like any other file in your
Library, so any process running as you can read them.

### Network

None. The app makes no network connections: no account, no analytics, no crash reporting, and update checks are off.
Commands you write yourself can of course open links or run programs that use the network. That is theirs to explain in
their confirmation.

### Running commands

Apropos can run what you define: a link, a Shortcut, a program, an AppleScript, a key press, and sequences of those. The
rules that keep this from becoming a way to run code you did not write:

- A command waits for your approval before its first run, showing what it does and what it can do to your Mac. Importing
  commands or sequences from a file never approves them.
- Text from outside, such as a selection, a page address or a link parameter, is passed as data: a separate argument,
  standard input, an environment variable, AppleScript `argv` or a percent-encoded URL part. It is never concatenated into
  program text. See [docs/context-actions.md](docs/context-actions.md).
- Outside callers get a narrow door. Only your own commands marked `allowFromURL` can run from an `apropos://` link or
  Shortcuts, the first call asks you, a caller cannot tell "does not exist" from "not allowed", and unknown or repeated
  parameters, paths, ports and oversized values are rejected. See [docs/integrations.md](docs/integrations.md).
- Steps that press menu items find their target by identifier, role, title and path, refuse ambiguous matches, never touch
  the Apple menu, recent items or password fields, and stop at the first failure with a named reason.

### Permissions

| Permission | Needed for | Asked |
|---|---|---|
| Accessibility | reading and pressing menus, reading the selection | at first launch, with a reason |
| Input Monitoring | recording a command | only when you press Allow on the recording screen |
| Automation | a command that controls another app with AppleScript | by macOS, the first time it happens |

### Build and distribution

- Releases are not notarized yet (see [docs/install.md](docs/install.md)). Until they are, the safest install is to build
  from source, or to check a download against its SHA-256 file. macOS Gatekeeper cannot vouch for an unnotarized app.
- The repository holds no signing keys, certificates, tokens or passwords. Signing material belongs in repository secrets,
  never in the tree, and `.gitignore` excludes the usual file types.
- Debug builds contain hooks for scripted checks (distributed notifications such as `com.zawalid.apropos.debug.run`, and
  a snapshot folder set by an environment variable). They are compiled out of Release builds. Do not use a Debug build as
  your daily app.

### Out of scope

- An attacker who already controls your macOS account, has root, or runs malware with its own Accessibility access. With
  those, Apropos is not what stands in the way.
- Another app you granted Accessibility to. macOS lets it read other apps' UI regardless of Apropos.
- Anything that needs you to approve a malicious command, or to edit a command file yourself.
- Menus an app builds lazily, or titles that differ between app versions. Those make a step fail, which is reported as a
  bug, not a vulnerability.
