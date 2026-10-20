// Screenshots of the built site for review: desktop and 375px, light and dark.
//   npm run build && npx astro preview --port 4321 &   then   node scripts/shots.mjs [http://localhost:4321] [out dir]
import { chromium } from 'playwright-core';
import { mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const base = (process.argv[2] ?? 'http://localhost:4321').replace(/\/$/, '');
const out = process.argv[3] ?? fileURLToPath(new URL('../.shots/', import.meta.url));
await mkdir(out, { recursive: true });

const browser = await chromium.launch({ channel: 'chrome' });

async function run(label, viewport, scheme, stops) {
  const context = await browser.newContext({ viewport, colorScheme: scheme, deviceScaleFactor: 1, hasTouch: viewport.width < 600 });
  const page = await context.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 140)); });
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 140)));
  await page.goto(base, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1800);
  for (const [name, target] of stops) {
    const y = await page.evaluate((t) => {
      if (typeof t === 'number') return t;
      const el = document.querySelector(t.sel);
      if (!el) return -1;
      return el.getBoundingClientRect().top + window.scrollY + (t.dy ?? 0);
    }, target);
    if (y < 0) { console.log(label, name, 'missing selector'); continue; }
    await page.evaluate((v) => window.scrollTo(0, v), y);
    await page.waitForTimeout(1400);
    await page.screenshot({ path: `${out}${label}-${scheme}-${name}.png` });
  }
  const overflow = await page.evaluate(() => ({ sw: document.documentElement.scrollWidth, cw: document.documentElement.clientWidth, h: document.documentElement.scrollHeight }));
  console.log(label, scheme, `scrollWidth ${overflow.sw} / clientWidth ${overflow.cw}, page height ${overflow.h}`, errors.length ? `console errors: ${errors.join(' | ')}` : 'no console errors');
  await context.close();
}

const desktop = [
  ['01-hero', 0], ['02-hero-scroll', 450], ['03-hero-full', 1200],
  ['04-why-a', { sel: '#why', dy: 300 }], ['05-why-b', { sel: '#why', dy: 1300 }], ['06-why-c', { sel: '#why', dy: 2100 }],
  ['07-tour', { sel: '#tour', dy: -40 }], ['08-chapter-2', { sel: '[data-chapter]:nth-child(2)', dy: -160 }], ['09-chapter-5', { sel: '[data-chapter]:nth-child(5)', dy: -160 }],
  ['10-apps', { sel: '#apps', dy: 0 }], ['11-raycast', { sel: '#raycast', dy: 0 }],
  ['12-safety', { sel: '#safety', dy: 0 }], ['13-quiet', { sel: '.quiet', dy: -60 }],
  ['14-install', { sel: '#install', dy: -20 }], ['15-faq', { sel: '#faq', dy: 0 }], ['16-footer', { sel: '.foot', dy: -100 }],
];
const mobile = [
  ['01-hero', 0], ['02-hero-scroll', 400], ['03-why', { sel: '#why', dy: 0 }], ['04-tour', { sel: '#tour', dy: 0 }],
  ['05-chapter', { sel: '[data-chapter]:nth-child(2)', dy: -20 }], ['06-apps', { sel: '#apps', dy: 0 }], ['07-raycast', { sel: '#raycast', dy: 0 }],
  ['08-safety', { sel: '#safety', dy: 0 }], ['09-install', { sel: '#install', dy: -10 }], ['10-faq', { sel: '#faq', dy: 0 }],
];

for (const scheme of ['dark', 'light']) {
  await run('desktop', { width: 1440, height: 900 }, scheme, desktop);
  await run('mobile', { width: 375, height: 812 }, scheme, mobile);
}
await browser.close();
