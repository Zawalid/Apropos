# Onboarding stage: make the right side real

For the session that redesigns the right-hand stage of the Apropos onboarding. Read this whole file, then
`docs/identity/native-design-brief.md` (process and constraints still apply) and `docs/identity/brand.md`.

## What exists and works (do not redo)
`App/AproposApp/Onboarding/OnboardingView.swift`. The left column (title, lead, status, step dots, buttons) is approved.
The right side is a glass `Stage` holding a big ring that is drawn as the person sets up: welcome 0.22, permission
0.36 (0.50 once granted), try it 0.62 (0.74 once the panel opened), done 304/360, which is exactly the app icon's
ring. The orange pearl rides the arc's tip and settles into the gap on the last step. The stage tilts toward the pointer
(`rotation3DEffect`) and the arc has a glow and a sheen. The model is `OnboardingModel.swift` (steps, `permission`,
`panelOpened`, `hotKey`); keep its API or extend it.

## Walid's verdict
The left side is good. The right side is not real and not creative enough:
1. The pearl sitting on the arc's tip at the welcome step looks out of place (it reads as a stray dot).
2. The Try it step is not real. The keys that "press themselves" and the app icon do not feel like the product, and the
   step does not handle the case where no other app is open (the stage says "Switch to any app" with an empty icon).
3. Overall the stage needs far more creativity and realism. Surprise him. He wants it to feel like an object from a
   very good Mac app, not a diagram.

## What to build
Treat the stage as the place where the person SEES Apropos working before they use it. Ideas to push, pick what is
best, invent better:
- Welcome: a real-looking miniature of the palette (reuse the real palette views with fixture data, `Preview/Fixtures.swift`)
  floating inside the ring, switching context between real app icons (Finder, Safari, Xcode, Notes) with the rows
  morphing as it does. The ring and pearl should relate to it, not decorate it. Rework the pearl so it belongs (for
  example it waits in the logo's gap position from the start and only travels when a step completes).
- Permission: a faithful System Settings Privacy and Security Accessibility list, live: the Apropos row flips to
  allowed the moment access is granted, with a satisfying ring-closing moment.
- Try it: make it real. Show the person's actual frontmost app (icon, name, one or two of its real menu items read via
  Accessibility when trusted) and the real shortcut as keys that light when the person ACTUALLY presses them (listen for
  the global hotkey through `.aproposPanelOpened`; modifier state can be read with a local `NSEvent` monitor while the
  window is key). If no other app is open or only Apropos and Finder are, give a clear instruction and a one-click
  helper such as "Open Notes" or "Open TextEdit" so the step can always be completed. When the panel opens, celebrate it.
- Done: the ring completes to the logo; the shortcut is shown; a hint where the menu bar icon is.
- Sound is allowed at the Accessibility moment only (already there). No other audio.
- Motion: spring physics, nothing looping on a timer that distracts, Reduce Motion honored (`aproposReduceMotion`).
- 3D: you may render new assets from `docs/identity/app-icon/index.html` (Three.js) if a real 3D object helps.

## Process and limits
- Render with `scripts/render-previews.sh` (PNGs in `build/previews/onboarding-*.png`) and READ every image. At least
  three passes, saved to `build/design-passes/onboarding-stage-<n>.png` with a short critique of each.
- Real glass, the tilt and live Accessibility cannot be judged in the renderer; say what you could not verify.
- Do not touch the palette, Settings or anything outside `Onboarding/`, `DesignSystem/` and `Preview/`. Explicit
  `git add` paths, lowercase conventional commits, no attribution lines, no emojis, no force unwraps in production code.
- Never launch, kill or relaunch the person's app and never run `scripts/dev.sh` (see CLAUDE.md).
- Done means: previews for every step and state in dark and light (including "no other app open"), notes of what you
  tried, `swift test` green, the app target building, and an honest list of what is unverified.
