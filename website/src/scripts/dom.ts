export function one<T extends Element = HTMLElement>(selector: string, root: ParentNode = document): T | null {
  return root.querySelector<T>(selector);
}

export function all<T extends Element = HTMLElement>(selector: string, root: ParentNode = document): T[] {
  return Array.from(root.querySelectorAll<T>(selector));
}

export const clamp = (v: number, min = 0, max = 1): number => Math.min(max, Math.max(min, v));

export const isSmall = (): boolean => window.matchMedia('(max-width: 899px)').matches;
