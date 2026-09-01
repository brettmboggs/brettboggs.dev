/* The picture viewer: a full screen stage for pictures bigger than the page.
   Every plate opens at its full pixel size, pans and zooms, and steps through
   the others. No dependencies. Plates that do not state their size are measured
   when the full picture arrives. */

type Plate = {
  full: string;
  thumb: string;
  w: number;
  h: number;
  title: string;
  meta: string;
};

type View = { scale: number; x: number; y: number };

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export function mountViewer(root: ParentNode = document): void {
  const triggers = Array.from(root.querySelectorAll<HTMLElement>('[data-plate]'));
  if (triggers.length === 0) return;

  // read at open time, not at mount: the arc swaps its own source under us
  const plateOf = (el: HTMLElement): Plate => {
    const img = el.querySelector('img');
    return {
      full: el.dataset.full ?? img?.currentSrc ?? img?.src ?? '',
      thumb: img?.currentSrc ?? img?.src ?? '',
      w: Number(el.dataset.w ?? img?.naturalWidth ?? 0) || 0,
      h: Number(el.dataset.h ?? img?.naturalHeight ?? 0) || 0,
      title: el.dataset.title ?? '',
      meta: el.dataset.meta ?? '',
    };
  };

  // --- shell -----------------------------------------------------------
  const overlay = document.createElement('div');
  overlay.className = 'ec-viewer';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', 'Full size picture');
  overlay.hidden = true;
  overlay.innerHTML = `
    <div class="ec-stage" id="ec-stage">
      <img class="ec-img" id="ec-img" alt="" draggable="false" />
    </div>
    <div class="ec-bar ec-bar-top">
      <p class="ec-label"><span class="ec-title" id="ec-title"></span><span class="ec-meta" id="ec-meta"></span></p>
      <div class="ec-tools">
        <button type="button" class="ec-btn" id="ec-out" aria-label="Zoom out">&minus;</button>
        <button type="button" class="ec-btn ec-zoom" id="ec-fit" aria-label="Reset zoom"><span id="ec-pct">Fit</span></button>
        <button type="button" class="ec-btn" id="ec-in" aria-label="Zoom in">+</button>
        <button type="button" class="ec-btn ec-close" id="ec-close" aria-label="Close">Close</button>
      </div>
    </div>
    <div class="ec-bar ec-bar-bottom">
      <button type="button" class="ec-btn" id="ec-prev" aria-label="Previous picture">&larr;</button>
      <p class="ec-hint" id="ec-hint"></p>
      <button type="button" class="ec-btn" id="ec-next" aria-label="Next picture">&rarr;</button>
    </div>
    <p class="ec-loading" id="ec-loading" role="status">Loading full size</p>`;
  document.body.appendChild(overlay);

  const $ = <T extends HTMLElement>(id: string) => overlay.querySelector(id) as T;
  const stage = $<HTMLDivElement>('#ec-stage');
  const img = $<HTMLImageElement>('#ec-img');
  const elTitle = $('#ec-title');
  const elMeta = $('#ec-meta');
  const elPct = $('#ec-pct');
  const elHint = $('#ec-hint');
  const elLoading = $('#ec-loading');

  let index = 0;
  let plate = plateOf(triggers[0]);
  let v: View = { scale: 1, x: 0, y: 0 };
  let fit = 1;
  let opener: HTMLElement | null = null;
  let token = 0;

  const box = () => stage.getBoundingClientRect();

  function computeFit(): number {
    const b = box();
    if (!plate.w || !plate.h || !b.width || !b.height) return 1;
    return Math.min(b.width / plate.w, b.height / plate.h);
  }

  function apply(): void {
    const b = box();
    const w = plate.w * v.scale;
    const h = plate.h * v.scale;
    // a picture smaller than the stage sits in the middle; a bigger one stays covering it
    v.x = w <= b.width ? (b.width - w) / 2 : clamp(v.x, b.width - w, 0);
    v.y = h <= b.height ? (b.height - h) / 2 : clamp(v.y, b.height - h, 0);
    img.style.width = `${plate.w}px`;
    img.style.height = `${plate.h}px`;
    img.style.transform = `translate3d(${v.x}px, ${v.y}px, 0) scale(${v.scale})`;
    const pct = Math.round((v.scale / fit) * 100);
    elPct.textContent = Math.abs(v.scale - fit) < 0.001 ? 'Fit' : `${pct}%`;
    stage.classList.toggle('is-zoomed', v.scale > fit * 1.002);
  }

  function reset(): void {
    fit = computeFit();
    v = { scale: fit, x: 0, y: 0 };
    apply();
  }

  function zoomAt(factor: number, px: number, py: number): void {
    const next = clamp(v.scale * factor, fit, Math.max(fit * 12, 6));
    if (next === v.scale) return;
    const b = box();
    const cx = px - b.left;
    const cy = py - b.top;
    v.x = cx - ((cx - v.x) * next) / v.scale;
    v.y = cy - ((cy - v.y) * next) / v.scale;
    v.scale = next;
    apply();
  }

  function zoomCentre(factor: number): void {
    const b = box();
    zoomAt(factor, b.left + b.width / 2, b.top + b.height / 2);
  }

  function show(i: number): void {
    index = (i + triggers.length) % triggers.length;
    plate = plateOf(triggers[index]);
    const mine = ++token;

    elTitle.textContent = plate.title;
    elMeta.textContent = plate.meta;
    img.alt = plate.title;
    elHint.textContent = `${index + 1} of ${triggers.length}`;
    // the thumbnail is already decoded, so the frame is never empty
    img.src = plate.thumb;
    elLoading.hidden = false;
    reset();

    const full = new Image();
    full.decoding = 'async';
    full.src = plate.full;
    const done = () => {
      if (mine !== token) return;
      // a plate that never said how big it is gets measured now, then fitted
      if (!plate.w || !plate.h) {
        plate.w = full.naturalWidth;
        plate.h = full.naturalHeight;
        reset();
      }
      img.src = plate.full;
      elLoading.hidden = true;
    };
    if (full.complete) done();
    else {
      full.onload = done;
      full.onerror = () => {
        if (mine === token) elLoading.hidden = true;
      };
    }
  }

  function open(i: number, from: HTMLElement): void {
    opener = from;
    overlay.hidden = false;
    document.documentElement.classList.add('ec-locked');
    show(i);
    requestAnimationFrame(() => {
      overlay.classList.add('is-on');
      reset();
    });
    $('#ec-close').focus();
  }

  function close(): void {
    token++;
    overlay.classList.remove('is-on');
    overlay.hidden = true;
    document.documentElement.classList.remove('ec-locked');
    elLoading.hidden = true;
    opener?.focus();
    opener = null;
  }

  // --- wiring ----------------------------------------------------------
  triggers.forEach((el, i) => {
    el.addEventListener('click', (e) => {
      // a plate that carries its own link opens that, not the viewer
      if ((e.target as HTMLElement).closest('a')) return;
      e.preventDefault();
      open(i, el);
    });
    el.addEventListener('keydown', (e) => {
      const k = (e as KeyboardEvent).key;
      if (k === 'Enter' || k === ' ') {
        e.preventDefault();
        open(i, el);
      }
    });
  });

  $('#ec-close').addEventListener('click', close);
  $('#ec-in').addEventListener('click', () => zoomCentre(1.5));
  $('#ec-out').addEventListener('click', () => zoomCentre(1 / 1.5));
  $('#ec-fit').addEventListener('click', reset);
  $('#ec-prev').addEventListener('click', () => show(index - 1));
  $('#ec-next').addEventListener('click', () => show(index + 1));

  // a click on the ground closes, but a drag that happens to end there does not
  let downAt: { x: number; y: number } | null = null;
  overlay.addEventListener('pointerdown', (e) => {
    downAt = { x: e.clientX, y: e.clientY };
  });
  overlay.addEventListener('click', (e) => {
    const moved = downAt ? Math.hypot(e.clientX - downAt.x, e.clientY - downAt.y) : 0;
    downAt = null;
    if (moved > 6) return;
    if (e.target === overlay || e.target === stage) close();
  });

  document.addEventListener('keydown', (e) => {
    if (overlay.hidden) return;
    switch (e.key) {
      case 'Escape': close(); break;
      case 'ArrowLeft': show(index - 1); break;
      case 'ArrowRight': show(index + 1); break;
      case '+': case '=': zoomCentre(1.5); break;
      case '-': case '_': zoomCentre(1 / 1.5); break;
      case '0': reset(); break;
      default: return;
    }
    e.preventDefault();
  });

  stage.addEventListener(
    'wheel',
    (e) => {
      e.preventDefault();
      zoomAt(Math.exp(-e.deltaY * 0.0016), e.clientX, e.clientY);
    },
    { passive: false },
  );

  stage.addEventListener('dblclick', (e) => {
    e.preventDefault();
    if (v.scale > fit * 1.002) reset();
    else zoomAt(3, e.clientX, e.clientY);
  });

  // pointer drag, and two finger pinch, on one set of handlers
  const live = new Map<number, { x: number; y: number }>();
  let pinch: { dist: number; scale: number } | null = null;
  let swipe: { x: number; y: number; multi: boolean } | null = null;

  stage.addEventListener('pointerdown', (e) => {
    if (e.target !== img) return;
    try {
      stage.setPointerCapture(e.pointerId);
    } catch {
      /* no capture available, the handlers still work off the element */
    }
    live.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (live.size === 1) swipe = { x: e.clientX, y: e.clientY, multi: false };
    else if (swipe) swipe.multi = true;
    if (live.size === 2) {
      const [a, b] = [...live.values()];
      pinch = { dist: Math.hypot(a.x - b.x, a.y - b.y) || 1, scale: v.scale };
    }
  });

  stage.addEventListener('pointermove', (e) => {
    const prev = live.get(e.pointerId);
    if (!prev) return;
    const now = { x: e.clientX, y: e.clientY };
    live.set(e.pointerId, now);

    if (live.size >= 2 && pinch) {
      const [a, b] = [...live.values()];
      const d = Math.hypot(a.x - b.x, a.y - b.y) || 1;
      const target = clamp((pinch.scale * d) / pinch.dist, fit, Math.max(fit * 12, 6));
      zoomAt(target / v.scale, (a.x + b.x) / 2, (a.y + b.y) / 2);
      return;
    }
    if (v.scale <= fit * 1.002) return;
    v.x += now.x - prev.x;
    v.y += now.y - prev.y;
    apply();
  });

  const drop = (e: PointerEvent) => {
    live.delete(e.pointerId);
    if (live.size < 2) pinch = null;
    // at fit size a sideways swipe is how a phone expects to change picture
    if (live.size === 0 && swipe && !swipe.multi && v.scale <= fit * 1.002) {
      const dx = e.clientX - swipe.x;
      const dy = e.clientY - swipe.y;
      if (Math.abs(dx) > 60 && Math.abs(dx) > Math.abs(dy) * 1.5) show(index + (dx < 0 ? 1 : -1));
    }
    if (live.size === 0) swipe = null;
  };
  stage.addEventListener('pointerup', drop);
  stage.addEventListener('pointercancel', drop);

  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    if (overlay.hidden) return;
    window.clearTimeout(resizeTimer);
    resizeTimer = window.setTimeout(reset, 120);
  });
}
