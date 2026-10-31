// Checks the basics of every page of the built site: one h1, sensible title and description, a correct canonical, valid
// structured data, alt text, working internal links, a share image that loads, robots.txt and the sitemap. It also
// scans the visible text for em dashes and emojis, and checks that nothing scrolls sideways at 375px.
//   npm run build && npx astro preview --port 4321 &   then   node scripts/check-seo.mjs [http://localhost:4321]
import { chromium } from 'playwright-core';

const origin = 'https://apropos.zawalid.com';
const base = (process.argv[2] ?? 'http://localhost:4321').replace(/\/$/, '');
const problems = [];
const note = (page, message) => problems.push(`${page}: ${message}`);

const sitemap = await (await fetch(`${base}/sitemap.xml`)).text();
const robots = await (await fetch(`${base}/robots.txt`)).text();
if (!robots.includes(`Sitemap: ${origin}/sitemap.xml`)) note('robots.txt', 'does not point at the sitemap');
const pages = [...sitemap.matchAll(/<loc>https:\/\/apropos\.zawalid\.com(\/[^<]*)<\/loc>/g)].map((m) => m[1]);
if (pages.length < 1) note('sitemap.xml', 'lists no pages');

const emoji = /\p{Emoji_Presentation}/u;
const browser = await chromium.launch({ channel: 'chrome' });
const seenLinks = new Set();
for (const path of pages) {
  const page = await browser.newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 120)); });
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 120)));
  const response = await page.goto(base + path, { waitUntil: 'networkidle' });
  if (response?.status() !== 200) note(path, `status ${response?.status()}`);
  const info = await page.evaluate(() => ({
    title: document.title,
    description: document.querySelector('meta[name="description"]')?.content ?? '',
    canonical: document.querySelector('link[rel="canonical"]')?.href ?? '',
    h1: [...document.querySelectorAll('h1')].map((h) => h.textContent.trim()),
    og: document.querySelector('meta[property="og:image"]')?.content ?? '',
    twitter: document.querySelector('meta[name="twitter:image"]')?.content ?? '',
    twitterCard: document.querySelector('meta[name="twitter:card"]')?.content ?? '',
    robots: document.querySelector('meta[name="robots"]')?.content ?? '',
    lang: document.documentElement.lang,
    noAlt: [...document.querySelectorAll('img:not([alt])')].length,
    jsonld: [...document.querySelectorAll('script[type="application/ld+json"]')].map((s) => s.textContent),
    links: [...document.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')).filter((h) => h.startsWith('/') && !h.startsWith('//')),
    hashes: [...document.querySelectorAll('a[href^="#"]')].map((a) => a.getAttribute('href')).filter((h) => h.length > 1),
    ids: [...document.querySelectorAll('[id]')].map((e) => e.id),
    text: document.body.innerText + ' ' + document.title + ' ' + (document.querySelector('meta[name="description"]')?.content ?? ''),
    source: document.documentElement.outerHTML,
  }));
  if (info.title.length < 15 || info.title.length > 60) note(path, `title is ${info.title.length} characters: "${info.title}"`);
  if (info.description.length < 80 || info.description.length > 165) note(path, `description is ${info.description.length} characters`);
  if (info.canonical !== origin + path) note(path, `canonical is ${info.canonical}`);
  if (info.h1.length !== 1) note(path, `has ${info.h1.length} h1 elements`);
  if (!/index/.test(info.robots) || /noindex/.test(info.robots)) note(path, `robots meta is "${info.robots}"`);
  if (info.lang !== 'en') note(path, `html lang is "${info.lang}"`);
  if (info.noAlt) note(path, `${info.noAlt} images without an alt attribute`);
  if (info.twitterCard !== 'summary_large_image') note(path, `twitter:card is "${info.twitterCard}"`);
  if (info.og !== info.twitter) note(path, 'og:image and twitter:image differ');
  let hasApp = false;
  for (const text of info.jsonld) {
    try { if (JSON.parse(text)['@type'] === 'SoftwareApplication') hasApp = true; } catch { note(path, 'structured data does not parse'); }
  }
  if (!hasApp) note(path, 'no SoftwareApplication structured data');
  const image = await fetch(info.og.replace(origin, base));
  if (!image.ok) note(path, `share image ${info.og} answers ${image.status}`);
  for (const link of info.links) seenLinks.add(link.split('#')[0] || '/');
  for (const hash of info.hashes) if (!info.ids.includes(hash.slice(1))) note(path, `in-page link ${hash} has no target`);
  if (info.text.includes('—') || info.text.includes('–')) note(path, 'a dash character (em or en) appears in the text');
  if (emoji.test(info.text)) note(path, 'an emoji appears in the text');
  if (info.source.includes('—')) note(path, 'an em dash appears in the HTML');
  if (errors.length) note(path, `console errors: ${errors.join(' | ')}`);
  console.log(`${path}  title(${info.title.length}) description(${info.description.length}) h1="${info.h1[0]}"`);
  await page.close();
}

// Mobile: nothing may scroll sideways.
for (const path of pages) {
  const context = await browser.newContext({ viewport: { width: 375, height: 812 }, hasTouch: true });
  const page = await context.newPage();
  await page.goto(base + path, { waitUntil: 'networkidle' });
  const widths = await page.evaluate(() => ({ scroll: document.documentElement.scrollWidth, client: document.documentElement.clientWidth }));
  if (widths.scroll > widths.client) note(path, `scrolls sideways at 375px (${widths.scroll} > ${widths.client})`);
  await context.close();
}

for (const link of seenLinks) {
  const response = await fetch(base + link, { redirect: 'follow' });
  if (!response.ok) note(link, `internal link answers ${response.status}`);
}
const missing = await fetch(`${base}/this-page-does-not-exist/`);
if (missing.status !== 404) note('404', `an unknown address answers ${missing.status}`);
await browser.close();

if (problems.length) {
  console.log(`\n${problems.length} problem(s):`);
  for (const p of problems) console.log(' - ' + p);
  process.exit(1);
}
console.log(`\nOK: ${pages.length} page(s) and ${seenLinks.size} internal link(s) checked.`);
