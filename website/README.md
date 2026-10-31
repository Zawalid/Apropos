# Apropos website

The marketing site for Apropos, version 3 ("One key, slowed down"). Astro, static output, deployed on Cloudflare with
Wrangler. Only the tooling is shared with the Lopper site (Astro, wrangler, the check scripts). The direction and why it
looks the way it does: [docs/inspiration.md](docs/inspiration.md) (eight reference sites scrolled end to end with
Playwright, the primitives taken from each) and [docs/direction.md](docs/direction.md) (the story arc, layout language and
motion grammar).

```bash
cd website
npm install
npm run dev          # http://localhost:4321
npm run build        # static site in dist/
npm run preview -- --port 4321
```

With the preview running in another terminal:

```bash
npm run check:seo    # titles, descriptions, canonicals, share image, JSON-LD, sitemap, robots, dashes, emoji, 375px overflow
npm run check:ui     # Option-Space, the scenes' states, app switcher, selection actions, tally, command ways, install, nav, FAQ, copy; with and without motion
npm run check:a11y   # axe on every page, light and dark, 1440 and 375, with and without motion
npm run shots        # one screenshot per viewport down every section of every page, light and dark, into .shots/
npm run og           # redraws public/og.png from scripts/og.html
npm run ring         # re-renders the hero ring and pearl from the app icon's 3D scene
npm run harvest      # measures real apps with apropos-probe into src/data/apps.json (needs Accessibility, see below)
```

All browser scripts use Playwright (`playwright-core`) with the system Chrome. There is no TypeScript compiler in this folder;
Astro strips types at build, so `npm run build` is the gate.

## Art direction

- **The page is paper lying on the night desktop the app was captured on.** The desk (`wallpaper-night.webp`, the wallpaper
  behind the glass in every capture) is fixed behind the whole page. Day scenes are sheets of paper with rounded ends;
  night scenes are the desk showing between them. In dark mode the paper is the brand teal-black, so day and night still
  differ. The header capsules take the light of whatever scene is under them.
- Paper `#F3F5F4` and ink `#0E1A1D`, teal-black `#0B1418` in dark. SF Pro only, 600 and 700, sentence case. Mint only for
  matched letters and links. The pearl only for "now": the section you are reading in the nav, the current app in the
  switcher, the Usually next row, the install step you are reading.
- **Keys look like real keys** (`src/components/Key.astro`): a skirt you see below the top face, a lit, slightly dished top
  set into it, Mac legends (the option sign top right, "option" bottom left), a shadow on the desk, and the pair tilted a
  little away like keys on a desk. Pressing moves only the top face. The same keycap, in one element, is `.kbd` for keys
  inside text. White keys on paper, space grey keys in dark and on the desk.
- No section template. Each scene has one verb, its own layout and its own direction of motion (table in
  docs/direction.md). Scenes that tell a moment are pinned: the scene is taller than the screen, its stage sticks, and
  `src/scripts/scenes.ts` turns the scroll inside it into a progress value that each scene turns into transforms. Only
  `transform`, `opacity` and `clip-path` move. With reduced motion nothing is pinned and every scene is laid out in its
  finished state; every control still works.

### Pictures on phones

A whole window at phone width has text of about 6 px. `Window.astro` takes a `phone` crop (left, top, width, height as
fractions of the picture): on screens up to 600 px only that part is shown, scaled to the frame, and the image sizes ask
for the larger file. Panels show the search field and the left of their rows (`panelCrop` in `src/data/windows.ts`, row
titles at about 14 px); others are chosen per window so the edge falls between words (Learns shows only the row titles
of Usually next; the Mail draft shows its confirmation row). The Privacy and data page is too dense to crop and is left
out on phones; the lists beside it say the same in large type.

## What is on each page

### Home `/`

| # | Scene (`src/components/scenes/`) | Light | What happens | Pictures |
|---|---|---|---|---|
| 0 | Press (`#top`) | day to night | Two real looking keys under the headline. Scrolling presses them (so does a click, or Option-Space on your keyboard, which plays the moment), a circle of night opens out of the space bar and the real panel rises through it, then types n and f: New Folder first | `hero-open`, `hero-n`, `hero-nf` |
| 1 | Deep (`#deep`) | night | Xcode's menu bar, then Debug, View Debugging, Rendering, Color Hits Green and Misses Red open as a staircase of type down and right while the camera follows; then the staircase folds into its row in the real panel after typing clean | `deep-xcode` |
| 2 | Slip (`#slip`) | day | s h w o across the whole width; the w and o jump over each other, the word becomes show in mint, the real results for shwo rise | `slip` |
| 3 | Apps (`#apps`) | day | The first sideways scene: the real panel over 14 apps passes as a strip, the app names slide behind at another speed, an app switcher moves the pearl; click an icon or use the arrow keys | `app-*` |
| 4 | Holding (`#holding`) | day | One big paragraph. Select any words and the action bar docked under it (never over it) takes them; pick one and the page's own words change in place, the old ones struck and lifted away (the app's functions, `src/scripts/textTools.ts`). A phrase is marked for you until you select. Then files, page and folder or repository beside the real panel holding a page and a selection | `holding` |
| 5 | Send (`#send`) | night | A dotted route crosses the desk; a chip with a Safari selection rides it, turns to capitals through the UPPERCASE gate (which steps aside while the chip passes), and waits at the Mail draft for a second Return. Each station shows its real window | `send-list`, `sequence`, `confirm` |
| 6 | Next (`#next`) | day | A tally: twelve marks arrive, nine fill, the numeral counts to 9, and the pearl drops onto the Usually next row of the real panel, whose reason says the same | `usually-next` |
| 7 | Yours (`#yours`) | night | Radial: the command file in the middle, the four ways to run it at its corners, flying out from it; each in turn lights the lines it comes from and acts itself out. Then recording and keys for menu items, both Early | `recording-review`, `alias-popover` |
| 8 | Compare (`#compare`) | day | The sourced table, revealed once by a mint scan line when it comes into view; marks pop as the line passes; the column under the pointer lights. Each cell is two columns (mark centred on the first line, words aligned). Under 1280 px, where columns would fall under 170 px, it becomes one tool at a time beside Apropos; under 480 px the two cards stack | none |
| 9 | Private (`#private`) | night | The app icon's ring arrives large and settles into "Apropos makes 0 network connections" as its zero; the promise lights word by word. Then what is read, kept (real file names) and never kept, and the permissions, beside the real Privacy and data page scrolling in its window | `privacy-page` |
| 10 | Install (`#install`) | day | The keys come back; the space bar is the download. Three steps on one line, the pearl on the step you are reading. Then the questions, searchable | none |

Footer: on the desk, the ring and the links.

### Other pages

- `/compare/`: what each tool is best at, then the full table. `/compare/raycast/`, `/compare/spotlight/`, `/compare/alfred/`:
  how they differ, how to use both (keys, quicklinks, workflows), and a two column table.
- `/apps/`: every measured app with its counts and biggest menus, and a search over every measured command
  (`/apps/commands.json`, fetched only when the search is used). Without `apps.json` it shows the app icons only, is left out of
  the sitemap, and the footer hides its link.
- `/404/`.

## Pictures

Source: `/Users/walid/Pictures/Apropos Captures/2026-10-20/` (real glass, a Debug build in stage mode, captured at 2x). The
data inside the windows is sample data, except the menu commands, which are the real menu bars of the apps on the Mac that
took them.

`node scripts/import-windows.mjs <folder>` writes `src/assets/windows/<id>-dark.webp` (and `-light.webp` where a clean
light window exists; only the Privacy page has one). The typed list is `src/data/windows.ts`; `Window.astro` draws one.
- The capture run's own cutouts (`*-dark-cutout.png`) are used as they are.
- The website slot frames (`demo-open`, `demo-n`, `demo-nf`, `xcode`, `safari`) have no cutout: the script cuts the panel
  out at (560, 320, 1440 x 960) with a rounded mask (radius 58, inset 3). That place was found by matching the empty
  search header of the Finder cutout against the frame.
- Windows are dark in both themes. A dark glass panel on the paper page reads like the real thing and keeps one look.

**Left out, and why** (every file was opened and judged by eye)
- Every light scene and light cutout of the full run except the tall Settings pages: a football video on the real desktop
  shows through the glass (one light cutout even shows a different typed query). The dark ones are clean.
- `settings/commands-detail-*` (video beside the sheet), `settings/shortcuts-items-dark-*` (video blurred through the
  glass), `settings/integrations-dark-*` (the real Dock shows at the bottom), `onboarding/welcome-*` (a ghost of its own
  Continue button in the glass), `apps/list-safari-dark` (video; the website slot's Safari is used instead).
- Not needed for the story (not wrong): error, loading and permission states of the panel, interface sizes and icon
  styles, symbol picker states, the recording bar states, the other Settings pages and tiles, other onboarding steps.

Other real pictures: the ring and pearl (rendered from the icon scene), app icons (macOS's own icons for installed apps,
read with `NSWorkspace`), the share image.

## Measured app data

`npm run harvest` runs `apropos-probe <bundle id>` for 31 installed apps (it only reads the menu bar, it presses nothing) and
writes `src/data/apps.json` with the date, the Mac and macOS version, counts per app (total, with and without a shortcut, per
menu) and command titles. Titles under menus that can hold your own content (History, Bookmarks, Open Recent, the Window list,
mailboxes, Share, Services and similar) are counted but never written. Review the file before committing it.

It needs a terminal that has Accessibility. The agent shell that built this site does not, so **apps.json does not exist yet**
and `/apps/` shows icons only. The v3 home page shows no measured numbers at all; once the file exists, the counts belong
in `/apps/` (and could become a scene of their own, for example a count under the Deep staircase). `node scripts/harvest-apps.mjs --launch` also opens missing apps hidden (`open -gj`) and quits only those it opened.

## Where each claim comes from

Checked against `CHANGELOG.md`, `git log main` and the docs on 2026-10-20:
- Panel, menus, shortcuts, slips and abbreviations: CHANGELOG, `docs/ranking.md` (one swap of neighbouring letters, accents
  ignored, remembered abbreviations).
- Context actions and their safety: `builtin.json` (35 actions, counted at build), `docs/context-actions.md` (secure fields,
  password managers, a selection never becomes code).
- Send to: `docs/destinations.md` (eight built in places, shown only when installed, second Return for anything with a trace,
  Mail draft never sends, ids only remembered).
- Sequences: CHANGELOG and `docs/sequences.md` (each step reads the result of the one before; uppercase then Notes sends the capitals).
- Usually next: `docs/prediction.md` and the CHANGELOG example reason ("After Run Tests you chose Commit 9 of 12 times").
- Your commands, links and Shortcuts: `docs/user-commands.md`, `docs/integrations.md` (links and the Run Apropos Command
  action run only commands you allow; first run asks once).
- Privacy: the app's Privacy and data page (no network connections; the update check is off by default, see
  `SettingsRegistry.swift`), `docs/recorder.md` and CHANGELOG (Input Monitoring only for recording, typed text never recorded).
- Early, and tagged so on the page: recording, aliases and shortcuts for menu items, sequence step icons. Shortcut tips are
  not mentioned. Not claimed: anything in `docs/roadmap.md`, `docs/backlog.md` or `docs/recorder-plan.md`.

### Competitor facts (checked 2026-10-20)

Each table cell links its source. Notes with every fact and URL: `side-session-notes/local_45dabc38-.../competitors.md`.
- Raycast: default key Option-Space (manual.raycast.com/settings); Search Menu Bar Items (manual.raycast.com/navigation);
  `getSelectedText` and `getSelectedFinderItems` (developers.raycast.com/api-reference/environment); Free, Pro $10 a month or $96 a
  year, free clipboard history kept three months (raycast.com/pricing); AI from Pro (raycast.com/core-features/ai); no account
  needed, sync and AI need one (raycast.com/faq).
- Spotlight on macOS 26: actions through App Intents, menu items of the app in front, clipboard history you turn on (Apple
  newsroom, June 2025); Command-3 narrows to actions and menu items (macmost.com); Change Case and Translate actions
  (support.apple.com, Spotlight actions guide).
- Alfred 5: default key Option-Space (alfredapp.com/help/general, seen in a search snippet, not fetched); Powerpack £34
  (alfredapp.com/powerpack/buy); Universal Actions and clipboard history in the Powerpack; menu search only through the third
  party Menu Bar Search workflow (alfred.app/workflows/benziahamed/menu-bar-search).
- Help menu: Shift-Command-? (support.apple.com/en-us/102650); menu item results point at the item (Apple guide, 10.15 page).
- Not confirmed and so not claimed: whether Raycast's menu command is free or Pro, how Spotlight treats disabled items,
  whether the Help menu search works in every app. The table says "Not announced yet" for Apropos's price.
- Worth knowing: `docs/design.md` assumed Raycast uses Command-Space. Its default is Option-Space, like Apropos and Alfred.
  The FAQ and compare pages say so and suggest moving one of them.

## Cannot be verified from here

The global hotkey on a real Mac, live Accessibility reading (the pictures use sample data in a stage build), the download itself (no release exists), and every
"Early" feature. Nothing on the page claims these were checked.

## TODO for the owner

- **Measured numbers.** Run `npm run harvest` from a terminal with Accessibility, review `src/data/apps.json`, rebuild.
- **Repository name.** `src/data/site.ts` assumes `https://github.com/Zawalid/Apropos`.
- **Release asset.** The download pill points at `.../releases/latest/download/Apropos.dmg`. It 404s until a release with an
  asset of exactly that name exists.
- **Install steps.** The page says: move it to Applications, open it, allow Accessibility, press Option-Space. Add the
  first-launch step for a build that is not notarized, if that is how it ships.
- **Domain.** `apropos.zawalid.com` is assumed in `astro.config.mjs`, `wrangler.jsonc`, `public/robots.txt`, `src/data/site.ts`
  and `scripts/check-seo.mjs`.
- **Price.** The page says nothing about price except "Not announced yet" in the comparison.
- **Contact.** GitHub issues and the author's site only. No email address.
- **Licence.** No licence claim anywhere.
- **Deploy.** `deploy-workflow.yml.example` is ready to move to `.github/workflows/website.yml` with the two Cloudflare secrets.
  Nothing has been pushed or deployed.

## Quality gates (last run 2026-10-21, after the layout audit)

- `npm run build`, `check:seo`, `check:ui` (with and without motion) and `check:a11y` (axe, light and dark, 1440 and 375,
  with and without motion) pass.
- Layout audit (`side-session-notes/.../audit/dom2.mjs`): at 1440, 1100, 768 and 375, dark and light, scrolled in 300 px
  steps, no text under 11 px, no clipped or off-screen text, no table cell under 160 px, no icon off its first text line,
  no text overlapping text, no section heading under the header after a nav jump, no sideways scroll. All zero.
- Lighthouse 13, home page: mobile 96/100/100/100 (LCP 2.8 s, the phone crops load the larger pictures), desktop
  100/100/100/100.
- Viewport screenshots top to bottom at 1440 dark and 375 light were read.
