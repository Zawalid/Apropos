# M0 goal prompt (paste after /goal)

Build milestone M0 (Foundation) of Apropos, a native macOS command center. Read CLAUDE.md, docs/design.md and
docs/roadmap.md first, then study /Users/walid/Personal/Projects/Lopper for the project layout, XcodeGen setup,
scripts/dev.sh, CI workflow and docs conventions, and mirror them.

Deliver:
1. Scaffold: Swift 6 package with a `Apropos` core library and tests, an XcodeGen app target (App/project.yml) for a
   macOS 14+ menu-bar-only app, scripts/dev.sh (build, relaunch, --watch, --logs), swift-format config use,
   GitHub Actions CI that builds and runs tests, CHANGELOG.md, CONTRIBUTING.md.
2. Global hotkey (default Option+Space, configurable) that toggles a borderless floating panel: instant open, smooth
   spring animation, Escape closes, closes when focus is lost, appears on the active screen and Space.
3. Frontmost-app tracking in the core library using NSWorkspace plus AXObserver, exposed as an observable model.
4. Accessibility menu reader: read the frontmost app's full menu bar (including submenus, keyboard shortcuts,
   enabled and checked state) into command models; refresh when the app or its menus change.
5. Palette UI: search field, fuzzy-matched ranked list with the app icon and shortcut hints, full keyboard
   navigation, Return runs the selected menu item through AXPress, correct empty and error states.
6. Permission onboarding that detects missing Accessibility access, explains why, deep-links to System Settings and
   recovers live when access is granted.
7. Unit tests for the fuzzy matcher, the menu-to-command mapping (against fixtures, not live apps) and the ranking
   stub. Keep views thin and logic in the package.

Constraints: no force casts or force unwraps in production code, no emojis, local-only, nothing leaves the Mac.
Design language should match Lopper's design system quality. Commit work in small lowercase conventional commits
with no AI attribution lines.

Done when: `scripts/dev.sh` builds and launches the app, the hotkey opens the panel in Finder, Safari and Xcode
showing that app's menu commands, selecting one runs it, `swift test` passes, CI config is present, and you have
verified this by running the app and exercising it, not only by building. Report what was verified and what was not.
