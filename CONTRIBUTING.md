# Contributing to Cue

## Set up

```bash
brew install xcodegen
cd App && xcodegen generate && open Cue.xcodeproj
```

`App/Cue.xcodeproj` is generated from `App/project.yml` and is not committed. Run `xcodegen generate` again after
adding or removing files. See [docs/development.md](docs/development.md) for the fast dev loop.

## Before you open a pull request

1. Run the core tests: `swift test`.
2. Check formatting: `swift format lint --strict --recursive Sources Tests App/CueApp Package.swift`.
3. Add a test with the change. Logic belongs in the `Cue` package and is tested there against fixtures, never against
   a live app. Views stay thin.

## Style

- Swift 6, SwiftUI with Observation. No force casts, no force unwraps in production code, no emoji.
- Local-first: nothing about the user's screen, selection or documents leaves the Mac.
- Commit messages: `type: lowercase subject` (for example `fix: keep the selection when the menu refreshes`).
