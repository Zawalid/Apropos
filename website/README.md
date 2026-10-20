# Apropos website

The marketing site for Apropos, version 2 ("pearl and paper"). Astro, static output, deployed on Cloudflare with Wrangler.
Only the tooling is shared with the Lopper site (Astro, wrangler, the check scripts). Layout, type, colour, motion and copy are
Apropos's own, from `docs/identity/brand.md`.

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
npm run check:ui     # Option-Space demo, app dock and explorer keys, nav pearl, FAQ search, copy; with and without motion
npm run check:a11y   # axe on every page, light and dark, 1440 and 375 wide
npm run shots        # one screenshot per viewport down every section of every page, light and dark, into .shots/
npm run og           # redraws public/og.png from scripts/og.html
npm run ring         # re-renders the hero ring and pearl from the app icon's 3D scene
npm run harvest      # measures real apps with apropos-probe into src/data/apps.json (needs Accessibility, see below)
```

All browser scripts use Playwright (`playwright-core`) with the system Chrome. There is no TypeScript compiler in this folder;
Astro strips types at build, so `npm run build` is the gate.

## Art direction

- Paper `#F3F5F4` and ink `#0E1A1D` in light, the brand teal-black `#0B1418` in dark. Both themes follow the system.
- SF Pro (the system font) only, 600 and 700, sentence case, tight tracking at display sizes. No web fonts are loaded.
- Ink pills for the one main action per view (paper pills in dark). Mint only for matched letters and links. The pearl is the
  one "now" marker: it leaves the hero ring as you scroll, docks under the section you are reading in the nav, rides the line in
  the Send to story, and marks the selected app in the dock. It is never decoration.
- The hero object is the ring from `docs/identity/app-icon/index.html` (hero camera), rendered by `scripts/render-ring.mjs`
  into a ring layer (light and dark shadows) and a separate pearl layer, so the pearl can move on its own.
- Motion: only transform and opacity, ease-out, 120 to 420 ms. Reduced motion keeps every word, tab and dialog and drops
  the flight, the lighting words, the folding wall, the cycling text and the marquee.

### Primitives taken from the reference sites (technique only)

From the contact sheets of every section of these sites (`/private/tmp/claude-501/ref/full`):
- Raycast: a real product frame with dock-like tabs that swap the screen (One key section); words that light as you
  scroll (the gap statement); pressable key caps (hero, Make your own).
- Apple macOS page: the claim plus one sentence rhythm, a section nav with a current marker, footnotes for measured numbers.
- CleanShot: bento tiles that each do one small thing (alias, key press, copy link); alternating picture and text blocks.
- Droppy: one art direction around every picture (all captures over the same wallpaper), a moving wall of app icons to
  show breadth, a searchable FAQ.

## What is on each page

### Home `/`

| Section | Idea | Pictures (slot ids) | Data |
|---|---|---|---|
| Hero | Headline, download pill, the ring and pearl, key caps that open the demo; Option-Space on the page opens it too | demo: `demo-open`, `demo-n`, `demo-nf` | version from `App/project.yml` |
| Gap (`#gap`) | A statement that lights as you read, then measured counts per app and a wall of real menu titles that folds into one field | none | `apps.json` (numbers and wall appear only when it exists) |
| One key (`#onekey`) | Dock of real app icons swapping one capture per app, with a typed example per app | `finder`, `safari`, `mail`, `notes`, `xcode` | shortcuts shown only from `apps.json`; the build warns if a named menu item is not in it |
| Holding (`#holding`) | Text, files, page, folder and git: what each action leaves in your hands, and every action name | none | `Sources/Apropos/Resources/ActionPacks/builtin.json`, read at build |
| Reach (`#reach`) | Send to and sequences as a four step story with the pearl on a line, then the built in destinations | `send-list`, `sequence-draft` | |
| Learns (`#learns`) | Usually next with its reason, what it learns from and never keeps | `usually-next` | |
| Your commands (`#yours`) | Alias, key, link (copy), Shortcuts, recording and menu item keys (both tagged Early) | `recording-review`, `alias-popover` | |
| Apps (`#apps`) | Marquee of 31 real app icons, then an explorer of measured apps | none | icons from `scripts/app-icons.swift`; explorer needs `apps.json` |
| Compare (`#compare`) | Apropos, Raycast, Spotlight, Alfred and the Help menu, each cell linked to its source | none | `src/data/compare.ts` |
| Private (`#private`) | Read in the moment, kept on this Mac, never kept; each macOS permission and why; the network line | `settings-privacy` | |
| Install (`#install`) | Download, three steps, searchable FAQ (also FAQPage JSON-LD) | none | `src/data/faq.ts` |

### Other pages

- `/compare/`: what each tool is best at, then the full table. `/compare/raycast/`, `/compare/spotlight/`, `/compare/alfred/`:
  how they differ, how to use both (keys, quicklinks, workflows), and a two column table.
- `/apps/`: every measured app with its counts and biggest menus, and a search over every measured command
  (`/apps/commands.json`, fetched only when the search is used). Without `apps.json` it shows the app icons only, is left out of
  the sitemap, and the footer hides its link.
- `/404/`.

## Pictures

Every app picture is a real capture: a Debug build of the app in stage mode, its real glass window over the `paper`
(light) or `night` (dark) wallpaper, captured from the screen at 2x. The data inside the windows is sample data
(fixtures), except the menu commands, which are the real menu bars of the apps on the Mac that took them. Source:
`/Users/walid/Pictures/Apropos Captures/2026-10-20/website-slots/` (16 slots, light and dark, with `manifest.json`).

`node scripts/import-shots.mjs <folder> [slot ...]` copies them into `src/assets/shots/<slot>-light.webp` and `-dark.webp`
(WebP at quality 90, full size; about 2 MB for all 32 files instead of 95 MB of PNG). The build makes the smaller versions.
Each picture is a typed slot (`src/data/shots.ts`); an empty slot would render a flat panel naming the capture it waits for.

The frame takes the picture's own proportions and rounds it at 22 px. `zoom` and `zoomSmall` on `Shot` crop in toward the
middle, where the panel sits in every capture: a little in narrow columns, more below 700 px.

| Slot | Where | Shows |
|---|---|---|
| `demo-open`, `demo-n`, `demo-nf` | Hero demo (Option-Space on the page) | Finder, then "n", then "nf" with New Folder first |
| `mail`, `xcode`, `notes`, `safari`, `finder` | One key dock, in that order | "ra" Reply All, "clean" Clean Build Folder, "check" Checklist, "sidebra" Show Sidebar, "compress" Compress 3 Items |
| `sequence-draft`, `send-list` | Send to story (send list on the Send to Notes step) | Copy in Safari, UPPERCASE, Notes; the destination list |
| `usually-next` | Learning | Usually next with two reasons; the quote beside it is one of them |
| `recording-review`, `alias-popover` | Your commands (both tagged Early) | Review window; Command-K popover on Alias and shortcut |
| `settings-privacy` | Privacy | Top of Privacy and data (the window cannot be taller than the screen) |
| `menubar-popover` | Install | The menu bar popover under a drawn menu bar |

Not used: `recording-bar`. The bar is a small strip in a large wallpaper and says less than the review window beside it.

Waiting: the full capture run (`apps/`, `panel/`, `settings/`, `onboarding/`, `recording/`, `menubar/` in the same dated
folder) is still being reviewed by the capture session. When it is final, pick from it for the app wall and explorer,
the privacy and make-your-own sections and install, and list what was used and rejected here.

Other real pictures: the ring and pearl (rendered from the icon scene), the app icons (macOS's own icons for apps
installed on this Mac, read with `NSWorkspace`, nothing launched), the share image.

## Measured app data

`npm run harvest` runs `apropos-probe <bundle id>` for 31 installed apps (it only reads the menu bar, it presses nothing) and
writes `src/data/apps.json` with the date, the Mac and macOS version, counts per app (total, with and without a shortcut, per
menu) and command titles. Titles under menus that can hold your own content (History, Bookmarks, Open Recent, the Window list,
mailboxes, Share, Services and similar) are counted but never written. Review the file before committing it.

It needs a terminal that has Accessibility. The agent shell that built this site does not, so **apps.json does not exist yet**
and the page shows no numbers: the Gap section is the statement only, One key shows no shortcut keys, the explorer and `/apps/`
are hidden. `node scripts/harvest-apps.mjs --launch` also opens missing apps hidden (`open -gj`) and quits only those it opened.

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

The global hotkey on a real Mac, real glass, live Accessibility reading, the download itself (no release exists), and every
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

## Quality gates (last run 2026-10-20, with the 16 captures, without measured data)

- `npm run build`, `check:seo`, `check:ui` and `check:a11y` pass.
- Lighthouse 12, home page: mobile 99/100/100/100 (LCP 2.1 s, 236 KiB), desktop 100/100/100/100 (performance, accessibility, best practices, SEO).
- Nothing scrolls sideways at 375 px (the comparison table scrolls inside its own frame, with the row names pinned).
- Screenshots of every section of every page, desktop and 375 px, light and dark, were taken and reviewed.
Re-run all of these after `apps.json` lands or more pictures are added.
