# Cue: design

Working name. Written 2026-10-18 from the brainstorm with Walid. Items marked (call) are the author's guesses, not
decisions made by Walid.

## Intent

A native macOS command center in the spirit of Raycast whose palette is built around what the user is doing right
now: the frontmost app, the selection, the open document or URL, and recent actions. One hotkey, a fast and fluid
panel, the right actions first.

Why it is worth paying for: menu-bar search is a solved, cheap feature (about $5) and a weekend project. The value
is in context sensing, teachable commands and maintained per-app packs. Raycast exposes the frontmost app only to
extension authors and has no app-shaped command list. Spotlight on macOS 26 has actions, but only for apps that
adopted App Intents.

## Positioning (decided 2026-10-18)

Cue runs alongside Raycast, not instead of it. Raycast stays the launcher (apps, files, clipboard, windows, snippets).
Cue is the context companion: it answers "what can I do right now, in this app, with this selection". It has its
own hotkey (default Option+Space, Raycast's is Command+Space) and never launches apps or manages the clipboard.

## Goals
- Palette that reshapes around the frontmost app and context with no setup
- Instant open, fluid animation, fully keyboard-driven, native look
- Record an action once in any app and get a reusable command
- Learn per-app which actions the user reaches for and rank accordingly
- Free core, Pro tier for sync and team packs (call)

## Non-goals (v1)
- Anything a general launcher does: app launching, file search, clipboard history, snippets, window management,
  calculator. Raycast owns those (see Positioning)
- A natural-language agent that operates the whole screen
- Mac App Store distribution, iOS companion, a pack marketplace

## Anti-goals
- A laggy or janky panel, even if every feature works
- Needing per-app configuration before it is useful
- Sending screen content, selections or document names to a server by default

## Features

### v1: core (call)
1. Native panel: SwiftUI plus AppKit, global hotkey, instant open, keyboard-first
2. App-aware home: frontmost app's menu commands, its pinned and most-used actions, then global commands
3. Context sensing: selected text, current file, URL or document title, app state where readable
4. Record-to-command: capture a sequence of accessibility-element actions, name it, bind a key, run it later
5. Learned ranking per app and context, stored locally
6. Command library: user commands, a few starter packs, Shortcuts, App Intents and AppleScript as backends
7. Permission onboarding for Accessibility (and Screen Recording only if a feature needs it)

### v2: where the money is (call)
8. Cross-app actions that take context from one app and act in another
9. Curated packs for pro tools (Xcode, Figma, Notion, Slack, Linear), maintained against app updates
10. Sync across Macs and shared team packs (Pro)

### Later
Natural-language "do it" over the screen, pack marketplace, iOS companion.

## Constraints and technical calls (call)
- Swift 6, SwiftUI plus AppKit, macOS 14+
- Core in a Swift package, app target generated with XcodeGen, same layout and tooling as Lopper
- Accessibility API for reading menus and UI trees; AXObserver for app and focus changes
- Direct distribution with notarization, Sparkle for updates, license via a merchant of record (decide later)
- Local-first storage; sync is an opt-in Pro feature
- Recorded commands target accessibility elements (role, title, hierarchy path) with fallbacks, not pixel positions

## Open questions for Walid
- Final product name and domain
- Pricing level and whether the free tier has any command limits
- Side project or full commitment (affects scope of v2)

## Left to the builder
Panel visuals within the Lopper design language, the command data model, fuzzy search and ranking algorithm,
recording format, test strategy, CI setup.
