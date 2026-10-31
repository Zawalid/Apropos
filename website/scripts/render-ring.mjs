// Renders the hero object from the app icon's 3D scene (docs/identity/app-icon, hero camera) into two transparent layers:
// the ring with its shadow (one per theme, the shadow is stronger on the dark page) and the pearl alone, cropped, with
// its place on the ring written to src/data/ring.json so the page can stack the two exactly.
//   node scripts/render-ring.mjs
import { chromium } from 'playwright-core';
import sharp from 'sharp';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, '..');
const out = join(site, 'src/assets/ring');
mkdirSync(out, { recursive: true });
const size = 1600;

const browser = await chromium.launch({ channel: 'chrome', args: ['--use-angle=metal', '--enable-gpu', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 900, height: 900 } });
page.on('pageerror', (e) => console.error(String(e)));
await page.goto(pathToFileURL(join(here, 'ring/scene.html')).href + '?hero=1');
await page.waitForFunction(() => window.sceneReady === true, null, { timeout: 30000 });

async function grab(layer, shadow) {
  const url = await page.evaluate(([l, s, n]) => { window.layer(l, s); return window.exportHero(n); }, [layer, shadow, size]);
  return Buffer.from(url.split(',')[1], 'base64');
}

const ringLight = await grab('ring', 0.09);
const ringDark = await grab('ring', 0.5);
const pearl = await grab('pearl', 0);
await browser.close();

// The ring layers share one crop so the pearl lands in the same place on both.
const { info } = await sharp(ringDark).trim({ threshold: 1 }).toBuffer({ resolveWithObject: true });
const box = { left: -info.trimOffsetLeft, top: -info.trimOffsetTop, width: info.width, height: info.height };
const pad = 24;
const crop = {
  left: Math.max(0, box.left - pad),
  top: Math.max(0, box.top - pad),
  width: Math.min(size - Math.max(0, box.left - pad), box.width + pad * 2),
  height: Math.min(size - Math.max(0, box.top - pad), box.height + pad * 2),
};
for (const [name, buffer] of [['ring-light', ringLight], ['ring-dark', ringDark]]) {
  await sharp(buffer).extract(crop).png().toFile(join(out, `${name}.png`));
}

const pearlTrim = await sharp(pearl).trim({ threshold: 1 }).toBuffer({ resolveWithObject: true });
const p = pearlTrim.info;
const pearlBox = { left: -p.trimOffsetLeft, top: -p.trimOffsetTop, width: p.width, height: p.height };
await sharp(pearlTrim.data).png().toFile(join(out, 'pearl.png'));

// Where the pearl sits, in percent of the cropped ring image.
const place = {
  left: ((pearlBox.left - crop.left) / crop.width) * 100,
  top: ((pearlBox.top - crop.top) / crop.height) * 100,
  width: (pearlBox.width / crop.width) * 100,
  ratio: crop.width / crop.height,
};
writeFileSync(join(site, 'src/data/ring.json'), JSON.stringify(place, null, 2) + '\n');
console.log('ring', crop, 'pearl', pearlBox, place);
