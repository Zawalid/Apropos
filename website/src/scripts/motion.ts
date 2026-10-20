// The motion layer. One timing family for the whole page (ease-out, springs only for things that land), only transform
// and opacity, everything off with reduced motion. Content is never hidden unless this script is running.

const root = document.documentElement;
const motion = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const fine = window.matchMedia('(pointer: fine)').matches;
const $ = <T extends Element>(sel: string, scope: ParentNode = document) => scope.querySelector<T>(sel);
const $$ = <T extends Element>(sel: string, scope: ParentNode = document) => [...scope.querySelectorAll<T>(sel)];

/** Runs `fn` once, the first time `el` is well into the viewport. */
function onceSeen(el: Element, fn: () => void, threshold = 0.2) {
  new IntersectionObserver(
    ([e], obs) => {
      if (!e.isIntersecting) return;
      obs.disconnect();
      fn();
    },
    { threshold, rootMargin: '0px 0px -8% 0px' },
  ).observe(el);
}

/** Wraps each word in a mask so it can rise into place. The words stay plain text for assistive tech. */
function splitWords(el: HTMLElement) {
  if (el.dataset.split) return;
  el.dataset.split = '1';
  let i = 0;
  const walk = (node: Node) => {
    for (const child of [...node.childNodes]) {
      if (child.nodeType === Node.TEXT_NODE) {
        const parts = (child.textContent ?? '').split(/(\s+)/);
        const frag = document.createDocumentFragment();
        for (const part of parts) {
          if (!part) continue;
          if (/^\s+$/.test(part)) {
            frag.append(part);
            continue;
          }
          const w = document.createElement('span');
          w.className = 'w';
          const inner = document.createElement('span');
          inner.className = 'wi';
          inner.style.setProperty('--wd', `${i++ * 45}ms`);
          inner.textContent = part;
          w.append(inner);
          frag.append(w);
        }
        child.replaceWith(frag);
      } else if (child.nodeType === Node.ELEMENT_NODE && !(child as HTMLElement).matches('.w, .visually-hidden')) {
        walk(child);
      }
    }
  };
  walk(el);
}

function countUp(el: HTMLElement) {
  const to = Number(el.textContent);
  if (!Number.isFinite(to) || to <= 0) return;
  const start = performance.now();
  const ms = 900;
  const tick = (now: number) => {
    const t = Math.min(1, (now - start) / ms);
    el.textContent = String(Math.round(to * (1 - Math.pow(1 - t, 3))));
    if (t < 1) requestAnimationFrame(tick);
  };
  el.textContent = '0';
  requestAnimationFrame(tick);
}

if (motion) {
  root.classList.add('motion-on');

  // Headlines rise word by word as they come into view; the hero's on load.
  const heads = $$<HTMLElement>('.claim, .faq-title, .f-text h3, .hero .title').filter((h) => !h.closest('[data-lit]'));
  // Story chapter titles rise each time their chapter comes on (the story script toggles .on).
  for (const h of $$<HTMLElement>('.chapter h3')) splitWords(h);
  for (const h of heads) {
    splitWords(h);
    const go = () => {
      h.classList.add('in');
      for (const c of $$<HTMLElement>('[data-count] .wi', h)) countUp(c);
    };
    if (h.closest('.hero')) requestAnimationFrame(() => setTimeout(go, 120));
    else onceSeen(h, go, 0.4);
  }

  // Blocks settle in a beat after their headline, siblings one after another.
  // Every section arrives its own way, so scrolling reads as a sequence of scenes rather than one repeated fade.
  //   selector, entrance, stagger between siblings (ms)
  const scenes: [string, string, number][] = [
    ['.section-head .lede', 'up', 0],
    // Actions: the playground wipes open left to right like a selection being made; the three kinds fan up.
    ['.lab', 'wipe', 0],
    ['.kind', 'fan', 110],
    ['.kinds + .after', 'up', 0],
    // Apps: the panel drops in from above; the dock icons pop up one after another (see the dock wave below).
    ['.sw-panels', 'drop', 0],
    ['.sw-dock button', 'pop', 45],
    ['.others', 'up', 0],
    // Your commands: the file slides in from the left, its lines typing down; the four ways come in from the right.
    ['.file', 'left', 0],
    ['.file .ln', 'line', 55],
    ['.ways li', 'right', 90],
    ['.feature:not(.flip) .f-text', 'left', 0],
    ['.feature:not(.flip) .f-win .win', 'swing-r', 0],
    ['.feature.flip .f-text', 'right', 0],
    ['.feature.flip .f-win .win', 'swing-l', 0],
    // Compare: tool icons drop onto their columns, then the table wipes open column by column.
    ['.tool .tool-mark', 'drop', 80],
    ['.wide tbody', 'wipe', 0],
    ['.narrow', 'up', 0],
    ['.legend', 'up', 0],
    // Privacy: Your Mac opens out from its middle; Nothing. lands like a stamp.
    ['.mac', 'open', 0],
    ['.outside', 'up', 0],
    ['.out-none', 'stamp', 0],
    ['.perms', 'left', 0],
    ['.pages', 'zoom', 0],
    // Install: the button rises, the steps slide in, the screen turns on.
    ['.get .pill', 'pop', 0],
    ['.step-tabs button', 'left', 90],
    ['.screen', 'boot', 0],
    ['.qs details', 'up', 50],
    ['.faq-head .search', 'up', 0],
  ];
  for (const [sel, kind, step] of scenes) {
    const all = $$<HTMLElement>(sel).filter((el) => !el.closest('.hero'));
    for (const el of all) {
      const siblings = el.parentElement ? [...el.parentElement.children].filter((s) => s.matches(sel)) : [el];
      const index = Math.max(0, siblings.indexOf(el));
      el.classList.add('rv', `rv-${kind}`);
      el.style.setProperty('--d', `${Math.min(index, 14) * step}ms`);
      // Items inside a group start when the group is seen, so a stagger plays as one gesture.
      // A fully clipped element never counts as visible, so clip reveals watch their parent instead.
      const clipped = ['wipe', 'open', 'boot'].includes(kind);
      const trigger = el.matches('.ln, .sw-dock button, .tool-mark')
        ? (el.closest('.file, .sw-dock, thead') ?? el)
        : clipped
          ? (el.parentElement ?? el)
          : el;
      onceSeen(trigger, () => el.classList.add('in'), 0.12);
    }
  }

  // Headlines arrive from different directions per section: most rise, Apps falls into place, Compare slides in.
  for (const h of $$<HTMLElement>('#apps .claim')) h.classList.add('from-top');
  for (const h of $$<HTMLElement>('#compare .claim, #install .claim')) h.classList.add('from-side');

  // Hero: the ring settles, the pearl drops into its gap, then the keys press themselves once as an invitation.
  const hero = $<HTMLElement>('[data-hero]');
  if (hero) {
    hero.classList.add('intro');
    requestAnimationFrame(() => requestAnimationFrame(() => hero.classList.add('go')));
    const keys = $$<HTMLElement>('[data-press]', hero);
    setTimeout(() => {
      keys[0]?.classList.add('down');
      setTimeout(() => keys[1]?.classList.add('down'), 140);
      setTimeout(() => keys.forEach((k) => k.classList.remove('down')), 520);
    }, 1700);
  }

  // Dock magnification, like the real Dock: icons near the pointer grow and lift.
  for (const dock of $$<HTMLElement>('.sw-dock')) {
    if (!fine) continue;
    const icons = $$<HTMLElement>('button', dock);
    dock.addEventListener('pointermove', (e) => {
      for (const b of icons) {
        const r = b.getBoundingClientRect();
        const d = Math.abs(e.clientX - (r.left + r.width / 2));
        const k = Math.max(0, 1 - d / 140);
        const s = 1 + 0.55 * k * k;
        b.style.setProperty('--mag', s.toFixed(3));
      }
    });
    dock.addEventListener('pointerleave', () => icons.forEach((b) => b.style.setProperty('--mag', '1')));
  }

  // Magnetic main buttons: they lean toward the pointer a little.
  if (fine) {
    for (const b of $$<HTMLElement>('.pill, header .get')) {
      b.addEventListener('pointermove', (e) => {
        const r = b.getBoundingClientRect();
        const x = (e.clientX - (r.left + r.width / 2)) / r.width;
        const y = (e.clientY - (r.top + r.height / 2)) / r.height;
        b.style.setProperty('--mx', `${(x * 10).toFixed(1)}px`);
        b.style.setProperty('--my', `${(y * 8).toFixed(1)}px`);
      });
      b.addEventListener('pointerleave', () => {
        b.style.setProperty('--mx', '0px');
        b.style.setProperty('--my', '0px');
      });
    }
  }

  // Compare: pointing at a column lights it from top to bottom.
  const table = $<HTMLTableElement>('.compare table');
  if (table) {
    table.addEventListener('pointerover', (e) => {
      const cell = (e.target as HTMLElement).closest('td, th');
      if (!cell || !cell.parentElement) return;
      const col = [...cell.parentElement.children].indexOf(cell);
      table.dataset.col = col > 0 ? String(col) : '';
      for (const c of $$<HTMLElement>('td, th', table)) {
        const i = c.parentElement ? [...c.parentElement.children].indexOf(c) : -1;
        c.classList.toggle('col-on', col > 0 && i === col && !c.closest('.group'));
      }
    });
    table.addEventListener('pointerleave', () => $$('.col-on', table).forEach((c) => c.classList.remove('col-on')));
    onceSeen(table, () => table.classList.add('marks-in'), 0.15);
  }
}

// Text that types itself in: used by the action playground for each new result.
export function typeIn(el: HTMLElement, text: string) {
  if (!motion || text.length > 600) {
    el.textContent = text;
    return;
  }
  el.textContent = '';
  const frag = document.createDocumentFragment();
  [...text].forEach((ch, i) => {
    const s = document.createElement('span');
    s.className = 'ch';
    s.style.setProperty('--cd', `${Math.min(i, 80) * 9}ms`);
    s.textContent = ch;
    frag.append(s);
  });
  el.append(frag);
}

export const motionOn = motion;
