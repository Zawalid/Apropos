// Measures the menu commands of real apps with apropos-probe (read only, it presses nothing) and writes
// src/data/apps.json, which the gap section, the app wall and the /apps/ explorer read.
//
//   node scripts/harvest-apps.mjs            measure the listed apps that are running now
//   node scripts/harvest-apps.mjs --launch   also open the listed apps that are not running, hidden and in the
//                                            background (open -gj), measure them, then quit only those it opened
//
// The terminal that runs it needs Accessibility (System Settings > Privacy & Security > Accessibility), the same as
// the probe. Titles under menus that can hold your own content (History, Bookmarks, Open Recent, the window list,
// mailboxes, playlists) are counted but never written to the file. Review the JSON before committing it.
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const site = resolve(here, '..');
const repo = resolve(site, '..');
const out = join(site, 'src/data/apps.json');
const launch = process.argv.includes('--launch');

// name, path, kind. Kind is how the app is built, so the page never claims more than the menu bar for web shells.
const apps = [
  ['Finder', '/System/Library/CoreServices/Finder.app', 'apple'],
  ['Safari', '/Applications/Safari.app', 'apple'],
  ['Mail', '/System/Applications/Mail.app', 'apple'],
  ['Notes', '/System/Applications/Notes.app', 'apple'],
  ['Preview', '/System/Applications/Preview.app', 'apple'],
  ['Xcode', '/Applications/Xcode.app', 'apple'],
  ['Calendar', '/System/Applications/Calendar.app', 'apple'],
  ['Reminders', '/System/Applications/Reminders.app', 'apple'],
  ['Photos', '/System/Applications/Photos.app', 'apple'],
  ['Music', '/System/Applications/Music.app', 'apple'],
  ['TextEdit', '/System/Applications/TextEdit.app', 'apple'],
  ['Freeform', '/System/Applications/Freeform.app', 'apple'],
  ['Messages', '/System/Applications/Messages.app', 'apple'],
  ['QuickTime Player', '/System/Applications/QuickTime Player.app', 'apple'],
  ['Shortcuts', '/System/Applications/Shortcuts.app', 'apple'],
  ['Terminal', '/System/Applications/Utilities/Terminal.app', 'apple'],
  ['Arc', '/Applications/Arc.app', 'native'],
  ['Ghostty', '/Applications/Ghostty.app', 'native'],
  ['MarkEdit', '/Applications/MarkEdit.app', 'native'],
  ['IINA', '/Applications/IINA.app', 'native'],
  ['Shottr', '/Applications/Shottr.app', 'native'],
  ['Todoist', '/Applications/Todoist.app', 'native'],
  ['Telegram', '/Applications/Telegram.app', 'native'],
  ['Google Chrome', '/Applications/Google Chrome.app', 'chromium'],
  ['Brave Browser', '/Applications/Brave Browser.app', 'chromium'],
  ['IntelliJ IDEA', '/Applications/IntelliJ IDEA.app', 'jvm'],
  ['Visual Studio Code', '/Applications/Visual Studio Code.app', 'electron'],
  ['Figma', '/Applications/Figma.app', 'electron'],
  ['Notion', '/Applications/Notion.app', 'electron'],
  ['Discord', '/Applications/Discord.app', 'electron'],
  ['Spotify', '/Applications/Spotify.app', 'web'],
];

// Menus whose items are the person's own content. Counted, never listed.
const privateMenus = new Set([
  'History', 'Bookmarks', 'Favorites', 'Favourites', 'Open Recent', 'Recent Items', 'Recent', 'Recently Closed',
  'Recently Closed Tabs', 'Window', 'Mailbox', 'Move To', 'Copy To', 'Move to', 'Copy to', 'Playlists', 'Profiles',
  'Spaces', 'Accounts', 'Open With', 'Share', 'Tags', 'Services',
]);

function bundleID(path) {
  try {
    return execFileSync('defaults', ['read', join(path, 'Contents/Info'), 'CFBundleIdentifier'], { encoding: 'utf8' }).trim();
  } catch {
    return null;
  }
}

function running(id) {
  const r = spawnSync('osascript', ['-e', `application id "${id}" is running`], { encoding: 'utf8' });
  return r.stdout.trim() === 'true';
}

const probe = join(repo, '.build/debug/apropos-probe');
execFileSync('swift', ['build', '--product', 'apropos-probe'], { cwd: repo, stdio: 'inherit' });

function measure(id) {
  const r = spawnSync(probe, [id], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  const lines = r.stdout.split('\n').filter(Boolean);
  const head = lines.shift() ?? '';
  const m = head.match(/: (\d+) commands in (\d+) ms/);
  if (!m) return { error: head || r.stderr.trim() };
  const items = lines.map((line) => {
    const disabled = line.includes(' [disabled]');
    const checked = line.includes(' [checked]');
    const clean = line.replace(' [disabled]', '').replace(' [checked]', '');
    const [trail, rest = ''] = clean.split(' › ').length > 1
      ? [clean.slice(0, clean.lastIndexOf(' › ')), clean.slice(clean.lastIndexOf(' › ') + 3)]
      : ['', clean];
    const [title, shortcut] = rest.split('  ');
    const path = trail.split(' › ').filter(Boolean);
    return { path, title, shortcut: shortcut?.trim() || null, disabled, checked };
  });
  return { total: Number(m[1]), readMs: Number(m[2]), items };
}

const launched = [];
const result = [];
for (const [name, path, kind] of apps) {
  if (!existsSync(path)) continue;
  const id = bundleID(path);
  if (!id) continue;
  if (!running(id)) {
    if (!launch) {
      console.log(`skip ${name}: not running`);
      continue;
    }
    spawnSync('open', ['-gj', '-a', path]);
    launched.push(id);
    await new Promise((r) => setTimeout(r, 6000));
  }
  const m = measure(id);
  if (m.error) {
    console.log(`skip ${name}: ${m.error}`);
    continue;
  }
  const withShortcut = m.items.filter((i) => i.shortcut).length;
  const menus = {};
  for (const i of m.items) {
    const top = i.path[0] ?? 'Menu';
    menus[top] = (menus[top] ?? 0) + 1;
  }
  const listed = m.items
    .filter((i) => !i.path.some((p) => privateMenus.has(p)))
    .map(({ path, title, shortcut }) => ({ path, title, shortcut }));
  result.push({
    name,
    bundleId: id,
    kind,
    total: m.total,
    withShortcut,
    withoutShortcut: m.total - withShortcut,
    disabledNow: m.items.filter((i) => i.disabled).length,
    readMs: m.readMs,
    menus,
    commands: listed,
  });
  console.log(`${name}: ${m.total} commands, ${withShortcut} with a shortcut, read in ${m.readMs} ms`);
}

for (const id of launched) spawnSync('osascript', ['-e', `tell application id "${id}" to quit`]);

const hw = execFileSync('sysctl', ['-n', 'hw.model'], { encoding: 'utf8' }).trim();
const chip = execFileSync('sysctl', ['-n', 'machdep.cpu.brand_string'], { encoding: 'utf8' }).trim();
const macos = execFileSync('sw_vers', ['-productVersion'], { encoding: 'utf8' }).trim();
const commit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: repo, encoding: 'utf8' }).trim();
const previous = existsSync(out) ? JSON.parse(readFileSync(out, 'utf8')) : null;

const data = {
  measuredOn: new Date().toISOString().slice(0, 10),
  mac: `${hw}, ${chip}`,
  macOS: macos,
  probe: `apropos-probe at ${commit}, menu bar only, read only`,
  note: 'Counts are what the panel lists for the app as it was open at the time: menus change with the window and selection. Titles under menus that hold personal content are counted, never listed.',
  apps: result,
};
if (result.length === 0 && previous) {
  console.log('nothing measured, kept the previous file');
} else {
  writeFileSync(out, JSON.stringify(data, null, 1) + '\n');
  console.log(`wrote ${out} with ${result.length} apps`);
}
