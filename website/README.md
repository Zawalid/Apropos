# Apropos website

The marketing site for Apropos. Astro, static output, deployed on Cloudflare with Wrangler, built the same way as the Lopper
site (`/Users/walid/Personal/Projects/Lopper/website`): GSAP and Lenis for the scroll work, `playwright-core` for the checks.

```bash
cd website
npm install
npm run dev          # http://localhost:4321
npm run build        # static site in dist/
npm run preview -- --port 4321
```

With the preview running in another terminal:

```bash
npm run check:seo    # titles, description, canonical, share image, JSON-LD, sitemap, robots, dashes, emoji, 375px overflow
npm run check:ui     # app tabs by keyboard, FAQ, copy button, control names; with motion and with reduced motion
npm run shots        # desktop and 375px screenshots, light and dark, into .shots/ (not committed)
npm run og           # redraws public/og.png from scripts/og.html
npm run images       # recrops src/assets/shots from the app's preview renders
```

All scripts use the system Chrome (`channel: 'chrome'`), like Lopper's.

## What is on the page

| Section | Idea | Pictures (renders of the real views) |
|---|---|---|
| Hero | The right command for the moment, one download button | `palette-finder` |
| Why | One key, a different palette per app. Pinned and scroll driven on big screens, real tabs everywhere | `palette-finder`, `palette-safari`, `palette-xcode` |
| Tour | Six chapters, alternating sides, each with one outlined detail | `palette-search-matches`, `palette-usually-next`, `palette-send-list`, `palette-sequence-draft`, `palette-actions`, `recording-review` |
| Apps | What the list offers by situation, as typography | none |
| Raycast | Sits next to a launcher, with a "reach for" table | none |
| Safety | "Apropos will ... only when ..." ledger, the privacy statement | `settings-privacy-and-data` |
| Install | Download, first launch, Accessibility, `apropos://open` | none |
| FAQ | Ten honest questions | none |

## Where the images come from

`src/assets/shots/*.png` are cropped from `build/previews/` in the main checkout, which `scripts/render-previews.sh` writes
from the app's own SwiftUI views without launching the app. They are renders with example data, they carry no real glass, and
they are labelled as renders on the page. Nothing here is a live capture. To refresh them after the UI changes, run
`scripts/render-previews.sh` in the repo root, then `npm run images` here (the folder defaults to
`/Users/walid/Personal/Projects/Cue/build/previews`, pass another as the first argument).

Not shown, because it cannot be captured without the real app on screen: the glass over a real desktop, the global hotkey,
live Accessibility reading. The hero says so under the panel.

## Where each claim comes from

Everything on the page was checked against `CHANGELOG.md`, `git log main` and these docs on 2026-10-20: `docs/design.md`
(positioning next to Raycast, no launching apps or clipboard), `docs/context-actions.md` (the actions listed under Apps, the
secure-field and password-manager rules), `docs/destinations.md` (Send to, Mail draft never sends, second Return),
`docs/sequences.md`, `docs/ranking.md` (typed slips, match highlighting), `docs/prediction.md` (what Usually next stores),
`docs/integrations.md` (`apropos://`, Raycast quicklinks, Alfred), `docs/user-commands.md`, and the app's own Privacy and data
page. Early features carry an "early" tag: aliases and shortcuts for menu items, and recording. Not sold as features:
anything in `docs/roadmap.md`, `docs/backlog.md` or `docs/recorder-plan.md` (packs, sync, Pro, a pack registry, AI step,
controls and typed text in recordings).

## TODO for the owner (nothing here is on the page as a placeholder)

- **Repository name.** `src/data/site.ts` assumes `https://github.com/Zawalid/Apropos`.
- **Release asset.** The download button points at `https://github.com/Zawalid/Apropos/releases/latest/download/Apropos.dmg`.
  It 404s until a release with an asset of exactly that name exists.
- **Install steps.** The Install section says macOS asks to confirm the first launch because the build is not notarized, and
  stops there. Add the exact steps (and a one line command, if you want one like Lopper's) once they exist. There is no Homebrew
  tap, so no brew command is shown.
- **Domain.** `apropos.zawalid.com` is assumed in `astro.config.mjs`, `wrangler.jsonc`, `public/robots.txt`,
  `src/data/site.ts` and `scripts/check-seo.mjs`. Change all five if it differs.
- **Contact.** The footer links to GitHub issues, zawalid.com, GitHub and X. There is no email address on the page.
- **License.** There is no LICENSE file in the repo, so the page makes no open source claim beyond "the source is open to read".
  Add the licence and a footer link when decided.
- **Price.** Not mentioned anywhere. `docs/design.md` leaves it open.
- **Analytics.** The footer says there are none, and the site has none. Lopper loads the Cloudflare beacon; this one does not.
- **Deploy.** `deploy-workflow.yml.example` is a copy of Lopper's workflow for this folder. Move it to
  `.github/workflows/website.yml`, add the repo secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, and it deploys on
  pushes to `main` that touch `website/`. Nothing has been pushed or deployed from this work.
- **Videos.** There are none. Lopper's site plays short recordings; Apropos has no recordings of the real app yet, so the
  Worker that serves video ranges was left out of `wrangler.jsonc`. Add `worker.js` back if mp4 files come.

## Design notes

- Type: Barlow 800 and 900 in lowercase for display lines, the system font (SF Pro) for everything else, IBM Plex Mono for the
  small mono lines. Three font files, all self hosted.
- Colour: off-black and off-white surfaces from the brand tokens, light and dark by `prefers-color-scheme`. One accent. Mint
  is `#0A8F70` on light and `#8CF2CC` on dark in the app; on paper the text and buttons use a darker step (`#07785D`) so contrast
  holds at 4.5:1. The pearl orange appears only as the "now" marker: the full stop of the headline, the glide in Why, the dots in
  the tour captions.
- Motion: only transform, opacity and clip-path. `prefers-reduced-motion` gives a plain layout with the same content and the
  same tabs. If the animation module fails to start within six seconds, the static layout takes over.
