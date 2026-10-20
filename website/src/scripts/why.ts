import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import type Lenis from 'lenis';
import { all, clamp, one } from './dom';

/**
 * One key, a different palette per app. The three words are real tabs (arrow keys, Home and End work), and on a big
 * screen the section is pinned so scrolling walks through them. The pearl glides to the current word.
 */
export function initWhy(lenis: Lenis | null, motion: boolean): void {
  const section = one('[data-why]');
  const list = one('[data-why-tabs]');
  const pearl = one('[data-why-pearl]');
  if (!section || !list || !pearl) return;
  const tabs = all<HTMLButtonElement>('[data-why-tab]', section);
  const panels = all('[data-why-panel]', section);
  const lines = all('[data-why-line]', section);
  let active = -1;

  const place = () => {
    const tab = tabs[active];
    if (!tab) return;
    // Centre the pearl on the first line of the word.
    const size = parseFloat(getComputedStyle(tab).fontSize);
    pearl.style.setProperty('--y', `${tab.offsetTop + size * 0.5 - 7}px`);
  };

  const select = (index: number, focus = false) => {
    if (index === active) return;
    active = index;
    tabs.forEach((tab, i) => {
      const on = i === index;
      tab.setAttribute('aria-selected', on ? 'true' : 'false');
      tab.tabIndex = on ? 0 : -1;
      panels[i]?.toggleAttribute('data-on', on);
      const line = lines[i];
      if (line) {
        line.toggleAttribute('data-on', on);
        line.setAttribute('aria-hidden', on ? 'false' : 'true');
      }
    });
    place();
    if (focus) tabs[index]?.focus();
  };

  const pinned = () => motion && window.matchMedia('(min-width: 900px) and (min-height: 600px)').matches;
  // Where in the pinned section a given word becomes the current one.
  const scrollTo = (index: number) => {
    const total = section.offsetHeight - window.innerHeight;
    const top = section.getBoundingClientRect().top + window.scrollY + total * ((index + 0.5) / tabs.length);
    if (lenis) lenis.scrollTo(top, { duration: 1 });
    else window.scrollTo({ top, behavior: 'smooth' });
  };

  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => {
      if (pinned()) scrollTo(i);
      else select(i);
    });
    tab.addEventListener('keydown', (event) => {
      const last = tabs.length - 1;
      const next = { ArrowDown: i + 1, ArrowRight: i + 1, ArrowUp: i - 1, ArrowLeft: i - 1, Home: 0, End: last }[event.key];
      if (next === undefined) return;
      event.preventDefault();
      const target = clamp(next, 0, last);
      if (pinned()) {
        scrollTo(target);
        tabs[target]?.focus();
      } else select(target, true);
    });
  });

  select(0);
  void document.fonts.ready.then(place);
  window.addEventListener('resize', place);

  if (motion) {
    gsap.matchMedia().add('(min-width: 900px) and (min-height: 600px)', () => {
      const trigger = ScrollTrigger.create({
        trigger: section,
        start: 'top top',
        end: 'bottom bottom',
        onUpdate: (self) => select(Math.min(tabs.length - 1, Math.floor(self.progress * tabs.length))),
      });
      return () => trigger.kill();
    });
  }
}
