// Checks the interactive parts of the scenes against the built site, with motion allowed and with reduced motion:
// Option-Space plays the opening, the scenes reach their states when scrolled, the app switcher answers arrow keys, a
// selection in the Holding paragraph opens its actions and changes the words, the ways of running a command light their
// lines, the install steps and the FAQ answer, the copy button copies, the nav pearl docks, and every control has a name.
//   npm run build && npx astro preview --port 4321 &   then   node scripts/check-ui.mjs [http://localhost:4321]
import { chromium } from 'playwright-core';

const base = (process.argv[2] ?? 'http://localhost:4321').replace(/\/$/, '');
const problems = [];
const check = (ok, message) => {
  if (!ok) problems.push(message);
};
const browser = await chromium.launch({ channel: 'chrome' });

/** Scrolls a pinned or plain scene to progress p, in steps so scroll-linked code runs as it would. */
async function goTo(page, scene, p) {
  const y = await page.evaluate(
    ([scene, p]) => {
      const el = document.querySelector(`[data-scene="${scene}"]`) ?? document.querySelector(scene);
      return el.getBoundingClientRect().top + window.scrollY + (el.offsetHeight - window.innerHeight) * p;
    },
    [scene, p],
  );
  const from = await page.evaluate(() => window.scrollY);
  for (let i = 1; i <= 8; i++) {
    await page.evaluate((v) => window.scrollTo(0, v), from + ((y - from) * i) / 8);
    await page.waitForTimeout(30);
  }
  await page.waitForTimeout(350);
}

for (const reducedMotion of ['no-preference', 'reduce']) {
  const label = reducedMotion === 'reduce' ? 'reduced motion' : 'motion';
  const motion = reducedMotion !== 'reduce';
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(base, { waitUntil: 'networkidle' });

  // Press: Option-Space plays the opening and lands on the panel after n, f.
  await page.keyboard.press('Alt+Space');
  await page.waitForTimeout(1800);
  check((await page.evaluate(() => window.scrollY)) > 200, `${label}: Option-Space did not move to the panel`);
  if (motion) {
    const frame = await page.evaluate(() => [...document.querySelectorAll('[data-frame]')].findIndex((f) => f.classList.contains('on')));
    check(frame === 2, `${label}: after Option-Space the panel shows frame ${frame}, expected 2 (nf)`);
  }
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(200);

  if (motion) {
    // Deep folds into the panel; Slip ends on "show" in mint; Send turns the chip to capitals; Private lights its promise.
    await goTo(page, 'deep', 0.9);
    check(await page.evaluate(() => document.querySelector('[data-scene="deep"]').classList.contains('folded')), `${label}: the menu staircase did not fold`);
    await goTo(page, 'slip', 0.6);
    const mint = await page.evaluate(() => document.querySelector('[data-l="0"]').style.color);
    check(mint.includes('mint'), `${label}: the slipped word did not turn mint`);
    await goTo(page, 'send', 0.6);
    const chip = await page.evaluate(() => document.querySelector('[data-chip-text]').textContent);
    check(chip === chip.toUpperCase(), `${label}: past UPPERCASE the chip reads "${chip}"`);
    await goTo(page, 'private', 0.95);
    const unlit = await page.evaluate(() => document.querySelectorAll('.private .pw:not(.lit)').length);
    check(unlit === 0, `${label}: ${unlit} words of the privacy promise are not lit`);
  }

  // Apps: arrow keys on the switcher move to the next app.
  await goTo(page, 'apps', 0);
  await page.locator('[data-to="0"]').focus();
  await page.keyboard.press('ArrowRight');
  await page.waitForTimeout(1600);
  const pressed = await page.evaluate(() => document.querySelector('[data-to="1"]').getAttribute('aria-pressed'));
  check(pressed === 'true', `${label}: ArrowRight in the app switcher did not move to the second app`);

  // Holding: a selection in the paragraph opens the actions; UPPERCASE changes the words; the words come back.
  await goTo(page, 'holding', 0);
  await page.evaluate(() => {
    const p = document.querySelector('[data-copytext]');
    const node = p.firstChild;
    const at = node.textContent.indexOf('Mail or Safari');
    const r = document.createRange();
    r.setStart(node, at);
    r.setEnd(node, at + 'Mail or Safari'.length);
    const s = window.getSelection();
    s.removeAllRanges();
    s.addRange(r);
  });
  await page.waitForTimeout(300);
  check(await page.evaluate(() => !document.querySelector('[data-pop]').hidden), `${label}: selecting words did not open the actions`);
  await page.locator('[data-pop-list] button', { hasText: 'UPPERCASE' }).first().click();
  await page.waitForTimeout(200);
  check(await page.evaluate(() => document.querySelector('[data-essay]').textContent.includes('MAIL OR SAFARI')), `${label}: UPPERCASE did not change the selected words`);
  await page.locator('[data-reset]').click();
  await page.waitForTimeout(100);
  check(await page.evaluate(() => document.querySelector('[data-essay]').textContent.includes('Mail or Safari')), `${label}: Put the words back did not restore them`);

  // Next: the tally counts to nine.
  await goTo(page, 'next', 0.2);
  await page.waitForTimeout(2200);
  check((await page.evaluate(() => document.querySelector('[data-n]').textContent)) === '9', `${label}: the tally did not reach 9`);

  // Yours: pointing at a way lights the lines of the file it comes from.
  await page.locator('[data-way="key"]').scrollIntoViewIfNeeded();
  await page.locator('[data-way="key"]').hover();
  await page.waitForTimeout(200);
  const lit = await page.evaluate(() => [...document.querySelectorAll('.ln.lit')].map((l) => l.dataset.for));
  check(lit.length === 2 && lit.every((f) => f === 'key'), `${label}: pointing at Press its key lit ${JSON.stringify(lit)}`);

  // Install: the space bar is the download, and the pearl moves along the steps as they pass.
  check((await page.locator('#install .k-get').getAttribute('href'))?.includes('Apropos.dmg'), `${label}: the space bar is not the download link`);
  await page.locator('[data-steps]').scrollIntoViewIfNeeded();
  await page.evaluate(() => window.scrollBy(0, -window.innerHeight * 0.4));
  await page.waitForTimeout(200);
  const first = await page.evaluate(() => [...document.querySelectorAll('[data-step]')].findIndex((s) => s.classList.contains('now')));
  await page.evaluate(() => window.scrollBy(0, window.innerHeight * 0.6));
  await page.waitForTimeout(200);
  const later = await page.evaluate(() => [...document.querySelectorAll('[data-step]')].findIndex((s) => s.classList.contains('now')));
  check(first >= 0 && later > first, `${label}: the install pearl went from step ${first} to ${later} while scrolling`);

  // Nav pearl: docked under the section being read.
  await page.evaluate(() => document.getElementById('holding').scrollIntoView());
  await page.waitForTimeout(500);
  check(await page.evaluate(() => document.documentElement.classList.contains('docked')), `${label}: the nav pearl did not dock`);
  const current = await page.evaluate(() => document.querySelector('[data-nav] a[aria-current="true"]')?.dataset.for);
  check(current === 'holding', `${label}: the nav marks ${current} while reading the selection scene`);

  // FAQ: a click opens an answer (animated with motion) and a second click closes it.
  const q = page.locator('details[data-q]').first();
  await q.scrollIntoViewIfNeeded();
  await q.locator('summary').click();
  await page.waitForTimeout(400);
  const openH = await q.evaluate((d) => (d.open ? d.getBoundingClientRect().height : 0));
  check(openH > 70, `${label}: the first answer did not open (${openH}px)`);
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
console.log('\nOK: opening, scenes, app switcher, selection, tally, command ways, install steps, nav, FAQ, copy and control names checked, with and without motion.');
