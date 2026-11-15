// Tells IndexNow search engines (Bing, Yandex and the assistants that read Bing's index) about every page in the
// live sitemap. It runs after each deploy (see .github/workflows/pages.yml) and by hand:  npm run indexnow
// (add --dry-run to only print the list). Google does not use IndexNow; it reads the sitemap submitted in Search Console.
const HOST = 'apropos.zawalid.com';
const KEY = '822037b207d76a2e755feda38136c843';

const dry = process.argv.includes('--dry-run');
const res = await fetch(`https://${HOST}/sitemap.xml`);
if (!res.ok) throw new Error(`sitemap returned ${res.status}`);
const urls = [...(await res.text()).matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]).filter((u) => new URL(u).host === HOST);
console.log(`${urls.length} URLs`);
if (dry) {
  urls.forEach((u) => console.log('  ' + u));
  process.exit(0);
}
const out = await fetch('https://api.indexnow.org/IndexNow', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify({ host: HOST, key: KEY, keyLocation: `https://${HOST}/${KEY}.txt`, urlList: urls }),
});
console.log(`IndexNow answered ${out.status} ${out.statusText}`);
if (!out.ok && out.status !== 202) process.exit(1);
