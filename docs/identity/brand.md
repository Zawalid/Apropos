# Apropos brand system (draft 1)

Written 2026-10-18. This is the spec the native build follows for every surface except the command palette, which Walid
approved as it is. It derives from the app icon ([app-icon](app-icon/)): a mint ceramic ring with a tangerine pearl set in
its gap, on a deep teal glass plate. Nothing here is decoration. Every rule exists so a screen made by anyone, human or
agent, comes out recognisably Apropos instead of generic.

## Idea in one line
The ring is the place, the pearl is the moment. Apropos shows what fits the moment, so the pearl is the one thing that
moves and glows, and only when something is happening now.

## Colour

Surfaces are deep teal-black in dark, cool paper in light. Never pure black or white.

| Token | Dark | Light | Use |
|---|---|---|---|
| ink-950 | `#060B0E` | | window floor, behind glass |
| ink-900 | `#0B1418` | `#F2F5F4` | window background |
| ink-800 | `#111D22` | `#E8EEEC` | sidebar, raised sections |
| ink-700 | `#182A31` | `#DDE6E3` | hover, selected row |
| line | `rgba(255,255,255,.08)` | `rgba(10,24,28,.10)` | hairlines, 1 px |
| text | `#EAF3F1` | `#0E1A1D` | primary |
| text-2 | `rgba(234,243,241,.64)` | `rgba(14,26,29,.66)` | secondary |
| text-3 | `rgba(234,243,241,.44)` | `rgba(14,26,29,.50)` | hints, captions (4.5:1 on ink-900 for text-3 only at 13 px and above) |
| mint-300 | `#8CF2CC` | | accent text and fills in dark |
| mint-600 | `#0A8F70` | `#0A8F70` | accent in light, focus rings |
| pearl | `#FF8A4C` | `#E56F2E` | the moment (see below) |
| danger | `#FF6B6B` | `#C73A3A` | errors only |

Rules:
1. **Mint is for what you can act on**: selection, primary button, links, toggles on, focus.
2. **Pearl (tangerine) means "now"**. It appears only for: the current selection marker in navigation, a recording in
   progress, the Usually next marker, the current step in a flow. Never on buttons, never as decoration. If pearl is on
   a screen, something there is live or current.
3. No third hue. No gradients on controls or tiles. A gradient is allowed only inside the 3D renders.

## Type

System font (SF Pro). Sentence case everywhere. No all caps except 10 px mono labels.

| Role | Size / weight | Tracking |
|---|---|---|
| Window title | 22 / 600 | -0.02 em |
| Page title | 20 / 600 | -0.015 em |
| Section label | 12 / 500, text-3 | 0 |
| Row title | 13.5 / 500 | -0.005 em |
| Row detail | 12 / 400, text-2 | 0 |
| Body | 13 / 400 | 0 |
| Keycap, id | SF Mono 11 / 500 | 0.02 em |

Numerals in shortcuts and counts are tabular. Nothing under 11 px.

## Space, shape, depth
- 4 px grid. Row height 40 (44 for two lines). Window padding 24, section gap 28.
- Radii: control 8, section container 12, window 14, floating panel 22. One radius family, nothing in between.
- Hairlines (1 px `line`) separate rows. Sections are flat containers on ink-800 with no shadow and no border. Cards
  inside cards are banned.
- Only floating things (the palette, popovers) use glass and a shadow. Windows are solid.

## Motion
- Ease-out `cubic-bezier(.23,1,.32,1)`, 120 to 200 ms, for state changes. Nothing the person does by keyboard is animated.
- The **pearl** is the one spring: it glides between positions in about 420 ms with a small overshoot.
- The panel itself never animates open or close.
- Reduce Motion: pearl and everything else cross-fade in 100 ms.

## The pearl (signature)
A 6 px tangerine bead with a soft halo (blur 6 px, 40 percent). Four jobs, no others:
1. **Navigation**: marks the current page in a sidebar or list and glides to the next one.
2. **Flow**: in onboarding it sits on the current step of a thin ring segment line and moves to the next.
3. **Recording**: pulses (1.2 s) while a recording is live.
4. **Usually next**: marks the predicted row.

## Icons and images
- SF Symbols only, regular weight, monochrome (text-2, mint when active). No coloured or gradient tiles, no emoji.
- 3D renders (the icon scene, `docs/identity/app-icon/index.html`) are for hero and empty-state art only, rendered with
  the same lights, in dark and light, transparent. They never appear in controls or rows.

## Voice
Plain verbs. "Allow Accessibility", "Save command". No exclamation marks, no "powerful", "seamless", "supercharge".
Say what happens and what it needs. Errors name what failed and what to do, never the content involved.

## Ban list (any of these in a design is a bug)
- A centered stack of icon, heading, paragraph and a pill button as a whole screen
- Row or sidebar icons in coloured or gradient rounded tiles
- Dots as step indicators (use the ring line with the pearl)
- Glow or blur behind ordinary content
- Cards in cards, shadows on in-window sections, mixed corner radii
- More than one filled button per view
- Pearl used for decoration, or any second accent
- Placeholder art, lorem ipsum, fake perfect numbers
- Settings rows that explain what the setting means in a paragraph instead of one line
