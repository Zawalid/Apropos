# Cue

Native macOS command center (Raycast-like) whose palette adapts to the frontmost app and its context.
Read [docs/design.md](docs/design.md) before making product decisions, and [docs/roadmap.md](docs/roadmap.md)
for what to build next.

## Stack
- Swift 6, SwiftUI plus AppKit, macOS 14+
- Core logic lives in a Swift package (`Sources/Cue`), the app target is generated with XcodeGen (`App/project.yml`)
- Accessibility API for menu and UI reading, App Intents and AppleScript as action backends
- Distributed directly (not the Mac App Store, accessibility is incompatible with the sandbox), updates via Sparkle

## Rules
- Mirror the layout and tooling of the Lopper project (`/Users/walid/Personal/Projects/Lopper`): `scripts/dev.sh`,
  `docs/`, `CHANGELOG.md`, GitHub Actions CI, swift-format with the committed config
- No emojis in code. No `as any` style escapes: no force casts or force unwraps in production code
- Keep core logic in the package and unit-tested; keep views thin
- Local-first and private: nothing about the user's screen or selection leaves the Mac unless they opt in
- The panel must open instantly and animate smoothly. Treat jank as a bug
- Commit subjects are lowercase `feat:` / `fix:` / `chore:` lines, no AI attribution lines
