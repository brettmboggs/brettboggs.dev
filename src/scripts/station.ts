// The Station: shared geometry for the site's scene-anchored navigation.
// Every coordinate lives on the film's landing frame (2560x1440 master,
// rendered at 2x as poster-end-2x.webp). Landmarks are measured from the
// frame's pixels: the sun's bright-core centroid and the ridge silhouette.

export const IMG = { w: 2560, h: 1440 };
export const CREST = { x: 913, y: 1210 };
export const SUN = { x: 399, y: 542 };

export type SceneKey = 'work' | 'lab' | 'about';

export interface Scene {
  /** image-space point the marker is planted on */
  marker: { x: number; y: number };
  /** the crest benchmark or a small survey tick */
  big: boolean;
  /** which way the flag flies off the marker */
  dir: 'up' | 'down';
  /** stem length in screen px */
  stem: number;
  /** marker ring radius in screen px */
  r: number;
  /** ring gets a sunflower dot (the sun is its own dot) */
  dot: boolean;
  /** crop framing: cx centres it; bottom pins the lower edge, cy the middle */
  cx: number;
  bottom?: number;
  cy?: number;
  /** crop width as a share of the master; smaller = deeper dive */
  f: number;
  /** needle bearing when this section is home, degrees from north */
  bearing: number;
}

export const SCENES: Record<SceneKey, Scene> = {
  work: {
    marker: CREST, big: true, dir: 'up', stem: 150, r: 32, dot: true,
    cx: 913, bottom: 1280, f: 0.4, bearing: 0,
  },
  lab: {
    marker: { x: 2010, y: 1292 }, big: false, dir: 'up', stem: 150, r: 9, dot: true,
    cx: 2010, bottom: 1380, f: 0.45, bearing: 64,
  },
  about: {
    marker: SUN, big: false, dir: 'down', stem: 96, r: 27, dot: false,
    cx: 480, cy: 560, f: 0.42, bearing: -50,
  },
};

export const ORDER: SceneKey[] = ['work', 'lab', 'about'];

/** cover-fit of the master frame, centred both ways: the film canvas and the
    poster (object-fit: cover) both centre, and the station must sit on the
    same pixels they draw */
export function coverFit(vw: number, vh: number): { s: number; x: number; y: number } {
  const s = Math.max(vw / IMG.w, vh / IMG.h);
  return { s, x: (vw - IMG.w * s) / 2, y: (vh - IMG.h * s) / 2 };
}

/** a scene's crop rect on the master, matched to the viewport's aspect */
export function sceneRect(
  scene: SceneKey,
  vw: number,
  vh: number,
): { x: number; y: number; w: number; h: number } {
  const sc = SCENES[scene];
  let w = IMG.w * sc.f;
  let h = (w * vh) / vw;
  if (h > IMG.h) {
    h = IMG.h;
    w = (h * vw) / vh;
  }
  const x = Math.min(Math.max(sc.cx - w / 2, 0), IMG.w - w);
  const yRaw = sc.bottom !== undefined ? sc.bottom - h : sc.cy! - h / 2;
  const y = Math.min(Math.max(yRaw, 0), IMG.h - h);
  return { x, y, w, h };
}

/** transform that flies a cover-fit stage into a scene's crop */
export function zoomTransform(
  scene: SceneKey,
  vw: number,
  vh: number,
): { dx: number; dy: number; k: number } {
  const rect = sceneRect(scene, vw, vh);
  const fit = coverFit(vw, vh);
  const k = vw / rect.w / fit.s;
  return { k, dx: -fit.x - k * fit.s * rect.x, dy: -fit.y - k * fit.s * rect.y };
}

/** paint a fixed full-viewport element with a scene's crop, ghost-faint */
export function paintGhost(el: HTMLElement, scene: SceneKey): void {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const rect = sceneRect(scene, vw, vh);
  const s = vw / rect.w;
  el.style.backgroundSize = `${IMG.w * s}px ${IMG.h * s}px`;
  el.style.backgroundPosition = `${-rect.x * s}px ${-rect.y * s}px`;
  // ridge scenes fade in from the top so the header owns paper; the sun
  // scene keeps its landmark high, so only the very top is shielded
  const sky = SCENES[scene].bottom === undefined;
  const mask = sky
    ? 'linear-gradient(to bottom, transparent 0%, rgba(0,0,0,0.7) 9%, #000 20%)'
    : 'linear-gradient(to bottom, transparent 0%, rgba(0,0,0,0.55) 18%, #000 45%)';
  (el.style as unknown as { webkitMaskImage: string }).webkitMaskImage = mask;
  el.style.maskImage = mask;
  el.style.opacity = sky ? '0.6' : '0.42';
}
