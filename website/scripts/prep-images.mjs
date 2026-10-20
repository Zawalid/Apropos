// Crops the app's preview renders into website/src/assets/shots, with rounded corners and a transparent outside, so the page
// can frame them like windows. The renders come from scripts/render-previews.sh (a copy of the real views, no app launched).
// Run: node scripts/prep-images.mjs [folder with the renders]
import sharp from 'sharp';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const source = process.argv[2] ?? '/Users/walid/Personal/Projects/Cue/build/previews';
const out = fileURLToPath(new URL('../src/assets/shots/', import.meta.url));
await mkdir(out, { recursive: true });

// The floating panel sits inside a flat stand-in background: keep only the panel.
const panel = { left: 56, top: 56, width: 1440, height: 960, radius: 52 };
// Windows are rendered edge to edge, so they keep their whole frame.
const jobs = [
  ...[
    'palette-finder', 'palette-safari', 'palette-xcode', 'palette-actions', 'palette-send-list',
    'palette-sequence-draft', 'palette-usually-next',
  ].map((name) => ({ name, ...panel })),
  // The typed-search render is mostly empty below its two rows, so keep only the top of the panel.
  { name: 'palette-search-matches', ...panel, height: 385 },
  { name: 'recording-review', left: 0, top: 60, width: 1200, height: 1060, radius: 44 },
  { name: 'settings-privacy-and-data', left: 500, top: 70, width: 1100, height: 985, radius: 44 },
];

for (const job of jobs) {
  for (const mode of ['dark', 'light']) {
    const file = `${source}/${job.name}-${mode}.png`;
    const mask = Buffer.from(
      `<svg xmlns="http://www.w3.org/2000/svg" width="${job.width}" height="${job.height}"><rect width="${job.width}" height="${job.height}" rx="${job.radius}" fill="#fff"/></svg>`,
    );
    await sharp(file)
      .extract({ left: job.left, top: job.top, width: job.width, height: job.height })
      .ensureAlpha()
      .composite([{ input: mask, blend: 'dest-in' }])
      .png({ compressionLevel: 9, palette: false })
      .toFile(`${out}${job.name}-${mode}.png`);
  }
  console.log('wrote', job.name);
}
