import { eachFrame } from './scenes';
// The parts of the page that are not a scene: the header takes the light of the scene under it, and the pearl in the
// section nav marks the scene you are reading.

const root = document.documentElement;
const $$ = <T extends Element>(sel: string) => [...document.querySelectorAll<T>(sel)];

const lights = $$<HTMLElement>('[data-light]');
const navLinks = $$<HTMLAnchorElement>('[data-nav] a');
const bead = document.querySelector<HTMLElement>('[data-nav-bead]');
const sections = navLinks
  .map((a) => document.getElementById(a.dataset.for ?? ''))
  .filter((s): s is HTMLElement => s !== null);

let current = '';
function placeBead() {
  const link = navLinks.find((a) => a.dataset.for === current);
  const box = bead?.parentElement?.getBoundingClientRect();
  if (!bead || !link || !box) return;
  const r = link.getBoundingClientRect();
  bead.style.setProperty('--x', `${r.left + r.width / 2 - box.left}px`);
}

eachFrame(() => {
  // The header sits in the top 60 px; whichever scene covers that line sets its light.
  const line = 34;
  let night = false;
  // Later scenes lie on top of earlier ones where they overlap, so the last one covering the line wins.
  for (const n of lights) {
    const r = n.getBoundingClientRect();
    if (r.top <= line && r.bottom > line) night = (n.dataset.lightNow ?? n.dataset.light) === 'night';
  }
  root.classList.toggle('under-night', night);

  const read = window.innerHeight * 0.4;
  let found = '';
  for (const s of sections) if (s.getBoundingClientRect().top <= read) found = s.id;
  if (found !== current) {
    current = found;
    for (const a of navLinks) a.setAttribute('aria-current', String(a.dataset.for === current));
    root.classList.toggle('docked', current !== '');
    placeBead();
  }
});
window.addEventListener('resize', placeBead);

// Copy buttons anywhere on the page.
for (const b of $$<HTMLButtonElement>('[data-copy]')) {
  b.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(b.dataset.copy ?? '');
      const was = b.textContent;
      b.textContent = 'Copied';
      setTimeout(() => (b.textContent = was), 1400);
    } catch {
      // Clipboard refused: the text is still on the page to select.
    }
  });
}
