/**
 * The comparison, checked on the web on 2026-10-20 (sources per cell, also listed in README.md). Facts about other tools
 * are kept to what their own pages or a named review say; where nothing was found, the cell says so.
 */
export type ToolId = 'apropos' | 'raycast' | 'spotlight' | 'alfred' | 'help';

export interface Tool {
  id: ToolId;
  name: string;
  short: string;
  /** One line on what it is best at, for the "keep both" framing. */
  bestAt: string;
}

export const tools: Tool[] = [
  { id: 'apropos', name: 'Apropos', short: 'Apropos', bestAt: 'What you can do in the app in front, with what you selected.' },
  { id: 'raycast', name: 'Raycast', short: 'Raycast', bestAt: 'Launching, a large extension store, clipboard, windows, snippets and AI.' },
  { id: 'spotlight', name: 'Spotlight on macOS 26 and later', short: 'Spotlight', bestAt: 'Files, apps and App Intents actions, built into macOS.' },
  { id: 'alfred', name: 'Alfred 5', short: 'Alfred', bestAt: 'Launching and file search, with deep workflows in the Powerpack.' },
  { id: 'help', name: 'The Help menu search', short: 'Help menu', bestAt: 'Finding where a command lives in the menus of one app.' },
];

/** yes: does it; some: does part of it, or only with an add-on or a paid plan; no: does not. Facts rows have none. */
export type Mark = 'yes' | 'some' | 'no';

export interface Cell {
  text: string;
  source?: string;
  mark?: Mark;
}

export interface Row {
  label: string;
  group: 'Does' | 'Setup and price';
  cells: Record<ToolId, Cell>;
}

export const sources = {
  raycastSettings: 'https://manual.raycast.com/settings',
  raycastNavigation: 'https://manual.raycast.com/navigation',
  raycastApi: 'https://developers.raycast.com/api-reference/environment',
  raycastPricing: 'https://www.raycast.com/pricing',
  raycastAi: 'https://www.raycast.com/core-features/ai',
  raycastFaq: 'https://www.raycast.com/faq',
  tahoe: 'https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/',
  spotlightKeys: 'https://support.apple.com/guide/mac-help/spotlight-keyboard-shortcuts-mh26783/mac',
  spotlightActions: 'https://support.apple.com/guide/mac-help/take-actions-and-shortcuts-in-spotlight-mchl4953dfeb/mac',
  spotlightMenus: 'https://macmost.com/using-spotlight-to-access-the-menu-bar.html',
  alfredHelp: 'https://www.alfredapp.com/help/general/',
  alfredPowerpack: 'https://www.alfredapp.com/powerpack/',
  alfredBuy: 'https://www.alfredapp.com/powerpack/buy/',
  alfredUniversal: 'https://www.alfredapp.com/universal-actions/',
  alfredMenuWorkflow: 'https://alfred.app/workflows/benziahamed/menu-bar-search',
  helpMenu: 'https://support.apple.com/en-us/102650',
  helpMenuGuide: 'https://support.apple.com/en-asia/guide/mac-help/hlpvw003/10.15/mac',
};

const s = sources;

export const rows: Row[] = [
  {
    label: 'Default key',
    group: 'Setup and price',
    cells: {
      apropos: { text: 'Option-Space, any key you like' },
      raycast: { text: 'Option-Space', source: s.raycastSettings },
      spotlight: { text: 'Command-Space', source: s.spotlightKeys },
      alfred: { text: 'Option-Space', source: s.alfredHelp },
      help: { text: 'Shift-Command-?', source: s.helpMenu },
    },
  },
  {
    label: 'Menu commands of the app in front',
    group: 'Does',
    cells: {
      apropos: { text: 'The list itself: every command, its menu path and its shortcut, as soon as it opens', mark: 'yes' },
      raycast: { text: 'Through the Search Menu Bar Items command', mark: 'yes', source: s.raycastNavigation },
      spotlight: { text: 'Mixed into results; Command-3 narrows to actions and menu items', mark: 'some', source: s.spotlightMenus },
      alfred: { text: 'With a third-party workflow, which needs the Powerpack', mark: 'some', source: s.alfredMenuWorkflow },
      help: { text: 'Search by name; it points at the item in its menu', mark: 'yes', source: s.helpMenuGuide },
    },
  },
  {
    label: 'Actions on what you selected',
    group: 'Does',
    cells: {
      apropos: { text: 'Built in for text, files, the page, the folder and git, plus your own', mark: 'yes' },
      raycast: { text: 'Extensions can read selected text and Finder items', mark: 'some', source: s.raycastApi },
      spotlight: { text: 'Some actions, such as Change Case and Translate', mark: 'some', source: s.spotlightActions },
      alfred: { text: 'Universal Actions, in the Powerpack', mark: 'some', source: s.alfredUniversal },
      help: { text: 'None', mark: 'no' },
    },
  },
  {
    label: 'Launch apps and search files',
    group: 'Does',
    cells: {
      apropos: { text: 'No, on purpose', mark: 'no' },
      raycast: { text: 'Yes', mark: 'yes', source: s.raycastPricing },
      spotlight: { text: 'Yes', mark: 'yes', source: s.tahoe },
      alfred: { text: 'Yes', mark: 'yes', source: s.alfredPowerpack },
      help: { text: 'No', mark: 'no' },
    },
  },
  {
    label: 'Clipboard history',
    group: 'Does',
    cells: {
      apropos: { text: 'No', mark: 'no' },
      raycast: { text: 'Yes; three months on the free plan', mark: 'yes', source: s.raycastPricing },
      spotlight: { text: 'Yes, once you turn it on', mark: 'yes', source: s.tahoe },
      alfred: { text: 'Yes, in the Powerpack', mark: 'some', source: s.alfredPowerpack },
      help: { text: 'No', mark: 'no' },
    },
  },
  {
    label: 'Account',
    group: 'Setup and price',
    cells: {
      apropos: { text: 'None' },
      raycast: { text: 'Not required; sync and AI need one', source: s.raycastFaq },
      spotlight: { text: 'Part of macOS' },
      alfred: { text: 'A licence key for the Powerpack', source: s.alfredBuy },
      help: { text: 'Part of macOS' },
    },
  },
  {
    label: 'Price',
    group: 'Setup and price',
    cells: {
      apropos: { text: 'Not announced yet' },
      raycast: { text: 'Free; Pro $10 a month or $96 a year', source: s.raycastPricing },
      spotlight: { text: 'Included with macOS' },
      alfred: { text: 'Free; Powerpack £34', source: s.alfredBuy },
      help: { text: 'Included with macOS' },
    },
  },
];

/** What only the comparison pages say, per tool: how to use it next to Apropos. */
export const pairing: Record<Exclude<ToolId, 'apropos' | 'help'>, { title: string; intro: string; together: string[] }> = {
  raycast: {
    title: 'Apropos and Raycast',
    intro:
      'Raycast is a launcher with a large extension store. It also has a Search Menu Bar Items command. Apropos is narrower: the list it opens is the app in front, its menus, and what you can do with your selection.',
    together: [
      'Both default to Option-Space. Keep Raycast on Command-Space, as many people do, or give Apropos another key in its Settings.',
      'Raycast stays your launcher, clipboard and window manager. Apropos never launches apps or keeps your clipboard.',
      'A Raycast quicklink can run an Apropos command: apropos://run?command=up&text={Selected Text}.',
    ],
  },
  spotlight: {
    title: 'Apropos and Spotlight',
    intro:
      'Since macOS 26, Spotlight runs actions from apps that adopted App Intents and can find menu items of the app in front, mixed in with apps and files. Apropos opens straight onto that app: its menus with their paths and shortcuts, then actions for your selection.',
    together: [
      'They use different keys, Command-Space and Option-Space, so nothing needs to change.',
      'Use Spotlight for files, apps and App Intents actions. Use Apropos for the menus of the app you are in and for your selection.',
      'Apropos learns, on your Mac, which command usually comes next, and says why.',
    ],
  },
  alfred: {
    title: 'Apropos and Alfred',
    intro:
      'Alfred is a launcher with file search, and with the Powerpack, workflows, clipboard history and Universal Actions. Menu search needs a third-party workflow. Apropos has the menus of the app in front built in.',
    together: [
      'Both default to Option-Space. Change one of them: Alfred in its General preferences, Apropos in its Settings.',
      'Alfred stays your launcher and file search. Apropos never launches apps or searches files.',
      'An Alfred workflow can open an apropos:// link to run one of your Apropos commands.',
    ],
  },
};
