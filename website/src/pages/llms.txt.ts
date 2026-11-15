import type { APIRoute } from 'astro';
import { links, site, version } from '../data/site';
import { pairing } from '../data/compare';
import { measurement } from '../data/apps';

// A short plain-text guide to the site for language models (the llms.txt convention), built from the same records
// as the pages so it cannot disagree with them.
const flat = (text: string) => text.replace(/\s+/g, ' ').replace(/\s*—\s*/g, ': ').trim();

export const GET: APIRoute = () => {
  const lines = [
    `# ${site.name}`,
    '',
    `> ${flat(site.description)} A native macOS app, open source, made by Walid Zakan.`,
    '',
    '## Key facts',
    '',
    '- What it is: a Mac app that lists every menu command of the app in front, plus actions for what you selected and your own commands, from one shortcut (Option-Space by default).',
    `- Version: ${version}, for macOS ${site.minimumMacOS} or later. An early release.`,
    '- Privacy: it runs on your Mac. This site uses no cookies and no analytics.',
    `- Source and downloads: ${links.repo} (open source). Latest release: ${links.releases}.`,
    `- Maker: Walid Zakan, a full stack developer in Rabat, Morocco (${links.author}).`,
    '',
    '## Pages',
    '',
    `- [Home](${site.url}/): what Apropos does, with the real app`,
    `- [Compare](${site.url}/compare/): how it sits next to the tools people already use`,
    ...Object.entries(pairing).map(([id, p]) => `- [${flat(p.title)}](${site.url}/compare/${id}/): ${flat(p.intro).split('. ')[0]}.`),
    ...(measurement ? [`- [Apps](${site.url}/apps/): how many menu commands Apropos found in real Mac apps`] : []),
    '',
    '## Elsewhere',
    '',
    `- [Changelog](${links.changelog})`,
    `- [Report a problem](${links.issues})`,
    '- [Portfolio of the maker](https://www.zawalid.com/projects/apropos): the case study',
    '',
  ];
  return new Response(lines.join('\n'), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
