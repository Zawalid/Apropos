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
- A menu-bar app with a global shortcut (Option-Space by default, changeable in Settings) that opens a floating
  palette on the screen you are using. Escape or clicking away closes it.
- The palette lists the frontmost app's menu bar commands with their shortcuts, enabled and checked state, searches
  them with fuzzy matching, and runs the selected one with Return.
- Accessibility onboarding that explains why access is needed, opens System Settings, and picks the change up
  without a restart.
