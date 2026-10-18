# Onboarding stage: notes

Written 2026-10-18 for the redesign asked for in [onboarding-stage-brief.md](onboarding-stage-brief.md). Code:
`App/AproposApp/Onboarding/OnboardingStage.swift` (the stage), `OnboardingLive.swift` (what it reads from the Mac).
Passes: `build/design-passes/onboarding-stage-1.png` to `-4.png`.

## The idea
The stage is where the person sees Apropos work before using it. One object carries all four steps: the app icon's ring,
large enough to frame the stage. The pearl waits in the logo's gap from the first step and never moves. The ring closes
around it as setup gets done (0.30, 0.40 then 0.52 once access is given, 0.62 then 0.74 once the panel opened), and on the
last step the line thickens and the pearl grows to the icon's proportions, so the drawing becomes the logo. Each time the
ring grows, the pearl pulses once and a ripple leaves it. That is the only motion that happens without the pointer. When
the window opens, the first arc draws itself in.

Inside the ring floats the thing the step is about, drawn like the real thing:
- **Welcome**: the palette miniature (its own `IconTile`, `KeyCap`, `Theme`, compact metrics and `RowRise`) over Finder,
  Safari, Notes and Mail, with their real icons and commands their menus really have, plus one context action each. A
  Dock slice below switches apps on hover or click. It moves on by itself every 3.6 s only while the pointer is off the
  stage, and not at all under Reduce Motion.
- **Permission**: a System Settings Accessibility window as a background window (grey traffic lights, the system's own
  sentence, the list with Apropos between two neutral rows, + and -). A pointer rests on the switch; with "Not in the
  list?" open it moves to +. On grant the switch springs on, the ring grows, the pearl pulses and Glass plays.
- **Try it**: the palette over the app the panel will really open over (the last app in front that is not Apropos), with
  four of its real menu commands read through Accessibility. Below, the shortcut as real keys: each modifier lights while
  it is held (local `flagsChanged` monitor, plus a global one once access is granted; only modifier state is read), and the
  caption becomes "Now press Space" when all modifiers are down. With only Finder open, the palette says so and offers
  Open TextEdit. Without access, it says the commands show once Accessibility is on. When the panel opens, the header
  reads "Opened over Safari", the keys light mint and the ring grows.
- **Done**: the finished logo holds the shortcut; a slice of the menu bar slides in at the top with Apropos's icon
  picked out and labelled, next to the real time.

## Passes
1. Ring 340, thin line, objects centred on it. The objects hid the pearl, the ring's shadow was a hard dark double, the
   ridge highlight looked like a white stripe, Safari's icon had an alias arrow (the /Applications path is a link), the
   menu bar strip had square corners against the round stage.
2. Objects dropped below the pearl, softer shadow and ridge, icons looked up by bundle id, and the finished ring takes
   the icon's proportions (line 30, pearl 84). The last step now reads as the logo. Still: in the middle steps the
   objects covered most of the ring, so its growth was hard to see, and the menu bar label was clipped.
3. Draw-in on open, lighter shadow in dark, label no longer clipped. Confirmed the middle-step problem.
4. Ring widened to 412 so every object sits inside it with the pearl clear. The arc gained on each step is now visible
   around the palette, the keys and dock stay outside it, and the last step fills the stage (line 36, pearl 100).

## Choices to look at
- The pearl in the gap is big (50, then 100). Smaller read as a stray dot; logo proportions read as the brand.
- The two other rows in the Accessibility list are blank on purpose. Naming real apps would invent a list the person
  does not have.
- The step dots on the left stay as approved, although `brand.md` bans dots as step indicators.

## Not verified (needs the real app)
- Real glass behind the stage and the palette miniature's material over a real desktop: the renderer shows them flat.
- The pointer tilt, parallax and hover-to-switch in the Dock, and the spring and ripple timing.
- Live Accessibility: reading the front app's menus, the grant flipping the switch, the Glass sound.
- Modifier keys lighting over other apps (global monitor) and the panel-opened celebration from the real hotkey.
- Open TextEdit launching and the stage following it to the front.
- Whether the first guess at the target app (the app in front when the guide opens) is right on first launch.
