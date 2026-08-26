/*
 * Datum stack hero
 * Scroll-scrubbed frame sequence on a canvas. No dependencies.
 *
 * Quick start (auto-mount):
 *   <div data-stack-hero data-frame-path="datum-stack-hero/frames/" data-frame-count="120"></div>
 *   <script type="module" src="datum-stack-hero/stack-hero.js"></script>
 *
 * Or mount manually:
 *   import { mountStackHero } from "./datum-stack-hero/stack-hero.js";
 *   mountStackHero(document.querySelector("#hero"), {
 *     framePath: "/datum-stack-hero/frames/",
 *     frameCount: 120,
 *   });
 */

const DEFAULTS = {
  framePath: "frames/",
  framePrefix: "f",
  framePad: 4,
  frameExt: ".webp",
  frameCount: 120,
  aspect: 2048 / 896,        // width / height of the frames
  scrollLength: 3.0,         // viewport-heights of scroll that drive the scrub
  exitFrames: 14,            // trailing frames played while the canvas scrolls away
  exitSpan: 0.6,             // fraction of a viewport-height the exit frames span
  poster: null,              // shown while loading and for reduced motion
  fallbackVideo: null,       // optional mp4 used when scrubbing is not wanted
  mode: "scrub",             // "scrub" | "loop" (loop plays fallbackVideo inline)
};

function frameUrl(o, i) {
  return o.framePath + o.framePrefix + String(i + 1).padStart(o.framePad, "0") + o.frameExt;
}

export function mountStackHero(container, options = {}) {
  const o = { ...DEFAULTS, ...options };
  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  container.classList.add("dsh-root");

  // Reduced motion or loop mode: plain media, no scroll wiring.
  if (reduced || o.mode === "loop") {
    if (o.fallbackVideo && !reduced) {
      const v = document.createElement("video");
      v.src = o.fallbackVideo;
      v.muted = true;
      v.loop = true;
      v.autoplay = true;
      v.playsInline = true;
      v.className = "dsh-media";
      container.appendChild(v);
    } else {
      const img = document.createElement("img");
      img.src = o.poster || frameUrl(o, 0);
      img.alt = "Datum product tour";
      img.className = "dsh-media";
      container.appendChild(img);
    }
    return { destroy() { container.replaceChildren(); } };
  }

  // Scrub mode: tall wrapper + sticky stage + canvas.
  const wrapper = document.createElement("div");
  wrapper.className = "dsh-wrapper";
  wrapper.style.height = `${o.scrollLength * 100}vh`;

  const stage = document.createElement("div");
  stage.className = "dsh-stage";

  const canvas = document.createElement("canvas");
  canvas.className = "dsh-canvas";
  stage.appendChild(canvas);
  wrapper.appendChild(stage);
  container.appendChild(wrapper);

  const ctx = canvas.getContext("2d");
  const frames = new Array(o.frameCount).fill(null);
  let current = -1;
  let pending = -1;
  let destroyed = false;

  function load(i) {
    if (i < 0 || i >= o.frameCount || frames[i]) return;
    const img = new Image();
    img.decoding = "async";
    img.src = frameUrl(o, i);
    frames[i] = img;
    img.onload = () => { if (i === pending) draw(i); };
  }

  // Preload outward from a frame so the nearest frames are ready first.
  function preloadAround(center, radius) {
    for (let d = 0; d <= radius; d++) {
      load(center + d);
      load(center - d);
    }
  }

  function sizeCanvas() {
    const w = stage.clientWidth;
    const h = Math.round(w / o.aspect);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
    canvas.style.width = w + "px";
    canvas.style.height = h + "px";
    current = -1;
    draw(pending < 0 ? 0 : pending);
  }

  function draw(i) {
    const img = frames[i];
    if (!img || !img.complete || !img.naturalWidth) { pending = i; return; }
    if (i === current) return;
    current = i;
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  }

  // Main frames play while the stage is pinned; the trailing exitFrames play
  // as the stage un-sticks and scrolls away, so the fade happens in motion.
  function frameFromScroll() {
    const rect = wrapper.getBoundingClientRect();
    const pinned = rect.height - window.innerHeight;
    const exit = Math.min(o.exitFrames, o.frameCount - 1);
    const main = o.frameCount - exit;
    if (pinned <= 0) return 0;
    if (-rect.top <= pinned || exit === 0) {
      const p = Math.min(1, Math.max(0, -rect.top / pinned));
      return Math.round(p * (main - 1));
    }
    const e = Math.min(1, (-rect.top - pinned) / (window.innerHeight * o.exitSpan));
    return main - 1 + Math.round(e * exit);
  }

  let ticking = false;
  function onScroll() {
    if (ticking || destroyed) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const i = frameFromScroll();
      pending = i;
      draw(i);
      preloadAround(i, 12);
    });
  }

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", sizeCanvas);

  sizeCanvas();
  load(0);
  preloadAround(0, 12);
  // Fill in the rest once the page is idle.
  const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 800));
  idle(() => { for (let i = 0; i < o.frameCount; i++) load(i); });

  return {
    destroy() {
      destroyed = true;
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", sizeCanvas);
      container.replaceChildren();
    },
  };
}

// Auto-mount any [data-stack-hero] element.
function autoMount() {
  document.querySelectorAll("[data-stack-hero]").forEach((el) => {
    if (el.dataset.dshMounted) return;
    el.dataset.dshMounted = "1";
    mountStackHero(el, {
      framePath: el.dataset.framePath || DEFAULTS.framePath,
      frameCount: parseInt(el.dataset.frameCount || DEFAULTS.frameCount, 10),
      scrollLength: parseFloat(el.dataset.scrollLength || DEFAULTS.scrollLength),
      exitFrames: parseInt(el.dataset.exitFrames ?? DEFAULTS.exitFrames, 10),
      exitSpan: parseFloat(el.dataset.exitSpan || DEFAULTS.exitSpan),
      poster: el.dataset.poster || null,
      fallbackVideo: el.dataset.fallbackVideo || null,
      mode: el.dataset.mode || DEFAULTS.mode,
    });
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", autoMount);
} else {
  autoMount();
}

window.DatumStackHero = { mount: mountStackHero };
