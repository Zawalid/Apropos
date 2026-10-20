// Checks the interactive bits against the built site: the app tabs answer the keyboard, the FAQ opens and closes, the copy
// button copies, and every control has a name. Runs with motion allowed and with reduced motion.
//   npm run build && npx astro preview --port 4321 &   then   node scripts/check-ui.mjs [http://localhost:4321]
import { chromium } from 'playwright-core';

const base = (process.argv[2] ?? 'http://localhost:4321').replace(/\/$/, '');
const problems = [];
const check = (ok, message) => { if (!ok) problems.push(message); };
const browser = await chromium.launch({ channel: 'chrome' });

for (const reducedMotion of ['no-preference', 'reduce']) {
  const label = reducedMotion === 'reduce' ? 'reduced motion' : 'motion';
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  await page.goto(base, { waitUntil: 'networkidle' });
  await page.waitForTimeout(1200);

  const isPinned = await page.evaluate(() => parseFloat(getComputedStyle(document.querySelector('[data-why]')).height) > window.innerHeight * 2);
  check(reducedMotion === 'reduce' ? !isPinned : isPinned, `${label}: the Why section is ${isPinned ? 'pinned' : 'not pinned'}`);

  // Tabs: arrow keys move the selection (and, when pinned, scroll to it).
  await page.locator('#why').scrollIntoViewIfNeeded();
  await page.locator('#why-tab-0').focus();
  await page.keyboard.press('ArrowDown');
  await page.waitForTimeout(1500);
  const selected = await page.evaluate(() => [...document.querySelectorAll('[data-why-tab]')].map((t) => t.getAttribute('aria-selected')));
  check(selected.join() === 'false,true,false', `${label}: ArrowDown did not select the second tab (${selected.join()})`);
  await page.keyboard.press('End');
  await page.waitForTimeout(1500);
  const last = await page.evaluate(() => document.querySelector('#why-tab-2').getAttribute('aria-selected'));
  check(last === 'true', `${label}: End did not select the last tab`);
  const visiblePanels = await page.evaluate(() => [...document.querySelectorAll('[data-why-panel]')].filter((p) => getComputedStyle(p).visibility === 'visible').length);
  check(visiblePanels === 1, `${label}: ${visiblePanels} picture panels are visible, expected 1`);

  // FAQ
  const first = page.locator('details[data-faq]').first();
  await first.scrollIntoViewIfNeeded();
  await first.locator('summary').click();
  await page.waitForTimeout(700);
  check(await first.evaluate((d) => d.open), `${label}: the first FAQ answer did not open`);
  await first.locator('summary').click();
  await page.waitForTimeout(700);
  check(!(await first.evaluate((d) => d.open)), `${label}: the first FAQ answer did not close`);

  // Copy
  const copy = page.locator('[data-copy]').first();
  await copy.scrollIntoViewIfNeeded();
  await copy.click();
  await page.waitForTimeout(300);
  check((await copy.textContent()) === 'Copied', `${label}: the copy button did not say Copied`);
  check((await page.evaluate(() => navigator.clipboard.readText())) === 'open "apropos://open"', `${label}: the clipboard does not hold the command`);

  // Every link and button has a name.
  const unnamed = await page.evaluate(() => [...document.querySelectorAll('a[href], button')].filter((e) => !(e.getAttribute('aria-label') || e.textContent.trim() || e.querySelector('img[alt]:not([alt=""])'))).length);
  check(unnamed === 0, `${label}: ${unnamed} links or buttons have no name`);

  await context.close();
}
await browser.close();

if (problems.length) {
  console.log(`${problems.length} problem(s):`);
  for (const p of problems) console.log(' - ' + p);
  process.exit(1);
}
console.log('OK: tabs, FAQ, copy and control names work with motion and with reduced motion.');
