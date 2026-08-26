// The Field — a prairie computed live. Compute passes integrate every grass
// blade as a spring driven by a traveling wind field, and a drift of seeds
// riding the same wind; render passes draw a warm sky, the blades back to
// front, then the seeds in the air. Blades bent by a gust catch the low sun,
// so wind crosses the field as waves of light. The pointer parts the grass
// and scatters the seeds. Palette and styling match the keepsake drawings;
// the edges are the site's paper so the field grows straight out of the page.

const HORIZON = 0.42; // fraction of canvas height where the field begins
const SEGMENTS = 6; // strip segments per blade
const DPR_CAP = 1.75;

const COMMON_WGSL = /* wgsl */ `
struct U {
  resolution: vec2f,
  pointer: vec2f,   // field coords (x across, y depth 0 back / 1 front)
  gust: vec2f,      // x: pointer-drag gust, y: pointer presence 0..1
  time: f32,
  dt: f32,
  horizon: f32,
  count: f32,
  praw: vec2f,      // pointer in raw canvas fractions, for the seeds
}
struct Blade {
  root: vec2f,
  height: f32,
  width: f32,
  stiffness: f32,
  color: f32,
  seed: f32,
  lift: f32,        // ground swell: how far this root rides above its row
}
struct BladeState {
  bend: f32,
  vel: f32,
}
struct Seed {
  pos: vec2f,       // raw canvas fractions
  vel: vec2f,
  phase: f32,
  size: f32,
  pad: vec2f,
}
fn hash2(p: vec2f) -> f32 {
  return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453123);
}
fn vnoise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  let a = hash2(i);
  let b = hash2(i + vec2f(1.0, 0.0));
  let c = hash2(i + vec2f(0.0, 1.0));
  let d = hash2(i + vec2f(1.0, 1.0));
  return mix(mix(a, b, s.x), mix(c, d, s.x), s.y) * 2.0 - 1.0;
}
// gusts travel across the field left to right
fn wind(p: vec2f, t: f32) -> f32 {
  let q = vec2f(p.x * 3.0 - t * 0.55, p.y * 2.0);
  return 0.55 * vnoise(q) + 0.3 * vnoise(q * 2.7 + vec2f(t * 0.2, 0.0)) + 0.14;
}
`;

const BLADE_COMPUTE_WGSL = /* wgsl */ `
${COMMON_WGSL}
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read> blades: array<Blade>;
@group(0) @binding(2) var<storage, read_write> state: array<BladeState>;

@compute @workgroup_size(64)
fn step(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  if (f32(i) >= u.count) { return; }
  let b = blades[i];
  var s = state[i];
  // 'target' is reserved in WGSL, hence 'goal'
  var goal = wind(b.root, u.time) * 0.9;
  goal += 0.05 * sin(u.time * 2.0 + b.seed * 6.2831);
  let d = (b.root - u.pointer) * vec2f(1.0, 0.62);
  let near = exp(-dot(d, d) * 60.0);
  goal += u.gust.x * near;
  // the grass parts around a present pointer and springs back behind it
  goal += sign(d.x) * 0.6 * near * u.gust.y;
  let acc = (goal - s.bend) * b.stiffness - s.vel * 2.6;
  s.vel += acc * u.dt;
  s.bend += s.vel * u.dt;
  state[i] = s;
}
`;

const SEED_COMPUTE_WGSL = /* wgsl */ `
${COMMON_WGSL}
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read_write> seeds: array<Seed>;

@compute @workgroup_size(64)
fn step(@builtin(global_invocation_id) gid: vec3u) {
  let i = gid.x;
  var s = seeds[i];
  let w = wind(vec2f(s.pos.x, 0.5), u.time);
  var drift = vec2f(
    0.012 + w * 0.035,
    0.005 * vnoise(s.pos * 5.0 + vec2f(0.0, u.time * 0.15)) - 0.0015,
  );
  // the big ones are distant gliders: steadier, quicker, less tumbled
  if (s.size > 1.5) {
    drift = vec2f(0.024 + w * 0.016, drift.y * 0.45);
  }
  s.vel = mix(s.vel, drift, 0.05);
  let d = s.pos - u.praw;
  let near = exp(-dot(d, d) * 40.0);
  s.vel += normalize(d + vec2f(0.0001, 0.0)) * near * 0.06 * u.gust.y;
  s.pos += s.vel * u.dt * 3.0;
  if (s.pos.x > 1.06) { s.pos.x -= 1.12; }
  if (s.pos.x < -0.06) { s.pos.x += 1.12; }
  s.pos.y = clamp(s.pos.y, -0.04, 1.04);
  seeds[i] = s;
}
`;

const SKY_WGSL = /* wgsl */ `
${COMMON_WGSL}
@group(0) @binding(0) var<uniform> u: U;

@vertex
fn vs(@builtin(vertex_index) vi: u32) -> @builtin(position) vec4f {
  var p = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
  return vec4f(p[vi], 0.0, 1.0);
}

@fragment
fn fs(@builtin(position) pos: vec4f) -> @location(0) vec4f {
  let fy = pos.y / u.resolution.y;
  // a warm band settles just above the horizon and fades out by the edges,
  // so the canvas still meets the page as plain paper
  let band = smoothstep(u.horizon - 0.34, u.horizon, fy) * (1.0 - smoothstep(u.horizon + 0.05, 1.0, fy));
  let paper = vec3f(0.957, 0.929, 0.875);
  let glow = vec3f(0.949, 0.882, 0.741);
  return vec4f(mix(paper, glow, band * 0.5), 1.0);
}
`;

const BLADE_RENDER_WGSL = /* wgsl */ `
${COMMON_WGSL}
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read> blades: array<Blade>;
@group(0) @binding(2) var<storage, read> state: array<BladeState>;

// far to near, the keepsake's sun-faded earth tones
const PAL = array<vec3f, 8>(
  vec3f(0.788, 0.749, 0.643),
  vec3f(0.690, 0.561, 0.361),
  vec3f(0.655, 0.604, 0.447),
  vec3f(0.541, 0.541, 0.345),
  vec3f(0.435, 0.490, 0.306),
  vec3f(0.627, 0.420, 0.212),
  vec3f(0.361, 0.290, 0.188),
  vec3f(0.290, 0.227, 0.149),
);

struct VOut {
  @builtin(position) pos: vec4f,
  @location(0) color: vec3f,
}

@vertex
fn vs(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> VOut {
  let b = blades[ii];
  let s = state[ii];
  let t = f32(vi / 2u) / ${SEGMENTS}.0;
  let side = f32(vi % 2u) * 2.0 - 1.0;

  let horizonY = u.horizon * u.resolution.y;
  let rootY = horizonY + pow(clamp(b.root.y, 0.0, 1.1), 1.35) * (u.resolution.y - horizonY)
    - b.lift * u.resolution.y;
  let rootX = b.root.x * u.resolution.x;
  let bladeH = b.height * u.resolution.y;
  let halfW = b.width * u.resolution.x * 0.5;

  // quadratic bend: the tip carries most of it, and a hard bend shortens reach
  let bend = clamp(s.bend, -1.6, 1.6);
  let px = rootX + bend * t * t * bladeH * 0.75 + side * halfW * (1.0 - t * 0.85);
  let py = rootY - t * bladeH * (1.0 - 0.18 * bend * bend * t * t);

  var out: VOut;
  out.pos = vec4f(px / u.resolution.x * 2.0 - 1.0, 1.0 - py / u.resolution.y * 2.0, 0.0, 1.0);

  var color = PAL[u32(b.color)] * (0.92 + 0.16 * b.seed);
  // haze: the far rows dissolve toward warm air
  color = mix(vec3f(0.898, 0.847, 0.737), color, 0.40 + 0.60 * clamp(b.root.y, 0.0, 1.0));
  // golden light catches the tips
  color = mix(color, vec3f(0.851, 0.592, 0.118), t * t * 0.22);
  // blades leaning with the gust catch the low sun, so wind reads as light
  let lit = clamp(s.bend, -0.4, 0.9);
  color += vec3f(0.115, 0.085, 0.025) * lit * t;
  out.color = color;
  return out;
}

@fragment
fn fs(v: VOut) -> @location(0) vec4f {
  return vec4f(v.color, 1.0);
}
`;

const SEED_RENDER_WGSL = /* wgsl */ `
${COMMON_WGSL}
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var<storage, read> seeds: array<Seed>;

struct VOut {
  @builtin(position) pos: vec4f,
  @location(0) quad: vec2f,
  @location(1) alpha: f32,
  @location(2) dark: f32,
}

@vertex
fn vs(@builtin(vertex_index) vi: u32, @builtin(instance_index) ii: u32) -> VOut {
  let s = seeds[ii];
  var corners = array<vec2f, 4>(
    vec2f(-1.0, -1.0), vec2f(1.0, -1.0), vec2f(-1.0, 1.0), vec2f(1.0, 1.0),
  );
  let c = corners[vi];
  let sizePx = s.size * u.resolution.y * 0.004;
  let center = s.pos * u.resolution;
  let p = center + c * sizePx;
  var out: VOut;
  out.pos = vec4f(p / u.resolution * vec2f(2.0, -2.0) + vec2f(-1.0, 1.0), 0.0, 1.0);
  out.quad = c;
  let dark = step(1.5, s.size);
  out.dark = dark;
  let twinkle = 0.28 + 0.22 * sin(u.time * 1.7 + s.phase * 6.2831);
  out.alpha = mix(twinkle, 0.42 + 0.08 * sin(u.time * 1.1 + s.phase * 6.2831), dark);
  return out;
}

@fragment
fn fs(v: VOut) -> @location(0) vec4f {
  let r = length(v.quad);
  let a = (1.0 - smoothstep(0.25, 1.0, r)) * v.alpha;
  let gold = vec3f(0.910, 0.796, 0.549);
  let ink = vec3f(0.310, 0.258, 0.184);
  let color = mix(gold, ink, v.dark);
  return vec4f(color * a, a);
}
`;

function bladeCount(canvas: HTMLCanvasElement): number {
  const area = canvas.clientWidth * canvas.clientHeight;
  const coarse = matchMedia('(pointer: coarse)').matches;
  const base = Math.round(area / (coarse ? 60 : 32));
  return Math.max(4000, Math.min(coarse ? 10000 : 26000, base));
}

function makeBlades(count: number): Float32Array {
  const data = new Float32Array(count * 8);
  // the ground swells like the ridge: a smooth profile the roots ride on
  const a1 = Math.random() * Math.PI * 2;
  const a2 = Math.random() * Math.PI * 2;
  const hill = (x: number) =>
    (Math.sin(x * 2.1 * Math.PI + a1) * 0.5 + Math.sin(x * 4.7 * Math.PI + a2) * 0.3 + 0.8) / 1.6;
  const blades: number[][] = [];
  for (let i = 0; i < count; i++) {
    const x = Math.random() * 1.04 - 0.02;
    const y = Math.random() * 1.06;
    const depth = Math.min(y, 1);
    // most blades stay short; a few stand proud so the silhouette breaks up
    const tallness = Math.pow(Math.random(), 1.7);
    let height = (0.035 + 0.12 * tallness) * (0.22 + 1.15 * Math.pow(depth, 1.3));
    if (Math.random() < 0.06) height *= 1.45;
    const width = (0.0012 + 0.0024 * Math.random()) * (0.42 + 1.05 * Math.pow(depth, 1.4));
    // tall front blades swing slower and further than the stiff back rows
    const stiffness = (4.2 - 2.2 * depth) * (0.8 + 0.5 * Math.random());
    let color: number;
    const r = Math.random();
    if (depth < 0.3) color = r < 0.7 ? Math.floor(Math.random() * 3) : 3;
    else if (depth < 0.72) color = 2 + Math.floor(Math.random() * 3) + (r < 0.12 ? 3 : 0);
    else color = r < 0.45 ? 6 + Math.floor(Math.random() * 2) : 3 + Math.floor(Math.random() * 3);
    const lift = hill(x) * (0.015 + 0.075 * depth);
    blades.push([x, y, height, width, stiffness, Math.min(color, 7), Math.random(), lift]);
  }
  blades.sort((a, b) => a[1] - b[1]); // back to front, painter's order
  blades.forEach((b, i) => data.set(b, i * 8));
  return data;
}

function makeSeeds(count: number): Float32Array {
  const data = new Float32Array(count * 8);
  for (let i = 0; i < count; i++) {
    // a few read as distant gliders; the rest are seeds catching the light
    const glider = Math.random() < 0.07;
    data.set(
      [
        Math.random() * 1.1 - 0.05,
        glider ? Math.random() * 0.45 : Math.pow(Math.random(), 1.4) * 0.9,
        0,
        0,
        Math.random(),
        glider ? 1.7 + Math.random() * 0.5 : 0.55 + Math.random() * 0.85,
        0,
        0,
      ],
      i * 8,
    );
  }
  return data;
}

export async function mountField(canvas: HTMLCanvasElement): Promise<boolean> {
  try {
    if (!navigator.gpu) return false;
    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) return false;
    const device = await adapter.requestDevice();
    const context = canvas.getContext('webgpu');
    if (!context) return false;
    const format = navigator.gpu.getPreferredCanvasFormat();
    context.configure({ device, format, alphaMode: 'opaque' });

    const count = bladeCount(canvas);
    const seedCount = matchMedia('(pointer: coarse)').matches ? 220 : 480;
    const bladeData = makeBlades(count);

    const bladeBuf = device.createBuffer({
      size: bladeData.byteLength,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    device.queue.writeBuffer(bladeBuf, 0, bladeData);
    const stateBuf = device.createBuffer({
      size: count * 8,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    device.queue.writeBuffer(stateBuf, 0, new Float32Array(count * 2));
    const seedBuf = device.createBuffer({
      size: seedCount * 32,
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    device.queue.writeBuffer(seedBuf, 0, makeSeeds(seedCount));
    const uniforms = new Float32Array(12);
    const uniformBuf = device.createBuffer({
      size: 48,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    const bladeCompute = device.createComputePipeline({
      layout: 'auto',
      compute: { module: device.createShaderModule({ code: BLADE_COMPUTE_WGSL }), entryPoint: 'step' },
    });
    const bladeComputeBind = device.createBindGroup({
      layout: bladeCompute.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuf } },
        { binding: 1, resource: { buffer: bladeBuf } },
        { binding: 2, resource: { buffer: stateBuf } },
      ],
    });
    const seedCompute = device.createComputePipeline({
      layout: 'auto',
      compute: { module: device.createShaderModule({ code: SEED_COMPUTE_WGSL }), entryPoint: 'step' },
    });
    const seedComputeBind = device.createBindGroup({
      layout: seedCompute.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuf } },
        { binding: 1, resource: { buffer: seedBuf } },
      ],
    });

    const skyModule = device.createShaderModule({ code: SKY_WGSL });
    const skyPipeline = device.createRenderPipeline({
      layout: 'auto',
      vertex: { module: skyModule, entryPoint: 'vs' },
      fragment: { module: skyModule, entryPoint: 'fs', targets: [{ format }] },
      primitive: { topology: 'triangle-list' },
      multisample: { count: 4 },
    });
    const skyBind = device.createBindGroup({
      layout: skyPipeline.getBindGroupLayout(0),
      entries: [{ binding: 0, resource: { buffer: uniformBuf } }],
    });

    const bladeModule = device.createShaderModule({ code: BLADE_RENDER_WGSL });
    const bladePipeline = device.createRenderPipeline({
      layout: 'auto',
      vertex: { module: bladeModule, entryPoint: 'vs' },
      fragment: { module: bladeModule, entryPoint: 'fs', targets: [{ format }] },
      primitive: { topology: 'triangle-strip' },
      multisample: { count: 4 },
    });
    const bladeBind = device.createBindGroup({
      layout: bladePipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuf } },
        { binding: 1, resource: { buffer: bladeBuf } },
        { binding: 2, resource: { buffer: stateBuf } },
      ],
    });

    const seedModule = device.createShaderModule({ code: SEED_RENDER_WGSL });
    const seedPipeline = device.createRenderPipeline({
      layout: 'auto',
      vertex: { module: seedModule, entryPoint: 'vs' },
      fragment: {
        module: seedModule,
        entryPoint: 'fs',
        targets: [
          {
            format,
            blend: {
              color: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' },
              alpha: { srcFactor: 'one', dstFactor: 'one-minus-src-alpha' },
            },
          },
        ],
      },
      primitive: { topology: 'triangle-strip' },
      multisample: { count: 4 },
    });
    const seedBind = device.createBindGroup({
      layout: seedPipeline.getBindGroupLayout(0),
      entries: [
        { binding: 0, resource: { buffer: uniformBuf } },
        { binding: 1, resource: { buffer: seedBuf } },
      ],
    });

    let msaa: GPUTexture | null = null;
    const resize = () => {
      const dpr = Math.min(devicePixelRatio || 1, DPR_CAP);
      const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
      const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
      if (canvas.width === w && canvas.height === h && msaa) return;
      canvas.width = w;
      canvas.height = h;
      msaa?.destroy();
      msaa = device.createTexture({
        size: [w, h],
        sampleCount: 4,
        format,
        usage: GPUTextureUsage.RENDER_ATTACHMENT,
      });
    };
    resize();
    new ResizeObserver(resize).observe(canvas);

    // the pointer parts the grass where it rests and drags a gust when it moves
    let pointer = [0.5, 0.6];
    let praw = [0.5, 0.5];
    let gust = 0;
    let presence = 0;
    let present = false;
    let lastPx = 0.5;
    canvas.addEventListener('pointermove', (e) => {
      const rect = canvas.getBoundingClientRect();
      const px = (e.clientX - rect.left) / rect.width;
      const frac = (e.clientY - rect.top) / rect.height;
      praw = [px, frac];
      const py = Math.pow(Math.max(0, (frac - HORIZON) / (1 - HORIZON)), 1 / 1.35);
      pointer = [px, Math.min(py, 1)];
      gust = Math.max(-2.5, Math.min(2.5, gust + (px - lastPx) * 22));
      lastPx = px;
      present = true;
    });
    canvas.addEventListener('pointerleave', () => {
      present = false;
    });

    let time = 0;
    let last = performance.now();
    let running = true;
    let visible = true;

    const frame = (now: number) => {
      if (!running) return;
      requestAnimationFrame(frame);
      if (!visible || document.hidden || !msaa) {
        last = now;
        return;
      }
      const dt = Math.min((now - last) / 1000, 0.033);
      last = now;
      time += dt;
      gust *= 0.9;
      presence += ((present ? 1 : 0) - presence) * 0.08;

      uniforms.set(
        [canvas.width, canvas.height, pointer[0], pointer[1], gust, presence, time, dt, HORIZON, count, praw[0], praw[1]],
        0,
      );
      device.queue.writeBuffer(uniformBuf, 0, uniforms);

      const encoder = device.createCommandEncoder();
      const compute = encoder.beginComputePass();
      compute.setPipeline(bladeCompute);
      compute.setBindGroup(0, bladeComputeBind);
      compute.dispatchWorkgroups(Math.ceil(count / 64));
      compute.setPipeline(seedCompute);
      compute.setBindGroup(0, seedComputeBind);
      compute.dispatchWorkgroups(Math.ceil(seedCount / 64));
      compute.end();

      const pass = encoder.beginRenderPass({
        colorAttachments: [
          {
            view: msaa.createView(),
            resolveTarget: context.getCurrentTexture().createView(),
            clearValue: { r: 0.957, g: 0.929, b: 0.875, a: 1 }, // paper
            loadOp: 'clear',
            storeOp: 'discard',
          },
        ],
      });
      pass.setPipeline(skyPipeline);
      pass.setBindGroup(0, skyBind);
      pass.draw(3);
      pass.setPipeline(bladePipeline);
      pass.setBindGroup(0, bladeBind);
      pass.draw((SEGMENTS + 1) * 2, count);
      pass.setPipeline(seedPipeline);
      pass.setBindGroup(0, seedBind);
      pass.draw(4, seedCount);
      pass.end();
      device.queue.submit([encoder.finish()]);
    };

    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
    }).observe(canvas);
    device.lost.then(() => {
      running = false;
    });
    requestAnimationFrame(frame);
    return true;
  } catch {
    return false;
  }
}

// the still: the same field drawn once, for browsers without WebGPU and for
// anyone who prefers reduced motion. deterministic, so it always looks composed.
export function stillField(): string {
  let a = 1234567;
  const rand = () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const W = 1600;
  const H = 900;
  const horizon = H * HORIZON;
  const hex = ['#C9BFA4', '#B08F5C', '#A79A72', '#8A8A58', '#6F7D4E', '#A06B36', '#5C4A30', '#4A3A26'];
  const blades: { depth: number; path: string }[] = [];
  for (let i = 0; i < 1500; i++) {
    const depth = rand();
    const y = horizon + Math.pow(depth, 1.35) * (H - horizon);
    const x = rand() * W;
    const h = (0.035 + 0.12 * Math.pow(rand(), 1.7)) * (0.22 + 1.15 * Math.pow(depth, 1.3)) * H * 1.4;
    const lean = (rand() * 1.1 - 0.25) * h;
    const wdt = (1 + 2.4 * rand()) * (0.55 + 0.65 * depth);
    const c = depth < 0.3 ? Math.floor(rand() * 4) : depth < 0.72 ? 2 + Math.floor(rand() * 4) : 3 + Math.floor(rand() * 5);
    blades.push({
      depth,
      path: `<path d="M ${x.toFixed(1)} ${y.toFixed(1)} q ${(lean * 0.25).toFixed(1)} ${(-h * 0.6).toFixed(1)} ${lean.toFixed(1)} ${(-h).toFixed(1)}" stroke="${hex[Math.min(c, 7)]}" stroke-width="${wdt.toFixed(1)}" fill="none" stroke-linecap="round"/>`,
    });
  }
  blades.sort((p, q) => p.depth - q.depth);
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMidYMax slice" role="img" aria-label="A still field of grasses"><rect width="${W}" height="${H}" fill="#F4EDDF"/>` +
    blades.map((b) => b.path).join('') +
    '</svg>'
  );
}
