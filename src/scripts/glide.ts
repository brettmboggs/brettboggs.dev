/* The Glide.
   A one button flyer for the 404 page. Hold to climb, let go to fall, and keep
   the bird off the ridge. It opens over open prairie, then timber gates come up
   out of the ridge, then the cave closes a rock ceiling over the top and the
   corridor narrows from there. The light walks to dusk with distance, so how
   dark it got is how far you went.

   No dependencies. 2D canvas. The camera is fixed vertically, so the canvas is
   the playfield and y is screen space, pointing down. */

const BIRD_X = 0.3; // share of the width the bird holds
const R = 11; // bird radius, and an honest hitbox
const LIFT = 2400;
const GRAV = 1900;
const VY_UP = -430;
const VY_DOWN = 470;
const SPEED0 = 265;
const SPEED_GAIN = 0.085;
const SPEED_CAP = 480;
const METERS = 20; // world px per metre
const DUSK_AT = 1800; // metres from golden hour to full dusk
const BEST_KEY = 'glide.best';

// where the run changes character
const GATES_AT = 300;
const CAVE_AT = 1500;
const GATE_SPACING = 600;
const GATE_HALF = 17;
const CAVE_IN = 340; // metres the cave roof takes to come down
const GATE_STOP = 700; // world px of clear air before the cave starts
// the first gate stands clear of where the stage is called, so it arrives from
// off screen rather than appearing on top of the bird
const GATE_LEAD = 900;

type Rgb = [number, number, number];

const hex = (s: string): Rgb => [
  parseInt(s.slice(1, 3), 16),
  parseInt(s.slice(3, 5), 16),
  parseInt(s.slice(5, 7), 16),
];

const mix = (a: Rgb, b: Rgb, t: number): Rgb => [
  a[0] + (b[0] - a[0]) * t,
  a[1] + (b[1] - a[1]) * t,
  a[2] + (b[2] - a[2]) * t,
];

const css = (c: Rgb, alpha = 1) =>
  alpha >= 1
    ? `rgb(${c[0] | 0} ${c[1] | 0} ${c[2] | 0})`
    : `rgb(${c[0] | 0} ${c[1] | 0} ${c[2] | 0} / ${alpha})`;

const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);

/* Golden hour walking down to dusk. No sun disc, only the glow it leaves. */
const DAY = {
  skyTop: hex('#F1E6D0'),
  skyMid: hex('#F0D9A4'),
  skyLow: hex('#E9B96A'),
  far: hex('#BFC8CC'),
  mid: hex('#9AA486'),
  near: hex('#61684A'),
  land: hex('#33291C'),
  rim: hex('#D9971E'),
};

const DUSK = {
  skyTop: hex('#241D14'),
  skyMid: hex('#4B3325'),
  skyLow: hex('#8F3F22'),
  far: hex('#3C3529'),
  mid: hex('#2F2A1F'),
  near: hex('#241E15'),
  land: hex('#17120C'),
  rim: hex('#B85C38'),
};

type Phase = 'attract' | 'playing' | 'over';
type Stage = 'open' | 'gates' | 'cave';

export interface GlideHandle {
  destroy(): void;
}

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  life: number;
}

export function mountGlide(root: HTMLElement): GlideHandle {
  const canvas = root.querySelector<HTMLCanvasElement>('[data-glide-canvas]');
  if (!canvas) throw new Error('glide: no canvas');
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('glide: no 2d context');

  const hud = root.querySelector<HTMLElement>('[data-glide-hud]');
  const distOut = root.querySelector<HTMLElement>('[data-glide-dist]');
  const bestOut = root.querySelector<HTMLElement>('[data-glide-best]');
  const stageOut = root.querySelector<HTMLElement>('[data-glide-stage]');
  const hint = root.querySelector<HTMLElement>('[data-glide-hint]');
  const intro = root.querySelector<HTMLElement>('[data-glide-intro]');
  const overCard = root.querySelector<HTMLElement>('[data-glide-over]');
  const overDist = root.querySelector<HTMLElement>('[data-glide-over-dist]');
  const overBest = root.querySelector<HTMLElement>('[data-glide-over-best]');
  const overNote = root.querySelector<HTMLElement>('[data-glide-over-note]');
  const playBtn = root.querySelector<HTMLButtonElement>('[data-glide-play]');
  const againBtn = root.querySelector<HTMLButtonElement>('[data-glide-again]');

  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)');

  let w = 0;
  let h = 0;
  let dpr = 1;
  let hs = 1; // vertical scale, so a short canvas gets a calmer ridge

  /* --- terrain: three sines under a slowly drifting amplitude, so a run has
     calm stretches and rough ones without any authored level data --- */
  let p0 = 0;
  let p1 = 0;
  let p2 = 0;
  let p3 = 0;

  function reseed() {
    p0 = Math.random() * 99;
    p1 = Math.random() * 99;
    p2 = Math.random() * 99;
    p3 = Math.random() * 99;
  }

  const groundBase = () => h * 0.86;
  // in a run the bird sits left with the world ahead of it. Idling, it flies
  // out on the right instead, clear of the card the message sits in.
  const anchor = () => (phase === 'playing' ? BIRD_X : 0.7);

  /** height of the ridge above its baseline, positive up. The first stretch
      eases in from flat, so nobody is thrown at a hillside on frame one. */
  function ridgeAt(x: number) {
    const amp = 34 + 15 * Math.sin(x * 0.00047 + p0);
    const ease = clamp(x / 900, 0, 1);
    return (
      (amp * Math.sin(x * 0.00295 + p1) +
        17 * Math.sin(x * 0.0069 + p2) +
        6 * Math.sin(x * 0.0161 + p3)) *
      hs *
      ease
    );
  }

  const floorY = (x: number) => groundBase() - ridgeAt(x);

  // a stable per-gate number, so gate n is the same gate every time it draws
  function hash(n: number) {
    const r = Math.sin(n * 127.1 + p2 * 13.7) * 43758.5453;
    return r - Math.floor(r);
  }

  let phase: Phase = 'attract';
  let bx = 0;
  let by = 0;
  let vy = 0;
  let speed = SPEED0;
  let holding = false;
  let camX = 0;
  let startX = 0;
  let dist = 0;
  let light = 1;
  let flapPhase = 0;
  let spin = 0;
  let crashT = 0;
  let stage: Stage = 'open';
  let dust: Particle[] = [];
  let best = 0;
  let hudTint = '';

  try {
    best = Number(localStorage.getItem(BEST_KEY)) || 0;
  } catch {
    best = 0;
  }

  // how far down the canvas the message card reaches, so the idling bird can
  // stay clear of it. Measured on layout changes rather than every frame.
  let introBottom = 0;
  function measureIntro() {
    if (!intro || intro.hasAttribute('hidden')) {
      introBottom = 0;
      return;
    }
    introBottom = Math.max(0, intro.getBoundingClientRect().bottom - canvas!.getBoundingClientRect().top);
  }

  function resize() {
    const rect = canvas!.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    w = Math.max(1, Math.round(rect.width));
    h = Math.max(1, Math.round(rect.height));
    hs = clamp(h / 440, 0.62, 1.15);
    canvas!.width = Math.round(w * dpr);
    canvas!.height = Math.round(h * dpr);
    ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  /* --- the shape of the run -------------------------------------------- */

  function stageAt(m: number): Stage {
    if (m < GATES_AT) return 'open';
    if (m < CAVE_AT) return 'gates';
    return 'cave';
  }

  /** clear height a gate leaves, tightening the deeper the run goes */
  function gapSize(m: number) {
    return (215 - Math.min(58, Math.max(0, m - GATES_AT) * 0.05)) * hs;
  }

  /** clear height of the cave corridor. The roof comes down over the first
      stretch instead of arriving at full depth on top of whoever is flying
      high when the cave starts, which was an unavoidable death. */
  function corridor(m: number) {
    const settled = (200 - Math.min(68, Math.max(0, m - CAVE_AT - CAVE_IN) * 0.045)) * hs;
    const wide = h * 1.6; // starts above the frame entirely
    const ease = clamp((m - CAVE_AT) / CAVE_IN, 0, 1);
    return wide + (settled - wide) * ease;
  }

  /** the rock ceiling, only once the cave has started. It follows the floor,
      so the corridor is a tube through the ridge rather than a flat lid. */
  function ceilYAt(x: number, m: number) {
    const c = corridor(m);
    const y =
      floorY(x) - c - (22 * Math.sin(x * 0.0041 + p2) + 12 * Math.sin(x * 0.0111 + p3)) * hs;
    // parked just above the frame until it descends, so it neither draws nor
    // kills, and the bird cannot slip out over the top of it either
    return Math.max(-24, y);
  }

  const gateZero = () => GATES_AT * METERS + GATE_LEAD;

  /** the gate straddling this world x, if there is one. Gates belong to the
      world, not to the stage: they are simply placed from here to the cave,
      so one is never conjured into existence around whoever is flying. */
  function gateNear(x: number) {
    // the idling scene stays open country however long it is left running
    if (phase !== 'playing') return null;
    const x0 = gateZero();
    const n = Math.round((x - x0) / GATE_SPACING);
    if (n < 0) return null;
    const gx = x0 + n * GATE_SPACING;
    // stop short of the cave, or the last gate blinks out as the roof arrives
    if (gx > CAVE_AT * METERS - GATE_STOP) return null;
    const fy = floorY(gx);
    // the gap must fit between the top margin and the ridge, on any canvas
    const gap = Math.min(gapSize(distAt(gx)), Math.max(70, fy - 62));
    const lo = gap / 2 + 20;
    const hi = fy - gap / 2 - 22;
    const want = fy - 78 * hs - hash(n) * 130 * hs;
    const center = hi < lo ? (lo + hi) / 2 : clamp(want, lo, hi);
    return { x: gx, center, gap };
  }

  const distAt = (x: number) => Math.max(0, (x - startX) / METERS);

  /* --- simulation ------------------------------------------------------- */

  function step(dt: number) {
    if (crashT > 0) {
      crashT -= dt;
      spin += dt * 12;
      vy += GRAV * dt;
      by += vy * dt;
      const fy = floorY(bx);
      if (by > fy - 4) {
        by = fy - 4;
        vy *= -0.3;
      }
      camX += (bx - w * anchor() - camX) * Math.min(1, dt * 5);
      stepDust(dt);
      if (crashT <= 0) finish();
      return;
    }

    const playing = phase === 'playing';
    const m = playing ? dist : 0;

    // idling, the bird flies itself with the same one button
    const up = playing ? holding : autopilot();

    vy += (up ? -LIFT : GRAV) * dt;
    vy = clamp(vy, VY_UP, VY_DOWN);

    speed = playing ? Math.min(SPEED_CAP, SPEED0 + dist * SPEED_GAIN) : SPEED0;
    bx += speed * dt;
    by += vy * dt;

    if (playing) {
      dist = distAt(bx);
      const next = stageAt(dist);
      if (next !== stage) {
        stage = next;
        announce(stage);
      }
      light = 1 - Math.min(1, dist / DUSK_AT);
    }

    // the top of the frame is sky in the open, and rock once the cave starts
    const ceil = stage === 'cave' ? ceilYAt(bx, m) : 0;
    if (by < ceil + R) {
      if (stage === 'cave' && playing) return crash();
      by = Math.max(by, ceil + R);
      if (vy < 0) vy = 0;
    }

    const fy = floorY(bx);
    if (by > fy - R) {
      if (playing) return crash();
      by = fy - R;
      if (vy > 0) vy = 0;
    }

    const gate = gateNear(bx);
    if (gate && Math.abs(bx - gate.x) < GATE_HALF + R) {
      const top = gate.center - gate.gap / 2;
      const bot = gate.center + gate.gap / 2;
      if (by - R < top || by + R > bot) {
        if (playing) return crash();
        by = clamp(by, top + R, bot - R);
      }
    }

    flapPhase += dt * (up ? 13 : 3.5);
    camX += (bx - w * anchor() - camX) * Math.min(1, dt * 14);

    if (up && Math.random() < dt * 26) {
      dust.push({
        x: bx - 14,
        y: by + 6,
        vx: -speed * 0.35 - Math.random() * 40,
        vy: 40 + Math.random() * 60,
        life: 0.35 + Math.random() * 0.25,
      });
    }
    stepDust(dt);
  }

  function stepDust(dt: number) {
    for (let i = dust.length - 1; i >= 0; i--) {
      const d = dust[i];
      d.life -= dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      if (d.life <= 0) dust.splice(i, 1);
    }
  }

  /** the idling bird aims at the middle of whatever it is flying through, and
      stays under the message card, which on a phone covers most of the sky */
  function autopilot() {
    const ahead = bx + 190;
    const gate = gateNear(ahead);
    let target = gate && Math.abs(ahead - gate.x) < 300 ? gate.center : floorY(ahead) - 96 * hs;
    const lo = introBottom + 30;
    const hi = floorY(ahead) - 34;
    if (introBottom > 0 && hi - lo > 24) target = clamp(target, lo, hi);
    return by > target;
  }

  function crash() {
    crashT = 0.8;
    spin = 0;
    holding = false;
    vy = -150;
    for (let i = 0; i < 16; i++) {
      dust.push({
        x: bx,
        y: by,
        vx: (Math.random() - 0.4) * 240,
        vy: (Math.random() - 0.5) * 260,
        life: 0.45 + Math.random() * 0.45,
      });
    }
  }

  function announce(s: Stage) {
    if (!stageOut) return;
    stageOut.textContent = s === 'gates' ? 'The stands' : s === 'cave' ? 'The cave' : '';
    stageOut.classList.remove('is-on');
    void stageOut.offsetWidth; // restart the fade
    if (s !== 'open') stageOut.classList.add('is-on');
  }

  function finish() {
    phase = 'over';
    holding = false;
    const score = Math.round(dist);
    const record = score > best;
    if (record) {
      best = score;
      try {
        localStorage.setItem(BEST_KEY, String(best));
      } catch {
        /* private mode: the score just does not outlive the tab */
      }
    }
    if (overDist) overDist.textContent = `${score.toLocaleString()} m`;
    if (overBest) overBest.textContent = `${best.toLocaleString()} m`;
    if (overNote) {
      overNote.textContent = record
        ? 'A new best.'
        : stage === 'cave'
          ? 'The cave got you.'
          : stage === 'gates'
            ? 'Clipped a stand.'
            : 'Into the ridge.';
    }
    hud?.setAttribute('hidden', '');
    hint?.setAttribute('hidden', '');
    stageOut?.classList.remove('is-on');
    overCard?.removeAttribute('hidden');
    canvas!.classList.remove('is-live');
    root.classList.remove('is-live');
    document.documentElement.classList.remove('glide-locked');
    window.setTimeout(() => againBtn?.focus(), 60);
  }

  /* --- drawing ---------------------------------------------------------- */

  function tint(t: number) {
    return {
      skyTop: mix(DAY.skyTop, DUSK.skyTop, t),
      skyMid: mix(DAY.skyMid, DUSK.skyMid, t),
      skyLow: mix(DAY.skyLow, DUSK.skyLow, t),
      far: mix(DAY.far, DUSK.far, t),
      mid: mix(DAY.mid, DUSK.mid, t),
      near: mix(DAY.near, DUSK.near, t),
      land: mix(DAY.land, DUSK.land, t),
      rim: mix(DAY.rim, DUSK.rim, t),
    };
  }

  function ridgeBand(color: string, factor: number, amp: number, len: number, lift: number, ph: number) {
    const y0 = h * 0.58 + lift * hs;
    ctx!.fillStyle = color;
    ctx!.beginPath();
    ctx!.moveTo(0, h);
    for (let sx = 0; sx <= w + 10; sx += 10) {
      // parallax slows the layer down, it must not squash its shape: offset
      // the scroll by the factor, then walk the screen at full width
      const wx = camX * factor + sx;
      const y =
        y0 -
        (amp * Math.sin(wx / len + ph) + amp * 0.42 * Math.sin(wx / (len * 0.38) + ph * 1.7)) * hs;
      ctx!.lineTo(sx, y);
    }
    ctx!.lineTo(w, h);
    ctx!.closePath();
    ctx!.fill();
  }

  /** a gate drawn as timber, the same frame that stands on the front page */
  function gate(g: { x: number; center: number; gap: number }, land: string, rim: string) {
    const sx = g.x - camX;
    const top = g.center - g.gap / 2;
    const bot = g.center + g.gap / 2;
    const fy = floorY(g.x);

    ctx!.fillStyle = land;
    ctx!.fillRect(sx - GATE_HALF, -2, GATE_HALF * 2, top + 2);
    ctx!.fillRect(sx - GATE_HALF, bot, GATE_HALF * 2, fy - bot + 6);

    // rungs and a brace, so the block reads as built timber and not a pipe
    ctx!.strokeStyle = rim;
    ctx!.lineWidth = 1.3;
    ctx!.globalAlpha = 0.5;
    ctx!.beginPath();
    const rungs = (y0: number, y1: number) => {
      for (let y = y0 + 14; y < y1 - 6; y += 22) {
        ctx!.moveTo(sx - GATE_HALF + 2.5, y);
        ctx!.lineTo(sx + GATE_HALF - 2.5, y);
        ctx!.moveTo(sx - GATE_HALF + 2.5, y);
        ctx!.lineTo(sx + GATE_HALF - 2.5, y + 22);
      }
      // the rails the rungs run between
      ctx!.moveTo(sx - GATE_HALF + 2.5, y0);
      ctx!.lineTo(sx - GATE_HALF + 2.5, y1);
      ctx!.moveTo(sx + GATE_HALF - 2.5, y0);
      ctx!.lineTo(sx + GATE_HALF - 2.5, y1);
    };
    rungs(0, top);
    rungs(bot, fy);
    ctx!.stroke();
    ctx!.globalAlpha = 1;

    // the lit edges of the opening
    ctx!.strokeStyle = rim;
    ctx!.lineWidth = 2.5;
    ctx!.beginPath();
    ctx!.moveTo(sx - GATE_HALF, top);
    ctx!.lineTo(sx + GATE_HALF, top);
    ctx!.moveTo(sx - GATE_HALF, bot);
    ctx!.lineTo(sx + GATE_HALF, bot);
    ctx!.stroke();
  }

  /** one wing: broad at the shoulder, tapering to a point, swept back. Theta
      is the beat, negative on the recovery stroke and positive on the power
      stroke. Kept shallow so the tips stay near the hitbox the bird has. */
  function wing(theta: number, len: number, c: string, alpha: number) {
    const rootFx = 6; // leading edge at the shoulder
    const rootFy = -2.4;
    const rootBx = -10; // trailing edge, giving the wing its root chord
    const rootBy = 0.6;
    const tx = rootFx - len * Math.cos(theta);
    const ty = rootFy + len * Math.sin(theta);
    // perpendicular to the wing, to bow the two edges apart
    const px = -Math.sin(theta);
    const py = -Math.cos(theta);
    const mx = (rootFx + tx) / 2;
    const my = (rootFy + ty) / 2;

    ctx!.globalAlpha = alpha;
    ctx!.fillStyle = c;
    ctx!.beginPath();
    ctx!.moveTo(rootFx, rootFy);
    ctx!.quadraticCurveTo(mx + px * 4.5, my + py * 4.5, tx, ty);
    ctx!.quadraticCurveTo(mx - px * 6, my - py * 6, rootBx, rootBy);
    ctx!.closePath();
    ctx!.fill();
    ctx!.globalAlpha = 1;
  }

  function bird(c: string, rim: string) {
    const sx = bx - camX;
    const angle = crashT > 0 ? spin : clamp(Math.atan2(vy, speed), -0.55, 0.7);
    ctx!.save();
    ctx!.translate(sx, by);
    ctx!.rotate(angle);
    ctx!.scale(1.15, 1.15);

    const beat = (Math.sin(flapPhase) + 1) / 2; // 0 wing up, 1 wing down
    const theta = -0.7 + beat * 1.05;

    // the far wing runs behind the near one, which is what gives a flat
    // silhouette any depth at all
    wing(theta - 0.34, 25, c, 0.42);

    // head, back, tail, belly as one silhouette: a slim body with a real head
    // on the front and a tapered tail, not a blade at each end
    ctx!.fillStyle = c;
    ctx!.beginPath();
    ctx!.moveTo(23, 1.4); // beak
    ctx!.lineTo(16, -1.8);
    ctx!.quadraticCurveTo(11.5, -5.4, 6, -5); // crown
    ctx!.quadraticCurveTo(-3, -4.4, -13, -2.6); // back
    ctx!.quadraticCurveTo(-21, -1.8, -28, -4); // tail, upper edge
    ctx!.lineTo(-29, -1.6);
    ctx!.quadraticCurveTo(-22, 0.2, -13, 0.9); // tail, lower edge
    ctx!.quadraticCurveTo(-3, 3.6, 7, 3.2); // belly
    ctx!.quadraticCurveTo(14, 2.8, 17, 2.2); // throat
    ctx!.closePath();
    ctx!.fill();

    wing(theta, 29, c, 1);

    // the edge the low sun puts along its back, and the eye
    ctx!.strokeStyle = rim;
    ctx!.lineWidth = 1.5;
    ctx!.beginPath();
    ctx!.moveTo(16.5, -1.6);
    ctx!.quadraticCurveTo(11.5, -5, 6, -4.6);
    ctx!.stroke();
    ctx!.fillStyle = rim;
    ctx!.beginPath();
    ctx!.arc(13.4, -1.6, 0.95, 0, Math.PI * 2);
    ctx!.fill();
    ctx!.restore();
  }

  function draw() {
    const t = Math.pow(1 - light, 1.35);
    const c = tint(t);
    const land = css(c.land);
    const rim = css(c.rim);

    const g = ctx!.createLinearGradient(0, 0, 0, h * 0.58 + 70);
    g.addColorStop(0, css(c.skyTop));
    g.addColorStop(0.62, css(c.skyMid));
    g.addColorStop(1, css(c.skyLow));
    ctx!.fillStyle = g;
    ctx!.fillRect(0, 0, w, h);

    // the glow the low sun leaves along the horizon, no disc
    const glow = ctx!.createLinearGradient(0, h * 0.58 - 90, 0, h * 0.58 + 30);
    glow.addColorStop(0, css(c.skyLow, 0));
    glow.addColorStop(1, css(c.skyLow, 0.85));
    ctx!.fillStyle = glow;
    ctx!.fillRect(0, h * 0.58 - 90, w, 120);

    // once the cave closes over, the country outside stops being visible and
    // the corridor goes to rock light. Without this it reads as a canyon.
    const m = phase === 'playing' ? dist : 0;
    const caveMix = stage === 'cave' ? clamp((m - CAVE_AT) / CAVE_IN, 0, 1) : 0;

    ctx!.globalAlpha = 1 - caveMix;
    ridgeBand(css(c.far), 0.1, 30, 430, 16, p1);
    ridgeBand(css(c.mid), 0.26, 42, 300, 58, p2);
    ridgeBand(css(c.near), 0.52, 52, 230, 104, p3);
    ctx!.globalAlpha = 1;

    if (caveMix > 0) {
      ctx!.fillStyle = css(mix(c.land, DUSK.land, 0.45), caveMix * 0.78);
      ctx!.fillRect(0, 0, w, h);
    }

    // the ridge the bird has to stay off
    ctx!.fillStyle = land;
    ctx!.beginPath();
    ctx!.moveTo(-4, h);
    for (let sx = -4; sx <= w + 8; sx += 4) ctx!.lineTo(sx, floorY(camX + sx));
    ctx!.lineTo(w + 8, h);
    ctx!.closePath();
    ctx!.fill();

    ctx!.strokeStyle = css(c.rim, 0.9);
    ctx!.lineWidth = 2.5;
    ctx!.beginPath();
    for (let sx = -4; sx <= w + 8; sx += 4) {
      const y = floorY(camX + sx);
      if (sx === -4) ctx!.moveTo(sx, y);
      else ctx!.lineTo(sx, y);
    }
    ctx!.stroke();

    // grass, jittered off the world position so it stays put as the camera
    // moves and the crest never reads as a comb
    ctx!.strokeStyle = land;
    ctx!.lineWidth = 1.2;
    ctx!.beginPath();
    const first = Math.floor(camX / 14) * 14;
    for (let x = first - 14; x < camX + w + 14; x += 14) {
      const r = Math.sin(x * 12.9898) * 43758.5453;
      const j = r - Math.floor(r);
      if (j < 0.32) continue;
      const px = x + (j - 0.5) * 11;
      const sy = floorY(px);
      const near = Math.max(0, 1 - Math.abs(px - bx) / 220);
      const len = (4.5 + j * 5.5 + near * 3) * hs;
      const bend = 1.6 + j * 2 + near * 4 + Math.sin(px * 0.05 + flapPhase * 0.2) * 1.1;
      ctx!.moveTo(px - camX, sy + 1);
      ctx!.lineTo(px - camX - bend, sy - len);
    }
    ctx!.stroke();

    // the cave lid
    if (stage === 'cave') {
      ctx!.fillStyle = land;
      ctx!.beginPath();
      ctx!.moveTo(-4, -4);
      for (let sx = -4; sx <= w + 8; sx += 4) ctx!.lineTo(sx, ceilYAt(camX + sx, m));
      ctx!.lineTo(w + 8, -4);
      ctx!.closePath();
      ctx!.fill();

      ctx!.strokeStyle = css(c.rim, 0.75);
      ctx!.lineWidth = 2;
      ctx!.beginPath();
      for (let sx = -4; sx <= w + 8; sx += 4) {
        const y = ceilYAt(camX + sx, m);
        if (sx === -4) ctx!.moveTo(sx, y);
        else ctx!.lineTo(sx, y);
      }
      ctx!.stroke();
    }

    // gates in range
    const gx0 = gateZero();
    const n0 = Math.floor((camX - gx0) / GATE_SPACING) - 1;
    for (let n = n0; n <= n0 + Math.ceil(w / GATE_SPACING) + 2; n++) {
      if (n < 0) continue;
      const gt = gateNear(gx0 + n * GATE_SPACING);
      if (gt) gate(gt, land, rim);
    }

    for (const d of dust) {
      ctx!.fillStyle = css(c.land, Math.max(0, d.life) * 0.5);
      ctx!.fillRect(d.x - camX, d.y, 2.5, 2.5);
    }

    bird(land, rim);

    // the readouts have to survive the walk from oat paper to near black
    const tone = t > 0.5 ? css(DAY.skyTop) : css(DAY.land);
    if (tone !== hudTint) {
      hudTint = tone;
      root.style.setProperty('--glide-hud', tone);
    }
  }

  /* --- loop ------------------------------------------------------------- */

  let raf = 0;
  let last = 0;
  let running = false;

  function frame(now: number) {
    if (!running) return;
    const dt = Math.min(0.032, last ? (now - last) / 1000 : 0.016);
    last = now;
    step(dt);
    draw();
    if (phase === 'playing' && distOut) distOut.textContent = Math.round(dist).toLocaleString();
    raf = requestAnimationFrame(frame);
  }

  function play() {
    if (running) return;
    running = true;
    last = 0;
    raf = requestAnimationFrame(frame);
  }

  function pause() {
    running = false;
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
  }

  function reset(forRun: boolean) {
    reseed();
    bx = 0;
    startX = 0;
    by = clamp(floorY(0) - 165 * hs, 46, h * 0.55);
    vy = 0;
    speed = SPEED0;
    holding = false;
    camX = bx - w * anchor();
    dist = 0;
    light = 1;
    spin = 0;
    crashT = 0;
    stage = 'open';
    dust = [];
    if (!forRun) by = clamp(floorY(0) - 110 * hs, 46, h * 0.6);
    announce('open');
  }

  /* --- input ------------------------------------------------------------ */

  function down(e: PointerEvent) {
    if (phase !== 'playing') return;
    holding = true;
    e.preventDefault();
  }

  function up() {
    holding = false;
  }

  // every key the browser would scroll with, swallowed for the run
  const SCROLLERS = new Set([
    'Space',
    'ArrowUp',
    'ArrowDown',
    'ArrowLeft',
    'ArrowRight',
    'PageUp',
    'PageDown',
    'Home',
    'End',
  ]);

  function onKey(e: KeyboardEvent) {
    if (phase !== 'playing') return;
    if (e.code === 'Space' || e.code === 'ArrowUp' || e.code === 'KeyW') {
      if (!e.repeat) holding = true;
      e.preventDefault();
    } else if (e.code === 'Escape') {
      crash();
    } else if (SCROLLERS.has(e.code)) {
      e.preventDefault();
    }
  }

  function onTouchMove(e: TouchEvent) {
    if (phase === 'playing') e.preventDefault();
  }

  function onKeyUp(e: KeyboardEvent) {
    if (e.code === 'Space' || e.code === 'ArrowUp' || e.code === 'KeyW') holding = false;
  }

  function startRun() {
    reset(true);
    phase = 'playing';
    // hold the page still for the run, so space drives the bird and nothing
    // else. Bring the field into view first, or the lock traps it off screen.
    root.scrollIntoView({ block: 'center', behavior: 'auto' });
    document.documentElement.classList.add('glide-locked');
    root.classList.add('is-live');
    intro?.setAttribute('hidden', '');
    introBottom = 0;
    overCard?.setAttribute('hidden', '');
    hud?.removeAttribute('hidden');
    hint?.removeAttribute('hidden');
    canvas!.classList.add('is-live');
    if (bestOut) bestOut.textContent = best.toLocaleString();
    if (distOut) distOut.textContent = '0';
    window.setTimeout(() => hint?.setAttribute('hidden', ''), 4600);
    canvas!.focus({ preventScroll: true });
    play();
  }

  function onVisibility() {
    if (document.hidden) {
      pause();
      return;
    }
    if (phase === 'over') return;
    if (phase === 'attract' && reduced.matches) return;
    play();
  }

  playBtn?.addEventListener('click', startRun);
  againBtn?.addEventListener('click', startRun);
  canvas.addEventListener('pointerdown', down);
  window.addEventListener('pointerup', up);
  window.addEventListener('pointercancel', up);
  window.addEventListener('keydown', onKey);
  window.addEventListener('keyup', onKeyUp);
  window.addEventListener('touchmove', onTouchMove, { passive: false });
  document.addEventListener('visibilitychange', onVisibility);

  const ro = new ResizeObserver(() => {
    const wasFresh = phase === 'attract';
    resize();
    measureIntro();
    if (wasFresh) by = clamp(by, 40, floorY(bx) - R);
    if (!running) draw();
  });
  ro.observe(canvas);

  // attract: the bird flies itself over the open ridge behind the card. Under
  // reduced motion it holds on one frame until someone asks for a run.
  resize();
  measureIntro();
  reset(false);
  if (bestOut) bestOut.textContent = best.toLocaleString();
  if (reduced.matches) {
    for (let i = 0; i < 260; i++) step(1 / 60);
    draw();
  } else {
    play();
  }

  return {
    destroy() {
      pause();
      ro.disconnect();
      document.documentElement.classList.remove('glide-locked');
      window.removeEventListener('touchmove', onTouchMove);
      playBtn?.removeEventListener('click', startRun);
      againBtn?.removeEventListener('click', startRun);
      canvas.removeEventListener('pointerdown', down);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', up);
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('keyup', onKeyUp);
      document.removeEventListener('visibilitychange', onVisibility);
    },
  };
}
