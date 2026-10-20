import type { ImageMetadata } from 'astro';

/**
 * Measured menu commands per app, written by `node scripts/harvest-apps.mjs` (apropos-probe, read only) into
 * apps.json. When the file is missing the page shows no numbers at all: it never invents them.
 */
export interface MeasuredCommand {
  path: string[];
  title: string;
  shortcut: string | null;
}

export interface MeasuredApp {
  name: string;
  bundleId: string;
  kind: 'apple' | 'native' | 'chromium' | 'jvm' | 'electron' | 'web';
  total: number;
  withShortcut: number;
  withoutShortcut: number;
  disabledNow: number;
  readMs: number;
  menus: Record<string, number>;
  commands: MeasuredCommand[];
}

export interface Measurement {
  measuredOn: string;
  mac: string;
  macOS: string;
  probe: string;
  note: string;
  apps: MeasuredApp[];
}

const files = import.meta.glob<Measurement>('./apps.json', { eager: true, import: 'default' });
export const measurement: Measurement | null = files['./apps.json'] ?? null;

const icons = import.meta.glob<ImageMetadata>('../assets/apps/*.png', { eager: true, import: 'default' });

export function slug(name: string): string {
  return name.toLowerCase().replace(/\s+/g, '-');
}

export function iconFor(name: string): ImageMetadata | undefined {
  return icons[`../assets/apps/${slug(name)}.png`];
}

/** Every app with an icon, for the wall, in the order the wall shows them. */
export const wallApps = [
  'Finder', 'Safari', 'Mail', 'Notes', 'Xcode', 'Preview', 'Calendar', 'Reminders', 'Photos', 'Music', 'TextEdit',
  'Freeform', 'Messages', 'QuickTime Player', 'Shortcuts', 'Terminal', 'Arc', 'Ghostty', 'MarkEdit', 'IINA', 'Shottr',
  'Todoist', 'Telegram', 'Google Chrome', 'Brave Browser', 'IntelliJ IDEA', 'Visual Studio Code', 'Figma', 'Notion',
  'Discord', 'Spotify',
].filter((name) => iconFor(name));

export function measured(name: string): MeasuredApp | undefined {
  return measurement?.apps.find((a) => a.name === name);
}

/** Checks that a menu item the page names really exists in the measured app; null when the app was not measured. */
export function hasCommand(app: string, title: string): boolean | null {
  const m = measured(app);
  if (!m) return null;
  const want = title.toLowerCase();
  return m.commands.some((c) => c.title.toLowerCase() === want);
}

export function fmt(n: number): string {
  return n.toLocaleString('en-US');
}
