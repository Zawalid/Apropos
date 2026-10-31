# Inspiration (website v3)

Written 2026-10-20. Eight sites were scrolled from the top to the footer with Playwright (headless system Chrome, 1440 x 900,
300 px wheel steps with a pause after each, one frame per step, so pinned and scroll-linked sections were caught mid
animation). Every frame was read on 4 x 4 contact sheets. The sheets and a small tech probe per site (sticky elements,
scroll timelines, video, canvas) are kept in the session notes folder, `side-session-notes/local_1b7b3923-.../ref-sheets/`.

| Site | Frames | What it is built with (probe) |
|---|---|---|
| getdroppy.app | 86 | 63 videos, 4 sticky scenes, CSS scroll timelines, system font |
| raycast.com | 53 | one WebGL canvas (hero light), CSS scroll timelines, Inter and Geist Mono |
| linear.app | 33 | no video, no sticky, product drawn in HTML, Inter and Berkeley Mono |
| arc.net | 20 | 4 videos, a scroll timeline, a serif display face |
| family.co | 37 | Lottie, 2 sticky columns, 9 videos |
| apple.com/macos | 33 | 2 sticky bars, carousels, SF Pro |
| cleanshot.com | 38 | 9 videos, one sticky element |
| screen.studio | 56 | product videos in tabbed players |

The rule for all of it: **technique only**. No colour, typeface, layout, illustration style or section order is taken from
any of them. Apropos keeps its own paper, ink, mint, pearl and SF Pro.

## getdroppy.app (the owner's named reference)

What makes it a story is that no two sections enter the same way, and the colour of the whole page changes between scenes.

- **A punchline typed inside a growing card.** Right under the hero a white card rises and grows while pinned, a line types
  itself inside it ("Your Mac is sooooo"), then the card holds one word on its own. The first scroll is a joke told in time,
  not a feature list. Primitive: a pinned frame that grows while text types inside it, ending on one word.
- **Weather as the transition.** Scenes do not meet at a hard edge: clouds rise from below and the blue scene turns into a
  white one; later a full navy night scene arrives, then it is day again. Primitive: the page's atmosphere changes between
  scenes (day, night, back to day) and the change itself is a moment.
- **The tiny thing becomes the big thing.** In the night scene a small pill sits alone under the headline; on scroll it
  expands into the full player and keeps growing past the edge into the next section. Primitive: one product object that
  changes scale across a section boundary.
- **A hand puts the product in place.** An engraved hand sets cubes into an orbit, then a toggle switches on and a grid of 42
  extensions fills in. Primitive: a switch that turns the next section on.
- **One phone splits into three.** A single device fans out into three on scroll. Primitive: one object becoming several to
  show breadth.
- **Words light as you read.** A grey paragraph turns to ink word by word, tied to scroll.
- **Explosion into a grid.** One tile scatters into nine.
- **FAQ as alternating bubbles**, left and right like a conversation, and a giant wordmark under clouds as the floor.

## raycast.com

- **The product rises out of the hero and is used in place.** The window comes up from below inside a desktop frame (menu
  bar and all), then scales to fill the width as you scroll. Primitive: the product is first seen small and far, then the
  camera moves in.
- **A statement over a dim object.** "It's not about saving time" sits over a keyboard grid that fades in behind it.
- **Blueprint scene.** The developer section changes medium completely: isometric line drawings on a dotted grid, text
  zig-zagging left and right down the page with figure labels. Primitive: one section drawn in a different medium (drawing
  instead of product), on a grid.
- **The keyboard as the ending.** A giant keyboard rises at the bottom of the page with the shortcut keys lit and a long
  bar glowing; the download sits under it. Primitive: the page ends where the product starts, on the keys.
- **Brand-coloured cards in a carousel** for extensions, each with one live interaction (a checklist ticking, a player).

## linear.app

- **The product tilts in.** The app screenshot enters at an angle in perspective and flattens as you scroll.
- **Figures, not pictures.** Small wireframe objects with figure numbers ("FIG 0.2") give a technical, documented tone.
- **Product fragments bleed off the bottom edge** of each section instead of being framed whole.
- **Data as texture.** A scatter of dots (cycle time) moves as a living chart.
- **The close is centred and short**: one line, two buttons.
- Counter-example: almost every section is the same two-column template (label left, text right, picture under). Exactly
  what the owner rejected here, so only the tilt, the figures and the living data are taken.

## arc.net

- **One window, many skins.** The same browser window stays on screen while its theme colour and content change per
  section (blue, pink, green, yellow). Primitive: a persistent product object that is re-dressed by each scene.
- **A collage collapses into the window.** Photos scattered at full width are pulled into the window frame on scroll.
- **Hand-drawn wavy dividers** and a marquee of press quotes between scenes.

## family.co

- **Micro state changes as the proof.** "Details that matter" keeps its title pinned on the left while small cards pass on
  the right, each acting out one state change (Analyzing transaction, then Transaction safe; a list reordering).
  Primitive: one small, exact state change per beat, with a spring.
- Characters and colour carry the warmth; not taken.

## apple.com/macos

- **The device collage opens.** Devices start overlapped and spread apart as you scroll.
- **Light switch between chapters.** A dark chapter (intelligence) ends and the page turns white for the next one, with the
  headline fading from grey to ink as it arrives.
- **Carousels with a play and pause control** and pagination for long sets; "And so much more" as a dense grid at the end;
  footnotes for every measured claim.

## cleanshot.com

- **The product in the middle of real work.** The capture overlay sits on a busy desktop next to a chart and a cat photo.
- **A cursor that acts inside each tile**: it clicks a toggle, presses a key cap, strikes out a word and writes the new one.
  Primitive: edits made on top of text (strike and replace) to show a transformation.
- **Redaction as pixelation** right over the content.

## screen.studio

- **The camera follows the action.** The hero recording zooms into the cell the cursor is clicking and pulls back out.
  Primitive: zoom into the exact row being acted on, then pull back.
- Tabbed video players per feature: functional, but a template; not taken.

## What Apropos takes (summary)

| Primitive | From | Where it lands |
|---|---|---|
| Pinned frame that grows while text types inside, ending on one word | Droppy | Hero: the keys press, the panel grows out of the space bar and types |
| Atmosphere changes between scenes (day, night, day) | Droppy, Apple | Paper scenes and night-desktop scenes alternate; the change is a moment |
| Tiny object becomes the big object across a boundary | Droppy, Raycast | The panel leaves the space key; the ring becomes the zero in Privacy |
| Product seen far, then the camera moves in | Raycast, Screen Studio | Deep menus: the camera dives down a menu path, then pulls back to one row |
| A section in a different medium | Raycast blueprint | Deep menus drawn as a staircase of type; Learns as a tally |
| One persistent object re-dressed per scene | Arc | Apps: one panel, re-dressed by 14 apps while a switcher moves |
| Collage collapses into the frame | Arc | The menu staircase folds into one row of the panel |
| One exact state change per beat | Family | Send and sequences: the chip changes case on its way to Notes |
| Strike and replace on top of text | CleanShot | Selection: the page's own words change when you pick an action |
| Words light as you read | Droppy | Used once, for the privacy promise |
| The page ends on the keys | Raycast | Install: the Option and Space keys come back, the download sits on them |
| Figures and footnotes for measured claims | Linear, Apple | Every number on the page has its source in the README |
| FAQ as a conversation | Droppy | FAQ questions as typed queries with answers as results |
