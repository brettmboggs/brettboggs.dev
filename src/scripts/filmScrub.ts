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
  // `settled` means the request finished either way; `usable` means it finished
  // with pixels. Collapsing the two is what turned a failed load into a black
  // screen: an alpha:false canvas starts opaque black, so the moment it was
  // sized it covered the poster, and a browser that cannot decode webp fails
  // every frame. The canvas now stays hidden until a frame actually paints.
  const settled: boolean[] = new Array(frameCount).fill(false);
  const usable: boolean[] = new Array(frameCount).fill(false);
  let current = 0;
  let drawn = -1;
  let painted = false;

  function url(i: number): string {
    return `${dir}${String(i).padStart(3, '0')}.webp`;
  }

  function nearestLoaded(i: number): HTMLImageElement | null {
    if (usable[i]) return frames[i];
    for (let d = 1; d < frameCount; d++) {
      if (i - d >= 0 && usable[i - d]) return frames[i - d];
      if (i + d < frameCount && usable[i + d]) return frames[i + d];
    }
    return null;
  }

  function draw(i: number): void {
    const img = nearestLoaded(i);
    // naturalWidth is 0 on a broken image, which would scale the frame by
    // Infinity and throw inside drawImage
    if (!img || !img.naturalWidth) return;
    const cw = canvas.width;
    const ch = canvas.height;
    const s = Math.max(cw / img.naturalWidth, ch / img.naturalHeight);
    const w = img.naturalWidth * s;
    const h = img.naturalHeight * s;
    ctx.drawImage(img, (cw - w) / 2, (ch - h) / 2, w, h);
    drawn = i;
    // first real frame: hand over from the poster. Same image, so no seam.
    if (!painted) {
      painted = true;
      canvas.style.opacity = '1';
    }
  }

  function load(i: number, onload?: () => void, idle = false): void {
    if (frames[i]) return;
    const img = new Image();
    // backfill runs behind whatever the page still needs
    if (idle) (img as any).fetchPriority = 'low';
    frames[i] = img;
    const settle = (): void => {
      if (settled[i]) return;
      settled[i] = true;
      usable[i] = img.naturalWidth > 0;
      onload?.();
    };
    img.onload = settle;
    img.onerror = settle;
    img.src = url(i);
    // pre-warm off the scroll path: a first drawImage on an undecoded frame stalls the main
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

  // Refinement used to run to completion the moment the page loaded, so someone
  // who never scrolled still pulled all 96 frames of their tier. Nothing is
  // dropped or re-encoded here: the coarse pass lands up front so the scrub is
  // usable from the first pixel of scroll, the rest is fetched around the
  // playhead as it actually moves, and the remainder backfills at low priority
  // once the film is genuinely being watched. Anyone who watches it sees every
  // frame exactly as before. Anyone who skips it stops paying for the sequence.
  const COARSE = 8;
  const WINDOW = 20;
  const REFINE_STEP = 4;
  let lastRefined = -Infinity;
  let backfilling = false;

  function onFrameReady(i: number): void {
    // a newly arrived neighbour can be a better match than what is on screen
    if (Math.abs(i - current) <= COARSE) draw(current);
  }

  function loadCoarse(): void {
    for (let i = 0; i < frameCount; i += COARSE) load(i, () => onFrameReady(i));
    // the frame the page settles on is never left to a neighbour
    load(frameCount - 1, () => onFrameReady(frameCount - 1));
  }

  function refineAround(centre: number): void {
    if (Math.abs(centre - lastRefined) < REFINE_STEP) return;
    lastRefined = centre;
    const lo = Math.max(0, centre - WINDOW);
    const hi = Math.min(frameCount - 1, centre + WINDOW);
    for (let i = lo; i <= hi; i++) load(i, () => onFrameReady(i));
  }

  function backfill(): void {
    if (backfilling) return;
    backfilling = true;
    const idle: (cb: () => void) => void =
      (window as any).requestIdleCallback ?? ((cb: () => void) => setTimeout(cb, 200));
    let next = 0;
    const step = (): void => {
      let budget = 6;
      while (next < frameCount && budget > 0) {
        if (!frames[next]) {
          load(next, ((i: number) => () => onFrameReady(i))(next), true);
          budget--;
        }
        next++;
      }
      if (next < frameCount) idle(step);
    };
    idle(step);
  }

  load(0, () => {
    resize();
    loadCoarse();
    refineAround(0);
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
      refineAround(current);
      // once the film is being watched, quietly fetch the rest so scrubbing
      // back through it is as smooth as scrubbing forward
      if (self.progress > 0.01) backfill();
      onProgress?.(self.progress);
    },
  });
}
