import { all, one } from './dom';

/** Copy buttons next to commands. */
export function initCopy(): void {
  const status = one('[data-copy-status]');
  for (const button of all<HTMLButtonElement>('[data-copy]')) {
    let timer = 0;
    button.addEventListener('click', async () => {
      const text = button.dataset.copy ?? '';
      let ok = false;
      try {
        await navigator.clipboard.writeText(text);
        ok = true;
      } catch {
        const area = document.createElement('textarea');
        area.value = text;
        area.setAttribute('readonly', '');
        area.style.position = 'fixed';
        area.style.opacity = '0';
        document.body.append(area);
        area.select();
        ok = document.execCommand('copy');
        area.remove();
      }
      button.textContent = ok ? 'Copied' : 'Press Command-C';
      button.toggleAttribute('data-copied', ok);
      if (status) status.textContent = ok ? 'Command copied to the clipboard.' : 'Copy failed. Select the command and copy it.';
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        button.textContent = 'Copy';
        button.removeAttribute('data-copied');
      }, 1800);
    });
  }
}

/** FAQ: animate the answer when motion is allowed. Native details still works without this. */
export function initFaq(motion: boolean): void {
  if (!motion) return;
  for (const details of all<HTMLDetailsElement>('details[data-faq]')) {
    const summary = one<HTMLElement>('summary', details);
    const answer = one<HTMLElement>('.answer', details);
    if (!summary || !answer) continue;
    let anim: Animation | null = null;
    summary.addEventListener('click', (event) => {
      event.preventDefault();
      anim?.cancel();
      const opening = !details.open;
      if (opening) details.open = true;
      const full = answer.scrollHeight;
      anim = answer.animate(
        opening
          ? [{ height: '0px', opacity: 0 }, { height: `${full}px`, opacity: 1 }]
          : [{ height: `${full}px`, opacity: 1 }, { height: '0px', opacity: 0 }],
        { duration: opening ? 420 : 300, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' },
      );
      anim.onfinish = () => {
        if (!opening) details.open = false;
        anim = null;
      };
    });
  }
}

/** Nav: compact once the page moves, Download appears after the hero starts to scroll. */
export function initNav(motion: boolean): void {
  const nav = one('[data-nav]');
  if (!nav) return;
  const heroDownload = one('[data-hero-download]');
  let ticking = false;
  const update = () => {
    ticking = false;
    const y = window.scrollY;
    nav.classList.toggle('is-scrolled', y > 24);
    if (motion) {
      nav.classList.toggle('show-cta', y > window.innerHeight * 0.55);
    } else if (heroDownload) {
      nav.classList.toggle('show-cta', heroDownload.getBoundingClientRect().bottom < 0);
    }
  };
  window.addEventListener('scroll', () => {
    if (!ticking) {
      ticking = true;
      requestAnimationFrame(update);
    }
  }, { passive: true });
  update();
}
