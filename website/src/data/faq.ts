/** Questions people ask, with answers that stay inside what CHANGELOG.md and the docs say. Answers are HTML. */
export const faq: { q: string; a: string }[] = [
  {
    q: 'Does it replace Raycast, Alfred or Spotlight?',
    a: '<p>No. It does not launch apps, search files or keep your clipboard. Keep your launcher for those. Apropos opens on the app you are in: its menus, actions for your selection, and your own commands.</p>',
  },
  {
    q: 'Which key opens it?',
    a: '<p>Option-Space, and you can change it in Settings. Raycast and Alfred also use Option-Space by default, so if you use one of them, move one of the two to another key.</p>',
  },
  {
    q: 'Which apps does it work with?',
    a: '<p>Any app with a menu bar, from Finder and Xcode to apps built on web views. In apps built on web views it lists the menu bar, not the controls inside the window. Context actions work in any app where the selection or page can be read.</p>',
  },
  {
    q: 'Why does it need Accessibility?',
    a: '<p>To read the menus of the app in front and to press the item you choose. macOS has no other way to do that. Apropos explains this before asking, and opens the right page of System Settings.</p>',
  },
  {
    q: 'Does anything leave my Mac?',
    a: '<p>No. There is no account and no analytics, and it makes no network connections. The update check is off until you turn it on in Settings.</p>',
  },
  {
    q: 'What does it learn, and how do I make it forget?',
    a: '<p>Which commands you run, in which app and when, so it can rank them and offer what usually comes next. Never your selection, web addresses, document names or what you type. Settings, Prediction lists your habits with Forget, and Privacy and data forgets everything in one step.</p>',
  },
  {
    q: 'Can my selection run as code?',
    a: '<p>No. Values reach a command only as separate arguments, standard input or encoded link parts, never inside a script. A command definition that breaks this rule is refused when it loads, and a new command asks before its first run.</p>',
  },
  {
    q: 'Can other apps run my commands?',
    a: '<p>Yes, the ones you allow: through <code>apropos://</code> links, which work from Raycast quicklinks, Alfred and scripts, and through the Run Apropos Command action in Shortcuts. The first run asks you, once.</p>',
  },
  {
    q: 'Is recording ready?',
    a: '<p>It works and has a review step, but it is new and has not been checked enough on real Macs yet, so it is marked Early. The same goes for aliases and shortcuts on menu items. Typed text is never recorded.</p>',
  },
  {
    q: 'Which Macs does it run on?',
    a: '<p>macOS 14 Sonoma or later.</p>',
  },
];
