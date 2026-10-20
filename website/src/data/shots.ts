import type { ImageMetadata } from 'astro';

/**
 * Every picture of the app on the site is a slot with a fixed id. A slot is filled by real captures of the running app
 * (glass over the chosen wallpaper) saved as `src/assets/shots/<id>-light.png` and `<id>-dark.png` (either may be
 * missing; the other is used for both themes). An empty slot renders a neutral placeholder that names the capture it
 * waits for, so a missing picture is visible and never faked.
 */
export const slots = {
  'demo-open': { alt: 'Apropos open over Finder, listing Finder’s menu commands', want: 'panel just opened over Finder, empty search' },
  'demo-n': { alt: 'Apropos over Finder after typing n', want: 'same panel, typed "n"' },
  'demo-nf': { alt: 'Apropos over Finder after typing nf, New Folder first with its letters marked', want: 'same panel, typed "nf", New Folder first' },
  finder: { alt: 'Apropos over a Finder window with three files selected', want: 'panel over Finder with 3 files selected' },
  safari: { alt: 'Apropos over a Safari page, with page actions and Safari commands', want: 'panel over Safari on a page' },
  mail: { alt: 'Apropos over Mail with a message open', want: 'panel over Mail' },
  notes: { alt: 'Apropos over Notes with text selected', want: 'panel over Notes with a selection' },
  xcode: { alt: 'Apropos over Xcode, with Product commands and their shortcuts', want: 'panel over Xcode' },
  'usually-next': { alt: 'The Usually next group with its reason', want: 'Usually next row with its reason' },
  'send-list': { alt: 'The Send to list with Notes, Reminders and a Mail draft', want: 'Send selection to... level' },
  'sequence-draft': { alt: 'A sequence draft with three steps, each with its app icon', want: 'sequence draft level' },
  'alias-popover': { alt: 'The Command-K popover on a menu item with Alias and shortcut', want: 'Command-K popover, Alias and shortcut' },
  'recording-bar': { alt: 'The floating recording bar with the time and step count', want: 'recording bar near the top of the screen' },
  'recording-review': { alt: 'The review window after a recording, with Sturdy and Fair badges', want: 'recording review window' },
  'settings-privacy': { alt: 'Settings, Privacy and data: what Apropos keeps, with sizes and Forget', want: 'Settings > Privacy and data' },
  'menubar-popover': { alt: 'The menu bar popover with the app in front and recent commands', want: 'menu bar popover' },
} as const;

export type SlotId = keyof typeof slots;

const files = import.meta.glob<ImageMetadata>('../assets/shots/*.{png,jpg,webp}', { eager: true, import: 'default' });

function find(id: string, theme: 'light' | 'dark'): ImageMetadata | undefined {
  for (const ext of ['png', 'jpg', 'webp']) {
    const hit = files[`../assets/shots/${id}-${theme}.${ext}`] ?? files[`../assets/shots/${id}.${ext}`];
    if (hit) return hit;
  }
  return undefined;
}

export interface Shot {
  id: SlotId;
  alt: string;
  want: string;
  light?: ImageMetadata;
  dark?: ImageMetadata;
  filled: boolean;
}

export function shot(id: SlotId): Shot {
  const light = find(id, 'light');
  const dark = find(id, 'dark');
  return { id, ...slots[id], light: light ?? dark, dark: dark ?? light, filled: Boolean(light ?? dark) };
}
