// Everything that moves or answers on the page. Only transform and opacity are animated. With reduced motion the
// page stays complete and readable: no flight, no lighting words, no wall, the same tabs and dialog.

const root = document.documentElement;
const motion = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
if (motion) root.classList.add('js-motion');

const $ = <T extends Element>(sel: string, scope: ParentNode = document) => scope.querySelector<T>(sel);
const $$ = <T extends Element>(sel: string, scope: ParentNode = document) => [...scope.querySelectorAll<T>(sel)];
const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);

/** Calls every scroll-linked updater once per frame, only while something scrolled or resized. */
const onFrame: Array<() => void> = [];
let queued = false;
function schedule() {
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => {
    queued = false;
    for (const fn of onFrame) fn();
  });
}
window.addEventListener('scroll', schedule, { passive: true });
window.addEventListener('resize', schedule);

// Header: a hairline once the page moves, the small download pill once the hero's own button is gone.
const hero = $<HTMLElement>('[data-hero]');
onFrame.push(() => root.classList.toggle('scrolled', window.scrollY > 4));
const heroCta = $('[data-hero-cta]');
if (heroCta) {
  new IntersectionObserver(([e]) => root.classList.toggle('past-hero', !e.isIntersecting && e.boundingClientRect.top < 0)).observe(heroCta);
} else {
  root.classList.add('past-hero');
}

// Section nav: the pearl marks the section you are reading and glides to the next one.
const navLinks = $$<HTMLAnchorElement>('[data-nav] a');
const bead = $<HTMLElement>('[data-nav-bead]');
const navList = $<HTMLElement>('[data-nav]');
const sections = navLinks
  .map((a) => document.getElementById(a.dataset.for ?? ''))
  .filter((s): s is HTMLElement => s !== null);
let current = '';
function placeBead() {
  if (!bead || !navList) return;
  // Before the first section, the pearl waits at the first link.
  const link = navLinks.find((a) => a.dataset.for === current) ?? navLinks[0];
  if (!link) return;
  const navBox = bead.parentElement?.getBoundingClientRect();
  const box = link.getBoundingClientRect();
  if (!navBox) return;
  bead.style.setProperty('--x', `${box.left + box.width / 2 - navBox.left}px`);
}
onFrame.push(() => {
  const line = window.innerHeight * 0.35;
  let found = '';
  for (const s of sections) if (s.getBoundingClientRect().top <= line) found = s.id;
  if (found !== current) {
    current = found;
    for (const a of navLinks) a.setAttribute('aria-current', String(a.dataset.for === current));
    placeBead();
  }
  if (!hero) root.classList.toggle('docked', current !== '');
});
navList?.addEventListener('scroll', placeBead, { passive: true });
window.addEventListener('resize', placeBead);
placeBead();

// Hero: the ring tilts toward the pointer; the pearl leaves its gap as you scroll and docks in the section nav.
const tilt = $<HTMLElement>('[data-ring="hero"] [data-tilt]');
const pearl = $<HTMLElement>('[data-pearl="hero"]');
if (hero && tilt && motion && window.matchMedia('(pointer: fine)').matches) {
  hero.addEventListener('pointermove', (e) => {
    const r = tilt.getBoundingClientRect();
    const x = clamp((e.clientX - (r.left + r.width / 2)) / (window.innerWidth / 2), -1, 1);
    const y = clamp((e.clientY - (r.top + r.height / 2)) / (window.innerHeight / 2), -1, 1);
    tilt.style.setProperty('--rx', `${(-y * 9).toFixed(2)}deg`);
    tilt.style.setProperty('--ry', `${(x * 12).toFixed(2)}deg`);
    if (pearl && !pearl.dataset.flying) {
      pearl.style.setProperty('--px', `${(x * 14).toFixed(1)}px`);
      pearl.style.setProperty('--py', `${(y * 10).toFixed(1)}px`);
    }
  });
  hero.addEventListener('pointerleave', () => {
    tilt.style.setProperty('--rx', '0deg');
    tilt.style.setProperty('--ry', '0deg');
    pearl?.style.setProperty('--px', '0px');
    pearl?.style.setProperty('--py', '0px');
  });
}

if (hero && pearl && bead && motion) {
  onFrame.push(() => {
    const navShown = bead.parentElement && getComputedStyle(bead.parentElement).display !== 'none';
    const span = hero.offsetHeight * 0.7;
    const p = clamp(window.scrollY / span);
    if (p === 0) {
      delete pearl.dataset.flying;
      pearl.style.opacity = '';
      root.classList.toggle('docked', false);
      return;
    }
    pearl.dataset.flying = '1';
    // Where the pearl sits without its transform (measured from the ring, which never moves it), and where the bead is.
    const ringBox = (pearl.offsetParent as HTMLElement | null)?.getBoundingClientRect();
    if (!ringBox) return;
    const from = {
      left: ringBox.left + pearl.offsetLeft,
      top: ringBox.top + pearl.offsetTop,
      width: pearl.offsetWidth,
      height: pearl.offsetHeight,
    };
    const t = easeOut(p);
    if (!navShown) {
      pearl.style.setProperty('--px', '0px');
      pearl.style.setProperty('--py', `${(-t * 40).toFixed(1)}px`);
      pearl.style.setProperty('--ps', `${(1 - t * 0.4).toFixed(3)}`);
      pearl.style.opacity = String(1 - t);
      root.classList.toggle('docked', false);
      return;
    }
    const to = bead.getBoundingClientRect();
    const fx = from.left + from.width / 2;
    const fy = from.top + from.height / 2;
    const tx = to.left + to.width / 2;
    const ty = to.top + to.height / 2;
    // The pearl image carries its glow, so its sphere is about 45% of its box.
    const endScale = (to.width * 2.4) / from.width;
    pearl.style.setProperty('--px', `${((tx - fx) * t).toFixed(1)}px`);
    pearl.style.setProperty('--py', `${((ty - fy) * t).toFixed(1)}px`);
    pearl.style.setProperty('--ps', `${(1 + (endScale - 1) * t).toFixed(4)}`);
    const landed = p >= 0.98;
    pearl.style.opacity = landed ? '0' : '1';
    root.classList.toggle('docked', landed);
  });
}
if (!motion || !pearl) {
  onFrame.push(() => root.classList.toggle('docked', current !== ''));
}

// The demo: Option-Space, or the keys on the page, open captured frames of the real panel over the page.
const demo = $<HTMLDialogElement>('[data-demo]');
if (demo) {
  const frames = $$<HTMLElement>('[data-frame]', demo);
  const sr = $<HTMLElement>('[data-demo-sr]', demo);
  const caps = $$<HTMLElement>('[data-cap]', demo);
  const script = 'nf';
  let typed = '';
  const show = (i: number) => frames.forEach((f, n) => f.classList.toggle('on', n === i));
  // The key caps under the panel are the instructions: the next key stands out, typed keys stay pressed.
  const paint = () => {
    caps.forEach((c, i) => {
      c.classList.toggle('done', i < typed.length);
      c.classList.toggle('next', i === typed.length);
    });
    if (sr) {
      sr.textContent =
        typed.length === 0
          ? 'Type n then f, the first letters of New Folder.'
          : typed.length < script.length
            ? 'Typed n. Now f.'
            : 'Typed nf: New Folder is first. In the app, Return would run it.';
    }
  };
  const type = (letter: string) => {
    if (script[typed.length] !== letter) return;
    typed += letter;
    show(typed.length);
    paint();
  };
  const reset = () => {
    typed = '';
    show(0);
    paint();
  };
  const open = () => {
    if (demo.open) return;
    reset();
    demo.showModal();
  };
  caps.forEach((c) => c.addEventListener('click', () => type(c.dataset.cap ?? '')));
  for (const b of $$('[data-demo-open]')) b.addEventListener('click', open);
  $('[data-demo-close]', demo)?.addEventListener('click', () => demo.close());
  demo.addEventListener('click', (e) => {
    if (e.target === demo) demo.close();
  });
  // The frames sit in a closed dialog, so they would only start loading on the first press. Warm them up once the page
  // is idle, so the panel appears at once like the real one.
  const warm = () => $$<HTMLImageElement>('img', demo).forEach((img) => (img.loading = 'eager'));
  if ('requestIdleCallback' in window) window.requestIdleCallback(warm, { timeout: 4000 });
  else window.setTimeout(warm, 2500);
  const keys = $$<HTMLElement>('[data-press]');
  document.addEventListener('keydown', (e) => {
    if (e.altKey && e.code === 'Space' && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      for (const k of keys) k.classList.add('down');
      setTimeout(() => keys.forEach((k) => k.classList.remove('down')), 140);
      if (demo.open) demo.close();
      else open();
      return;
    }
    if (!demo.open || e.metaKey || e.ctrlKey || e.altKey) return;
    const letter = e.key.toLowerCase();
    if (letter.length === 1) type(letter);
  });
}

// Words that light as you read them, in the gap statement.
const lit = $<HTMLElement>('[data-lit]');
if (lit && motion) {
  const words = $$<HTMLElement>('span', lit);
  onFrame.push(() => {
    const r = lit.getBoundingClientRect();
    const vh = window.innerHeight;
    // Off screen the words stay lit, so the statement never sits at low contrast where nobody is reading it.
    if (r.top > vh || r.bottom < 0) {
      words.forEach((w) => w.classList.add('on'));
      return;
    }
    const p = clamp((vh * 0.85 - r.top) / (r.height + vh * 0.35));
    const n = Math.round(p * words.length);
    words.forEach((w, i) => w.classList.toggle('on', i < n));
  });
}

// The wall of menu titles folds into one field.
const wall = $<HTMLElement>('[data-wall]');
if (wall && motion) {
  onFrame.push(() => {
    const r = wall.getBoundingClientRect();
    const run = r.height - window.innerHeight;
    const p = clamp(-r.top / Math.max(run, 1));
    wall.style.setProperty('--p', p.toFixed(3));
  });
}

// The story: the chapter whose share of the track you are in is on, its pane shows, and the pearl moves down the rail.
const story = $<HTMLElement>('[data-story]');
if (story) {
  const track = $<HTMLElement>('.track', story);
  const chapters = $$<HTMLElement>('[data-chapter]', story);
  const panes = $$<HTMLElement>('[data-pane]', story);
  const bead = $<HTMLElement>('[data-story-bead]', story);
  let last = -1;
  const place = (at: number) => {
    if (!bead?.parentElement) return;
    const run = bead.parentElement.clientHeight;
    bead.style.setProperty('--y', `${((run * at) / Math.max(chapters.length - 1, 1)).toFixed(1)}px`);
  };
  onFrame.push(() => {
    if (!track) return;
    const box = track.getBoundingClientRect();
    const run = box.height - (window.innerHeight - 64);
    const p = clamp(-box.top / Math.max(run, 1), 0, 0.9999);
    const at = Math.floor(p * chapters.length);
    if (at === last) return;
    last = at;
    chapters.forEach((c, i) => c.classList.toggle('on', i === at));
    panes.forEach((c, i) => c.classList.toggle('on', i === at));
    place(at);
  });
  window.addEventListener('resize', () => {
    last = -1;
  });
}

// Selected text tile: the same words, turned by one action after another, while it is on screen.
const turns = $<HTMLElement>('[data-turns]');
if (turns && motion) {
  const rows = $$<HTMLElement>('[data-turn]', turns);
  let i = 1;
  let timer = 0;
  const tick = () => {
    i = (i + 1) % rows.length;
    rows.forEach((r, n) => r.classList.toggle('on', n === i));
  };
  new IntersectionObserver(([e]) => {
    window.clearInterval(timer);
    if (e.isIntersecting) timer = window.setInterval(tick, 1700);
  }).observe(turns);
}

// Tabs: the dock of apps and the measured app picker. Arrow keys move between tabs, as in a real tab list.
for (const group of $$<HTMLElement>('[data-tabs], [data-explorer], [data-switcher], [data-stepper]')) {
  const tabs = $$<HTMLButtonElement>('[data-tab]', group);
  const panels = $$<HTMLElement>('[data-panel]', group);
  const select = (i: number, focus = false) => {
    tabs.forEach((t, n) => {
      t.setAttribute('aria-selected', String(n === i));
      t.tabIndex = n === i ? 0 : -1;
    });
    panels.forEach((p, n) => (p.hidden = n !== i));
    if (focus) tabs[i]?.focus();
  };
  tabs.forEach((t, i) => {
    t.addEventListener('click', () => {
      group.dataset.touched = '1';
      select(i);
    });
    t.addEventListener('keydown', (e) => {
      const keys: Record<string, number> = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
      group.dataset.touched = '1';
      if (e.key in keys) {
        e.preventDefault();
        select((i + keys[e.key] + tabs.length) % tabs.length, true);
      } else if (e.key === 'Home') {
        e.preventDefault();
        select(0, true);
      } else if (e.key === 'End') {
        e.preventDefault();
        select(tabs.length - 1, true);
      }
    });
  });
  // The app switcher and the install steps move on by themselves while on screen, until someone picks one.
  if (motion && (group.matches('[data-switcher]') || group.matches('[data-stepper]'))) {
    const every = group.matches('[data-stepper]') ? 3200 : 2200;
    let timer = 0;
    let hover = false;
    group.addEventListener('pointerenter', () => (hover = true));
    group.addEventListener('pointerleave', () => (hover = false));
    const tick = () => {
      if (hover || group.dataset.touched || group.contains(document.activeElement)) return;
      const at = tabs.findIndex((t) => t.getAttribute('aria-selected') === 'true');
      select((at + 1) % tabs.length);
    };
    new IntersectionObserver(([e]) => {
      window.clearInterval(timer);
      if (e.isIntersecting) timer = window.setInterval(tick, every);
    }, { threshold: 0.4 }).observe(group);
  }
}

// Copy buttons.
for (const b of $$<HTMLButtonElement>('[data-copy]')) {
  b.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(b.dataset.copy ?? '');
      b.textContent = 'Copied';
    } catch {
      b.textContent = 'Select and copy';
    }
    setTimeout(() => (b.textContent = 'Copy'), 1600);
  });
}

// A page taller than the screen scrolls inside its window while the window crosses the viewport.
for (const frame of $$<HTMLElement>('[data-scroll-page]')) {
  const inner = frame.firstElementChild as HTMLElement | null;
  if (!inner || !motion) continue;
  onFrame.push(() => {
    const box = frame.getBoundingClientRect();
    const vh = window.innerHeight;
    if (box.bottom < 0 || box.top > vh) return;
    const p = clamp((vh - box.top) / (vh + box.height));
    const room = inner.offsetHeight - frame.clientHeight;
    inner.style.setProperty('--scroll', `${(-room * clamp((p - 0.15) / 0.7)).toFixed(1)}px`);
  });
}

// Windows that drift at their own pace as the page scrolls, so overlapping windows read as layers.
if (motion) {
  for (const el of $$<HTMLElement>('[data-drift]')) {
    const rate = Number(el.dataset.drift) || 0;
    onFrame.push(() => {
      // Measured on the parent, which does not move, so the drift never feeds back into itself.
      const box = (el.parentElement ?? el).getBoundingClientRect();
      if (box.bottom < -200 || box.top > window.innerHeight + 200) return;
      const off = box.top + box.height / 2 - window.innerHeight / 2;
      el.style.setProperty('--drift', `${(off * rate).toFixed(1)}px`);
    });
  }
}

// The shortcut tile presses its keys once when it comes into view.
const keyTile = $<HTMLElement>('[data-keys]');
if (keyTile && motion) {
  new IntersectionObserver(
    ([e], obs) => {
      if (!e.isIntersecting) return;
      obs.disconnect();
      setTimeout(() => keyTile.classList.add('down'), 300);
      setTimeout(() => keyTile.classList.remove('down'), 520);
    },
    { threshold: 0.8 },
  ).observe(keyTile);
}

// Questions: each answer slides open and closed instead of jumping. The details element keeps its native behaviour
// (keyboard, find in page, no script); the script only animates the height between the two states and fades the answer.
// With reduced motion it opens at once.
const accordionMs = 260;
for (const item of $$<HTMLDetailsElement>('details[data-q]')) {
  const summary = $<HTMLElement>('summary', item);
  const answer = $<HTMLElement>('.a', item);
  if (!summary || !answer) continue;
  let running: Animation | null = null;
  let fade: Animation | null = null;
  summary.addEventListener('click', (e) => {
    if (!motion) return;
    e.preventDefault();
    const opening = !item.open || item.dataset.closing === '1';
    const from = item.getBoundingClientRect().height;
    running?.cancel();
    if (opening) {
      delete item.dataset.closing;
      item.open = true;
    }
    const to = opening ? summary.offsetHeight + answer.offsetHeight : summary.offsetHeight;
    if (!opening) item.dataset.closing = '1';
    item.style.overflow = 'hidden';
    running = item.animate([{ height: `${from}px` }, { height: `${to}px` }], {
      duration: accordionMs,
      easing: 'cubic-bezier(0.23, 1, 0.32, 1)',
    });
    fade?.cancel();
    fade = answer.animate(
      opening
        ? [{ opacity: 0, transform: 'translateY(-6px)' }, { opacity: 1, transform: 'none' }]
        : [{ opacity: 1 }, { opacity: 0 }],
      { duration: opening ? accordionMs : accordionMs * 0.6, easing: 'ease-out', fill: 'forwards' },
    );
    running.onfinish = () => {
      running = null;
      item.style.overflow = '';
      if (item.dataset.closing === '1') {
        delete item.dataset.closing;
        item.open = false;
      }
      fade?.cancel();
      fade = null;
    };
  });
}

// Questions: filter as you type.
const faq = $<HTMLElement>('[data-faq]');
if (faq) {
  const input = $<HTMLInputElement>('[data-faq-search]', faq);
  const qs = $$<HTMLDetailsElement>('[data-q]', faq);
  const none = $<HTMLElement>('[data-faq-none]', faq);
  input?.addEventListener('input', () => {
    const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    let shown = 0;
    for (const q of qs) {
      const text = q.textContent?.toLowerCase() ?? '';
      const hit = words.every((w) => text.includes(w));
      q.hidden = !hit;
      if (hit) shown++;
      if (words.length && hit) q.open = true;
    }
    if (none) none.hidden = shown > 0;
  });
}

// The measured command search on /apps/.
const finder = $<HTMLElement>('[data-command-search]');
if (finder) {
  const input = $<HTMLInputElement>('input', finder);
  const out = $<HTMLElement>('[data-command-results]', finder);
  const count = $<HTMLElement>('[data-command-count]', finder);
  type Row = [app: string, path: string, title: string, keys: string];
  let rows: Row[] | null = null;
  const load = async () => {
    if (rows) return rows;
    const res = await fetch('/apps/commands.json');
    rows = (await res.json()) as Row[];
    return rows;
  };
  const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] ?? c);
  input?.addEventListener('focus', () => void load(), { once: true });
  input?.addEventListener('input', async () => {
    const q = input.value.trim().toLowerCase();
    if (!out || !count) return;
    if (q.length < 2) {
      out.innerHTML = '';
      count.textContent = '';
      return;
    }
    const all = await load();
    const hits = all.filter((r) => r[2].toLowerCase().includes(q) || r[0].toLowerCase() === q);
    count.textContent = `${hits.length} commands`;
    out.innerHTML = hits
      .slice(0, 80)
      .map(
        (r) =>
          `<li><span class="r-app">${esc(r[0])}</span><span class="r-title">${esc(r[2])}<span class="r-path">${esc(r[1])}</span></span>${r[3] ? `<kbd class="kbd">${esc(r[3])}</kbd>` : '<span></span>'}</li>`,
      )
      .join('');
  });
}

schedule();
