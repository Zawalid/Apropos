// Screenshots of every section of every page, top to bottom: desktop and 375px, light and dark, into .shots/.
// Each section is shot on its own after scrolling it into view, so scroll-linked states are real, not the first frame.
//   npx astro preview --port 4321 &   then   node scripts/shots.mjs [base] [--only light|dark] [--page /]
import { chromium } from 'playwright-core';
import { mkdirSync } from 'node:fs';

const args = process.argv.slice(2);
const base = (args.find((a) => a.startsWith('http')) ?? 'http://localhost:4321').replace(/\/$/, '');
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null;
const pageArg = args.includes('--page') ? args[args.indexOf('--page') + 1] : null;
const out = new URL('../.shots/', import.meta.url).pathname;
mkdirSync(out, { recursive: true });

const pages = pageArg ? [pageArg] : ['/', '/compare/', '/compare/raycast/', '/apps/', '/404/'];
const sizes = [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'mobile', width: 375, height: 812 },
];
const schemes = only ? [only] : ['light', 'dark'];

const browser = await chromium.launch({ channel: 'chrome' });
for (const scheme of schemes) {
  for (const size of sizes) {
    const context = await browser.newContext({
      viewport: { width: size.width, height: size.height },
      deviceScaleFactor: 1,
      colorScheme: scheme,
      hasTouch: size.name === 'mobile',
    });
    const page = await context.newPage();
    for (const path of pages) {
      await page.goto(base + path, { waitUntil: 'networkidle' });
      const slug = path === '/' ? 'home' : path.replace(/^\/|\/$/g, '').replace(/\//g, '-');
      const blocks = await page.$$eval('main > section, main > article, body > footer', (els) =>
        els.map((e, i) => ({ i, id: e.id || e.className.split(' ')[0] || `s${i}`, top: e.getBoundingClientRect().top + window.scrollY, h: e.offsetHeight })),
      );
      let n = 0;
      for (const b of blocks) {
        // One shot per viewport down each section.
        for (let y = b.top; y < b.top + b.h; y += size.height) {
          await page.evaluate((top) => window.scrollTo(0, top), Math.max(0, y - 64));
          await page.waitForTimeout(450);
          const file = `${out}${slug}-${size.name}-${scheme}-${String(n++).padStart(2, '0')}-${b.id}.png`;
          await page.screenshot({ path: file });
        }
      }
      console.log(`${slug} ${size.name} ${scheme}: ${n} shots`);
    }
    await context.close();
  }
}
await browser.close();
