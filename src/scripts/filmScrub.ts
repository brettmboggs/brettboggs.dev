import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);
// iOS collapses its toolbar mid-scroll and fires resize; without this the pin jumps
ScrollTrigger.config({ ignoreMobileResize: true });

interface FilmOptions {
  canvas: HTMLCanvasElement;
  pinTarget: HTMLElement;
  frameCount: number;
  onProgress?: (p: number) => void;
}

// source dimensions per tier, cheapest first. `portrait` is a centre crop of the
// master rather than a scaled-down copy, so a phone fills its screen from real
// pixels instead of stretching a 16:9 frame past 3x.
const TIERS = [
  { name: 'sm', w: 960, h: 540 },
  { name: 'portrait', w: 664, h: 1440 },
  { name: 'lg', w: 1600, h: 900 },
  { name: 'xl', w: 2560, h: 1440 },
];
// above this the frame is being stretched enough to read as mush
const MAX_UPSCALE = 1.4;

// cheapest tier that still covers the canvas without visible stretching. the
// canvas is cover-fit, so on a tall screen it is the height that sets the scale.
function pickTier(cw: number, ch: number): string {
  const conn = (navigator as any).connection;
  // a narrow pipe would rather be soft than stall
  if (conn && /(^|-)2g$/.test(conn.effectiveType ?? '')) return 'sm';
  for (const t of TIERS) {
    if (Math.max(cw / t.w, ch / t.h) <= MAX_UPSCALE) return t.name;
  }
  return TIERS[TIERS.length - 1].name;
}

export function initFilm({ canvas, pinTarget, frameCount, onProgress }: FilmOptions): void {
  const ctx = canvas.getContext('2d', { alpha: false })!;
  const dpr = Math.min(devicePixelRatio, 2);
  const dir = `/film/${pickTier(canvas.clientWidth * dpr, canvas.clientHeight * dpr)}/`;
  const frames: (HTMLImageElement | null)[] = new Array(frameCount).fill(null);
  const ready: boolean[] = new Array(frameCount).fill(false);
  let current = 0;
  let drawn = -1;

  function url(i: number): string {
    return `${dir}${String(i).padStart(3, '0')}.webp`;
  }

  function nearestLoaded(i: number): HTMLImageElement | null {
    if (ready[i]) return frames[i];
    for (let d = 1; d < frameCount; d++) {
      if (i - d >= 0 && ready[i - d]) return frames[i - d];
      if (i + d < frameCount && ready[i + d]) return frames[i + d];
    }
    return null;
  }

  function draw(i: number): void {
    const img = nearestLoaded(i);
    if (!img) return;
    const cw = canvas.width;
    const ch = canvas.height;
    const s = Math.max(cw / img.naturalWidth, ch / img.naturalHeight);
    const w = img.naturalWidth * s;
    const h = img.naturalHeight * s;
    ctx.drawImage(img, (cw - w) / 2, (ch - h) / 2, w, h);
    drawn = i;
  }

  function load(i: number, onload?: () => void): void {
    if (frames[i]) return;
    const img = new Image();
    frames[i] = img;
    const settle = (): void => {
      if (ready[i]) return;
      ready[i] = true;
      onload?.();
    };
    img.onload = settle;
    img.onerror = settle;
    img.src = url(i);
    // pre-warm off the scroll path — a first drawImage on an undecoded frame stalls the main
    // thread. best effort only: decode() never settles in a tab that isn't compositing.
    img.decode().then(settle, () => {});
  }

  function resize(): void {
    const w = Math.round(canvas.clientWidth * dpr);
    const h = Math.round(canvas.clientHeight * dpr);
    // assigning width/height always clears the canvas, so only do it when it actually changed
    if (canvas.width === w && canvas.height === h) return;
    canvas.width = w;
    canvas.height = h;
    // setting canvas dimensions resets context state
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    drawn = -1;
    draw(current);
  }
  window.addEventListener('resize', resize);

  const passes = [8, 4, 2, 1];
  let pass = 0;
  function loadPass(): void {
    if (pass >= passes.length) return;
    const step = passes[pass];
    let pending = 0;
    for (let i = 0; i < frameCount; i += step) {
      if (!frames[i]) {
        pending++;
        load(i, () => {
          pending--;
          if (Math.abs(i - current) <= step) draw(current);
          if (pending === 0) {
            pass++;
            loadPass();
          }
        });
      }
    }
    if (pending === 0) {
      pass++;
      loadPass();
    }
  }
  load(0, () => {
    resize();
    loadPass();
  });

  ScrollTrigger.create({
    trigger: pinTarget,
    start: 'top top',
    end: '+=280%',
    pin: true,
    scrub: 0.4,
    onUpdate: (self) => {
      current = Math.min(frameCount - 1, Math.round(self.progress * (frameCount - 1)));
      if (current !== drawn) draw(current);
      onProgress?.(self.progress);
    },
  });
}
