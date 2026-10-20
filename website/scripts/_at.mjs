// node at.mjs out scheme width selector-or-y [scrollFraction]: one screenshot at a place on the page.
import { chromium } from 'playwright-core';
const [out, scheme, width, where, frac] = process.argv.slice(2);
const b = await chromium.launch({ channel: 'chrome' });
const p = await b.newPage({ viewport: { width: Number(width), height: Number(width) < 600 ? 812 : 900 }, colorScheme: scheme });
await p.goto('http://localhost:4321/', { waitUntil: 'networkidle' });
await p.evaluate(async ([where, frac]) => {
  const el = document.querySelector(where);
  const top = el.getBoundingClientRect().top + scrollY;
  const y = frac ? top + el.offsetHeight * Number(frac) : top - 64;
  for (let s = 0; s <= y; s += 400) { scrollTo(0, s); await new Promise((r) => setTimeout(r, 30)); }
  scrollTo(0, y);
}, [where, frac]);
await p.waitForTimeout(700);
await p.screenshot({ path: out });
await b.close();
