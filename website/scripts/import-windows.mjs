// Turns the real captures into floating windows for the site: the window alone, transparent corners, no wallpaper and
// no shadow (the page draws the shadow). Output: src/assets/windows/<id>-dark.webp and, where a clean light capture
// exists, <id>-light.webp. Without a light file the dark window is used in both themes.
//   node scripts/import-windows.mjs "/Users/walid/Pictures/Apropos Captures/2026-10-20"
//
// Sources: the capture run's own cutouts (`*-dark-cutout.png`), the tall stitched Settings pages (`*-full-*.png`, already
// cut out), and the website slot frames, where the panel sits at the same place in every 2560 x 1600 frame and is cut
// here with a rounded mask. Light scenes of the full run are not used: a video on the desktop shows through their glass.
import sharp from 'sharp';
import { mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const from = process.argv[2];
if (!from) {
  console.log('usage: node scripts/import-windows.mjs <capture folder>');
  process.exit(64);
}
const out = resolve(fileURLToPath(new URL('../src/assets/windows/', import.meta.url)));
mkdirSync(out, { recursive: true });

// The panel in the website slot frames: found by matching the empty search header of the full run's Finder cutout.
const slotPanel = { left: 560, top: 320, width: 1440, height: 960, inset: 3, radius: 58 };

const apps = ['calendar', 'finder', 'mail', 'maps', 'music', 'notes', 'photos', 'preview', 'reminders', 'systemsettings', 'terminal', 'textedit', 'xcode'];

/** id -> { dark, light? }; a value is a cutout path, or { slot: file } for a website slot frame to cut. */
const map = {
  'hero-open': { dark: { slot: 'website-slots/demo-open-dark.png' } },
  'hero-n': { dark: { slot: 'website-slots/demo-n-dark.png' } },
  'hero-nf': { dark: { slot: 'website-slots/demo-nf-dark.png' } },
  'deep-xcode': { dark: { slot: 'website-slots/xcode-dark.png' } },
  'app-safari': { dark: { slot: 'website-slots/safari-dark.png' } },
  slip: { dark: 'panel/search-slip-finder-dark-cutout.png' },
  holding: { dark: 'apps/context-page-open-safari-dark-cutout.png' },
  'send-list': { dark: 'panel/send-list-safari-dark-cutout.png' },
  sequence: { dark: 'panel/sequence-draft-safari-dark-cutout.png' },
  confirm: { dark: 'panel/send-confirm-safari-dark-cutout.png' },
  'usually-next': { dark: 'panel/usually-next-finder-dark-cutout.png' },
  ...Object.fromEntries(apps.map((a) => [`app-${a}`, { dark: `apps/list-${a}-dark-cutout.png` }])),
  'alias-popover': { dark: 'panel/popover-finder-dark-cutout.png' },
  'recording-review': { dark: 'recording/review-filled-dark-cutout.png' },
  'recording-permission': { dark: 'recording/permission-ready-dark-cutout.png' },
  'privacy-page': { dark: 'settings/privacy-allowed-full-dark.png', light: 'settings/privacy-allowed-full-light.png' },
  'menubar-popover': { dark: 'menubar/popover-dark-cutout.png' },
  'onboarding-permission': { dark: 'onboarding/permission-dark-cutout.png' },
  'onboarding-allowed': { dark: 'onboarding/permission-allowed-dark-cutout.png' },
  'onboarding-done': { dark: 'onboarding/done-dark-cutout.png' },
};

async function slotCut(file) {
  const { left, top, width, height, inset, radius } = slotPanel;
  const svg = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect x="${inset}" y="${inset}" width="${width - 2 * inset}" height="${height - 2 * inset}" rx="${radius}" fill="#fff"/></svg>`,
  );
  const mask = await sharp(svg).extractChannel(0).toBuffer();
  // Crop first, then add the mask: sharp would otherwise join the channel before the crop.
  const crop = await sharp(join(from, file)).extract({ left, top, width, height }).removeAlpha().toBuffer();
  return sharp(crop).joinChannel(mask);
}

for (const [id, themes] of Object.entries(map)) {
  for (const [theme, source] of Object.entries(themes)) {
    const image = typeof source === 'string' ? sharp(join(from, source)) : await slotCut(source.slot);
    const info = await image.webp({ quality: 90, alphaQuality: 100, effort: 6, smartSubsample: true }).toFile(join(out, `${id}-${theme}.webp`));
    console.log(`${id}-${theme}: ${info.width}x${info.height}, ${Math.round(info.size / 1024)} KB`);
  }
}
