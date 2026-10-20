import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';
import 'lenis/dist/lenis.css';
import { initCopy, initFaq, initNav } from './basics';
import { initHero } from './hero';
import { initReveals } from './reveals';
import { initWhy } from './why';

declare global {
  interface Window { __aproposMotion?: boolean }
}

const root = document.documentElement;
const motion = root.classList.contains('motion');

initCopy();
initFaq(motion);
initNav(motion);

if (motion) {
  try {
    gsap.registerPlugin(ScrollTrigger);
    ScrollTrigger.config({ ignoreMobileResize: true });

    let lenis: Lenis | null = null;
    const coarse = window.matchMedia('(pointer: coarse)').matches;
    if (!coarse) {
      lenis = new Lenis({ lerp: 0.11, anchors: true, autoRaf: false });
      lenis.on('scroll', ScrollTrigger.update);
      gsap.ticker.add((time) => lenis?.raf(time * 1000));
      gsap.ticker.lagSmoothing(0);
    }

    initHero();
    initWhy(lenis, true);
    initReveals();
    window.__aproposMotion = true;

    // Fonts change line heights; measure again once they are in.
    void document.fonts.ready.then(() => ScrollTrigger.refresh());
  } catch (error) {
    root.classList.remove('motion');
    console.warn('Motion disabled', error);
    initWhy(null, false);
  }
} else {
  initWhy(null, false);
}
