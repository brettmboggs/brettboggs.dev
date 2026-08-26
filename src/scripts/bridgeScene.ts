// CINEMATIC SCENE - the scroll-scrubbed 3D film that opens the public landing
// page. A cable-stayed river crossing surveys, drafts, builds, opens, and
// lights up with data as the visitor scrolls, then dissolves into dawn and
// hands off to the editorial page below. Pure three.js - no React in here.
//
// Everything is a deterministic function of (progress, time): scrubbing
// backwards un-builds the bridge. The pipeline is physically-based end to
// end: PBR materials under an IBL environment + animated sun with PCF soft
// shadows, ACES tone mapping, HDR bloom, depth of field, and a film grade
// (grain / vignette / chromatic aberration) so the frame reads as rendered
// footage rather than a "3D on a website" widget.
//
// Scene-painting colors below are film values (concrete, steel, sky grades),
// not UI tokens - the UI-token rule governs CSS. The one brand color the
// scene borrows (hologram/data azure) is read from --cta at runtime.
import * as THREE from "three";
import { EffectComposer } from "three/examples/jsm/postprocessing/EffectComposer.js";
import { RenderPass } from "three/examples/jsm/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/examples/jsm/postprocessing/UnrealBloomPass.js";
import { BokehPass } from "three/examples/jsm/postprocessing/BokehPass.js";
import { ShaderPass } from "three/examples/jsm/postprocessing/ShaderPass.js";
import { OutputPass } from "three/examples/jsm/postprocessing/OutputPass.js";
import { SMAAPass } from "three/examples/jsm/postprocessing/SMAAPass.js";
import { RoomEnvironment } from "three/examples/jsm/environments/RoomEnvironment.js";
import { Water } from "three/examples/jsm/objects/Water.js";

export type CinematicQuality = "high" | "medium";

export interface CinematicHudPoint {
  id: string;
  /** CSS-percentage coordinates inside the viewport. */
  x: number;
  y: number;
  opacity: number;
}

export interface CinematicSceneHandle {
  setSize(width: number, height: number, dpr: number): void;
  /** Advance and draw one frame. progress ∈ [0,1] along the intro scroll. */
  render(progress: number, dt: number): void;
  /** Screen-space HUD anchor positions, refreshed by render(). */
  readonly hud: CinematicHudPoint[];
  dispose(): void;
}

/* ── Layout constants (one bridge, one valley - shared by blueprint + steel) ── */

const DECK_Y = 34; // road surface elevation
const GIRDER_DEPTH = 3.2;
const DECK_HALF_W = 11; // top width 22
const SEG_LEN = 15;
const SEG_COUNT = 28; // abutment → abutment = 420
const ABUTMENT_X = 210;
const PYLON_X = 90;
const PYLON_TOP = 98;
const MONUMENT = new THREE.Vector3(-122, 9.6, 42);

/* ── Timeline (progress windows for every beat of the build) ── */

const T = {
  gridDraw: [0.035, 0.14],
  bpPylons: [0.13, 0.19],
  bpDeck: [0.165, 0.245],
  bpCables: [0.21, 0.275],
  bpTicks: [0.245, 0.285],
  bpFadePylons: [0.295, 0.36],
  bpFadeDeck: [0.38, 0.47],
  bpFadeCables: [0.44, 0.56],
  bpFadeTicks: [0.30, 0.345],
  gridFade: [0.30, 0.40],
  pierRise: [0.285, 0.40],
  approachRise: [0.34, 0.425],
  deckSeat: [0.40, 0.585],
  cableDraw: [0.44, 0.615],
  details: [0.575, 0.65],
  craneUp: [0.28, 0.35],
  craneOut: [0.625, 0.685],
  lampsOn: [0.655, 0.71],
  pulses: [0.665, 0.87],
  traffic: [0.69, 0.90],
  dawn: [0.84, 1.0],
} as const;

/* ── Small math kit ── */

const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
/** 0→1 smoothly across [a,b]. */
const smooth = (a: number, b: number, x: number) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
const easeOutCubic = (t: number) => 1 - Math.pow(1 - clamp01(t), 3);
/** Window helper: 0 before [a,b], eased 0→1 inside, 1 after. */
const win = (w: readonly [number, number] | readonly number[], p: number) => smooth(w[0], w[1], p);
/** Bump: rises over [a,b], falls over [c,d]. */
const bump = (a: number, b: number, c: number, d: number, p: number) =>
  smooth(a, b, p) * (1 - smooth(c, d, p));

/** Piecewise-linear track through [progress, value] pairs. */
function track(p: number, keys: ReadonlyArray<readonly [number, number]>): number {
  if (p <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    if (p <= keys[i][0]) {
      const [t0, v0] = keys[i - 1];
      const [t1, v1] = keys[i];
      return lerp(v0, v1, (p - t0) / (t1 - t0));
    }
  }
  return keys[keys.length - 1][1];
}

/** Deterministic PRNG so layout jitter is identical every visit. */
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Value noise + fbm for terrain and generated textures. */
function makeNoise2D(seed: number): (x: number, y: number) => number {
  const rnd = mulberry32(seed);
  const perm = new Uint8Array(512);
  const base = Array.from({ length: 256 }, (_, i) => i);
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [base[i], base[j]] = [base[j], base[i]];
  }
  for (let i = 0; i < 512; i++) perm[i] = base[i & 255];
  const grad = (h: number, x: number, y: number) => {
    switch (h & 3) {
      case 0: return x + y;
      case 1: return -x + y;
      case 2: return x - y;
      default: return -x - y;
    }
  };
  const fade = (t: number) => t * t * t * (t * (t * 6 - 15) + 10);
  return (x: number, y: number) => {
    const xi = Math.floor(x) & 255;
    const yi = Math.floor(y) & 255;
    const xf = x - Math.floor(x);
    const yf = y - Math.floor(y);
    const u = fade(xf);
    const v = fade(yf);
    const aa = perm[perm[xi] + yi];
    const ab = perm[perm[xi] + yi + 1];
    const ba = perm[perm[xi + 1] + yi];
    const bb = perm[perm[xi + 1] + yi + 1];
    const x1 = lerp(grad(aa, xf, yf), grad(ba, xf - 1, yf), u);
    const x2 = lerp(grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1), u);
    return lerp(x1, x2, v) * 0.7071;
  };
}

const noise = makeNoise2D(1917);

function fbm(x: number, y: number, octaves = 4): number {
  let sum = 0;
  let amp = 0.5;
  let f = 1;
  for (let i = 0; i < octaves; i++) {
    sum += amp * noise(x * f, y * f);
    amp *= 0.5;
    f *= 2.03;
  }
  return sum;
}

/** Centripetal-ish Catmull-Rom for the camera spline. */
function catmullRom(p0: number, p1: number, p2: number, p3: number, t: number): number {
  const t2 = t * t;
  const t3 = t2 * t;
  return (
    0.5 *
    (2 * p1 +
      (-p0 + p2) * t +
      (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
      (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
  );
}

/* ── Terrain height field (analytic - shared by mesh, piers, trees, lights) ── */

function terrainHeight(x: number, z: number): number {
  const meander = Math.sin(z * 0.004) * 18;
  const d = Math.abs(x - meander);
  const bank = smooth(52, 135, d);
  const far = smooth(140, 460, d);
  let h = lerp(-7, 11 + 44 * far + fbm(x * 0.008, z * 0.008, 4) * 16 * (0.35 + far), bank);
  h += fbm(x * 0.05, z * 0.05, 3) * 1.6 * bank;
  // Plateaus: abutment pads + the survey monument's outcrop.
  const padW = 1 - smooth(14, 40, Math.hypot(x + ABUTMENT_X, z));
  const padE = 1 - smooth(14, 40, Math.hypot(x - ABUTMENT_X, z));
  h = lerp(h, 19, Math.max(padW, padE) * 0.9);
  const mon = 1 - smooth(6, 22, Math.hypot(x - MONUMENT.x, z - MONUMENT.z));
  h = lerp(h, 9.2, mon);
  return h;
}

/* ── Generated textures (no external assets - everything is synthesized) ── */

function makeCanvas(size: number): [HTMLCanvasElement, CanvasRenderingContext2D] {
  const c = document.createElement("canvas");
  c.width = c.height = size;
  const ctx = c.getContext("2d");
  if (!ctx) throw new Error("2d context unavailable");
  return [c, ctx];
}

function canvasTexture(c: HTMLCanvasElement, srgb: boolean, repeat = 1): THREE.CanvasTexture {
  const tex = new THREE.CanvasTexture(c);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(repeat, repeat);
  if (srgb) tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  return tex;
}

function concreteTextures(): { map: THREE.CanvasTexture; rough: THREE.CanvasTexture } {
  const rnd = mulberry32(77);
  const [c, ctx] = makeCanvas(512);
  ctx.fillStyle = "rgb(168,167,163)";
  ctx.fillRect(0, 0, 512, 512);
  // Mottle
  for (let i = 0; i < 2600; i++) {
    const g = 140 + rnd() * 55;
    ctx.fillStyle = `rgba(${g},${g},${g - 4},${0.05 + rnd() * 0.1})`;
    const r = 2 + rnd() * 22;
    ctx.beginPath();
    ctx.arc(rnd() * 512, rnd() * 512, r, 0, Math.PI * 2);
    ctx.fill();
  }
  // Board-form lines
  for (let y = 26; y < 512; y += 56) {
    ctx.fillStyle = `rgba(90,88,84,${0.16 + rnd() * 0.1})`;
    ctx.fillRect(0, y + rnd() * 6, 512, 1.6);
  }
  // Pores
  for (let i = 0; i < 900; i++) {
    ctx.fillStyle = `rgba(70,68,66,${0.25 + rnd() * 0.3})`;
    const r = 0.6 + rnd() * 1.8;
    ctx.beginPath();
    ctx.arc(rnd() * 512, rnd() * 512, r, 0, Math.PI * 2);
    ctx.fill();
  }
  const [cr, ctxR] = makeCanvas(256);
  for (let y = 0; y < 256; y++) {
    for (let x = 0; x < 256; x += 4) {
      const v = 215 + fbm(x * 0.05, y * 0.05, 3) * 60;
      ctxR.fillStyle = `rgb(${v},${v},${v})`;
      ctxR.fillRect(x, y, 4, 1);
    }
  }
  return { map: canvasTexture(c, true), rough: canvasTexture(cr, false) };
}

function asphaltTexture(): THREE.CanvasTexture {
  const rnd = mulberry32(31);
  const [c, ctx] = makeCanvas(256);
  ctx.fillStyle = "rgb(43,45,48)";
  ctx.fillRect(0, 0, 256, 256);
  for (let i = 0; i < 6000; i++) {
    const g = 30 + rnd() * 44;
    ctx.fillStyle = `rgba(${g},${g},${g + 2},0.5)`;
    ctx.fillRect(rnd() * 256, rnd() * 256, 1.4, 1.4);
  }
  return canvasTexture(c, true, 6);
}

function rockDetailTexture(): THREE.CanvasTexture {
  const [c, ctx] = makeCanvas(256);
  for (let y = 0; y < 256; y++) {
    for (let x = 0; x < 256; x += 2) {
      const v = 185 + fbm(x * 0.06 + 40, y * 0.06, 4) * 90;
      ctx.fillStyle = `rgb(${v},${v},${v})`;
      ctx.fillRect(x, y, 2, 1);
    }
  }
  return canvasTexture(c, true, 48);
}

function waterNormalsTexture(): THREE.CanvasTexture {
  const size = 256;
  const [c, ctx] = makeCanvas(size);
  const img = ctx.createImageData(size, size);
  const h = (x: number, y: number) =>
    fbm(x * 0.045, y * 0.045, 4) * 1.4 + fbm(x * 0.11 + 90, y * 0.11, 2) * 0.5;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = h(x + 1, y) - h(x - 1, y);
      const dy = h(x, y + 1) - h(x, y - 1);
      const n = new THREE.Vector3(-dx * 2.2, -dy * 2.2, 1).normalize();
      const i = (y * size + x) * 4;
      img.data[i] = (n.x * 0.5 + 0.5) * 255;
      img.data[i + 1] = (n.y * 0.5 + 0.5) * 255;
      img.data[i + 2] = (n.z * 0.5 + 0.5) * 255;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return canvasTexture(c, false);
}

function latticeAlphaTexture(): THREE.CanvasTexture {
  const [c, ctx] = makeCanvas(128);
  ctx.fillStyle = "black";
  ctx.fillRect(0, 0, 128, 128);
  ctx.strokeStyle = "white";
  ctx.lineWidth = 11;
  ctx.beginPath();
  ctx.moveTo(6, 0); ctx.lineTo(6, 128);
  ctx.moveTo(122, 0); ctx.lineTo(122, 128);
  ctx.moveTo(6, 0); ctx.lineTo(122, 64);
  ctx.moveTo(122, 64); ctx.lineTo(6, 128);
  ctx.moveTo(6, 64); ctx.lineTo(122, 0);
  ctx.moveTo(6, 64); ctx.lineTo(122, 128);
  ctx.stroke();
  const tex = canvasTexture(c, false, 1);
  tex.repeat.set(1, 8);
  return tex;
}

function softDotTexture(): THREE.CanvasTexture {
  const [c, ctx] = makeCanvas(64);
  const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32);
  g.addColorStop(0, "rgba(255,255,255,1)");
  g.addColorStop(0.35, "rgba(255,255,255,0.55)");
  g.addColorStop(1, "rgba(255,255,255,0)");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 64, 64);
  return canvasTexture(c, false);
}

/* ── GLSL ── */

const SKY_VERT = /* glsl */ `
  varying vec3 vDir;
  void main() {
    vDir = position;
    vec4 mv = modelViewMatrix * vec4(position, 1.0);
    gl_Position = projectionMatrix * mv;
  }
`;

const SKY_FRAG = /* glsl */ `
  varying vec3 vDir;
  uniform vec3 uSunDir;
  uniform vec3 uZenith;
  uniform vec3 uHorizon;
  uniform vec3 uHaze;
  uniform float uStars;
  uniform float uCirrus;
  uniform float uSunI;
  uniform float uTime;

  float hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
  }
  float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
  }
  float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
      mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
      mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
      u.y);
  }
  float fbm2(vec2 p) {
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
      s += a * vnoise(p);
      a *= 0.5;
      p *= 2.07;
    }
    return s;
  }

  void main() {
    vec3 d = normalize(vDir);
    float up = clamp(d.y, 0.0, 1.0);
    vec3 sky = mix(uHorizon, uZenith, pow(up, 0.55));
    sky += uHaze * pow(1.0 - abs(d.y), 6.0) * 0.65;

    // Sun disk + halo (tinted warm near the horizon)
    float s = clamp(dot(d, uSunDir), 0.0, 1.0);
    vec3 tint = mix(vec3(1.0, 0.52, 0.22), vec3(1.0, 0.96, 0.86), clamp(uSunDir.y * 3.0, 0.0, 1.0));
    sky += tint * uSunI * (pow(s, 1600.0) * 3.4 + pow(s, 64.0) * 0.30 + pow(s, 8.0) * 0.035);

    // Stars (twinkling, fading at the horizon)
    vec3 g = floor(d * 260.0);
    float h = hash13(g);
    float star = step(0.9986, h) * uStars * smoothstep(0.03, 0.25, d.y);
    sky += vec3(0.9, 0.94, 1.0) * star * (0.5 + 0.5 * sin(uTime * 2.0 + h * 87.0));

    // Thin cirrus
    float cir = fbm2(d.xz / (abs(d.y) + 0.14) * 1.7 + vec2(uTime * 0.005, 0.0));
    sky += uCirrus * vec3(0.72, 0.78, 0.88) * smoothstep(0.52, 0.86, cir) * smoothstep(0.02, 0.3, d.y) * 0.4;

    gl_FragColor = vec4(sky, 1.0);
  }
`;

const GRID_VERT = /* glsl */ `
  varying vec3 vWorld;
  void main() {
    vec4 wp = modelMatrix * vec4(position, 1.0);
    vWorld = wp.xyz;
    gl_Position = projectionMatrix * viewMatrix * wp;
  }
`;

const GRID_FRAG = /* glsl */ `
  varying vec3 vWorld;
  uniform vec2 uCenter;
  uniform float uRadius;
  uniform float uOpacity;
  uniform float uTime;
  uniform vec3 uColor;
  void main() {
    vec2 rel = vWorld.xz - uCenter;
    float r = length(rel);
    vec2 cMinor = vWorld.xz / 8.0;
    vec2 aMinor = abs(fract(cMinor - 0.5) - 0.5) / fwidth(cMinor);
    float minor = 1.0 - min(min(aMinor.x, aMinor.y), 1.0);
    vec2 cMajor = vWorld.xz / 40.0;
    vec2 aMajor = abs(fract(cMajor - 0.5) - 0.5) / fwidth(cMajor);
    float major = 1.0 - min(min(aMajor.x, aMajor.y), 1.0);
    float draw = smoothstep(uRadius, uRadius - 22.0, r);
    float outer = smoothstep(340.0, 230.0, r);
    float shimmer = 1.0 + 0.10 * sin(r * 0.8 - uTime * 3.2);
    float head = smoothstep(uRadius, uRadius - 5.0, r) - smoothstep(uRadius - 9.0, uRadius - 14.0, r);
    float a = (minor * 0.20 + major * 0.55) * draw * outer * uOpacity * shimmer;
    a += max(head, 0.0) * uOpacity * 0.9;
    gl_FragColor = vec4(uColor * (1.0 + max(head, 0.0) * 2.0), a);
  }
`;

const RINGS_FRAG = /* glsl */ `
  varying vec3 vWorld;
  uniform vec2 uCenter;
  uniform float uOpacity;
  uniform float uTime;
  uniform vec3 uColor;
  void main() {
    float r = length(vWorld.xz - uCenter);
    float wave = pow(max(0.0, sin(r * 1.35 - uTime * 2.4)), 20.0);
    float falloff = smoothstep(26.0, 4.0, r);
    float dot_ = smoothstep(1.6, 0.2, r) * (0.7 + 0.3 * sin(uTime * 4.0));
    float a = (wave * falloff * 0.42 + dot_) * uOpacity;
    gl_FragColor = vec4(uColor, a);
  }
`;

const LINES_VERT = /* glsl */ `
  attribute float aT;
  attribute float aDelay;
  attribute float aGroup;
  uniform float uDrawG[4];
  uniform float uFadeG[4];
  varying float vT;
  varying float vDelay;
  varying float vDraw;
  varying float vFade;
  void main() {
    vT = aT;
    vDelay = aDelay;
    int gi = int(aGroup + 0.5);
    vDraw = uDrawG[gi];
    vFade = uFadeG[gi];
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const LINES_FRAG = /* glsl */ `
  varying float vT;
  varying float vDelay;
  varying float vDraw;
  varying float vFade;
  uniform vec3 uColor;
  uniform float uPulse;
  uniform float uTime;
  void main() {
    float reach = vDraw * 1.06;
    float drawn = smoothstep(0.0, 0.05, reach - vT);
    float head = drawn * smoothstep(0.06, 0.0, reach - vT);
    float base = drawn * (1.0 - vFade) * 0.44;

    // Data packets racing the geometry after the build (act IV)
    float run = fract(vT * 2.0 - uTime * 0.16 + vDelay * 0.73);
    float packet = smoothstep(0.0, 0.018, run) * smoothstep(0.052, 0.02, run);
    packet *= uPulse * step(0.999, drawn);

    float a = base + head * 1.5 + packet * 3.2;
    if (a < 0.004) discard;
    vec3 col = uColor * (1.0 + head * 2.4 + packet * 3.4);
    gl_FragColor = vec4(col, a);
  }
`;

const BEAM_VERT = /* glsl */ `
  varying vec2 vUv;
  void main() {
    vUv = uv;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

const BEAM_FRAG = /* glsl */ `
  varying vec2 vUv;
  uniform float uOpacity;
  uniform vec3 uColor;
  void main() {
    float radial = smoothstep(0.5, 0.05, abs(vUv.x - 0.5));
    float vert = pow(1.0 - vUv.y, 1.6) * smoothstep(0.0, 0.12, vUv.y);
    gl_FragColor = vec4(uColor, radial * vert * uOpacity);
  }
`;

const GRADE_SHADER = {
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    uTime: { value: 0 },
    uGrain: { value: 0.05 },
    uVig: { value: 0.42 },
    uCA: { value: 0.0015 },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
  `,
  fragmentShader: /* glsl */ `
    varying vec2 vUv;
    uniform sampler2D tDiffuse;
    uniform float uTime;
    uniform float uGrain;
    uniform float uVig;
    uniform float uCA;
    float hash(vec2 p) {
      vec3 p3 = fract(vec3(p.xyx) * 0.1031);
      p3 += dot(p3, p3.yzx + 33.33);
      return fract((p3.x + p3.y) * p3.z);
    }
    void main() {
      vec2 c = vUv - 0.5;
      float rC = texture2D(tDiffuse, vUv + c * uCA).r;
      float gC = texture2D(tDiffuse, vUv).g;
      float bC = texture2D(tDiffuse, vUv - c * uCA).b;
      float vig = 1.0 - uVig * smoothstep(0.42, 1.3, length(c) * 2.0);
      float grain = (hash(vUv * vec2(1417.0, 813.0) + fract(uTime) * 91.0) - 0.5) * uGrain;
      gl_FragColor = vec4((vec3(rC, gC, bC) + grain) * vig, 1.0);
    }
  `,
};

/* ── Segment / cable pre-computation ── */

interface SegmentSpec {
  cx: number;
  seatT: number;
  fromWest: boolean; // which pylon (or abutment side) erects it
}

interface CableSpec {
  pylonX: number;
  side: 1 | -1; // z side of the deck
  top: THREE.Vector3;
  deck: THREE.Vector3;
  drawT: number;
}

function computeSegments(): SegmentSpec[] {
  const rnd = mulberry32(4242);
  const segs: SegmentSpec[] = [];
  for (let i = 0; i < SEG_COUNT; i++) {
    const cx = -ABUTMENT_X + SEG_LEN / 2 + i * SEG_LEN;
    const px = cx < 0 ? -PYLON_X : PYLON_X;
    const rank = Math.round((Math.abs(cx - px) - SEG_LEN / 2) / SEG_LEN); // 0..7
    const t = T.deckSeat[0] + ((rank + rnd() * 0.45) / 8.7) * (T.deckSeat[1] - T.deckSeat[0]);
    segs.push({ cx, seatT: t, fromWest: cx < 0 });
  }
  return segs;
}

function pylonLegZ(y: number): number {
  return lerp(13, 8.5, clamp01((y + 2) / (PYLON_TOP + 2)));
}

function computeCables(segs: SegmentSpec[]): CableSpec[] {
  const cables: CableSpec[] = [];
  const rnd = mulberry32(555);
  for (const seg of segs) {
    const px = seg.cx < 0 ? -PYLON_X : PYLON_X;
    const dist = Math.abs(seg.cx - px);
    const rank = Math.round((dist - SEG_LEN / 2) / SEG_LEN);
    if (rank > 5) continue; // outer approach segments ride the piers instead
    const topY = 58 + rank * 6.4;
    for (const side of [1, -1] as const) {
      cables.push({
        pylonX: px,
        side,
        top: new THREE.Vector3(px, topY, pylonLegZ(topY) * side),
        deck: new THREE.Vector3(seg.cx, DECK_Y + 0.4, (DECK_HALF_W - 0.6) * side),
        drawT: Math.min(seg.seatT + 0.018 + rnd() * 0.01, T.cableDraw[1] - 0.02),
      });
    }
  }
  return cables;
}

/* ── Blueprint line network (drawn as holograms, re-used as the data layer) ── */

interface LineBuild {
  positions: number[];
  ts: number[];
  delays: number[];
  groups: number[];
}

function pushPolyline(out: LineBuild, pts: THREE.Vector3[], group: number, delay: number): void {
  let total = 0;
  const cum = [0];
  for (let i = 1; i < pts.length; i++) {
    total += pts[i].distanceTo(pts[i - 1]);
    cum.push(total);
  }
  if (total <= 0) return;
  for (let i = 1; i < pts.length; i++) {
    out.positions.push(pts[i - 1].x, pts[i - 1].y, pts[i - 1].z, pts[i].x, pts[i].y, pts[i].z);
    out.ts.push(cum[i - 1] / total, cum[i] / total);
    out.delays.push(delay, delay);
    out.groups.push(group, group);
  }
}

function buildBlueprintGeometry(cables: CableSpec[]): THREE.BufferGeometry {
  const b: LineBuild = { positions: [], ts: [], delays: [], groups: [] };
  const rnd = mulberry32(99);
  const v = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);

  // Group 0 - pylons (outline both)
  for (const px of [-PYLON_X, PYLON_X]) {
    for (const s of [1, -1]) {
      const zB = pylonLegZ(-2) * s;
      const zT = pylonLegZ(PYLON_TOP) * s;
      pushPolyline(b, [v(px - 2.6, -2, zB), v(px - 2.6, PYLON_TOP, zT)], 0, rnd() * 0.4);
      pushPolyline(b, [v(px + 2.6, -2, zB), v(px + 2.6, PYLON_TOP, zT)], 0, rnd() * 0.4);
    }
    // Crossbeams
    pushPolyline(b, [v(px, 27, -pylonLegZ(27)), v(px, 27, pylonLegZ(27))], 0, rnd() * 0.4);
    pushPolyline(b, [v(px, 84, -pylonLegZ(84)), v(px, 84, pylonLegZ(84))], 0, rnd() * 0.4);
  }

  // Group 1 - deck chords (top edges + underside)
  for (const z of [DECK_HALF_W, -DECK_HALF_W]) {
    pushPolyline(b, [v(-ABUTMENT_X, DECK_Y, z), v(ABUTMENT_X, DECK_Y, z)], 1, rnd() * 0.3);
  }
  for (const z of [6, -6]) {
    pushPolyline(b, [v(-ABUTMENT_X, DECK_Y - GIRDER_DEPTH, z), v(ABUTMENT_X, DECK_Y - GIRDER_DEPTH, z)], 1, 0.3 + rnd() * 0.3);
  }
  // Cross ribs every 30
  for (let x = -ABUTMENT_X + 15; x < ABUTMENT_X; x += 30) {
    pushPolyline(b, [v(x, DECK_Y, -DECK_HALF_W), v(x, DECK_Y, DECK_HALF_W)], 1, 0.5 + rnd() * 0.5);
  }

  // Group 2 - cables
  for (const c of cables) {
    pushPolyline(b, [c.top.clone(), c.deck.clone()], 2, rnd());
  }

  // Group 3 - dimension ticks + span callouts (drafting garnish)
  const dimY = DECK_Y + 16;
  pushPolyline(b, [v(-PYLON_X, dimY - 3, 0), v(-PYLON_X, dimY + 3, 0)], 3, 0);
  pushPolyline(b, [v(PYLON_X, dimY - 3, 0), v(PYLON_X, dimY + 3, 0)], 3, 0.2);
  pushPolyline(b, [v(-PYLON_X, dimY, 0), v(PYLON_X, dimY, 0)], 3, 0.4);
  pushPolyline(b, [v(-ABUTMENT_X, dimY - 8, 0), v(-ABUTMENT_X, dimY - 2, 0)], 3, 0.5);
  pushPolyline(b, [v(ABUTMENT_X, dimY - 8, 0), v(ABUTMENT_X, dimY - 2, 0)], 3, 0.6);
  pushPolyline(b, [v(-ABUTMENT_X, dimY - 5, 0), v(ABUTMENT_X, dimY - 5, 0)], 3, 0.8);
  for (const px of [-PYLON_X, PYLON_X]) {
    pushPolyline(b, [v(px + 8, -2, 0), v(px + 8, PYLON_TOP, 0)], 3, rnd());
    for (const y of [-2, 27, 58, 84, PYLON_TOP]) {
      pushPolyline(b, [v(px + 6.5, y, 0), v(px + 9.5, y, 0)], 3, rnd());
    }
  }

  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(b.positions, 3));
  geo.setAttribute("aT", new THREE.Float32BufferAttribute(b.ts, 1));
  geo.setAttribute("aDelay", new THREE.Float32BufferAttribute(b.delays, 1));
  geo.setAttribute("aGroup", new THREE.Float32BufferAttribute(b.groups, 1));
  return geo;
}

/* ── Camera rig ── */

interface CamKey {
  t: number;
  pos: [number, number, number];
  look: [number, number, number];
  fov: number;
  ap: number; // bokeh aperture
}

const CAM_KEYS: CamKey[] = [
  { t: 0.0, pos: [-127, 12.8, 49.8], look: [-122, 9.9, 42], fov: 50, ap: 3.4e-4 },
  { t: 0.085, pos: [-136, 17, 63], look: [-116, 9.5, 34], fov: 51, ap: 2.0e-4 },
  { t: 0.155, pos: [-176, 44, 118], look: [-58, 20, -2], fov: 49, ap: 0.9e-4 },
  { t: 0.235, pos: [-132, 60, 152], look: [-8, 34, -6], fov: 47, ap: 0.7e-4 },
  { t: 0.315, pos: [-158, 25, 74], look: [-90, 54, 0], fov: 46, ap: 0.9e-4 },
  { t: 0.40, pos: [-146, 42, 50], look: [-84, 34, 0], fov: 45, ap: 0.9e-4 },
  { t: 0.445, pos: [-98, 47, 3], look: [-38, 33, -3], fov: 46, ap: 1.0e-4 },
  { t: 0.475, pos: [-56, 42, -40], look: [0, 33, 0], fov: 44, ap: 1.0e-4 },
  { t: 0.555, pos: [-16, 31, -74], look: [58, 36, 4], fov: 46, ap: 0.8e-4 },
  { t: 0.625, pos: [34, 55, -108], look: [-2, 34, 0], fov: 46, ap: 0.7e-4 },
  { t: 0.70, pos: [2, 7.5, 130], look: [0, 38, -8], fov: 48, ap: 0.9e-4 },
  { t: 0.79, pos: [-98, 63, 150], look: [-6, 32, -4], fov: 46, ap: 0.7e-4 },
  { t: 0.88, pos: [-30, 122, 252], look: [0, 26, -30], fov: 52, ap: 0.5e-4 },
  { t: 1.0, pos: [20, 214, 385], look: [0, 2, -85], fov: 55, ap: 0.4e-4 },
];

function evalCamera(
  p: number,
  outPos: THREE.Vector3,
  outLook: THREE.Vector3
): { fov: number; ap: number } {
  const keys = CAM_KEYS;
  let i = 0;
  while (i < keys.length - 2 && p > keys[i + 1].t) i++;
  const k1 = keys[i];
  const k2 = keys[i + 1];
  const k0 = keys[Math.max(0, i - 1)];
  const k3 = keys[Math.min(keys.length - 1, i + 2)];
  const s = clamp01((p - k1.t) / (k2.t - k1.t));
  for (let axis = 0; axis < 3; axis++) {
    const pv = catmullRom(k0.pos[axis], k1.pos[axis], k2.pos[axis], k3.pos[axis], s);
    const lv = catmullRom(k0.look[axis], k1.look[axis], k2.look[axis], k3.look[axis], s);
    if (axis === 0) { outPos.x = pv; outLook.x = lv; }
    else if (axis === 1) { outPos.y = pv; outLook.y = lv; }
    else { outPos.z = pv; outLook.z = lv; }
  }
  return { fov: lerp(k1.fov, k2.fov, smooth(0, 1, s)), ap: lerp(k1.ap, k2.ap, s) };
}

/* ── The scene ── */

export function createCinematicScene(
  canvas: HTMLCanvasElement,
  quality: CinematicQuality
): CinematicSceneHandle {
  const high = quality === "high";
  const disposables: Array<{ dispose(): void }> = [];
  const own = <D extends { dispose(): void }>(d: D): D => {
    disposables.push(d);
    return d;
  };

  // Brand azure for holograms/data - read from the live token so the scene
  // follows the design system's single source of truth.
  const azureCss = getComputedStyle(canvas).getPropertyValue("--cta").trim();
  const AZURE = new THREE.Color(azureCss || "#0a84ff");
  const AZURE_HOT = AZURE.clone().multiplyScalar(1.65);

  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: false,
    alpha: false,
    powerPreference: "high-performance",
    stencil: false,
  });
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.localClippingEnabled = true;

  const scene = new THREE.Scene();
  scene.fog = new THREE.FogExp2(0x0a1220, 0.0028);

  const camera = new THREE.PerspectiveCamera(52, 16 / 9, 0.5, 6000);
  camera.layers.enable(1); // holographic elements hidden from mirror renders

  // IBL: neutral studio environment at low intensity gives PBR speculars;
  // the animated sun/hemisphere carry the mood.
  const pmrem = own(new THREE.PMREMGenerator(renderer));
  const envRT = pmrem.fromScene(new RoomEnvironment(), 0.04);
  own(envRT);
  scene.environment = envRT.texture;
  scene.environmentIntensity = 0.35;

  /* ── Lights ── */
  const sun = new THREE.DirectionalLight(0xffffff, 0);
  sun.castShadow = true;
  sun.shadow.mapSize.set(high ? 2048 : 1024, high ? 2048 : 1024);
  const sc = sun.shadow.camera;
  sc.left = -280; sc.right = 280; sc.top = 170; sc.bottom = -80;
  sc.near = 60; sc.far = 1300;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 1.2;
  scene.add(sun, sun.target);

  const hemi = new THREE.HemisphereLight(0x243448, 0x0c0f12, 0.4);
  scene.add(hemi);

  const moon = new THREE.DirectionalLight(0x8fa8cc, 0.22);
  moon.position.set(-180, 300, 220);
  scene.add(moon);

  /* ── Sky ── */
  const skyUniforms = {
    uSunDir: { value: new THREE.Vector3(0, -1, 0) },
    uZenith: { value: new THREE.Color(0x04070f) },
    uHorizon: { value: new THREE.Color(0x0b1626) },
    uHaze: { value: new THREE.Color(0x1a2c42) },
    uStars: { value: 1 },
    uCirrus: { value: 0.15 },
    uSunI: { value: 0 },
    uTime: { value: 0 },
  };
  const skyMat = own(new THREE.ShaderMaterial({
    uniforms: skyUniforms,
    vertexShader: SKY_VERT,
    fragmentShader: SKY_FRAG,
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
  }));
  const sky = new THREE.Mesh(own(new THREE.SphereGeometry(3800, 40, 24)), skyMat);
  sky.renderOrder = -10;
  scene.add(sky);

  /* ── Terrain ── */
  const terrainGeo = own(new THREE.PlaneGeometry(1400, 900, high ? 190 : 110, high ? 130 : 76));
  terrainGeo.rotateX(-Math.PI / 2);
  {
    const pos = terrainGeo.attributes.position;
    const colors = new Float32Array(pos.count * 3);
    const rock = new THREE.Color(0x59544b);
    const rockB = new THREE.Color(0x6b665c);
    const scrub = new THREE.Color(0x49523f);
    const sand = new THREE.Color(0x6e6455);
    const tmp = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i);
      const z = pos.getZ(i);
      const h = terrainHeight(x, z);
      pos.setY(i, h);
      const n = fbm(x * 0.02 + 9, z * 0.02, 3);
      tmp.copy(rock).lerp(rockB, clamp01(0.5 + n));
      const scrubAmt = clamp01(0.5 + fbm(x * 0.013 - 30, z * 0.013, 3)) * smooth(6, 16, h) * (1 - smooth(48, 80, h));
      tmp.lerp(scrub, scrubAmt * 0.85);
      tmp.lerp(sand, 1 - smooth(1.2, 5, h));
      colors[i * 3] = tmp.r;
      colors[i * 3 + 1] = tmp.g;
      colors[i * 3 + 2] = tmp.b;
    }
    terrainGeo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
    terrainGeo.computeVertexNormals();
  }
  const rockTex = own(rockDetailTexture());
  const terrainMat = own(new THREE.MeshStandardMaterial({
    vertexColors: true,
    map: rockTex,
    roughness: 0.96,
    metalness: 0,
  }));
  const terrain = new THREE.Mesh(terrainGeo, terrainMat);
  terrain.receiveShadow = true;
  scene.add(terrain);

  /* ── Water ── */
  // Full-valley sheet: the banks rise above y=0 so the plane only reads as
  // water in the river channel - and its edges never enter the frame.
  let waterUpdate: (t: number, sunDir: THREE.Vector3, night: number) => void;
  const waterGeo = own(new THREE.PlaneGeometry(1400, 900, 1, 1));
  if (high) {
    const water = new Water(waterGeo, {
      textureWidth: 512,
      textureHeight: 512,
      waterNormals: own(waterNormalsTexture()),
      sunDirection: new THREE.Vector3(0, 1, 0),
      sunColor: 0xffffff,
      waterColor: 0x061018,
      distortionScale: 1.6,
      fog: true,
    });
    water.rotation.x = -Math.PI / 2;
    water.position.y = 0.25;
    scene.add(water);
    const wu = (water.material as THREE.ShaderMaterial).uniforms;
    own(water.material as THREE.ShaderMaterial);
    waterUpdate = (t, sunDir, night) => {
      wu.time.value = t * 0.55;
      (wu.sunDirection.value as THREE.Vector3).copy(sunDir);
      (wu.sunColor.value as THREE.Color).setRGB(
        lerp(1, 0.45, night), lerp(0.92, 0.55, night), lerp(0.82, 0.75, night));
      (wu.waterColor.value as THREE.Color).setHex(0x061018).lerp(new THREE.Color(0x03070c), night);
    };
  } else {
    const mat = own(new THREE.MeshStandardMaterial({
      color: 0x0a1219,
      metalness: 0.9,
      roughness: 0.14,
      envMapIntensity: 1.1,
    }));
    const water = new THREE.Mesh(waterGeo, mat);
    water.rotation.x = -Math.PI / 2;
    water.position.y = 0.25;
    scene.add(water);
    waterUpdate = () => undefined;
  }

  /* ── Materials ── */
  const conc = concreteTextures();
  own(conc.map); own(conc.rough);
  const concreteMat = own(new THREE.MeshStandardMaterial({
    color: 0xb4b2ac,
    map: conc.map,
    roughnessMap: conc.rough,
    roughness: 0.94,
    metalness: 0.0,
    envMapIntensity: 0.5,
  }));
  const girderMat = own(new THREE.MeshStandardMaterial({
    color: 0x9aacbe,
    metalness: 0.62,
    roughness: 0.4,
    envMapIntensity: 0.75,
  }));
  const asphaltMat = own(new THREE.MeshStandardMaterial({
    color: 0xffffff,
    map: own(asphaltTexture()),
    roughness: 0.96,
    metalness: 0,
    envMapIntensity: 0.15,
  }));
  const cableMat = own(new THREE.MeshStandardMaterial({
    color: 0xdde2e6,
    metalness: 0.35,
    roughness: 0.45,
    envMapIntensity: 0.5,
  }));
  const craneMat = own(new THREE.MeshStandardMaterial({
    color: 0xd99e1c,
    metalness: 0.3,
    roughness: 0.55,
    envMapIntensity: 0.4,
    transparent: true,
  }));
  const craneLatticeMat = own(new THREE.MeshStandardMaterial({
    color: 0xd99e1c,
    metalness: 0.3,
    roughness: 0.55,
    alphaMap: own(latticeAlphaTexture()),
    alphaTest: 0.5,
    side: THREE.DoubleSide,
    transparent: true,
  }));
  const railMat = own(new THREE.MeshStandardMaterial({
    color: 0x8b959e,
    metalness: 0.75,
    roughness: 0.35,
    envMapIntensity: 0.6,
  }));
  const brassMat = own(new THREE.MeshStandardMaterial({
    color: 0xc8963e,
    metalness: 1,
    roughness: 0.32,
    envMapIntensity: 1.1,
  }));
  const treeMat = own(new THREE.MeshStandardMaterial({ color: 0x1c291f, roughness: 1 }));
  const lampMat = own(new THREE.MeshStandardMaterial({
    color: 0x30343a,
    emissive: 0xffc37a,
    emissiveIntensity: 0,
    metalness: 0.4,
    roughness: 0.5,
  }));

  /* ── Datum monument (act I macro subject) ── */
  const monumentGroup = new THREE.Group();
  {
    const plinth = new THREE.Mesh(own(new THREE.CylinderGeometry(1.4, 1.7, 0.9, 24)), concreteMat);
    plinth.position.set(MONUMENT.x, MONUMENT.y - 0.45, MONUMENT.z);
    plinth.castShadow = plinth.receiveShadow = true;
    const disk = new THREE.Mesh(own(new THREE.CylinderGeometry(0.62, 0.62, 0.1, 32)), brassMat);
    disk.position.set(MONUMENT.x, MONUMENT.y + 0.06, MONUMENT.z);
    disk.castShadow = true;
    monumentGroup.add(plinth, disk);
  }
  scene.add(monumentGroup);

  // Rising light column + ground rings + survey grid - the hologram layer.
  const ringsUniforms = {
    uCenter: { value: new THREE.Vector2(MONUMENT.x, MONUMENT.z) },
    uOpacity: { value: 0 },
    uTime: { value: 0 },
    uColor: { value: AZURE_HOT },
  };
  const ringsMat = own(new THREE.ShaderMaterial({
    uniforms: ringsUniforms,
    vertexShader: GRID_VERT,
    fragmentShader: RINGS_FRAG,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    fog: false,
  }));
  const rings = new THREE.Mesh(own(new THREE.PlaneGeometry(64, 64)), ringsMat);
  rings.rotation.x = -Math.PI / 2;
  rings.position.set(MONUMENT.x, MONUMENT.y + 0.18, MONUMENT.z);
  scene.add(rings);

  const beamUniforms = {
    uOpacity: { value: 0 },
    uColor: { value: AZURE_HOT },
  };
  const beamMat = own(new THREE.ShaderMaterial({
    uniforms: beamUniforms,
    vertexShader: BEAM_VERT,
    fragmentShader: BEAM_FRAG,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    side: THREE.DoubleSide,
    fog: false,
  }));
  const beam = new THREE.Mesh(own(new THREE.PlaneGeometry(2.6, 46)), beamMat);
  beam.position.set(MONUMENT.x, MONUMENT.y + 23, MONUMENT.z);
  const beam2 = beam.clone();
  beam2.rotation.y = Math.PI / 2;
  // Layer 1 = "main camera only": the Water mirror camera renders layer 0, so
  // the light column never shows up as a hard-edged quad in the reflection.
  beam.layers.set(1);
  beam2.layers.set(1);
  scene.add(beam, beam2);

  const gridUniforms = {
    uCenter: { value: new THREE.Vector2(MONUMENT.x, MONUMENT.z) },
    uRadius: { value: 0 },
    uOpacity: { value: 0 },
    uTime: { value: 0 },
    uColor: { value: AZURE },
  };
  const gridMat = own(new THREE.ShaderMaterial({
    uniforms: gridUniforms,
    vertexShader: GRID_VERT,
    fragmentShader: GRID_FRAG,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    fog: false,
  }));
  const gridPlane = new THREE.Mesh(own(new THREE.PlaneGeometry(760, 760)), gridMat);
  gridPlane.rotation.x = -Math.PI / 2;
  gridPlane.position.set(MONUMENT.x, 6.0, MONUMENT.z);
  scene.add(gridPlane);

  /* ── Blueprint hologram lines ── */
  const segments = computeSegments();
  const cables = computeCables(segments);
  const linesUniforms = {
    uDrawG: { value: [0, 0, 0, 0] },
    uFadeG: { value: [0, 0, 0, 0] },
    uColor: { value: AZURE },
    uPulse: { value: 0 },
    uTime: { value: 0 },
  };
  const linesMat = own(new THREE.ShaderMaterial({
    uniforms: linesUniforms,
    vertexShader: LINES_VERT,
    fragmentShader: LINES_FRAG,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    fog: false,
  }));
  const blueprint = new THREE.LineSegments(own(buildBlueprintGeometry(cables)), linesMat);
  scene.add(blueprint);

  /* ── Pylons (clip-plane "pour") ── */
  const pylonClips: THREE.Plane[] = [];
  const pylonGroup = new THREE.Group();
  const collars: THREE.Mesh[] = [];
  for (const px of [-PYLON_X, PYLON_X]) {
    const clip = new THREE.Plane(new THREE.Vector3(0, -1, 0), -2); // clips y > constant*-1
    pylonClips.push(clip);
    const mat = concreteMat.clone();
    own(mat);
    mat.clippingPlanes = [clip];
    const one = new THREE.Group();
    for (const s of [1, -1]) {
      const legLen = PYLON_TOP + 4;
      const leg = new THREE.Mesh(own(new THREE.BoxGeometry(5.2, legLen, 3.6)), mat);
      const zBottom = pylonLegZ(-2) * s;
      const zTop = pylonLegZ(PYLON_TOP) * s;
      leg.position.set(px, (PYLON_TOP - 2) / 2, (zBottom + zTop) / 2);
      leg.rotation.x = Math.atan2((zTop - zBottom) * s, legLen) * s;
      leg.castShadow = leg.receiveShadow = true;
      one.add(leg);
    }
    const beamLo = new THREE.Mesh(own(new THREE.BoxGeometry(5.4, 5.6, pylonLegZ(27) * 2 + 2)), mat);
    beamLo.position.set(px, 26, 0);
    beamLo.castShadow = beamLo.receiveShadow = true;
    const beamHi = new THREE.Mesh(own(new THREE.BoxGeometry(4.6, 4.2, pylonLegZ(84) * 2 + 2)), mat);
    beamHi.position.set(px, 84, 0);
    beamHi.castShadow = true;
    one.add(beamLo, beamHi);
    // Caisson platform in the river
    const caisson = new THREE.Mesh(own(new THREE.CylinderGeometry(11, 12, 7, 24)), concreteMat);
    caisson.position.set(px, -0.4, 0);
    caisson.receiveShadow = true;
    one.add(caisson);
    // Slip-form collar riding the pour
    const collar = new THREE.Mesh(own(new THREE.BoxGeometry(8.4, 2.2, 24)), craneMat);
    collar.position.set(px, 0, 0);
    collar.castShadow = true;
    collars.push(collar);
    one.add(collar);
    pylonGroup.add(one);
  }
  scene.add(pylonGroup);

  /* ── Approach piers + abutments ── */
  const approachPiers: THREE.Mesh[] = [];
  const pierGroup = new THREE.Group();
  for (const px of [-150, -185, 150, 185]) {
    const baseY = Math.max(terrainHeight(px, 0), 0.5);
    const h = DECK_Y - GIRDER_DEPTH - baseY;
    const pier = new THREE.Mesh(own(new THREE.BoxGeometry(4.4, h, 9)), concreteMat);
    pier.position.set(px, baseY, 0); // grows upward via scale.y
    pier.geometry.translate(0, h / 2, 0);
    pier.castShadow = pier.receiveShadow = true;
    pier.scale.y = 0.001;
    approachPiers.push(pier);
    pierGroup.add(pier);
  }
  for (const px of [-ABUTMENT_X - 4, ABUTMENT_X + 4]) {
    const ab = new THREE.Mesh(own(new THREE.BoxGeometry(10, 14, 26)), concreteMat);
    ab.position.set(px, DECK_Y - GIRDER_DEPTH - 6, 0);
    ab.castShadow = ab.receiveShadow = true;
    pierGroup.add(ab);
  }
  scene.add(pierGroup);

  /* ── Deck segments ── */
  const deckGroup = new THREE.Group();
  const segMeshes: THREE.Group[] = [];
  {
    // Box-girder cross-section, extruded one segment long.
    const shape = new THREE.Shape();
    shape.moveTo(-DECK_HALF_W, 0);
    shape.lineTo(DECK_HALF_W, 0);
    shape.lineTo(9, -0.7);
    shape.lineTo(6.2, -GIRDER_DEPTH);
    shape.lineTo(-6.2, -GIRDER_DEPTH);
    shape.lineTo(-9, -0.7);
    shape.closePath();
    const girderGeo = own(new THREE.ExtrudeGeometry(shape, { depth: SEG_LEN, bevelEnabled: false }));
    girderGeo.rotateY(Math.PI / 2); // extrude along +X
    girderGeo.translate(-SEG_LEN / 2, 0, 0);
    const roadGeo = own(new THREE.BoxGeometry(SEG_LEN, 0.5, 20));
    for (const seg of segments) {
      const g = new THREE.Group();
      const girder = new THREE.Mesh(girderGeo, girderMat);
      girder.castShadow = girder.receiveShadow = true;
      const road = new THREE.Mesh(roadGeo, asphaltMat);
      road.position.y = 0.28;
      road.receiveShadow = true;
      g.add(girder, road);
      g.position.set(seg.cx, DECK_Y, 0);
      g.visible = false;
      deckGroup.add(g);
      segMeshes.push(g);
    }
  }
  scene.add(deckGroup);

  /* ── Deck furniture: rails, stripes, lamp poles ── */
  const furnitureGroup = new THREE.Group();
  const lampHeads: THREE.Mesh[] = [];
  const lampXs: number[] = [];
  {
    const postGeo = own(new THREE.BoxGeometry(0.18, 1.2, 0.18));
    const postCount = Math.floor((ABUTMENT_X * 2) / 5);
    const posts = new THREE.InstancedMesh(postGeo, railMat, postCount * 2);
    const m = new THREE.Matrix4();
    let pi = 0;
    for (let x = -ABUTMENT_X + 2.5; x < ABUTMENT_X; x += 5) {
      for (const s of [1, -1]) {
        m.makeTranslation(x, DECK_Y + 1.1, (DECK_HALF_W - 0.4) * s);
        posts.setMatrixAt(pi++, m);
      }
    }
    posts.castShadow = true;
    furnitureGroup.add(posts);
    own(postGeo);
    for (const s of [1, -1]) {
      const rail = new THREE.Mesh(own(new THREE.BoxGeometry(ABUTMENT_X * 2, 0.22, 0.22)), railMat);
      rail.position.set(0, DECK_Y + 1.7, (DECK_HALF_W - 0.4) * s);
      furnitureGroup.add(rail);
      const barrier = new THREE.Mesh(own(new THREE.BoxGeometry(ABUTMENT_X * 2, 0.9, 0.5)), concreteMat);
      barrier.position.set(0, DECK_Y + 0.72, (DECK_HALF_W - 1.3) * s);
      furnitureGroup.add(barrier);
    }
    // Center line dashes
    const dashGeo = own(new THREE.BoxGeometry(4.4, 0.06, 0.34));
    const dashMat = own(new THREE.MeshStandardMaterial({ color: 0xcfd4d8, roughness: 0.85 }));
    const dashCount = Math.floor((ABUTMENT_X * 2) / 12);
    const dashes = new THREE.InstancedMesh(dashGeo, dashMat, dashCount);
    let di = 0;
    for (let x = -ABUTMENT_X + 6; x < ABUTMENT_X - 6 && di < dashCount; x += 12) {
      m.makeTranslation(x, DECK_Y + 0.56, 0);
      dashes.setMatrixAt(di++, m);
    }
    furnitureGroup.add(dashes);
    // Lamp poles
    const poleGeo = own(new THREE.CylinderGeometry(0.16, 0.22, 7, 8));
    const headGeo = own(new THREE.SphereGeometry(0.42, 12, 8));
    for (let x = -195; x <= 195; x += 30) {
      const s = (Math.round(x / 30) % 2 === 0 ? 1 : -1);
      const pole = new THREE.Mesh(poleGeo, railMat);
      pole.position.set(x, DECK_Y + 4.2, (DECK_HALF_W - 0.9) * s);
      pole.castShadow = true;
      const head = new THREE.Mesh(headGeo, lampMat.clone());
      own(head.material as THREE.Material);
      head.position.set(x, DECK_Y + 7.8, (DECK_HALF_W - 0.9) * s - s * 1.4);
      lampHeads.push(head);
      lampXs.push(x);
      furnitureGroup.add(pole, head);
    }
  }
  furnitureGroup.visible = false;
  scene.add(furnitureGroup);

  // A couple of real point lights so the dusk deck reads lit (bloom does the rest).
  const deckLights: THREE.PointLight[] = [];
  for (const x of [-45, 15, 75]) {
    const pl = new THREE.PointLight(0xffb865, 0, 55, 1.8);
    pl.position.set(x, DECK_Y + 7, 0);
    deckLights.push(pl);
    scene.add(pl);
  }

  /* ── Stay cables (instanced) ── */
  const cableGeo = own(new THREE.CylinderGeometry(0.17, 0.17, 1, 6, 1));
  cableGeo.translate(0, -0.5, 0); // origin at top, extends -Y
  const cableMesh = new THREE.InstancedMesh(cableGeo, cableMat, cables.length);
  cableMesh.castShadow = true;
  cableMesh.count = cables.length;
  scene.add(cableMesh);

  /* ── Tower cranes ── */
  interface Crane {
    group: THREE.Group;
    jib: THREE.Group;
    baseX: number;
  }
  const cranes: Crane[] = [];
  const craneGroup = new THREE.Group();
  for (const sx of [-1, 1]) {
    const g = new THREE.Group();
    const baseX = sx * (PYLON_X + 26);
    const baseZ = -30; // far bank side - layers behind the pylons in the build shots
    const mast = new THREE.Mesh(own(new THREE.BoxGeometry(3, 116, 3)), craneLatticeMat);
    mast.position.set(baseX, 58 - 2, baseZ);
    mast.castShadow = true;
    const jib = new THREE.Group();
    const jibArm = new THREE.Mesh(own(new THREE.BoxGeometry(64, 2.4, 2.4)), craneLatticeMat);
    jibArm.position.x = 26;
    jibArm.castShadow = true;
    const counter = new THREE.Mesh(own(new THREE.BoxGeometry(18, 2.2, 2.2)), craneLatticeMat);
    counter.position.x = -13;
    const weight = new THREE.Mesh(own(new THREE.BoxGeometry(4, 3.4, 3.2)), concreteMat);
    weight.position.x = -20;
    const cab = new THREE.Mesh(own(new THREE.BoxGeometry(3.2, 3, 3)), craneMat);
    cab.position.set(2, -1.2, 0);
    jib.add(jibArm, counter, weight, cab);
    jib.position.set(baseX, 114 - 2, baseZ);
    g.add(mast, jib);
    craneGroup.add(g);
    cranes.push({ group: g, jib, baseX });
  }
  scene.add(craneGroup);

  /* ── Trees + bank lights + dust + sparks + traffic ── */
  // Distant treeline only - up close the cones read as props, at range they
  // read as forest silhouette.
  const treeGeo = own(new THREE.ConeGeometry(2.4, 7.5, 6));
  const treeCount = high ? 64 : 36;
  const trees = new THREE.InstancedMesh(treeGeo, treeMat, treeCount);
  {
    const rnd = mulberry32(2020);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const up = new THREE.Vector3(0, 1, 0);
    let placed = 0;
    let guard = 0;
    while (placed < treeCount && guard++ < 6000) {
      const x = (rnd() * 2 - 1) * 620;
      const z = (rnd() * 2 - 1) * 380;
      if (Math.abs(z) < 110 && Math.abs(x) < 240) continue; // far field only
      const h = terrainHeight(x, z);
      if (h < 10 || h > 58) continue;
      const s = 1.4 + rnd() * 1.4;
      q.setFromAxisAngle(up, rnd() * Math.PI);
      m.compose(new THREE.Vector3(x, h + 3.4 * s, z), q, new THREE.Vector3(s, s * (0.85 + rnd() * 0.5), s));
      trees.setMatrixAt(placed++, m);
    }
    trees.count = placed;
  }
  trees.castShadow = true;
  scene.add(trees);

  const dotTex = own(softDotTexture());

  function makePoints(
    count: number,
    size: number,
    color: THREE.Color | number,
    opacity: number
  ): { points: THREE.Points; mat: THREE.PointsMaterial; pos: Float32Array } {
    const geo = own(new THREE.BufferGeometry());
    const pos = new Float32Array(count * 3);
    geo.setAttribute("position", new THREE.BufferAttribute(pos, 3));
    const mat = own(new THREE.PointsMaterial({
      size,
      map: dotTex,
      transparent: true,
      opacity,
      color,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
      sizeAttenuation: true,
    }));
    const points = new THREE.Points(geo, mat);
    points.frustumCulled = false;
    return { points, mat, pos };
  }

  // Ambient dust motes
  const dustCount = high ? 850 : 380;
  const dust = makePoints(dustCount, 1.5, 0xcfd8e2, 0.0);
  {
    const rnd = mulberry32(808);
    for (let i = 0; i < dustCount; i++) {
      dust.pos[i * 3] = (rnd() * 2 - 1) * 320;
      dust.pos[i * 3 + 1] = rnd() * 90 + 2;
      dust.pos[i * 3 + 2] = (rnd() * 2 - 1) * 200;
    }
    dust.points.geometry.attributes.position.needsUpdate = true;
  }
  scene.add(dust.points);

  // Bank lights (distant settlements at night)
  const bankCount = 46;
  const bank = makePoints(bankCount, 2.6, 0xffb46b, 0.0);
  {
    const rnd = mulberry32(606);
    let i = 0;
    let guard = 0;
    while (i < bankCount && guard++ < 2000) {
      const x = (rnd() * 2 - 1) * 600;
      const z = (rnd() * 2 - 1) * 360;
      const h = terrainHeight(x, z);
      if (h < 12 || h > 70) continue;
      bank.pos[i * 3] = x;
      bank.pos[i * 3 + 1] = h + 1.8;
      bank.pos[i * 3 + 2] = z;
      i++;
    }
    bank.points.geometry.attributes.position.needsUpdate = true;
  }
  scene.add(bank.points);

  // Weld-spark bursts at every segment seat
  const SPARKS_PER = 42;
  const sparkBursts = Array.from({ length: 5 }, () => makePoints(SPARKS_PER, 2.2, 0xffc06a, 0));
  for (const sb of sparkBursts) scene.add(sb.points);
  const sparkRnd = mulberry32(1234);
  const sparkSeeds = Array.from({ length: SPARKS_PER }, () => ({
    dx: sparkRnd() * 2 - 1,
    dy: sparkRnd(),
    dz: sparkRnd() * 2 - 1,
    v: 8 + sparkRnd() * 20,
  }));

  // Hoist lines - a rising segment hangs from two lift cables so the hoist
  // reads as crane work, not levitation.
  const HOIST_MAX = 6;
  const hoistGeo = own(new THREE.BufferGeometry());
  const hoistArr = new Float32Array(HOIST_MAX * 4 * 3);
  hoistGeo.setAttribute("position", new THREE.BufferAttribute(hoistArr, 3));
  const hoistMat = own(new THREE.LineBasicMaterial({ color: 0x9aa2a8, transparent: true, opacity: 0.8 }));
  const hoistLines = new THREE.LineSegments(hoistGeo, hoistMat);
  hoistLines.frustumCulled = false;
  scene.add(hoistLines);

  // Traffic - paired head/tail lights once the bridge opens
  const TRAFFIC_N = 14;
  const traffic = makePoints(TRAFFIC_N, 4.2, 0xffffff, 0);
  const trafficDir: number[] = [];
  const trafficOff: number[] = [];
  {
    const rnd = mulberry32(3131);
    const colors = new Float32Array(TRAFFIC_N * 3);
    for (let i = 0; i < TRAFFIC_N; i++) {
      const dir = i % 2 === 0 ? 1 : -1;
      trafficDir.push(dir);
      trafficOff.push(rnd() * ABUTMENT_X * 2);
      const c = dir > 0 ? new THREE.Color(0xfff4d8) : new THREE.Color(0xff5040);
      colors[i * 3] = c.r; colors[i * 3 + 1] = c.g; colors[i * 3 + 2] = c.b;
    }
    traffic.points.geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
    traffic.mat.vertexColors = true;
    traffic.mat.color = new THREE.Color(0xffffff);
  }
  scene.add(traffic.points);

  /* ── Volumetric-ish light shafts (golden-hour only) ── */
  const shaftMat = own(new THREE.ShaderMaterial({
    uniforms: { uOpacity: { value: 0 }, uColor: { value: new THREE.Color(0xffb36a) } },
    vertexShader: BEAM_VERT,
    fragmentShader: BEAM_FRAG,
    transparent: true,
    blending: THREE.AdditiveBlending,
    depthWrite: false,
    side: THREE.DoubleSide,
    fog: false,
  }));
  const shafts: THREE.Mesh[] = [];
  for (const [sx, sz] of [[-70, -8], [-102, 10], [104, -6]] as Array<[number, number]>) {
    const shaft = new THREE.Mesh(own(new THREE.PlaneGeometry(16, 95)), shaftMat);
    shaft.position.set(sx, 50, sz);
    shaft.rotation.z = 0.32;
    shafts.push(shaft);
    scene.add(shaft);
  }

  /* ── Post-processing ── */
  // HDR composer target. NO hardware MSAA (samples: 0): a multisampled
  // HalfFloat target intermittently leaves a black rectangular tile from a
  // botched MSAA resolve on Apple Silicon / ANGLE-Metal. Edge AA is restored
  // by the SMAAPass below, which runs on a plain 8-bit buffer the bug can't
  // touch. HalfFloat stays for HDR bloom headroom.
  const size0 = renderer.getDrawingBufferSize(new THREE.Vector2());
  const composerRT = own(new THREE.WebGLRenderTarget(size0.width, size0.height, {
    type: THREE.HalfFloatType,
  }));
  const composer = new EffectComposer(renderer, composerRT);
  const renderPass = new RenderPass(scene, camera);
  composer.addPass(renderPass);
  let bokeh: BokehPass | null = null;
  if (high) {
    bokeh = new BokehPass(scene, camera, { focus: 12, aperture: 2.4e-4, maxblur: 0.009 });
    composer.addPass(bokeh);
  }
  const bloom = new UnrealBloomPass(new THREE.Vector2(384, 384), 0.5, 0.75, 0.82);
  composer.addPass(bloom);
  composer.addPass(new OutputPass());
  // Post-process AA replacing the dropped MSAA - smooths the thin azure
  // blueprint lines. Cheaper than 4× MSAA and immune to the Metal resolve bug.
  composer.addPass(new SMAAPass(size0.width, size0.height));
  const gradePass = new ShaderPass(GRADE_SHADER);
  composer.addPass(gradePass);

  /* ── HUD anchors ── */
  const HUD_WORLD: Array<{ id: string; pos: THREE.Vector3; w: [number, number] }> = [
    { id: "report", pos: new THREE.Vector3(0, DECK_Y + 4, 0), w: [0.685, 0.845] },
    { id: "rfi", pos: new THREE.Vector3(-PYLON_X, PYLON_TOP + 3, 0), w: [0.70, 0.85] },
    { id: "pour", pos: new THREE.Vector3(152, DECK_Y + 4, 0), w: [0.715, 0.845] },
    { id: "payapp", pos: new THREE.Vector3(PYLON_X, 72, 0), w: [0.73, 0.855] },
  ];
  const hud: CinematicHudPoint[] = HUD_WORLD.map((h) => ({ id: h.id, x: 50, y: 50, opacity: 0 }));

  /* ── Frame state ── */
  let elapsed = 0;
  let shakeAmp = 0;
  const prevSeated = segments.map(() => false);
  const camPos = new THREE.Vector3();
  const camLook = new THREE.Vector3();
  const sunDir = new THREE.Vector3();
  const tmpV = new THREE.Vector3();

  // Sky/mood palettes keyed by progress. Values are film-grade colors.
  const zenithKeys: Array<[number, THREE.Color]> = [
    [0.0, new THREE.Color(0x04070f)],
    [0.27, new THREE.Color(0x0a1526)],
    [0.34, new THREE.Color(0x27476e)],
    [0.46, new THREE.Color(0x2f5f9c)],
    [0.58, new THREE.Color(0x2a5490)],
    [0.66, new THREE.Color(0x18294a)],
    [0.74, new THREE.Color(0x0a1224)],
    [0.84, new THREE.Color(0x0c1526)],
    [0.92, new THREE.Color(0x5c88b8)],
    [1.0, new THREE.Color(0xa8c6e2)],
  ];
  const horizonKeys: Array<[number, THREE.Color]> = [
    [0.0, new THREE.Color(0x0b1626)],
    [0.27, new THREE.Color(0x2c2434)],
    [0.34, new THREE.Color(0xd98a4c)],
    [0.46, new THREE.Color(0xa9c6e2)],
    [0.58, new THREE.Color(0xd9a05e)],
    [0.66, new THREE.Color(0x8a4a34)],
    [0.74, new THREE.Color(0x1c1a30)],
    [0.84, new THREE.Color(0x241e36)],
    [0.92, new THREE.Color(0xffd9a0)],
    [1.0, new THREE.Color(0xf2ead9)],
  ];
  const colorTrack = (p: number, keys: Array<[number, THREE.Color]>, out: THREE.Color) => {
    if (p <= keys[0][0]) return out.copy(keys[0][1]);
    for (let i = 1; i < keys.length; i++) {
      if (p <= keys[i][0]) {
        const t = (p - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0]);
        return out.copy(keys[i - 1][1]).lerp(keys[i][1], t);
      }
    }
    return out.copy(keys[keys.length - 1][1]);
  };
  const zenithC = new THREE.Color();
  const horizonC = new THREE.Color();
  const fogC = new THREE.Color();

  function sunElevation(p: number): number {
    return track(p, [
      [0.0, -14], [0.27, -6], [0.31, 2], [0.40, 22], [0.50, 34], [0.58, 16],
      [0.645, 4], [0.68, -3], [0.74, -10], [0.84, -12], [0.885, -3], [0.93, 5], [1.0, 14],
    ]);
  }
  function sunAzimuth(p: number): number {
    // Radians around Y; the finale sun rises down-valley (−Z) behind the bridge.
    return track(p, [
      [0.0, 2.4], [0.31, 2.55], [0.50, 3.4], [0.68, 4.25], [0.84, 4.4], [0.86, 1.45], [1.0, 1.62],
    ]);
  }

  function render(progress: number, dt: number): void {
    const p = clamp01(progress);
    elapsed += dt;
    const t = elapsed;

    /* Sun + mood */
    const el = THREE.MathUtils.degToRad(sunElevation(p));
    const az = sunAzimuth(p);
    sunDir.set(Math.cos(el) * Math.cos(az), Math.sin(el), Math.cos(el) * Math.sin(az)).normalize();
    const dayness = smooth(-0.03, 0.12, sunDir.y);
    const night = 1 - dayness;
    sun.position.copy(sunDir).multiplyScalar(600);
    sun.intensity = dayness * lerp(1.6, 3.4, smooth(0.05, 0.5, sunDir.y));
    sun.color.setRGB(1, lerp(0.62, 0.95, smooth(0.02, 0.35, sunDir.y)), lerp(0.36, 0.88, smooth(0.02, 0.4, sunDir.y)));
    moon.intensity = night * 0.42;
    hemi.intensity = lerp(0.45, 1.0, dayness);
    hemi.color.setHex(0xbcd2ee).lerp(new THREE.Color(0x24344d), night);
    hemi.groundColor.setHex(0x4c4a40).lerp(new THREE.Color(0x0c0f12), night);
    scene.environmentIntensity = lerp(0.26, 0.55, dayness);

    colorTrack(p, zenithKeys, zenithC);
    colorTrack(p, horizonKeys, horizonC);
    skyUniforms.uZenith.value.copy(zenithC);
    skyUniforms.uHorizon.value.copy(horizonC);
    (skyUniforms.uHaze.value as THREE.Color).copy(horizonC).multiplyScalar(0.55);
    skyUniforms.uSunDir.value.copy(sunDir);
    skyUniforms.uStars.value = night * track(p, [[0, 1], [0.3, 0.9], [0.5, 0], [0.62, 0.4], [0.74, 1], [0.86, 0.6], [1, 0]]);
    skyUniforms.uCirrus.value = track(p, [[0, 0.1], [0.4, 0.5], [0.6, 0.4], [0.84, 0.2], [1, 0.55]]);
    skyUniforms.uSunI.value = track(p, [[0, 0], [0.29, 0.4], [0.4, 1], [0.66, 1], [0.72, 0.2], [0.84, 0], [0.9, 1.4], [1, 1.8]]);
    skyUniforms.uTime.value = t;

    const fog = scene.fog as THREE.FogExp2;
    fogC.copy(horizonC).lerp(zenithC, 0.35);
    if (p > T.dawn[0]) fogC.lerp(new THREE.Color(0xf2f3f5), smooth(T.dawn[0], 1, p) * 0.9);
    fog.color.copy(fogC);
    fog.density = track(p, [
      [0, 0.0030], [0.16, 0.0024], [0.34, 0.0012], [0.5, 0.0009], [0.62, 0.0012],
      [0.70, 0.0017], [0.80, 0.0011], [0.91, 0.0013], [1.0, 0.0036],
    ]);

    renderer.toneMappingExposure = track(p, [
      [0, 1.0], [0.34, 1.05], [0.62, 0.98], [0.70, 0.9], [0.8, 0.95], [0.9, 1.08], [0.955, 1.7], [1.0, 3.1],
    ]);

    /* Monument + grid + blueprint */
    const monumentOp = bump(0.005, 0.03, 0.16, 0.24, p);
    ringsUniforms.uOpacity.value = monumentOp;
    ringsUniforms.uTime.value = t;
    beamUniforms.uOpacity.value = monumentOp * 0.55;
    gridUniforms.uRadius.value = win(T.gridDraw, p) * 330;
    gridUniforms.uOpacity.value = 0.85 * (1 - win(T.gridFade, p));
    gridUniforms.uTime.value = t;
    gridPlane.visible = gridUniforms.uOpacity.value > 0.01 && p > T.gridDraw[0];
    rings.visible = beam.visible = beam2.visible = monumentOp > 0.01;

    const drawG = linesUniforms.uDrawG.value as number[];
    const fadeG = linesUniforms.uFadeG.value as number[];
    drawG[0] = win(T.bpPylons, p);
    drawG[1] = win(T.bpDeck, p);
    drawG[2] = win(T.bpCables, p);
    drawG[3] = win(T.bpTicks, p);
    fadeG[0] = win(T.bpFadePylons, p);
    fadeG[1] = win(T.bpFadeDeck, p);
    fadeG[2] = win(T.bpFadeCables, p);
    fadeG[3] = win(T.bpFadeTicks, p);
    const pulse = bump(T.pulses[0], T.pulses[0] + 0.03, T.pulses[1] - 0.03, T.pulses[1], p);
    linesUniforms.uPulse.value = pulse;
    linesUniforms.uTime.value = t;
    blueprint.visible = p > T.bpPylons[0] - 0.01 && (p < 0.62 || pulse > 0.01);

    /* Pylons pour */
    const pour = win(T.pierRise, p);
    const pourEased = easeOutCubic(pour);
    const topY = lerp(-2, PYLON_TOP + 2, pourEased);
    for (const clip of pylonClips) clip.constant = topY;
    pylonGroup.visible = p > T.pierRise[0] - 0.005;
    for (const collar of collars) {
      collar.position.y = Math.min(topY, PYLON_TOP - 2);
      collar.visible = pour > 0.01 && pour < 0.999;
    }

    /* Approach piers */
    for (let i = 0; i < approachPiers.length; i++) {
      const local = clamp01((win(T.approachRise, p) - i * 0.12) / 0.7);
      approachPiers[i].scale.y = Math.max(0.001, easeOutCubic(local));
    }
    pierGroup.visible = p > T.approachRise[0] - 0.005;

    /* Deck segments - hoisted from the river, eased into place */
    let seatImpulse = 0;
    let hoistCount = 0;
    deckGroup.visible = p > T.deckSeat[0] - 0.02;
    for (let i = 0; i < segments.length; i++) {
      const seg = segments[i];
      const g = segMeshes[i];
      const u = (p - seg.seatT) / 0.028;
      if (u <= 0) {
        g.visible = false;
        if (prevSeated[i]) prevSeated[i] = false;
        continue;
      }
      g.visible = true;
      const e = easeOutCubic(u);
      const rise = clamp01(e);
      g.position.y = DECK_Y - (1 - rise) * 30;
      g.rotation.z = (1 - rise) * 0.05 * (seg.fromWest ? 1 : -1);
      g.rotation.x = (1 - rise) * 0.03;
      if (u < 1 && hoistCount < HOIST_MAX) {
        const topY = g.position.y + 0.4;
        const liftY = DECK_Y + 16;
        const o = hoistCount * 12;
        hoistArr[o] = seg.cx - 5; hoistArr[o + 1] = topY; hoistArr[o + 2] = 6;
        hoistArr[o + 3] = seg.cx - 1.5; hoistArr[o + 4] = liftY; hoistArr[o + 5] = 2;
        hoistArr[o + 6] = seg.cx + 5; hoistArr[o + 7] = topY; hoistArr[o + 8] = -6;
        hoistArr[o + 9] = seg.cx + 1.5; hoistArr[o + 10] = liftY; hoistArr[o + 11] = -2;
        hoistCount++;
      }
      if (u >= 1 && !prevSeated[i]) {
        prevSeated[i] = true;
        seatImpulse = 1;
      }
      if (u < 1 && prevSeated[i]) prevSeated[i] = false;
    }
    hoistGeo.setDrawRange(0, hoistCount * 4);
    (hoistGeo.attributes.position as THREE.BufferAttribute).needsUpdate = true;
    hoistLines.visible = hoistCount > 0;
    if (seatImpulse > 0) shakeAmp = Math.min(1, shakeAmp + 0.55);
    shakeAmp *= Math.exp(-dt * 5.2);

    /* Spark bursts around each seat moment */
    let burstSlot = 0;
    for (let i = 0; i < segments.length && burstSlot < sparkBursts.length; i++) {
      const seg = segments[i];
      const u = (p - seg.seatT) / 0.016;
      if (u <= 0 || u >= 1.6) continue;
      const sb = sparkBursts[burstSlot++];
      const life = clamp01(u / 1.6);
      for (let j = 0; j < SPARKS_PER; j++) {
        const s = sparkSeeds[j];
        const fall = life * life * 26;
        sb.pos[j * 3] = seg.cx + s.dx * s.v * life;
        sb.pos[j * 3 + 1] = DECK_Y + 0.5 + s.dy * s.v * life * 0.6 - fall;
        sb.pos[j * 3 + 2] = s.dz * s.v * life * 0.7;
      }
      sb.points.geometry.attributes.position.needsUpdate = true;
      sb.mat.opacity = (1 - life) * 0.9;
      sb.points.visible = true;
    }
    for (let b = burstSlot; b < sparkBursts.length; b++) sparkBursts[b].points.visible = false;

    /* Cables */
    cableMesh.visible = p > T.cableDraw[0] - 0.01;
    if (cableMesh.visible) {
      const m = new THREE.Matrix4();
      const q = new THREE.Quaternion();
      const down = new THREE.Vector3(0, -1, 0);
      const dir = new THREE.Vector3();
      const scl = new THREE.Vector3();
      for (let i = 0; i < cables.length; i++) {
        const c = cables[i];
        const drawn = clamp01((p - c.drawT) / 0.02);
        const len = c.top.distanceTo(c.deck) * easeOutCubic(drawn);
        dir.copy(c.deck).sub(c.top).normalize();
        q.setFromUnitVectors(down, dir);
        scl.set(1, Math.max(len, 0.001), 1);
        m.compose(c.top, q, scl);
        cableMesh.setMatrixAt(i, m);
      }
      cableMesh.instanceMatrix.needsUpdate = true;
    }

    /* Furniture + lamps */
    furnitureGroup.visible = win(T.details, p) > 0.4;
    const lampsOn = win(T.lampsOn, p);
    for (let i = 0; i < lampHeads.length; i++) {
      const stagger = clamp01(lampsOn * 1.6 - (Math.abs(lampXs[i]) / 220) * 0.6);
      const flicker = stagger > 0 && stagger < 1 ? (Math.sin(t * 40 + i * 7) > -0.2 ? 1 : 0.2) : 1;
      (lampHeads[i].material as THREE.MeshStandardMaterial).emissiveIntensity =
        stagger * flicker * 5.2 * (1 - smooth(0.9, 1, p));
    }
    for (const pl of deckLights) {
      pl.intensity = lampsOn * night * 42;
    }

    /* Cranes */
    const craneIn = win(T.craneUp, p);
    const craneOut = win(T.craneOut, p);
    craneGroup.visible = craneIn > 0.01 && craneOut < 0.99;
    for (let ci = 0; ci < cranes.length; ci++) {
      const cr = cranes[ci];
      cr.group.position.y = lerp(-118, 0, easeOutCubic(craneIn));
      cr.jib.rotation.y = t * 0.05 * (ci === 0 ? 1 : -0.8) + ci * 2.1;
      cr.group.scale.setScalar(1 - craneOut * 0.001);
    }
    craneMat.opacity = 1 - craneOut;
    craneLatticeMat.opacity = 1 - craneOut;
    craneMat.transparent = craneLatticeMat.transparent = true;

    /* Dust, bank lights, traffic */
    dust.mat.opacity = track(p, [
      [0, 0.10], [0.1, 0.16], [0.3, 0.22], [0.5, 0.3], [0.62, 0.2], [0.72, 0.12], [0.86, 0.06], [1, 0.02],
    ]);
    {
      const posAttr = dust.points.geometry.attributes.position as THREE.BufferAttribute;
      const arr = posAttr.array as Float32Array;
      for (let i = 0; i < dustCount; i++) {
        arr[i * 3] += dt * 1.4;
        arr[i * 3 + 1] += Math.sin(t * 0.5 + i) * dt * 0.35;
        if (arr[i * 3] > 330) arr[i * 3] = -330;
      }
      posAttr.needsUpdate = true;
    }
    bank.mat.opacity = night * bump(0.6, 0.68, 0.9, 0.97, p) * 0.85;

    const trafficOn = bump(T.traffic[0], T.traffic[0] + 0.03, T.traffic[1] - 0.04, T.traffic[1], p);
    traffic.mat.opacity = trafficOn;
    traffic.points.visible = trafficOn > 0.01;
    if (traffic.points.visible) {
      for (let i = 0; i < TRAFFIC_N; i++) {
        const span = ABUTMENT_X * 2;
        const raw = (trafficOff[i] + t * 26) % span;
        const x = trafficDir[i] > 0 ? raw - ABUTMENT_X : ABUTMENT_X - raw;
        traffic.pos[i * 3] = x;
        traffic.pos[i * 3 + 1] = DECK_Y + 1.1;
        traffic.pos[i * 3 + 2] = 2.8 * trafficDir[i];
      }
      traffic.points.geometry.attributes.position.needsUpdate = true;
    }

    /* Light shafts at golden hour */
    const golden = smooth(0.02, 0.14, sunDir.y) * (1 - smooth(0.3, 0.5, sunDir.y));
    shaftMat.uniforms.uOpacity.value = golden * bump(0.34, 0.4, 0.6, 0.66, p) * 0.16;
    for (const s of shafts) s.visible = shaftMat.uniforms.uOpacity.value > 0.005;

    /* Camera */
    const cam = evalCamera(p, camPos, camLook);
    // Hand-held micro drift, damped near the ends
    const driftAmp = track(p, [[0, 0.25], [0.1, 0.5], [0.4, 0.9], [0.7, 0.6], [0.9, 0.3], [1, 0.05]]);
    camPos.x += Math.sin(t * 0.31) * driftAmp * 0.9;
    camPos.y += Math.sin(t * 0.23 + 1.7) * driftAmp * 0.5;
    camPos.z += Math.cos(t * 0.27 + 0.6) * driftAmp * 0.7;
    camLook.x += Math.sin(t * 0.4 + 2.4) * driftAmp * 0.5;
    camLook.y += Math.cos(t * 0.34 + 1.1) * driftAmp * 0.3;
    // Seat-impact shake
    if (shakeAmp > 0.002) {
      camPos.x += Math.sin(t * 51) * shakeAmp * 0.28;
      camPos.y += Math.cos(t * 47) * shakeAmp * 0.22;
    }
    camera.position.copy(camPos);
    camera.lookAt(camLook);
    camera.fov = cam.fov;
    camera.updateProjectionMatrix();

    if (bokeh) {
      const focusDist = camPos.distanceTo(camLook);
      (bokeh.uniforms as Record<string, THREE.IUniform>).focus.value = focusDist;
      (bokeh.uniforms as Record<string, THREE.IUniform>).aperture.value = cam.ap;
    }

    bloom.strength = track(p, [
      [0, 0.55], [0.16, 0.5], [0.34, 0.38], [0.6, 0.42], [0.7, 0.75], [0.84, 0.6], [0.93, 0.9], [1, 1.35],
    ]);

    /* Water + grade */
    waterUpdate(t, sunDir, night);
    const gu = gradePass.uniforms as Record<string, THREE.IUniform>;
    gu.uTime.value = t;
    gu.uGrain.value = high ? 0.045 : 0.03;
    gu.uVig.value = track(p, [[0, 0.5], [0.5, 0.4], [0.9, 0.42], [1, 0.2]]);
    gu.uCA.value = 0.0012 + shakeAmp * 0.002 + smooth(0.92, 1, p) * 0.004;

    /* HUD projection */
    for (let i = 0; i < HUD_WORLD.length; i++) {
      const spec = HUD_WORLD[i];
      tmpV.copy(spec.pos).project(camera);
      const behind = tmpV.z > 1;
      hud[i].x = (tmpV.x * 0.5 + 0.5) * 100;
      hud[i].y = (-tmpV.y * 0.5 + 0.5) * 100;
      hud[i].opacity = behind ? 0 : bump(spec.w[0], spec.w[0] + 0.02, spec.w[1] - 0.02, spec.w[1], p);
    }

    composer.render(dt);
  }

  function setSize(width: number, height: number, dpr: number): void {
    renderer.setPixelRatio(dpr);
    renderer.setSize(width, height, false);
    composer.setPixelRatio(dpr);
    composer.setSize(width, height);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  }

  function dispose(): void {
    scene.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (mesh.geometry) mesh.geometry.dispose();
    });
    for (const d of disposables) d.dispose();
    composer.dispose();
    renderer.dispose();
  }

  return { setSize, render, hud, dispose };
}
