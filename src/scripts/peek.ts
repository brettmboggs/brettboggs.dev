/* Peek: a still of the thing a row points at, riding beside the cursor while
   it rests on the row. A contact sheet that follows you, not a card grid.
   Pointer devices only; a phone keeps the rows exactly as they are. */

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

export function mountPeek(root: ParentNode = document): void {
  if (!window.matchMedia('(hover: hover) and (pointer: fine)').matches) return;
  const rows = Array.from(root.querySelectorAll<HTMLElement>('[data-peek]'));
  if (rows.length === 0) return;

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const el = document.createElement('div');
  el.className = 'peek';
  el.setAttribute('aria-hidden', 'true');
  const img = new Image();
  img.alt = '';
  img.decoding = 'async';
  el.appendChild(img);
  document.body.appendChild(el);

  let tx = 0;
  let ty = 0;
  let x = 0;
  let y = 0;
  let on = false;
  let leftAt = 0;
  let raf = 0;

  function step(): void {
    const k = reduced ? 1 : 0.16;
    x += (tx - x) * k;
    y += (ty - y) * k;
    el.style.transform = `translate3d(${x.toFixed(1)}px, ${y.toFixed(1)}px, 0)`;
    if (on || Math.abs(tx - x) > 0.5 || Math.abs(ty - y) > 0.5) raf = requestAnimationFrame(step);
    else raf = 0;
  }

  // to the right of the cursor, or the left when the right runs out of room
  function aim(e: PointerEvent): void {
    const w = el.offsetWidth || 288;
    const h = el.offsetHeight || 204;
    let nx = e.clientX + 32;
    if (nx + w > window.innerWidth - 16) nx = e.clientX - w - 32;
    tx = clamp(nx, 12, window.innerWidth - w - 12);
    ty = clamp(e.clientY - h * 0.5, 12, window.innerHeight - h - 12);
  }

  rows.forEach((row) => {
    row.addEventListener('pointerenter', (e) => {
      const src = row.dataset.peek;
      if (!src) return;
      if (img.getAttribute('src') !== src) img.src = src;
      const wasOn = on;
      on = true;
      aim(e);
      // arriving fresh, the mat appears where the cursor is; moving straight
      // from one row to the next, it glides there instead of jumping
      if (!wasOn && performance.now() - leftAt > 250) {
        x = tx;
        y = ty;
      }
      el.classList.add('is-on');
      if (!raf) step();
    });
    row.addEventListener('pointermove', aim);
    row.addEventListener('pointerleave', () => {
      on = false;
      leftAt = performance.now();
      el.classList.remove('is-on');
    });
  });

  // warm the stills once the page is idle, so the first hover is never a blank mat
  const warm = (): void => {
    rows.forEach((r) => {
      if (r.dataset.peek) new Image().src = r.dataset.peek;
    });
  };
  const idle = (window as Window & { requestIdleCallback?: (cb: () => void, o?: { timeout: number }) => void })
    .requestIdleCallback;
  if (idle) idle(warm, { timeout: 2000 });
  else window.setTimeout(warm, 800);
}
