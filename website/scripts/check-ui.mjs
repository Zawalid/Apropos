// Checks the interactive parts against the built site, with motion allowed and with reduced motion: the Option-Space
// demo opens from the keyboard and steps through its frames, the app dock and the explorer answer arrow keys, the FAQ
// filters, the copy button copies, the nav pearl docks after the hero, and every control has a name.
//   npm run build && npx astro preview --port 4321 &   then   node scripts/check-ui.mjs [http://localhost:4321]
import { chromium } from 'playwright-core';

const base = (process.argv[2] ?? 'http://localhost:4321').replace(/\/$/, '');
const problems = [];
const check = (ok, message) => {
  if (!ok) problems.push(message);
};
const browser = await chromium.launch({ channel: 'chrome' });

for (const reducedMotion of ['no-preference', 'reduce']) {
  const label = reducedMotion === 'reduce' ? 'reduced motion' : 'motion';
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(base, { waitUntil: 'networkidle' });

  // Demo: Option-Space opens it, n then f step the frames, Escape closes it.
  await page.keyboard.press('Alt+Space');
  await page.waitForTimeout(250);
  check(await page.evaluate(() => document.querySelector('[data-demo]').open), `${label}: Option-Space did not open the demo`);
  await page.keyboard.press('n');
  await page.keyboard.press('f');
  const frame = await page.evaluate(() => [...document.querySelectorAll('[data-frame]')].findIndex((f) => f.classList.contains('on')));
  check(frame === 2, `${label}: after typing nf the demo shows frame ${frame}, expected 2`);
  await page.keyboard.press('Escape');
  await page.waitForTimeout(150);
  check(!(await page.evaluate(() => document.querySelector('[data-demo]').open)), `${label}: Escape did not close the demo`);
  await page.locator('.key-opt').click();
  await page.waitForTimeout(150);
  check(await page.evaluate(() => document.querySelector('[data-demo]').open), `${label}: the option key did not open the demo`);
  await page.locator('[data-demo-close]').click();

  // App switcher: arrow keys move the selection and show one panel.
  await page.locator('#apps').scrollIntoViewIfNeeded();
  await page.locator('#sw-tab-0').focus();
  await page.keyboard.press('ArrowRight');
  const sel = await page.evaluate(() => document.querySelector('#sw-tab-1').getAttribute('aria-selected'));
  check(sel === 'true', `${label}: ArrowRight in the app switcher did not select the second app`);
  await page.keyboard.press('End');
  const shown = await page.evaluate(() => [...document.querySelectorAll('[data-switcher] [data-panel]')].filter((p) => !p.hidden).length);
  check(shown === 1, `${label}: ${shown} app panels are shown, expected 1`);

  // Install steps: clicking a step shows its window.
  await page.locator('#step-tab-2').scrollIntoViewIfNeeded();
  await page.locator('#step-tab-2').click();
  const step = await page.evaluate(() => !document.getElementById('step-2').hidden && document.getElementById('step-0').hidden);
  check(step, `${label}: clicking step 3 did not show its window`);

  // Story: scrolling into the middle of the track turns on a later chapter (wide screens).
  await page.evaluate(() => {
    const t = document.querySelector('[data-story] .track');
    window.scrollTo(0, t.getBoundingClientRect().top + window.scrollY + t.offsetHeight * 0.5);
  });
  await page.waitForTimeout(400);
  const on = await page.evaluate(() => [...document.querySelectorAll('[data-chapter]')].findIndex((c) => c.classList.contains('on')));
  check(on >= 2, `${label}: halfway down the story the chapter on is ${on}`);

  // Explorer, when there is measured data.
  if (await page.locator('[data-explorer]').count()) {
    await page.locator('#app-tab-0').focus();
    await page.keyboard.press('ArrowDown');
    const ex = await page.evaluate(() => document.querySelector('#app-tab-1').getAttribute('aria-selected'));
    check(ex === 'true', `${label}: ArrowDown in the explorer did not select the second app`);
  }

  // Nav pearl docks once the hero is gone (with motion it flies there; without, it is simply there).
  await page.evaluate(() => document.getElementById('holding').scrollIntoView());
  await page.waitForTimeout(700);
  check(await page.evaluate(() => document.documentElement.classList.contains('docked')), `${label}: the nav pearl did not dock`);
  const current = await page.evaluate(() => document.querySelector('[data-nav] a[aria-current="true"]')?.dataset.for);
  check(current === 'holding', `${label}: the nav marks ${current} while reading the actions`);

  // FAQ: a click opens an answer (animated with motion) and a second click closes it.
  const q = page.locator('details[data-q]').first();
  await q.scrollIntoViewIfNeeded();
  await q.locator('summary').click();
  await page.waitForTimeout(400);
  const openH = await q.evaluate((d) => (d.open ? d.getBoundingClientRect().height : 0));
  check(openH > 80, `${label}: the first answer did not open (${openH}px)`);
  await q.locator('summary').click();
  await page.waitForTimeout(400);
  check(!(await q.evaluate((d) => d.open)), `${label}: the first answer did not close`);

  // FAQ: typing filters, a miss says so.
  const search = page.locator('[data-faq-search]');
  await search.scrollIntoViewIfNeeded();
  await search.fill('accessibility');
  const visible = await page.evaluate(() => [...document.querySelectorAll('[data-q]')].filter((q) => !q.hidden).length);
  check(visible >= 1 && visible < 5, `${label}: searching "accessibility" left ${visible} questions`);
  await search.fill('zzzz');
  check(await page.evaluate(() => !document.querySelector('[data-faq-none]').hidden), `${label}: a search with no match says nothing`);
  await search.fill('');

  // Copy button.
  await page.locator('[data-copy]').first().click();
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  check(copied.startsWith('apropos://'), `${label}: the copy button copied "${copied}"`);

  // Every control has a name.
  const unnamed = await page.evaluate(() =>
    [...document.querySelectorAll('a, button, input, summary')]
      .filter((el) => !el.closest('[aria-hidden="true"]'))
      .filter((el) => !(el.getAttribute('aria-label') || el.textContent.trim() || el.labels?.length || el.getAttribute('title')))
      .map((el) => el.outerHTML.slice(0, 80)),
  );
  check(unnamed.length === 0, `${label}: controls without a name: ${unnamed.join(' | ')}`);
  check(errors.length === 0, `${label}: page errors: ${errors.join(' | ')}`);
  console.log(`${label}: checked`);
  await context.close();
}

// The command search on /apps/, when it exists.
{
  const page = await browser.newPage();
  await page.goto(`${base}/apps/`, { waitUntil: 'networkidle' });
  if (await page.locator('[data-command-search] input').count()) {
    await page.locator('[data-command-search] input').fill('new');
    await page.waitForTimeout(600);
    const n = await page.locator('[data-command-results] li').count();
    check(n > 0, '/apps/: searching "new" found no command');
  }
  await page.close();
}
await browser.close();

if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(' - ' + p);
  process.exit(1);
}
console.log('\nOK: demo, story, app switcher, install steps, nav, FAQ, copy and control names checked, with and without motion.');
