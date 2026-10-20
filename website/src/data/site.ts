import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * The version of the app, read from its own project file so the site never disagrees with it. The build runs from the
 * website folder, so that path is tried first.
 */
function readVersion(): string {
  const candidates = [
    resolve(process.cwd(), '../App/project.yml'),
    resolve(process.cwd(), 'App/project.yml'),
    fileURLToPath(new URL('../../../App/project.yml', import.meta.url)),
  ];
  for (const file of candidates) {
    try {
      const match = readFileSync(file, 'utf8').match(/MARKETING_VERSION:\s*(\S+)/);
      if (match?.[1]) return match[1];
    } catch {
      // try the next place
    }
  }
  throw new Error('Could not read MARKETING_VERSION from App/project.yml: the site would show the wrong version.');
}

export const version = readVersion();

// TODO(owner): confirm the repository name. The download link below uses the latest release asset pattern.
const repo = 'https://github.com/Zawalid/Apropos';

export const links = {
  repo,
  releases: `${repo}/releases`,
  download: `${repo}/releases/latest/download/Apropos.dmg`,
  changelog: `${repo}/blob/main/CHANGELOG.md`,
  issues: `${repo}/issues`,
  design: `${repo}/blob/main/docs/design.md`,
  safetyDoc: `${repo}/blob/main/docs/context-actions.md#safety-rules`,
  author: 'https://zawalid.com',
  github: 'https://github.com/Zawalid',
  x: 'https://x.com/Zawaalid',
};

export const site = {
  name: 'Apropos',
  url: 'https://apropos.zawalid.com',
  title: 'Apropos: a Mac command palette that fits the moment',
  description:
    'Press Option-Space in any Mac app. Apropos lists that app’s menu commands, actions for what you selected and your own commands. Local, private, native.',
  /** The day the page last changed in a way worth telling a search engine about. */
  updated: '2026-10-20',
};
