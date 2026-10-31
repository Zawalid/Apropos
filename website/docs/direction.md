# Direction (website v3): "One key, slowed down"

Written 2026-10-20 after [inspiration.md](inspiration.md). v2 was rejected because every section was the same template: a big
left headline, a grey paragraph, then a card or a floating window. v3 throws that layout away. Only the data, the pictures
and the tooling are kept.

## The idea

The page is one press of Option-Space, slowed down, then followed through a working day. You press the keys in the first
second. Everything after is what happens because you did: the panel leaves the key, dives into the menus of the app in front,
forgives your typing, follows you from app to app, acts on the words you selected (on this very page), passes them to other
apps, learns what you do next, takes your own commands, and never leaves your Mac. The page ends where it began, on the keys,
this time with the download on them.

Two atmospheres take turns, and the turn itself is a moment (Droppy's weather, Apple's light switch):
- **Day**: the paper page (`--paper`, or the teal-black page in dark mode). The reader's side: words, numbers, choices.
- **Night**: the real desktop the captures were taken on (`wallpaper-night.webp`, the very wallpaper behind the glass in
  every capture). The product's side: where the panel lives and acts. Captures only ever appear on it or on the plain page,
  never inside a drawn frame.

In dark mode day becomes the brand teal-black and night stays the wallpaper, so the change still reads as a change of light.

## The story arc, scene by scene

Each scene has one verb, its own layout, its own direction of motion, and one moment meant to surprise. No two share a layout.

| # | Scene | Light | Verb and direction | Layout | The surprise | Hands over by |
|---|---|---|---|---|---|---|
| 0 | **Press** (hero) | day | press, then Z toward you | centred, monumental: two physical key caps fill the width, the headline sits on them | the keys go down as you start scrolling (or when you press Option-Space for real); a circle of night opens out of the space bar and the real panel rises through it and types n, f | the circle has become the whole screen: we are on the desktop |
| 1 | **Deep** | night | dive down and right, then fold up and left | a staircase of type: Debug, View Debugging, Rendering, Color Hits Green and Misses Red, each level lower, further right and bigger | the whole staircase folds into one row of the real Xcode panel, path and shortcut included | the panel slides away left, paper rises from below like a sheet |
| 2 | **Slip** | day | swap, an arc | four giant letters across the full width | s h w o: the w and o jump over each other and the word becomes show, then the real results for shwo appear under it | the letters drop out, the track starts moving |
| 3 | **Apps** | day | sideways | a horizontal film strip, the first sideways motion of the page; giant app names travel at a different speed behind | the same panel, re-dressed by 14 apps in a row, while an app switcher under it moves its pearl from icon to icon | the last app is Safari with a page open, which is where scene 4 starts |
| 4 | **Holding** | day | inline, at the reader's own selection | editorial: one big paragraph, nothing else | you select words in the paragraph and a small action list opens at your selection; choose UPPERCASE and the page's own words change (strike and replace). Same functions as the app | the changed words become a chip that leaves the paragraph |
| 5 | **Send** | night | travel along an S-curve, left to right to left | a route across the full width with three stations | the chip rides the route, turns to capitals at UPPERCASE, lands in Notes; at Mail it stops and waits for a second Return | the route ends in a dot, the pearl |
| 6 | **Next** | day | count up | a giant tally: "9 of 12", twelve marks | twelve marks arrive one by one, nine fill; the pearl drops onto the Usually next row in the real panel with its reason | the pearl goes up to the nav, the page darkens to ink |
| 7 | **Yours** | ink | outward from the centre | radial: a command file in the middle, four ways to run it at the four sides | each way lights the lines of the file it comes from, then acts itself out (alias typed, keys pressed, link copied, Shortcuts action) | the file closes |
| 8 | **Compare** | day | a scan from top to bottom | a lineup: five tools as columns, rows as a spec sheet | a scan line passes and leaves the marks behind it; the column under the pointer lights | the scan reaches the bottom and the page goes dark |
| 9 | **Private** | night | inward, sealing | full bleed: the ring render is the zero of "0 network connections" | the ring settles into the sentence as its zero; what is read flows in, what is kept is listed as the real file names, and the promise lights word by word | the light comes back up |
| 10 | **Install** | day | back to the start | the keys again, smaller, the download on the space bar; three steps on a line with the pearl on the current one; the FAQ as typed questions with answers as results | the page ends on the keys you pressed at the top | footer: the ring |

## Layout language

- No section template. A scene's type size, anchor and alignment come from its verb: monumental centred (Press), diagonal
  staircase (Deep), full-width letters (Slip), horizontal strip (Apps), long-form paragraph (Holding), route (Send), numerals
  (Next), radial (Yours), table (Compare), full-bleed sentence (Private), keys and a line (Install).
- Full bleed where the product is: the night desktop always runs edge to edge. Day scenes break the column grid on purpose
  (letters wider than the page, numerals bleeding off the left, a capture bleeding off the right).
- Real windows only: the cutouts in `src/assets/windows`, at real proportions, with the page's own shadow. Nothing drawn to
  look like the app. Things drawn by the page (keys, route, tally, switcher) look like the page, not like the app.
- Type: SF Pro only, 600 and 700, sentence case. Display sizes from 64 px to 22 vw. Body 17 to 22 px. One weight change per
  scene at most.
- Colour: paper and ink, mint only for matched letters and links, the pearl only for "now" (current app, current step,
  the predicted row, the current section in the nav).

## Motion grammar

- Each scene owns one verb (press, dive, swap, slide, select, travel, count, radiate, scan, seal, return). It is never
  reused by another scene.
- Pinned scenes are scrubbed by scroll: the scene is taller than the screen, its stage is sticky, and the scroll position
  inside it becomes a progress value `--p` from 0 to 1 that CSS turns into transforms. Small things (a key press, a mark,
  a row) are one-shot with the brand ease-out `cubic-bezier(.23,1,.32,1)` in 160 to 240 ms. The pearl is the only spring.
- Only `transform`, `opacity` and `clip-path` are animated.
- The reader can always act: the keys press for real, the switcher takes clicks and arrow keys, the paragraph takes any
  selection, the file's ways take hover and focus. Scroll is the narrator, not the only control.
- Reduced motion: nothing is pinned or scrubbed, each scene is laid out in its finished state, and every control still works.
- Phones: the same scenes, shorter. The strip is a native swipe row, the staircase stacks, the route runs down instead of
  across. Nothing scrolls sideways at 375 px.

## Prototype first

Built first and shown before the rest: **Press**, **Deep** and **Apps**: three different directions (toward you, diagonal,
sideways) and three different surprises, enough to judge the whole grammar.
