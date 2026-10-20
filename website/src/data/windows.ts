import type { ImageMetadata } from 'astro';

/**
 * Real windows of the app, cut out of the stage captures by scripts/import-windows.mjs: the window alone with
 * transparent corners, so it floats on the page like it floats on a desktop. The data inside is sample data except the
 * menu commands, which are the real menu bars of the apps. A window without a light file is shown dark in both themes.
 */
export const windows = {
  'hero-open': 'Apropos open over Finder, listing Finder’s menu commands with their shortcuts',
  'hero-n': 'Apropos over Finder after typing n',
  'hero-nf': 'Apropos over Finder after typing nf: New Folder first, its letters marked',
  'deep-xcode': 'Apropos over Xcode after typing clean: Clean Build Folder first, with commands from the Debug menu below',
  'app-safari': 'Apropos over Safari after typing sidebra: Show Sidebar first',
  slip: 'Typing shwo still finds the Show commands',
  holding: 'Apropos over Safari with a page and a selection: chips for both, and Send selection to rows',
  'send-list': 'The Send selection to list: Notes, Mail draft, Reminders, Things, Obsidian, Bear, Share',
  sequence: 'A sequence draft: UPPERCASE, then Notes, with Run sequence and Save as command',
  confirm: 'A Mail draft waiting for Return, with a one-line preview of what will go',
  'usually-next': 'Usually next: two commands with the reason for each',
  'app-calendar': 'Apropos over Calendar',
  'app-finder': 'Apropos over Finder',
  'app-mail': 'Apropos over Mail',
  'app-maps': 'Apropos over Maps',
  'app-music': 'Apropos over Music',
  'app-notes': 'Apropos over Notes',
  'app-photos': 'Apropos over Photos',
  'app-preview': 'Apropos over Preview',
  'app-reminders': 'Apropos over Reminders',
  'app-systemsettings': 'Apropos over System Settings',
  'app-terminal': 'Apropos over Terminal',
  'app-textedit': 'Apropos over TextEdit',
  'app-xcode': 'Apropos over Xcode',
  'alias-popover': 'The actions of a row: Run, Add to sequence, Unpin, Hide in Finder, Alias and shortcut, Copy menu path',
  'recording-review': 'Review what you recorded: three steps in plain words with Fair and Sturdy badges, a name, an alias and a shortcut',
  'recording-permission': 'Recording needs two permissions: what each allows, why, and what is never kept',
  'privacy-page': 'Settings, Privacy and data: no network connections, permissions with reasons, what it keeps with Forget',
  'menubar-popover': 'The menu bar popover: the app in front, Pause context, Pause learning, Open Apropos and recent commands',
  'onboarding-permission': 'The welcome guide asking for Accessibility',
  'onboarding-allowed': 'The welcome guide once Accessibility is on',
  'onboarding-done': 'The last step of the welcome guide: Apropos is ready, Option-Space from any app',
} as const;

export type WindowId = keyof typeof windows;

const files = import.meta.glob<ImageMetadata>('../assets/windows/*.webp', { eager: true, import: 'default' });

export function win(id: WindowId) {
  const dark = files[`../assets/windows/${id}-dark.webp`];
  const light = files[`../assets/windows/${id}-light.webp`];
  if (!dark && !light) throw new Error(`No picture for window "${id}" in src/assets/windows`);
  return { id, alt: windows[id], dark: dark ?? light, light: light ?? null };
}
