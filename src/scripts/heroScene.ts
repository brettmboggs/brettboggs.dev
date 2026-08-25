import * as THREE from 'three';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const VERT = /* glsl */ `
attribute vec3 aGlyph;
attribute vec4 aSeed;
attribute float aAccent;
uniform float uTime;
uniform float uScroll;
uniform float uIntro;
uniform float uGlyphScale;
uniform float uPixelRatio;
uniform vec2 uMouse;
uniform vec3 uInk;
uniform vec3 uSunflower;
uniform vec3 uSienna;
uniform vec3 uOlive;
varying vec3 vColor;
varying float vAlpha;

vec3 abstractPos(vec4 s, float t) {
  float a1 = s.x * 6.2831 + t * 0.11;
  float a2 = s.y * 6.2831 + t * 0.19;
  float R = 2.5 + 0.4 * sin(t * 0.21 + s.z * 6.2831);
  float r = 0.95 + 0.4 * sin(t * 0.27 + s.w * 6.2831);
  vec3 p = vec3(
    (R + r * cos(a2)) * cos(a1),
    (R + r * cos(a2)) * sin(a1) * 0.62,
    r * sin(a2)
  );
  float c = cos(t * 0.08);
  float si = sin(t * 0.08);
  p = vec3(p.x, p.y * c - p.z * si, p.y * si + p.z * c);
  return p;
}

void main() {
  float t = uTime;

  vec3 scatter = normalize(aSeed.xyz - 0.5) * (5.0 + aSeed.w * 7.0);

  float ik = clamp((uIntro - aSeed.w * 0.3) / 0.7, 0.0, 1.0);
  ik = ik * ik * (3.0 - 2.0 * ik);

  vec3 namePos = aGlyph * uGlyphScale;
  namePos.x += sin(t * 0.7 + aSeed.x * 6.2831) * 0.018;
  namePos.y += cos(t * 0.6 + aSeed.y * 6.2831) * 0.018;

  vec2 d = namePos.xy - uMouse;
  float dist = length(d);
  namePos.xy += normalize(d + 0.0001) * smoothstep(1.1, 0.0, dist) * 0.38;

  vec3 A = mix(scatter, namePos, ik);
  vec3 B = abstractPos(aSeed, t);

  float sk = clamp((uScroll - aSeed.z * 0.35) / 0.6, 0.0, 1.0);
  sk = sk * sk * (3.0 - 2.0 * sk);

  vec3 p = mix(A, B, sk);

  vec4 mv = modelViewMatrix * vec4(p, 1.0);
  gl_Position = projectionMatrix * mv;

  float size = mix(mix(1.8, 2.4, aSeed.x), 3.3, sk);
  gl_PointSize = size * uPixelRatio * (10.0 / -mv.z);

  vec3 nameCol = mix(uInk, uSunflower, aAccent);
  vec3 pal = mix(
    mix(uSunflower, uSienna, step(0.33, aSeed.y)),
    uOlive,
    step(0.66, aSeed.y)
  );
  vColor = mix(nameCol, pal, sk);
  vAlpha = mix(0.35, 0.96, ik) * mix(1.0, 0.88, sk);
}
`;

const FRAG = /* glsl */ `
precision mediump float;
varying vec3 vColor;
varying float vAlpha;

void main() {
  vec2 uv = gl_PointCoord - 0.5;
  float d = length(uv);
  float a = smoothstep(0.5, 0.22, d) * vAlpha;
  if (a < 0.02) discard;
  gl_FragColor = vec4(vColor, a);
}
`;

interface Sampled {
  glyph: Float32Array;
  accent: Float32Array;
}

function sampleName(count: number): Sampled {
  const W = 1200;
  const H = 660;
  const canvas = document.createElement('canvas');
  canvas.width = W;
  canvas.height = H;
  const ctx = canvas.getContext('2d', { willReadFrequently: true })!;

  ctx.textBaseline = 'alphabetic';
  ctx.fillStyle = '#000';
  ctx.font = '600 250px "Fraunces Variable", Georgia, serif';
  ctx.fillText('Brett', 30, 265);
  ctx.font = 'italic 600 250px "Fraunces Variable", Georgia, serif';
  ctx.fillText('Boggs', 30, 570);
  const boggsWidth = ctx.measureText('Boggs').width;
  ctx.fillStyle = '#f00';
  ctx.fillText('.', 30 + boggsWidth, 570);

  const data = ctx.getImageData(0, 0, W, H).data;
  const pts: number[] = [];
  const accents: number[] = [];
  for (let y = 0; y < H; y += 2) {
    for (let x = 0; x < W; x += 2) {
      const i = (y * W + x) * 4;
      if (data[i + 3] > 128) {
        pts.push(x, y);
        accents.push(data[i] > 128 ? 1 : 0);
      }
    }
  }

  const n = pts.length / 2;
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  for (let i = 0; i < n; i++) {
    const x = pts[i * 2], y = pts[i * 2 + 1];
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }
  const cx = (minX + maxX) / 2;
  const cy = (minY + maxY) / 2;
  const span = maxX - minX; // normalize so the block is 1 unit wide

  const glyph = new Float32Array(count * 3);
  const accent = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const j = Math.floor(Math.random() * n);
    glyph[i * 3] = (pts[j * 2] - cx + (Math.random() - 0.5) * 2) / span;
    glyph[i * 3 + 1] = -(pts[j * 2 + 1] - cy + (Math.random() - 0.5) * 2) / span;
    glyph[i * 3 + 2] = (Math.random() - 0.5) * 0.012;
    accent[i] = accents[j];
  }
  return { glyph, accent };
}

export async function initHeroScene(hero: HTMLElement): Promise<void> {
  const coarse = window.matchMedia('(pointer: coarse)').matches;
  const small = window.innerWidth < 768;
  const COUNT = small ? 9000 : 22000;

  try {
    await Promise.all([
      document.fonts.load('600 250px "Fraunces Variable"'),
      document.fonts.load('italic 600 250px "Fraunces Variable"'),
    ]);
  } catch {
    /* sample with fallback serif if the face is unavailable */
  }

  const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: false, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, small ? 1.5 : 2));
  renderer.domElement.className = 'hero-canvas';
  hero.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 60);
  camera.position.z = 13;

  const { glyph, accent } = sampleName(COUNT);
  const seeds = new Float32Array(COUNT * 4);
  for (let i = 0; i < seeds.length; i++) seeds[i] = Math.random();

  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(COUNT * 3), 3));
  geo.setAttribute('aGlyph', new THREE.BufferAttribute(glyph, 3));
  geo.setAttribute('aSeed', new THREE.BufferAttribute(seeds, 4));
  geo.setAttribute('aAccent', new THREE.BufferAttribute(accent, 1));
  geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(), 30);

  const uniforms = {
    uTime: { value: 0 },
    uScroll: { value: 0 },
    uIntro: { value: 0 },
    uGlyphScale: { value: 9 },
    uPixelRatio: { value: renderer.getPixelRatio() },
    uMouse: { value: new THREE.Vector2(1e5, 1e5) },
    uInk: { value: new THREE.Color('#33291C') },
    uSunflower: { value: new THREE.Color('#D9971E') },
    uSienna: { value: new THREE.Color('#B85C38') },
    uOlive: { value: new THREE.Color('#6F7D4E') },
  };

  const mat = new THREE.ShaderMaterial({
    vertexShader: VERT,
    fragmentShader: FRAG,
    uniforms,
    transparent: true,
    depthWrite: false,
  });
  scene.add(new THREE.Points(geo, mat));

  let worldW = 1;
  let worldH = 1;
  function resize() {
    const w = hero.clientWidth;
    const h = hero.clientHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    worldH = 2 * camera.position.z * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    worldW = worldH * camera.aspect;
    uniforms.uGlyphScale.value = worldW * (small ? 0.92 : 0.8);
  }
  resize();
  window.addEventListener('resize', resize);

  if (!coarse) {
    const target = new THREE.Vector2(1e5, 1e5);
    hero.addEventListener('mousemove', (e) => {
      const r = hero.getBoundingClientRect();
      target.set(
        ((e.clientX - r.left) / r.width - 0.5) * worldW,
        -((e.clientY - r.top) / r.height - 0.5) * worldH,
      );
    });
    hero.addEventListener('mouseleave', () => target.set(1e5, 1e5));
    gsap.ticker.add(() => {
      uniforms.uMouse.value.lerp(target, 0.08);
    });
  }

  gsap.to(uniforms.uIntro, { value: 1, duration: 2.4, ease: 'power2.out', delay: 0.25 });

  ScrollTrigger.create({
    trigger: hero,
    start: 'top top',
    end: '+=130%',
    pin: true,
    scrub: 0.6,
    onUpdate: (self) => {
      uniforms.uScroll.value = self.progress;
    },
  });

  let visible = true;
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
  }).observe(hero);

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    if (!visible || document.hidden) return;
    uniforms.uTime.value = clock.getElapsedTime();
    renderer.render(scene, camera);
  });
}
