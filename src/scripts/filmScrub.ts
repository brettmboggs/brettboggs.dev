import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

interface FilmOptions {
  canvas: HTMLCanvasElement;
  pinTarget: HTMLElement;
  frameCount: number;
  onProgress?: (p: number) => void;
}

export function initFilm({ canvas, pinTarget, frameCount, onProgress }: FilmOptions): void {
  const ctx = canvas.getContext('2d')!;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  // pick the frame tier by the display's effective pixel width
  const effectiveWidth = window.innerWidth * Math.min(devicePixelRatio, 2);
  const tier = effectiveWidth >= 2000 ? 'xl' : effectiveWidth >= 1000 ? 'lg' : 'sm';
  const dir = `/film/${tier}/`;
  const frames: (HTMLImageElement | null)[] = new Array(frameCount).fill(null);
  let current = 0;
  let drawn = -1;

  function url(i: number): string {
    return `${dir}${String(i).padStart(3, '0')}.webp`;
  }

  function nearestLoaded(i: number): HTMLImageElement | null {
    if (frames[i]?.complete) return frames[i];
    for (let d = 1; d < frameCount; d++) {
      const a = frames[i - d];
      if (i - d >= 0 && a?.complete) return a;
      const b = frames[i + d];
      if (i + d < frameCount && b?.complete) return b;
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
    img.src = url(i);
    if (onload) img.onload = onload;
    frames[i] = img;
  }

  function resize(): void {
    canvas.width = canvas.clientWidth * Math.min(devicePixelRatio, 2);
    canvas.height = canvas.clientHeight * Math.min(devicePixelRatio, 2);
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
