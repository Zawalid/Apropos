// The text actions of Apropos, ported line for line from Sources/Apropos/Actions/TextTools.swift so the playground on
// the page gives the result the app gives. Each returns the new text, or null when the input does not fit (the app
// dims such an action with the reason instead of offering it).

export function words(text: string): string[] {
  const out: string[] = [];
  let current: string[] = [];
  const flush = () => {
    if (current.length) out.push(current.join(''));
    current = [];
  };
  const chars = [...text];
  const isLetter = (c: string) => /\p{L}/u.test(c);
  const isDigit = (c: string) => /\p{N}/u.test(c);
  const isUpper = (c: string) => isLetter(c) && c === c.toUpperCase() && c !== c.toLowerCase();
  const isLower = (c: string) => isLetter(c) && c === c.toLowerCase() && c !== c.toUpperCase();
  chars.forEach((c, i) => {
    if (!isLetter(c) && !isDigit(c)) {
      flush();
      return;
    }
    const last = current[current.length - 1];
    if (isUpper(c) && last) {
      const nextIsLower = i + 1 < chars.length && isLower(chars[i + 1]);
      if (isLower(last) || isDigit(last) || (isUpper(last) && nextIsLower)) flush();
    }
    current.push(c);
  });
  flush();
  return out;
}

const capitalize = (w: string) => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w);
const lines = (text: string) => {
  const parts = text.replace(/\r\n/g, '\n').split('\n');
  if (parts[parts.length - 1] === '') parts.pop();
  return parts;
};
const trim = (text: string) => text.trim();
const isMultiline = (text: string) => lines(trim(text)).length > 1;
const isJSON = (text: string) => {
  const t = trim(text);
  if (!(t.startsWith('{') || t.startsWith('['))) return false;
  try {
    JSON.parse(t);
    return true;
  } catch {
    return false;
  }
};
const isURL = (text: string) => /^https?:\/\/\S+$/i.test(trim(text));

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value as Record<string, unknown>)
        .sort()
        .map((k) => [k, sortKeys((value as Record<string, unknown>)[k])]),
    );
  }
  return value;
}

function plural(n: number, noun: string) {
  return `${n} ${noun}${n === 1 ? '' : 's'}`;
}

export interface TextAction {
  title: string;
  run: (text: string) => string | null;
  /** Why it is dimmed for this text, when it does not apply. */
  needs?: (text: string) => string | null;
  /** What happens instead of replacing the selection. */
  effect?: 'notice' | 'opens';
}

export const textActions: TextAction[] = [
  { title: 'UPPERCASE', run: (t) => t.toUpperCase() },
  { title: 'lowercase', run: (t) => t.toLowerCase() },
  { title: 'Title Case', run: (t) => t.replace(/\p{L}[\p{L}\p{N}']*/gu, capitalize) },
  { title: 'camelCase', run: (t) => words(t).map((w, i) => (i === 0 ? w.toLowerCase() : capitalize(w))).join('') },
  { title: 'snake_case', run: (t) => words(t).map((w) => w.toLowerCase()).join('_') },
  { title: 'kebab-case', run: (t) => words(t).map((w) => w.toLowerCase()).join('-') },
  { title: 'Trim whitespace', run: (t) => trim(t) },
  {
    title: 'Sort lines',
    run: (t) => lines(t).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).join('\n'),
    needs: (t) => (isMultiline(t) ? null : 'Needs more than one line'),
  },
  {
    title: 'Remove duplicate lines',
    run: (t) => [...new Set(lines(t))].join('\n'),
    needs: (t) => (isMultiline(t) ? null : 'Needs more than one line'),
  },
  {
    title: 'Join lines',
    run: (t) =>
      lines(t)
        .map((l) => l.trim())
        .filter(Boolean)
        .join(' '),
    needs: (t) => (isMultiline(t) ? null : 'Needs more than one line'),
  },
  {
    title: 'Count words and characters',
    run: (t) => `${plural(t.split(/\s+/).filter(Boolean).length, 'word')}, ${plural([...t].length, 'character')}, ${plural(lines(t).length, 'line')}`,
    effect: 'notice',
  },
  { title: 'Wrap in quotes', run: (t) => `“${trim(t)}”` },
  { title: 'Wrap as code block', run: (t) => '```\n' + t.replace(/^\n+|\n+$/g, '') + '\n```' },
  {
    title: 'Markdown quote',
    run: (t) =>
      lines(trim(t))
        .map((l) => (l ? `> ${l}` : '>'))
        .join('\n'),
  },
  { title: 'URL encode', run: (t) => encodeURIComponent(t) },
  {
    title: 'URL decode',
    run: (t) => {
      try {
        return decodeURIComponent(t);
      } catch {
        return null;
      }
    },
  },
  { title: 'Base64 encode', run: (t) => btoa(String.fromCharCode(...new TextEncoder().encode(t))) },
  {
    title: 'Base64 decode',
    run: (t) => {
      try {
        let c = t.replace(/\s/g, '').replace(/-/g, '+').replace(/_/g, '/');
        c += '='.repeat((4 - (c.length % 4)) % 4);
        return new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob(c), (ch) => ch.charCodeAt(0)));
      } catch {
        return null;
      }
    },
  },
  {
    title: 'Format JSON',
    run: (t) => JSON.stringify(sortKeys(JSON.parse(trim(t))), null, 2),
    needs: (t) => (isJSON(t) ? null : 'Needs JSON'),
  },
  {
    title: 'Minify JSON',
    run: (t) => JSON.stringify(sortKeys(JSON.parse(trim(t)))),
    needs: (t) => (isJSON(t) ? null : 'Needs JSON'),
  },
  { title: 'Search the web', run: (t) => `Searches the web for “${trim(t)}”`, effect: 'opens' },
  {
    title: 'Open as link',
    run: (t) => `Opens ${trim(t)}`,
    needs: (t) => (isURL(t) ? null : 'Needs a web address'),
    effect: 'opens',
  },
];
