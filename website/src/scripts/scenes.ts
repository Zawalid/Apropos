// The scene engine. A pinned scene ([data-pin]) is taller than the screen and its stage sticks; the scroll inside it
// becomes a progress value from 0 to 1, written to --p on the scene and handed to the scene's own updater, which turns it
// into transforms. Only transform, opacity and clip-path move. With reduced motion nothing is pinned: html.live is never
// set, so every scene keeps its finished layout and the updaters are not called.

export const motion = !window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const root = document.documentElement;
if (motion) root.classList.add('live');

export const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));
/** Progress of p through the window [a, b], from 0 to 1. */
export const span = (p: number, a: number, b: number) => clamp((p - a) / (b - a));
export const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);
export const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

type Updater = (p: number) => void;
const updaters = new Map<HTMLElement, Updater[]>();
const lastP = new WeakMap<HTMLElement, number>();

/** Calls fn with the scene's progress whenever it changes while the scene is near the screen. */
export function onScene(scene: HTMLElement | null, fn: Updater) {
  if (!scene || !motion) return;
  const list = updaters.get(scene) ?? [];
  list.push(fn);
  updaters.set(scene, list);
  schedule();
}

/** The scroll position at which a scene reaches progress p, for buttons and keys that jump to a moment. */
export function scrollFor(scene: HTMLElement, p: number) {
  const top = scene.getBoundingClientRect().top + window.scrollY;
  return top + (scene.offsetHeight - window.innerHeight) * p;
}

const frame: Array<() => void> = [];
/** Runs fn once per animation frame after any scroll or resize. */
export function eachFrame(fn: () => void) {
  frame.push(fn);
  schedule();
}

let queued = false;
let forced = false;
function schedule(force = false) {
  forced ||= force;
  if (queued) return;
  queued = true;
  requestAnimationFrame(tick);
}

function tick() {
  queued = false;
  const vh = window.innerHeight;
  for (const [scene, fns] of updaters) {
    const r = scene.getBoundingClientRect();
    if (r.bottom < -vh * 0.5 || r.top > vh * 1.5) continue;
    const len = Math.max(1, r.height - vh);
    const p = clamp(-r.top / len);
    if (!forced && lastP.get(scene) === p) continue;
    lastP.set(scene, p);
    scene.style.setProperty('--p', p.toFixed(4));
    for (const fn of fns) fn(p);
  }
  for (const fn of frame) fn();
  forced = false;
}

window.addEventListener('scroll', () => schedule(), { passive: true });
window.addEventListener('resize', () => schedule(true));
