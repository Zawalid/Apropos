import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * The context actions Apropos ships, read from the app's own pack at build time so the page lists exactly what the app
 * has: `Sources/Apropos/Resources/ActionPacks/builtin.json`.
 */
interface PackAction {
  id: string;
  title: string;
  requires: string[];
}

function readPack(): PackAction[] {
  const candidates = [
    resolve(process.cwd(), '../Sources/Apropos/Resources/ActionPacks/builtin.json'),
    resolve(process.cwd(), 'Sources/Apropos/Resources/ActionPacks/builtin.json'),
  ];
  for (const file of candidates) {
    try {
      const pack = JSON.parse(readFileSync(file, 'utf8')) as { actions: PackAction[] };
      if (pack.actions.length > 0) return pack.actions;
    } catch {
      // try the next place
    }
  }
  throw new Error('Could not read builtin.json: the context section would list actions the app may not have.');
}

const actions = readPack();

export type Holding = 'selectedText' | 'selectedFiles' | 'pageURL' | 'folder' | 'gitRepo';

export function titlesFor(kind: Holding): string[] {
  return actions.filter((a) => a.requires.includes(kind)).map((a) => a.title);
}

export const actionCount = actions.length;
