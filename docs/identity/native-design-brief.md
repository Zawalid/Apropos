# Native design brief: onboarding, Settings, menu bar, empty states

For whoever builds the designed surfaces of Apropos natively (SwiftUI and AppKit). Read this whole file first.

## Where we are
Apropos is a native macOS command center that runs alongside Raycast: a hotkey panel that lists the frontmost app's
menu commands, plus context actions, your own commands and sequences, learned suggestions and a send-this-to layer.
Everything works; the surfaces around the panel are still plain. **The command panel (the Cmd-K palette) is approved
and out of scope. Do not change its look.** Everything else a person sees is yours: onboarding, Settings, the menu
bar menu, empty and error states, the About window, and the design tokens behind them.

Walid's verdict on earlier attempts: the web prototypes (`docs/prototype/*.html`) look boring and vibe coded, and the
first native Settings and onboarding looked like generic AI output. The bar now is that someone would pay for this app
because of how it looks and feels. Aim for the craft of Raycast preferences, Arc, CleanShot X, Things 3, Bartender,
Linear's desktop app, and Apple's own macOS 26 Settings. What they share: native controls used well, real depth and
material, restraint, excellent typography, one recognisable signature, motion that explains, and empty states with
character.

## Read before you design
1. `docs/identity/brand.md`: tokens, the pearl motif, the ban list. Follow it unless you can justify a change in writing.
2. `docs/identity/app-icon/` and its scene `index.html` (`?hero=1` renders the floating ring and pearl): the 3D
   language. `docs/prototype/assets/hero-ring.png` is a rendered hero.
3. `docs/prototype/settings3.html` and `onboarding.html`: **structure and content only** (page list, groups, steps,
   copy, states). Do not copy their look; they are web sketches.
4. `docs/identity/inspiration/`: Walid's reference screenshots of in-app onboarding and preferences from apps he
   admires. Open every image. Before designing, write ten lines in `docs/identity/design-notes.md` on what makes
   them feel crafted (materials, spacing rhythm, type, control styling, motion, empty states) and what you will take.
5. `docs/design.md`, `docs/backlog.md`, and the current code under `App/AproposApp` (DesignSystem, Settings,
   Onboarding, MenuBar, Views) and the Xcode previews under `App/AproposApp/Preview`.

## What to build

**Design system first (small, mechanical).** Refactor `DesignSystem/Theme.swift` and friends to the brand tokens
(colour, type scale, spacing, radii, materials, motion curves), keeping the palette's current look exactly. Add the
pearl as a reusable view: a bead with halo that can glide between positions with a spring (matched geometry), pulse, and
fall back to a cross-fade under Reduce Motion.

**Onboarding** (4 steps: Welcome, Allow Accessibility, Try it, Ready). Replaces the current window. A left rail with a
drawn ring-line stepper and the gliding pearl; a main area that is not a centered stack. Real 3D hero art (the ring
and pearl render) used with confidence, not as a sticker. The Accessibility step must be genuinely helpful: a faithful
mini of the System Settings list, live detection that flips to Allowed, a Not in the list help that shows the exact
app path with Copy and Show in Finder, and a note that an old Cue entry can be removed. The Try it step completes when
the hotkey actually opens the panel. Skippable, reopenable from the menu bar, and the first run never nags after.

**Settings**: sidebar layout with a bead marking the current page, grouped as General and Appearance, Commands and
Destinations, Context and Prediction and Integrations, Privacy and data and About. Each page has a one-line live
status. Search that filters settings across pages, keyboard navigation, a permission line at the bottom of the
sidebar. Use native controls (Toggle, Picker, segmented, menu) restyled with restraint, not hand-drawn imitations,
so it feels like a Mac app. Pages and rows: see `settings3.html` and `Sources/Apropos/Settings` (the registry is the
source of truth for what exists). A Commands page for your own commands and sequences (list, hotkey, trust badge,
New, Import, Reveal folder) and a Destinations page; ask before inventing settings that do not exist in the registry.

**Menu bar menu and About window**: a considered menu with the live context header and recent commands, the ring and
bead glyph, and an About window with a hero render.

**Empty and error states**: no commands yet, no results, no access, and a failed action, each with a small rendered
asset or a drawn illustration in the brand language (render new ones from the icon scene if needed), and one clear
next step.

## How to work (this is the part that was missing before)
Design happens in native renders, not in your head.
1. Build each surface in SwiftUI with Xcode previews, then render it with `scripts/render-previews.sh` (and
   `scripts/shots.sh` in agent mode) and READ the PNGs.
2. For every surface do at least three passes. After each, write a short critique against the inspiration images and the
   ban list, then fix. Save the images of each pass to `build/design-passes/<surface>-<n>.png` and mention what
   changed. Do not stop at the first version that compiles.
3. Squint test and size test: does the screen still read at a glance, is there one clear focal point, are all text
   sizes at least 11 pt, is contrast fine in light and dark.
4. Details that make it feel expensive: optical alignment, consistent 4 pt rhythm, hairlines instead of boxes,
   tabular numerals, SF Symbols with hierarchical rendering at consistent weights, window chrome that is genuinely native
   (transparent titlebar, full-size content, vibrancy in the sidebar), subtle depth, springs for the pearl only.
5. If you disagree with `brand.md` or this brief, say so in `design-notes.md` and propose the alternative with a render.

## Constraints
- The panel is untouched. Do not edit its views, metrics or motion.
- Never launch, open, kill or relaunch the running app and never run `scripts/dev.sh` (see CLAUDE.md, Running the app).
  Verify with swift test, xcodebuild into `build/agent`, the preview renderer and agent-mode screenshots.
- Other sessions may be editing `Sources/Apropos` and palette code; keep your edits to `App/AproposApp/DesignSystem`,
  `Settings`, `Onboarding`, `MenuBar`, `Preview` and new asset catalog entries. Use explicit `git add` paths, never
  stash, reset, switch branches or amend. Lowercase conventional commits, no attribution lines.
- No emojis, no force casts or unwraps in production code. Sentence case, plain words, no exclamation marks.

## Done means
Screenshots of every surface and state in dark and light that you would put on a product page, three recorded passes
for each, the notes file, `swift test` green, previews for every state, and a report that says exactly what you could
not verify (real glass over a real desktop, real Accessibility, the running app).

## Later (not now)
The panel becomes movable with snap guides and a remembered position (see `docs/backlog.md`). Leave room for a Position
setting in General.
