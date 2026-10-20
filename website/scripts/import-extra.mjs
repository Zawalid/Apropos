// Copies chosen pictures from the full capture run into src/assets/shots as WebP under site slot names. Where only a dark
// file is listed, the site uses it for both themes (src/data/shots.ts falls back). The choices and the rejects are in
// README.md, Pictures.
//   node scripts/import-extra.mjs "/Users/walid/Pictures/Apropos Captures/2026-10-20"
import sharp from 'sharp';
import { mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const from = process.argv[2];
if (!from) {
  console.log('usage: node scripts/import-extra.mjs <capture folder>');
  process.exit(64);
}
const out = resolve(fileURLToPath(new URL('../src/assets/shots/', import.meta.url)));
mkdirSync(out, { recursive: true });

const apps = ['calendar', 'finder', 'mail', 'maps', 'music', 'notes', 'photos', 'preview', 'reminders', 'systemsettings', 'terminal', 'textedit', 'xcode'];
const map = {
  ...Object.fromEntries(apps.map((a) => [`app-${a}`, { dark: `apps/list-${a}-dark.png` }])),
  'ctx-files': { dark: 'apps/context-files-selected-finder-dark.png' },
  'ctx-page': { dark: 'apps/context-page-open-safari-dark.png' },
  'ctx-git': { dark: 'apps/context-git-folder-terminal-dark.png' },
  'send-confirm': { dark: 'panel/send-confirm-safari-dark.png' },
  // These two keep a thin strip of the desktop on their right edge, cropped off below.
  'settings-menu-keys': { light: 'settings/shortcuts-items-light-1.png' },
  'settings-links': { light: 'settings/integrations-light-1.png' },
  'onboarding-permission': { dark: 'onboarding/permission-dark.png' },
  'onboarding-done': { dark: 'onboarding/done-dark.png' },
};

for (const [slot, files] of Object.entries(map)) {
  for (const [theme, file] of Object.entries(files)) {
    let image = sharp(join(from, file));
    if (slot.startsWith('settings-')) {
      const { width, height } = await image.metadata();
      image = sharp(await image.extract({ left: 0, top: 0, width: Math.round(width * 0.945), height }).toBuffer());
    }
    const info = await image.webp({ quality: 90, effort: 6, smartSubsample: true }).toFile(join(out, `${slot}-${theme}.webp`));
    console.log(`${slot}-${theme}: ${info.width}x${info.height}, ${Math.round(info.size / 1024)} KB`);
  }
}
