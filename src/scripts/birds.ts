// Distant birds over the settled frame. They exist only while the film is
// at rest: during the scrub the camera moves and an overlay would detach
// from the world. Everything is silhouette and behavior, no detail: at this
// distance a bird is a soft dark wing-beat, and the haze plus the site's
// grain does the rest.

interface Bird {
  /** formation slot, px relative to the flock anchor */
  sx: number;
  sy: number;
  /** slow wander around the slot */
  wp: number;
  ws: number;
  /** half wingspan px, and the depth cue derived from it */
  size: number;
  alpha: number;
  vmul: number;
  /** wing-beat state: flap bursts separated by glides */
  phase: number;
  freq: number;
  mode: 'flap' | 'glide';
  modeLeft: number;
}

interface Flock {
  dir: 1 | -1;
  x: number;
  y: number;
  speed: number;
  slope: number;
  swayP: number;
  swayA: number;
  birds: Bird[];
}

const rand = (a: number, b: number): number => a + Math.random() * (b - a);
const pick = <T,>(arr: T[]): T => arr[Math.floor(Math.random() * arr.length)];

// three waves, three characters: a proper V, a ragged strung-out line, and
// a few stragglers. quantities breathe a little every pass.
const WAVES = [
  { kind: 'v', n: () => 6 + Math.floor(rand(0, 3)) },
  { kind: 'line', n: () => 10 + Math.floor(rand(0, 5)) },
  { kind: 'few', n: () => 2 + Math.floor(rand(0, 2)) },
] as const;

function makeBird(sx: number, sy: number): Bird {
  const size = rand(3.6, 7.6);
  const depth = (size - 3.6) / 4; // bigger reads nearer
  return {
    sx,
    sy,
    wp: rand(0, Math.PI * 2),
    ws: rand(0.2, 0.5),
    size,
    alpha: 0.4 + depth * 0.28,
    vmul: 0.92 + depth * 0.16,
    phase: rand(0, Math.PI * 2),
    freq: rand(2.4, 3.4),
    mode: Math.random() < 0.7 ? 'flap' : 'glide',
    modeLeft: rand(0.5, 2),
  };
}

function makeFlock(kind: string, n: number, vw: number, vh: number, near = false): Flock {
  const dir = Math.random() < 0.5 ? 1 : -1;
  const gap = 16;
  const birds: Bird[] = [];
  for (let i = 0; i < n; i++) {
    let sx = 0;
    let sy = 0;
    if (kind === 'v') {
      const arm = i === 0 ? 0 : i % 2 ? 1 : -1;
      const rank = Math.ceil(i / 2);
      sx = -dir * rank * gap * 1.5 + rand(-3, 3);
      sy = arm * rank * gap * 0.8 + rand(-3, 3);
    } else if (kind === 'line') {
      sx = -dir * i * gap * 1.05 + rand(-6, 6);
      sy = Math.sin(i * 1.7) * gap * 0.7 + rand(-5, 5);
    } else {
      sx = -dir * i * gap * 2.2 + rand(-8, 8);
      sy = rand(-10, 10);
    }
    birds.push(makeBird(sx, sy));
  }
  // the opening wave starts with its leader at the sky's edge so the page
  // does not sit empty; later waves take the full runway
  const margin = near ? 70 : n * gap * 2.4 + 60;
  return {
    dir,
    x: dir === 1 ? -margin : vw + margin,
    // the open sky band: below the header, above the ridge line
    y: vh * rand(0.12, 0.42),
    speed: vw / rand(26, 34),
    slope: rand(-0.045, 0.045),
    swayP: rand(0, Math.PI * 2),
    swayA: rand(6, 16),
    birds,
  };
}

function drawBird(ctx: CanvasRenderingContext2D, b: Bird, x: number, y: number, tilt: number): void {
  // wing lift: a glide holds a shallow V; a flap sweeps deep both ways with
  // a quick downstroke. left and right run a whisker apart so nothing twins.
  const lift = (side: number): number => {
    if (b.mode === 'glide') return 0.18;
    const t = Math.sin(b.phase + side * 0.18);
    return t >= 0 ? t * 0.55 : t * 0.42;
  };
  const s = b.size;
  ctx.save();
  ctx.translate(x, y);
  ctx.rotate(tilt);
  ctx.globalAlpha = b.alpha;
  ctx.lineWidth = Math.max(0.9, s * 0.26);
  ctx.beginPath();
  ctx.moveTo(-s, -lift(-1) * s);
  ctx.quadraticCurveTo(-s * 0.45, s * 0.16, 0, 0);
  ctx.quadraticCurveTo(s * 0.45, s * 0.16, s, -lift(1) * s);
  ctx.stroke();
  ctx.restore();
}

export interface BirdsHandle {
  setActive(on: boolean): void;
}

export function initBirds(canvas: HTMLCanvasElement): BirdsHandle {
  const ctx = canvas.getContext('2d')!;
  let active = false;
  let quietTime = 0;
  let nextWave = rand(1.5, 3);
  let firstWave = true;
  let order = [...WAVES].sort(() => Math.random() - 0.5);
  let wave = 0;
  const flocks: Flock[] = [];
  let last = performance.now();
  let raf = 0;

  function fit(): void {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
    }
  }

  function step(now: number): void {
    raf = requestAnimationFrame(step);
    const dt = Math.min(0.1, (now - last) / 1000);
    last = now;
    if (!active && flocks.length === 0) return; // nothing to do, skip work
    fit();
    const vw = canvas.width;
    const vh = canvas.height;

    if (active) {
      quietTime += dt;
      if (quietTime >= nextWave) {
        const arch = order[wave % order.length];
        flocks.push(makeFlock(arch.kind, arch.n(), vw, vh, firstWave));
        firstWave = false;
        wave++;
        if (wave % order.length === 0) order = [...WAVES].sort(() => Math.random() - 0.5);
        // "about a minute" apart, never metronomic
        nextWave = quietTime + rand(48, 75);
      }
    }

    ctx.clearRect(0, 0, vw, vh);
    ctx.strokeStyle = 'rgb(52, 42, 30)';
    ctx.lineCap = 'round';
    ctx.filter = 'blur(0.45px)';
    for (let f = flocks.length - 1; f >= 0; f--) {
      const fl = flocks[f];
      if (active) {
        fl.x += fl.dir * fl.speed * dt;
        fl.y += fl.speed * fl.slope * dt;
        fl.swayP += dt * 0.5;
      }
      const fy = fl.y + Math.sin(fl.swayP) * fl.swayA;
      let alive = false;
      for (const b of fl.birds) {
        if (active) {
          b.wp += dt * b.ws;
          b.modeLeft -= dt;
          if (b.modeLeft <= 0) {
            b.mode = b.mode === 'flap' ? 'glide' : 'flap';
            b.modeLeft = b.mode === 'flap' ? rand(1, 2.6) : rand(0.7, 1.9);
          }
          if (b.mode === 'flap') b.phase += dt * b.freq * Math.PI * 2;
        }
        const x = fl.x + b.sx * b.vmul + Math.sin(b.wp) * 4;
        const y = fy + b.sy + Math.cos(b.wp * 0.8) * 3;
        if (x > -40 && x < vw + 40) alive = true;
        if (y > -20 && y < vh + 20) {
          drawBird(ctx, b, x, y, fl.slope * fl.dir + Math.sin(b.wp) * 0.04);
        }
      }
      const gone = fl.dir === 1 ? fl.x - 400 > vw + (fl.birds.length * 40) : fl.x + 400 < -(fl.birds.length * 40);
      if (!alive && gone) flocks.splice(f, 1);
    }
    ctx.filter = 'none';
  }

  raf = requestAnimationFrame(step);
  document.addEventListener('visibilitychange', () => {
    // rAF stops in hidden tabs on its own; just avoid a giant dt on return
    if (!document.hidden) last = performance.now();
  });

  const api: BirdsHandle = {
    setActive(on: boolean): void {
      if (on === active) return;
      active = on;
      canvas.style.opacity = on ? '1' : '0';
    },
  };
  if (import.meta.env.DEV) {
    // headless review tooling drives time by hand; dev builds only
    (window as unknown as { __birds: object }).__birds = {
      ...api,
      tick(ms: number): void {
        const t = performance.now();
        for (let i = 0; i < ms; i += 16) step(t + i);
        cancelAnimationFrame(raf);
      },
      hurry(): void {
        quietTime = nextWave;
      },
    };
  }
  return api;
}
