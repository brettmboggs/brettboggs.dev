// The Bridge - the scroll-track conductor for the 3D film in bridgeScene.ts.
// Ported from Datum's v1 landing intro (datum-core eb8bbde, PR #446): this
// wrapper owns the scroll track, the copy overlays and HUD chips, and the
// dawn hand-off veil; all the 3D lives in bridgeScene.ts, lazy-loaded so the
// page's first paint never waits on three.js.

import type { CinematicSceneHandle, CinematicQuality } from './bridgeScene';

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const smooth = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
const bump = (a: number, b: number, c: number, d: number, p: number) =>
  smooth(a, b, p) * (1 - smooth(c, d, p));

// Beat windows must match the DOM order of .cin-beat elements on the page.
const BEAT_WINDOWS: Array<{ window: [number, number]; center?: boolean }> = [
  { window: [0.012, 0.115] },
  { window: [0.16, 0.27] },
  { window: [0.41, 0.56] },
  { window: [0.68, 0.82] },
  { window: [0.85, 0.93], center: true },
];

export function hasWebGL2(): boolean {
  try {
    const c = document.createElement('canvas');
    return !!c.getContext('webgl2');
  } catch {
    return false;
  }
}

function pickQuality(): CinematicQuality {
  const coarse = typeof window.matchMedia === 'function' && window.matchMedia('(pointer: coarse)').matches;
  const cores = navigator.hardwareConcurrency || 8;
  return coarse || cores <= 4 ? 'medium' : 'high';
}

export function mountBridgeFilm(track: HTMLElement): void {
  const stage = track.querySelector<HTMLElement>('.cin-stage');
  const canvas = track.querySelector<HTMLCanvasElement>('.cin-canvas');
  if (!stage || !canvas) return;

  const beatEls = Array.from(track.querySelectorAll<HTMLElement>('.cin-beat'));
  const chipEls = Array.from(track.querySelectorAll<HTMLElement>('.cin-chip'));
  const veil = track.querySelector<HTMLElement>('.cin-veil');
  const hint = track.querySelector<HTMLElement>('.cin-hint');
  const brand = track.querySelector<HTMLElement>('.cin-brand');
  const skipBtn = track.querySelector<HTMLButtonElement>('.cin-skip');

  let scene: CinematicSceneHandle | null = null;
  let disposed = false;
  let active = true;
  let pSmooth = 0;
  let last = performance.now();
  const quality = pickQuality();

  const applySize = () => {
    if (!scene) return;
    const w = stage.clientWidth;
    const h = stage.clientHeight;
    const maxDpr = quality === 'high' ? 2 : 1.5;
    const dpr = Math.min(window.devicePixelRatio || 1, maxDpr, 2800 / Math.max(w, 1));
    scene.setSize(w, h, dpr);
  };

  const resizeObs = new ResizeObserver(applySize);
  resizeObs.observe(stage);
  const io = new IntersectionObserver((entries) => {
    active = entries[0]?.isIntersecting ?? true;
  });
  io.observe(track);

  import('./bridgeScene').then((mod) => {
    if (disposed) return;
    scene = mod.createCinematicScene(canvas, quality);
    applySize();
    canvas.style.opacity = '1';
  });

  const trackTop = () => track.getBoundingClientRect().top + window.scrollY;

  const targetProgress = () => {
    const span = track.offsetHeight - window.innerHeight;
    if (span <= 0) return 1;
    return clamp01((window.scrollY - trackTop()) / span);
  };

  if (skipBtn) {
    skipBtn.addEventListener('click', () => {
      window.scrollTo({ top: trackTop() + track.offsetHeight - window.innerHeight + 2 });
    });
  }

  const frame = (now: number) => {
    if (disposed) return;
    requestAnimationFrame(frame);
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    if (!active) return;
    const pT = targetProgress();
    pSmooth += (pT - pSmooth) * (1 - Math.exp(-dt * 6.5));
    if (Math.abs(pT - pSmooth) < 0.0004) pSmooth = pT;
    const p = pSmooth;

    if (scene) scene.render(p, dt);

    for (let i = 0; i < BEAT_WINDOWS.length && i < beatEls.length; i++) {
      const el = beatEls[i];
      const [a, b] = BEAT_WINDOWS[i].window;
      const o = bump(a, a + 0.024, b - 0.024, b, p);
      const enter = smooth(a, a + 0.024, p);
      const dy = ((1 - enter) * 18).toFixed(2);
      el.style.opacity = o.toFixed(3);
      // Centered beats carry their centering in the transform: compose, don't clobber.
      el.style.transform = BEAT_WINDOWS[i].center
        ? `translate(-50%, -50%) translateY(${dy}px)`
        : `translateY(${dy}px)`;
      el.style.visibility = o > 0.001 ? 'visible' : 'hidden';
    }

    if (scene) {
      for (let i = 0; i < scene.hud.length && i < chipEls.length; i++) {
        const chip = chipEls[i];
        const pt = scene.hud[i];
        chip.style.left = `${pt.x.toFixed(2)}%`;
        chip.style.top = `${pt.y.toFixed(2)}%`;
        chip.style.opacity = pt.opacity.toFixed(3);
        chip.style.visibility = pt.opacity > 0.001 ? 'visible' : 'hidden';
      }
    }

    if (veil) veil.style.opacity = smooth(0.94, 0.985, p).toFixed(3);
    if (hint) hint.style.opacity = (1 - smooth(0.004, 0.03, p)).toFixed(3);
    if (brand) brand.style.opacity = (1 - smooth(0.9, 0.96, p)).toFixed(3);
    if (skipBtn) {
      skipBtn.style.opacity = (1 - smooth(0.88, 0.94, p)).toFixed(3);
      skipBtn.style.pointerEvents = p > 0.92 ? 'none' : 'auto';
    }
  };
  requestAnimationFrame(frame);

  window.addEventListener('pagehide', () => {
    disposed = true;
    resizeObs.disconnect();
    io.disconnect();
    if (scene) scene.dispose();
  });
}
