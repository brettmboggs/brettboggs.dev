// The Drafting Film - the conductor. One requestAnimationFrame loop drives
// every element of the drawing from scroll progress; springs do the motion,
// so scrubbing either direction always settles smoothly. Ported from Datum's
// v5 landing intro (React) to vanilla DOM; the choreography is unchanged.

import {
  SCATTER_END,
  SILOS_END,
  LEAVE_END,
  CONFLICT_END,
  INERT_END,
  ASM_AT,
  ASM_SPAN,
  VEIL_AT,
  SEEN_KEY,
  FLD_SHEET,
  BEATS,
  TURN_BEAT,
  CHAPTERS,
  CONFLICTS,
  TRUE_DIM,
  TRUE_DIM_XY,
  PATHS,
  TEXTS,
  N_PATHS,
  N_ELS,
  elSheet,
  elOrder,
  DROPLINES,
} from './draftingFilmData';

/* ── Math helpers ─────────────────────────────────────────────────────── */

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const smooth = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
const bump = (a: number, b: number, c: number, d: number, p: number) =>
  smooth(a, b, p) * (1 - smooth(c, d, p));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const frac = (x: number) => x - Math.floor(x);

// Deterministic PRNG so the exploded layout is identical across sessions.
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ── Token colors ─────────────────────────────────────────────────────── */

type RGB = [number, number, number];

function parseColor(value: string): RGB {
  const s = value.trim();
  if (s.startsWith('#')) {
    const hex =
      s.length === 4
        ? s
            .slice(1)
            .split('')
            .map((c) => c + c)
            .join('')
        : s.slice(1);
    return [
      parseInt(hex.slice(0, 2), 16),
      parseInt(hex.slice(2, 4), 16),
      parseInt(hex.slice(4, 6), 16),
    ];
  }
  const m = s.match(/rgba?\(([^)]+)\)/);
  if (m) {
    const parts = m[1].split(',').map((v) => parseFloat(v));
    return [parts[0] || 0, parts[1] || 0, parts[2] || 0];
  }
  return [255, 255, 255];
}

const mixRGB = (a: RGB, b: RGB, t: number): RGB => [
  Math.round(lerp(a[0], b[0], t)),
  Math.round(lerp(a[1], b[1], t)),
  Math.round(lerp(a[2], b[2], t)),
];
const rgba = (c: RGB, a: number) => `rgba(${c[0]},${c[1]},${c[2]},${a.toFixed(3)})`;

/* ── Mount ────────────────────────────────────────────────────────────── */

export function mountDraftingFilm(track: HTMLElement): void {
  const stage = track.querySelector<HTMLElement>('.cin5-stage');
  if (!stage) return;

  const q = <T extends Element>(sel: string) => stage.querySelector<T>(sel);
  const qa = <T extends Element>(sel: string) => Array.from(stage.querySelectorAll<T>(sel));

  const root = q<SVGGElement>('.cin5-root');
  const paths = qa<SVGPathElement>('path.cin5-el');
  const texts = qa<SVGTextElement>('text.cin5-tx');
  const frames = qa<SVGGElement>('g.cin5-frame');
  const conflicts = qa<SVGGElement>('g.cin5-conflict');
  const datumLine = q<SVGPathElement>('.cin5-datum-line');
  const datumTicks = q<SVGPathElement>('.cin5-datum-ticks');
  const datumLabel = q<SVGTextElement>('.cin5-datum-label');
  const drops = qa<SVGPathElement>('path.cin5-drop');
  const pulses = qa<SVGPathElement>('path.cin5-pulse'); // [glow, line]
  const beatEls = qa<HTMLElement>('.cin5-beat'); // five beats then the turn
  const mark = q<HTMLElement>('.cin5-mark');
  const markWord = q<HTMLElement>('.cin5-mark-word');
  const markTag = q<HTMLElement>('.cin5-mark-tag');
  const hint = q<HTMLElement>('.cin5-hint');
  const skipBtn = q<HTMLButtonElement>('.cin5-skip');
  const veil = q<HTMLElement>('.cin5-veil');
  const rail = q<HTMLElement>('.cin5-rail');
  const railStops = qa<HTMLButtonElement>('.cin5-rail-stop');
  if (!root || paths.length !== N_PATHS || texts.length !== TEXTS.length) return;

  let returning = false;
  try {
    returning = localStorage.getItem(SEEN_KEY) === '1';
  } catch {
    /* private mode */
  }

  const trackTop = () => track.getBoundingClientRect().top + window.scrollY;

  const seek = (fracOfTrack: number) => {
    const span = track.offsetHeight - window.innerHeight;
    window.scrollTo({ top: trackTop() + span * fracOfTrack, behavior: 'smooth' });
  };
  railStops.forEach((stop, i) => {
    stop.addEventListener('click', () => seek(CHAPTERS[i].at));
  });

  if (skipBtn) {
    skipBtn.addEventListener('click', () => {
      try {
        localStorage.setItem(SEEN_KEY, '1');
      } catch {
        /* private mode */
      }
      window.scrollTo({ top: trackTop() + track.offsetHeight - window.innerHeight + 2 });
    });
    if (returning) skipBtn.classList.add('cin5-skip--on');
    else window.setTimeout(() => skipBtn.classList.add('cin5-skip--on'), 3000);
  }

  // Palette from the page's scoped tokens: ink, faint gray, and one warmth.
  const cs = getComputedStyle(stage);
  const ink = parseColor(cs.getPropertyValue('--text-primary'));
  const dim = parseColor(cs.getPropertyValue('--text-faint'));
  const cta = parseColor(cs.getPropertyValue('--cta'));
  const datumCol = mixRGB(ink, cta, 0.5);
  const pulseCol = mixRGB(cta, ink, 0.15);

  /* Measure the finished drawing: element centers, per-sheet bounds, and the
     path lengths that draw-on scrubbing needs. */
  const els: Array<SVGPathElement | SVGTextElement> = [...paths, ...texts];
  const centers: Array<[number, number]> = els.map((el) => {
    const b = el.getBBox();
    return [b.x + b.width / 2, b.y + b.height / 2];
  });

  // Sheet centroids + bounds, then per-sheet cluster scale (fit in a frame).
  const SHEET_POS = frames.map((g) => ({
    ax: parseFloat(g.dataset.ax || '0'),
    ay: parseFloat(g.dataset.ay || '0'),
  }));
  const sCx = new Float32Array(6);
  const sCy = new Float32Array(6);
  const sScale = new Float32Array(6);
  for (let s = 0; s < 6; s++) {
    let minX = Infinity,
      maxX = -Infinity,
      minY = Infinity,
      maxY = -Infinity,
      n = 0;
    for (let i = 0; i < N_ELS; i++) {
      if (elSheet(i) !== s) continue;
      const b = els[i].getBBox();
      minX = Math.min(minX, b.x);
      maxX = Math.max(maxX, b.x + b.width);
      minY = Math.min(minY, b.y);
      maxY = Math.max(maxY, b.y + b.height);
      sCx[s] += centers[i][0];
      sCy[s] += centers[i][1];
      n++;
    }
    sCx[s] /= Math.max(1, n);
    sCy[s] /= Math.max(1, n);
    sScale[s] = Math.min(0.6, 264 / Math.max(1, maxX - minX), 150 / Math.max(1, maxY - minY));
  }

  // Exploded (beat 01) and clustered (beat 02) targets, deterministic.
  const rng = mulberry32(20260706);
  const scT = new Float32Array(N_ELS * 3); // tx, ty, rot
  const clT = new Float32Array(N_ELS * 3); // tx, ty, scale
  for (let i = 0; i < N_ELS; i++) {
    const [cx, cy] = centers[i];
    const dirX = rng() < 0.5 ? -1 : 1;
    scT[i * 3] = dirX * (110 + rng() * 330);
    scT[i * 3 + 1] = (rng() - 0.5) * 2 * (70 + rng() * 240);
    scT[i * 3 + 2] = (rng() - 0.5) * 46;
    const s = elSheet(i);
    const ks = sScale[s];
    clT[i * 3] = SHEET_POS[s].ax + (cx - sCx[s]) * ks - cx;
    clT[i * 3 + 1] = SHEET_POS[s].ay + 8 + (cy - sCy[s]) * ks - cy;
    clT[i * 3 + 2] = ks;
  }

  // Draw-on lengths.
  for (let i = 0; i < N_PATHS; i++) {
    if (!PATHS[i].redraw) continue;
    const el = paths[i];
    const len = el.getTotalLength();
    el.style.strokeDasharray = `${len}`;
    el.dataset.len = String(len);
  }
  const prepLine = (el: SVGPathElement | null) => {
    if (!el) return 0;
    const len = el.getTotalLength();
    el.style.strokeDasharray = `${len}`;
    el.style.strokeDashoffset = `${len}`;
    return len;
  };
  const datumLen = prepLine(datumLine);
  const dropLens = drops.map((el) => {
    const len = el.getTotalLength();
    // dashed line still draw-scrubs cleanly with the native pattern
    el.style.strokeDasharray = `4 6`;
    return len;
  });
  const pulseLine = pulses[1] ?? null;
  const pulseGlow = pulses[0] ?? null;
  const pulseLen = pulseLine ? pulseLine.getTotalLength() : 0;

  // Spring state per element: x, y, rot, scale (+velocities), opacity, warmth.
  const px = new Float32Array(N_ELS),
    pvx = new Float32Array(N_ELS);
  const py = new Float32Array(N_ELS),
    pvy = new Float32Array(N_ELS);
  const pr = new Float32Array(N_ELS),
    pvr = new Float32Array(N_ELS);
  const psc = new Float32Array(N_ELS),
    pvs = new Float32Array(N_ELS);
  const pop = new Float32Array(N_ELS);
  const pwm = new Float32Array(N_ELS);
  for (let i = 0; i < N_ELS; i++) {
    px[i] = scT[i * 3];
    py[i] = scT[i * 3 + 1];
    pr[i] = scT[i * 3 + 2];
    psc[i] = 0.9;
  }

  // Pause all work while the track is offscreen.
  let active = true;
  const io = new IntersectionObserver((entries) => {
    active = entries[0]?.isIntersecting ?? true;
  });
  io.observe(track);

  let last = performance.now();
  let pSmooth = 0;
  let bobAmp = 4;
  let seenSaved = false;
  let lastChapter = -1;
  let lastDimText = '';
  const K = 26; // spring stiffness, roughly a 0.8s organic settle
  const DAMP = 7.5;

  const targetProgress = () => {
    const span = track.offsetHeight - window.innerHeight;
    if (span <= 0) return 1;
    const rect = track.getBoundingClientRect();
    return clamp01(-rect.top / span);
  };

  const spanDimText = texts[0]; // `48'-0" CLEAR SPAN`, the contested number

  const frame = (now: number) => {
    requestAnimationFrame(frame);
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    if (!active) return;
    const time = now / 1000;

    const pT = targetProgress();
    pSmooth += (pT - pSmooth) * (1 - Math.exp(-dt * 7));
    if (Math.abs(pT - pSmooth) < 0.0004) pSmooth = pT;
    const p = pSmooth;

    const seg =
      p < SCATTER_END ? 0 : p < SILOS_END ? 1 : p < LEAVE_END ? 2 : p < CONFLICT_END ? 3 : p < INERT_END ? 4 : 5;
    const asm = clamp01((p - ASM_AT) / ASM_SPAN); // registration snap
    const fadeIn = smooth(0.002, 0.04, p); // cold open from dark
    const leaveLocal = clamp01((p - SILOS_END) / (LEAVE_END - SILOS_END));
    // While the wordmark holds the stage the drawing recedes to a ghost;
    // the datum line and its label stay: the reference remains.
    const markE = smooth(0.885, 0.93, p) * (1 - smooth(0.958, 0.985, p));
    const markDim = 1 - 0.82 * markE;

    // Sheet bob dies completely in the inert beat and never returns.
    const ease = 1 - Math.exp(-dt * 3);
    bobAmp += ([4, 5, 5, 5, 0, 0][seg] - bobAmp) * ease;
    const dampMul = Math.exp(-DAMP * dt);

    /* ── Elements: per-beat targets, springs do the rest ── */
    for (let i = 0; i < N_ELS; i++) {
      const sheet = elSheet(i);
      const ord = elOrder(i);
      const isFld = sheet === FLD_SHEET;
      const redraw = i < N_PATHS && PATHS[i].redraw === true;

      let tx: number,
        ty: number,
        trr: number,
        tsc: number,
        top: number,
        twm = 0;
      const bob = Math.sin(time * 0.9 + sheet * 1.7) * bobAmp;

      if (seg === 0) {
        tx = scT[i * 3];
        ty = scT[i * 3 + 1] + bob;
        trr = scT[i * 3 + 2];
        tsc = 0.9;
        top = 0.5;
      } else if (seg <= 4) {
        tx = clT[i * 3];
        ty = clT[i * 3 + 1] + bob;
        trr = 0;
        tsc = clT[i * 3 + 2];
        top = seg === 4 ? 0.28 : 0.62;
        if (isFld && seg >= 2) {
          if (seg === 2) {
            // flare warm as the loss registers, then slide off the table
            const drift = smooth(0.3, 0.9, leaveLocal);
            tx += drift * 900;
            twm = bump(0.02, 0.2, 0.35, 0.7, leaveLocal) * 0.7;
            top = (0.62 + 0.38 * bump(0.02, 0.18, 0.3, 0.6, leaveLocal)) * (1 - smooth(0.45, 0.9, leaveLocal));
          } else {
            tx += 900;
            top = 0; // gone, until the datum re-draws it
          }
        }
      } else {
        // The turn: registration. Everything springs home in construction
        // order; the lost Field linework re-draws in place instead.
        const wake = smooth(ord * 0.55, ord * 0.55 + 0.3, asm);
        if (redraw) {
          // hard-place at true position; the dash draw-on is the motion
          px[i] = 0;
          py[i] = 0;
          pr[i] = 0;
          psc[i] = 1;
          pvx[i] = 0;
          pvy[i] = 0;
          pvr[i] = 0;
          pvs[i] = 0;
          tx = 0;
          ty = 0;
          trr = 0;
          tsc = 1;
          const el = paths[i];
          const len = parseFloat(el.dataset.len || '0');
          el.style.strokeDashoffset = `${(len * (1 - wake)).toFixed(1)}`;
          top = wake > 0.001 ? 0.95 : 0;
          twm = wake;
        } else if (wake > 0.001) {
          tx = 0;
          ty = 0;
          trr = 0;
          tsc = 1;
          top = 0.95 * (0.2 + 0.8 * wake);
          twm = wake;
        } else {
          tx = clT[i * 3] + (isFld ? 900 : 0);
          ty = clT[i * 3 + 1];
          trr = 0;
          tsc = clT[i * 3 + 2];
          top = isFld ? 0 : 0.28;
        }
      }

      pvx[i] = (pvx[i] + (tx - px[i]) * K * dt) * dampMul;
      pvy[i] = (pvy[i] + (ty - py[i]) * K * dt) * dampMul;
      pvr[i] = (pvr[i] + (trr - pr[i]) * K * dt) * dampMul;
      pvs[i] = (pvs[i] + (tsc - psc[i]) * K * dt) * dampMul;
      px[i] += pvx[i] * dt;
      py[i] += pvy[i] * dt;
      pr[i] += pvr[i] * dt;
      psc[i] += pvs[i] * dt;
      const propEase = 1 - Math.exp(-dt * 4.5);
      pop[i] += (top - pop[i]) * propEase;
      pwm[i] += (twm - pwm[i]) * propEase;

      const el = els[i];
      const a = pop[i] * fadeIn * markDim;
      el.style.opacity = a <= 0.004 ? '0' : a.toFixed(3);
      if (a > 0.004) {
        el.style.transform = `translate(${px[i].toFixed(1)}px, ${py[i].toFixed(1)}px) rotate(${pr[i].toFixed(2)}deg) scale(${psc[i].toFixed(3)})`;
        const col = rgba(mixRGB(dim, ink, pwm[i]), 1);
        if (i < N_PATHS) (el as SVGPathElement).style.stroke = col;
        else (el as SVGTextElement).style.fill = col;
      }
    }

    /* ── Sheet frames ── */
    const frameIn = smooth(SCATTER_END + 0.01, SCATTER_END + 0.045, p);
    const frameOut = 1 - smooth(INERT_END, INERT_END + 0.045, p);
    for (let s = 0; s < 6; s++) {
      const el = frames[s];
      if (!el) continue;
      let a = frameIn * frameOut * (seg === 4 ? 0.4 : 0.8);
      let dx = 0;
      if (s === FLD_SHEET && p >= SILOS_END) {
        const drift = smooth(0.3, 0.9, leaveLocal);
        dx = drift * 900;
        a *= 1 - smooth(0.45, 0.9, leaveLocal);
        if (p >= LEAVE_END) a = 0;
      }
      el.style.opacity = a <= 0.004 ? '0' : a.toFixed(3);
      if (a > 0.004) {
        el.style.transform = `translate(${dx.toFixed(1)}px, ${(Math.sin(time * 0.9 + s * 1.7) * bobAmp).toFixed(1)}px)`;
        el.style.color = rgba(dim, 1);
      }
    }

    /* ── Conflicting dimensions (beat 04, resolved at the turn) ── */
    for (let c = 0; c < CONFLICTS.length; c++) {
      const el = conflicts[c];
      if (!el) continue;
      const inAt = LEAVE_END + 0.012 + c * 0.02;
      const stamp = smooth(inAt, inAt + 0.018, p);
      // fly home to the one true dimension, fading as they merge
      const home = smooth(ASM_AT + 0.02, ASM_AT + 0.09, p);
      const a = stamp * (seg === 4 ? 0.45 : 1) * (1 - home) * fadeIn;
      el.style.opacity = a <= 0.004 ? '0' : a.toFixed(3);
      if (a > 0.004) {
        const wob = Math.sin(time * 2.1 + c * 2.4) * (seg === 3 ? 2.2 : 0);
        const hx = (TRUE_DIM_XY[0] - CONFLICTS[c].x) * home;
        const hy = (TRUE_DIM_XY[1] - CONFLICTS[c].y) * home;
        const pop2 = 1 + 0.18 * (1 - smooth(inAt, inAt + 0.03, p));
        el.style.transform = `translate(${hx.toFixed(1)}px, ${(hy + wob).toFixed(1)}px) scale(${pop2.toFixed(3)})`;
        el.style.color = rgba(mixRGB(dim, ink, seg === 3 ? 0.45 : 0.15), 1);
      }
    }

    // The contested number settles: it flickers through the wrong values
    // while the copies fly home, then locks true.
    if (spanDimText) {
      const settle = p > ASM_AT + 0.02 && p < ASM_AT + 0.1;
      const next = settle
        ? `${CONFLICTS[Math.floor(p * 400) % CONFLICTS.length].v} CLEAR SPAN`
        : `${TRUE_DIM} CLEAR SPAN`;
      if (next !== lastDimText) {
        spanDimText.textContent = next;
        lastDimText = next;
      }
    }

    /* ── The datum line and its reference furniture ── */
    const lineDraw = smooth(INERT_END, INERT_END + 0.05, p);
    if (datumLine) {
      datumLine.style.strokeDashoffset = `${(datumLen * (1 - lineDraw)).toFixed(1)}`;
      datumLine.style.opacity = lineDraw > 0.001 ? '1' : '0';
      datumLine.style.stroke = rgba(datumCol, 0.9);
    }
    const tickA = smooth(INERT_END + 0.04, INERT_END + 0.075, p);
    if (datumTicks) {
      datumTicks.style.opacity = (tickA * 0.7).toFixed(3);
      datumTicks.style.stroke = rgba(datumCol, 0.8);
    }
    if (datumLabel) {
      datumLabel.style.opacity = tickA.toFixed(3);
      datumLabel.style.fill = rgba(mixRGB(ink, cta, 0.35), 1);
    }
    for (let i = 0; i < DROPLINES.length; i++) {
      const el = drops[i];
      if (!el) continue;
      const at = 0.845 + i * 0.018;
      const draw = smooth(at, at + 0.03, p);
      el.style.opacity = (draw * 0.65).toFixed(3);
      el.style.strokeDashoffset = `${(dropLens[i] * (1 - draw)).toFixed(1)}`;
      el.style.stroke = rgba(datumCol, 0.9);
    }

    /* ── Life on the finished profile: real time, so the drawing keeps
           breathing even when the visitor stops scrolling ── */
    const pulseA = smooth(0.88, 0.92, p) * (1 - smooth(0.985, 1, p));
    const drawPulse = (el: SVGPathElement | null, alpha: number) => {
      if (!el) return;
      el.style.opacity = alpha <= 0.004 ? '0' : alpha.toFixed(3);
      if (alpha > 0.004) {
        const t = frac(time * 0.22);
        const segLen = pulseLen * 0.08;
        el.style.strokeDasharray = `${segLen.toFixed(1)} ${pulseLen.toFixed(1)}`;
        el.style.strokeDashoffset = `${(-t * pulseLen).toFixed(1)}`;
        el.style.stroke = rgba(pulseCol, 1);
      }
    };
    drawPulse(pulseLine, pulseA * 0.9 * (1 - 0.5 * markE));
    drawPulse(pulseGlow, pulseA * 0.22 * (1 - 0.5 * markE));

    // Once assembled, the whole drawing breathes. Barely.
    const alive = smooth(0.86, 0.92, p);
    const sBreath = 1 + alive * 0.004 * Math.sin(time * 1.1);
    root.style.transform = `scale(${sBreath.toFixed(5)})`;
    root.style.transformOrigin = '800px 560px';

    /* ── Typography ── */
    const beatSpecs = [...BEATS.map((b) => b.window), TURN_BEAT.window];
    for (let i = 0; i < beatEls.length && i < beatSpecs.length; i++) {
      const el = beatEls[i];
      const [A, B] = beatSpecs[i];
      const vis = bump(A, A + 0.028, B - 0.02, B, p);
      el.style.opacity = vis.toFixed(3);
      el.style.visibility = vis > 0.001 ? 'visible' : 'hidden';
      if (vis > 0.001) {
        const enter = smooth(A, A + 0.05, p);
        const exit = smooth(B - 0.026, B, p);
        el.style.transform = `translateY(${((1 - enter) * 4 - exit * 4).toFixed(2)}vh)`;
      }
    }

    if (mark) {
      const e = markE;
      mark.style.opacity = e.toFixed(3);
      mark.style.visibility = e > 0.001 ? 'visible' : 'hidden';
      if (markWord) {
        markWord.style.transform = `scale(${(0.9 + 0.1 * e).toFixed(4)})`;
        markWord.style.letterSpacing = `${(0.3 - 0.18 * e).toFixed(3)}em`;
      }
      if (markTag) {
        markTag.style.opacity = smooth(0.91, 0.945, p).toFixed(3);
      }
    }
    if (!seenSaved && p > 0.9) {
      seenSaved = true;
      try {
        localStorage.setItem(SEEN_KEY, '1');
      } catch {
        /* private mode: the film just replays next visit */
      }
    }

    /* ── Chrome ── */
    if (hint) {
      const o = 1 - smooth(0.004, 0.026, p) + smooth(0.96, 0.99, p);
      hint.style.opacity = clamp01(o).toFixed(3);
    }
    if (veil) veil.style.opacity = smooth(VEIL_AT, 0.998, p).toFixed(3);
    if (skipBtn) {
      skipBtn.style.opacity = p > 0.9 ? '0' : '';
      skipBtn.style.pointerEvents = p > 0.9 ? 'none' : '';
    }
    if (rail) {
      const o = bump(0.01, 0.04, 0.93, 0.97, p);
      rail.style.opacity = o.toFixed(3);
      rail.style.pointerEvents = o > 0.1 ? 'auto' : 'none';
    }
    let ch = 0;
    for (let i = CHAPTERS.length - 1; i >= 0; i--) {
      if (p >= (i === 0 ? 0 : (CHAPTERS[i - 1].at + CHAPTERS[i].at) / 2)) {
        ch = i;
        break;
      }
    }
    if (ch !== lastChapter) {
      lastChapter = ch;
      railStops.forEach((stop, i) => stop.classList.toggle('cin5-rail-stop--on', i === ch));
    }
  };
  requestAnimationFrame(frame);
}
