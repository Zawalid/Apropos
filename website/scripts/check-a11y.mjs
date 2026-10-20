// Runs axe on every page in light and dark, at 1440 and 375 wide, after scrolling through the page so lazy pictures
// and scroll states are in place. Fails on any violation.
//   npx astro preview --port 4321 &   then   node scripts/check-a11y.mjs [http://localhost:4321]
import { chromium } from 'playwright-core';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const axe = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8');
const base = (process.argv[2] ?? 'http://localhost:4321').replace(/\/$/, '');
const sitemap = await (await fetch(`${base}/sitemap.xml`)).text();
const pages = [...sitemap.matchAll(/<loc>https?:\/\/[^/]+(\/[^<]*)<\/loc>/g)].map((m) => m[1]).concat('/404/');
const browser = await chromium.launch({ channel: 'chrome' });
let failures = 0;
for (const colorScheme of ['light', 'dark']) {
  for (const width of [1440, 375]) {
    const context = await browser.newContext({ viewport: { width, height: 900 }, colorScheme });
    const page = await context.newPage();
    for (const path of pages) {
      await page.goto(base + path, { waitUntil: 'networkidle' });
      await page.evaluate(async () => {
        for (let y = 0; y < document.body.scrollHeight; y += 700) {
          window.scrollTo(0, y);
          await new Promise((r) => setTimeout(r, 40));
        }
        window.scrollTo(0, 0);
      });
      // Long enough for every entrance animation to finish, so contrast is measured on the settled page.
      await page.waitForTimeout(1800);
      await page.addScriptTag({ content: axe });
      const result = await page.evaluate(async () => {
        const r = await window.axe.run(document, { resultTypes: ['violations'] });
        return r.violations.map((v) => `${v.id} (${v.impact}): ${v.nodes.slice(0, 3).map((n) => n.target.join(' ')).join(', ')}`);
      });
      if (result.length) {
        failures += result.length;
        console.log(`${path} ${colorScheme} ${width}:`);
        for (const line of result) console.log('  ' + line);
      }
    }
    await context.close();
  }
}
await browser.close();
if (failures) {
  console.log(`\n${failures} violation(s)`);
  process.exit(1);
}
console.log(`OK: axe found nothing on ${pages.length} pages, light and dark, 1440 and 375.`);
