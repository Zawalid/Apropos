# Contributing to Apropos

Thanks for helping. Apropos reads other apps through Accessibility and can run commands on your Mac, so the bar for
changes that touch reading, recording or running is high. The bar for everything else is "clear and tested".

By contributing you agree that your work is released under the [MIT license](LICENSE) of this project. Please follow the
[code of conduct](CODE_OF_CONDUCT.md). For a security problem, do not open an issue: see [SECURITY.md](SECURITY.md).

## Before you start

- For anything bigger than a small fix, open an issue or a [discussion](https://github.com/Zawalid/Apropos/discussions)
  first, so you do not spend a weekend on something that does not fit. Apropos is the context companion next to a
  launcher: it does not launch apps, search files or manage the clipboard.
- Good first changes: a fix with a failing test, a symbol or action pack for an app, a clearer sentence in the docs.

## Set up

You need macOS 14 or later, Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd App && xcodegen generate && open Apropos.xcodeproj
```

`App/Apropos.xcodeproj` is generated from `App/project.yml` and is not committed. Run `xcodegen generate` again after
adding or removing files. [docs/development.md](docs/development.md) has the fast loops:

- **Live previews** in Xcode (`App/AproposApp/Preview/Previews.swift`, Option-Command-Return) show every screen in every
  state without launching the app, signing it or granting any permission. Start UI work there. When you add or change a
  screen, add or update its scene in `PreviewCatalog`. `scripts/render-previews.sh` writes the same scenes to PNGs.
- **`scripts/dev.sh`** rebuilds a Debug build and relaunches it, for what only the real app can show: the global hotkey,
  real glass and Accessibility on live apps. It quits and reopens the Apropos it builds, so do not run it while that is
  the copy you rely on.
- **`swift test`** runs the unit tests.

## Before you open a pull request

1. Run `swift test`. It must pass.
2. Build the app: `cd App && xcodegen generate && xcodebuild build -project Apropos.xcodeproj -scheme Apropos -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
3. Add a test with the change. Logic belongs in the `Apropos` package and is tested there against fixtures and fakes,
   never against a live app. Views stay thin.
4. Format the files you touched: `swift format -i <files>` (the repository's `.swift-format` sets 120 columns and 4
   spaces). The CI format check is informational for now because older files predate it, so please do not mix a mass
   reformat into a feature change.
5. If you changed what people see or can do, add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md). A test
   reads that file, so keep its format.
6. Keep pull requests small and about one thing.

## Rules for changes that read, record or run

- Local-first: nothing about the user's screen, selection, typing or documents leaves the Mac. Do not add network code
  without an issue that says why.
- Values from outside (a selection, a page title, a link parameter, a file name) are data. Pass them as separate
  arguments, standard input, environment or AppleScript `argv`, never join them into program text.
- The recorder records intent, not input. It reads key codes and modifiers, never characters, and a test enforces it.
  Anything that would widen what is read needs a test that fails first, and an update to [SECURITY.md](SECURITY.md).
- Never touch password fields, secure input, the Apple menu, recent items, or apps on the privacy list.
- A new permission, or a new use of one, needs an issue first.

## Style

- Swift 6, SwiftUI with Observation, macOS 14 as the floor. Keep views small and put logic in models that are tested.
- No force casts and no force unwraps in production code. No emoji anywhere.
- The panel must open instantly and animate smoothly. A change that adds jank is a bug.
- User-facing text is plain and specific. No marketing words.
- Commit messages: `type: lowercase subject`, with `feat`, `fix`, `docs`, `chore`, `test` or `refactor` (for example
  `fix: keep the selection when the menu refreshes`).

## Reporting bugs

Use the bug template. Say which macOS version and which app was in front, and what you expected. Settings, About, Copy
support info gives a report you can paste. Read it before you post it. If a step pressed the wrong
control, say so at the top.
