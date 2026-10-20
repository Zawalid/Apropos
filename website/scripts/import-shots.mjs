// Copies real captures into src/assets/shots as high quality WebP, keeping the slot names (<slot>-light, <slot>-dark).
// The PNGs from a capture run are about 3 MB each; the WebP sources keep the full 2x size at a tenth of the weight, and the
// build still makes its own smaller versions from them.
//   node scripts/import-shots.mjs "/Users/walid/Pictures/Apropos Captures/2026-10-20/website-slots" [slot ...]
import sharp from 'sharp';
import { readdirSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const [from, ...only] = process.argv.slice(2);
if (!from) {
  console.log('usage: node scripts/import-shots.mjs <folder> [slot ...]');
  process.exit(64);
}
const out = resolve(fileURLToPath(new URL('../src/assets/shots/', import.meta.url)));
mkdirSync(out, { recursive: true });
for (const file of readdirSync(from).filter((f) => /-(light|dark)\.png$/.test(f)).sort()) {
  const slot = file.replace(/-(light|dark)\.png$/, '');
  if (only.length && !only.includes(slot)) continue;
  const target = join(out, file.replace(/\.png$/, '.webp'));
  const info = await sharp(join(from, file)).webp({ quality: 90, effort: 6, smartSubsample: true }).toFile(target);
  console.log(`${file} -> ${info.width}x${info.height}, ${Math.round(info.size / 1024)} KB`);
}
