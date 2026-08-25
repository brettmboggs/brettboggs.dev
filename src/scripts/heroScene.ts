import * as THREE from 'three';
import { FontLoader, type Font } from 'three/examples/jsm/loaders/FontLoader.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import regularData from '../assets/fraunces-600.typeface.json';
import italicData from '../assets/fraunces-600-italic.typeface.json';

gsap.registerPlugin(ScrollTrigger);

const BRONZE = new THREE.Color('#45331f');
const GOLD = new THREE.Color('#D9971E');
const COPPER = new THREE.Color('#B85C38');
const OLIVE_METAL = new THREE.Color('#6F7D4E');
const MOLTEN = new THREE.Color('#8F3F22');
const PALETTE = [GOLD, COPPER, OLIVE_METAL];

interface Letter {
  mesh: THREE.Mesh<THREE.ExtrudeGeometry, THREE.MeshPhysicalMaterial>;
  base: THREE.Vector3;
  baseColor: THREE.Color;
  morphColor: THREE.Color;
  seed: number;
  orbitAngle: number;
  orbitRadius: number;
  orbitY: number;
  spinAxis: THREE.Vector3;
  spinSpeed: number;
  stagger: number;
}

function buildLine(
  font: Font,
  data: { glyphs: Record<string, { ha: number }>; kern?: Record<string, number>; resolution: number },
  text: string,
  small: boolean,
): { group: THREE.Group; letters: Letter[]; width: number } {
  const SIZE = 1;
  const scale = SIZE / data.resolution;
  const group = new THREE.Group();
  const letters: Letter[] = [];
  let pen = 0;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (i > 0 && data.kern) pen += (data.kern[text[i - 1] + ch] ?? 0) * scale;

    const shapes = font.generateShapes(ch, SIZE);
    const geo = new THREE.ExtrudeGeometry(shapes, {
      depth: 0.11,
      bevelEnabled: true,
      bevelThickness: 0.016,
      bevelSize: 0.012,
      bevelSegments: 3,
      curveSegments: small ? 7 : 11,
    });
    geo.computeBoundingBox();

    const isDot = ch === '.';
    const baseColor = isDot ? GOLD.clone() : BRONZE.clone();
    const morphColor = isDot
      ? GOLD.clone()
      : PALETTE[Math.floor(Math.random() * PALETTE.length)].clone();

    const mat = new THREE.MeshPhysicalMaterial({
      color: baseColor.clone(),
      metalness: 1.0,
      roughness: isDot ? 0.22 : 0.32,
      clearcoat: 0.35,
      clearcoatRoughness: 0.25,
      flatShading: true,
      transparent: true,
      opacity: 0,
    });
    mat.userData.baseRoughness = mat.roughness;

    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.x = pen;
    group.add(mesh);

    letters.push({
      mesh,
      base: new THREE.Vector3(pen, 0, 0),
      baseColor,
      morphColor,
      seed: Math.random(),
      orbitAngle: Math.random() * Math.PI * 2,
      orbitRadius: 1.2 + Math.random() * 1.0,
      orbitY: (Math.random() - 0.5) * 1.8,
      spinAxis: new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize(),
      spinSpeed: 0.08 + Math.random() * 0.18,
      stagger: Math.random(),
    });

    pen += data.glyphs[ch].ha * scale;
  }

  return { group, letters, width: pen };
}

export async function initHeroScene(hero: HTMLElement): Promise<void> {
  const coarse = window.matchMedia('(pointer: coarse)').matches;
  const small = window.innerWidth < 768;

  const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, small ? 1.5 : 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.1;
  renderer.domElement.className = 'hero-canvas';
  hero.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(35, 1, 0.1, 60);
  camera.position.z = 13;

  // studio environment: this is what makes metal read as metal
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.85;

  scene.add(new THREE.HemisphereLight(0xf7f0e2, 0x8a6f4d, 0.45));
  const sun = new THREE.DirectionalLight(0xffe3b0, 1.2);
  sun.position.set(-4, 6, 8);
  scene.add(sun);
  const rim = new THREE.DirectionalLight(0xb85c38, 0.7);
  rim.position.set(5, -3, -6);
  scene.add(rim);

  // soft contact shadow beneath the name
  const shadowCanvas = document.createElement('canvas');
  shadowCanvas.width = shadowCanvas.height = 256;
  const sctx = shadowCanvas.getContext('2d')!;
  const grad = sctx.createRadialGradient(128, 128, 10, 128, 128, 128);
  grad.addColorStop(0, 'rgba(51, 41, 28, 0.30)');
  grad.addColorStop(1, 'rgba(51, 41, 28, 0)');
  sctx.fillStyle = grad;
  sctx.fillRect(0, 0, 256, 256);
  const shadowMat = new THREE.MeshBasicMaterial({
    map: new THREE.CanvasTexture(shadowCanvas),
    transparent: true,
    depthWrite: false,
    opacity: 0,
  });
  const shadow = new THREE.Mesh(new THREE.PlaneGeometry(9.5, 2.2), shadowMat);
  shadow.position.set(0, -2.35, -0.6);
  scene.add(shadow);

  const loader = new FontLoader();
  const regular = loader.parse(regularData as never);
  const italic = loader.parse(italicData as never);

  const root = new THREE.Group();
  scene.add(root);

  const line1 = buildLine(regular, regularData as never, 'Brett', small);
  const line2 = buildLine(italic, italicData as never, 'Boggs.', small);
  const LEADING = 1.05;
  line1.group.position.y = LEADING / 2 + 0.12;
  line2.group.position.y = -LEADING / 2 - 0.35;
  for (const l of line2.letters) l.base.y = line2.group.position.y;
  for (const l of line1.letters) l.base.y = line1.group.position.y;
  // reparent letters into root so every letter shares one coordinate space
  for (const line of [line1, line2]) {
    for (const l of line.letters) {
      l.mesh.position.y = l.base.y;
      root.add(l.mesh);
    }
  }
  const letters = [...line1.letters, ...line2.letters];
  const blockWidth = Math.max(line1.width, line2.width);
  for (const l of letters) {
    l.base.x -= blockWidth / 2;
    l.mesh.position.x = l.base.x;
  }

  // shared shader uniforms for the melt displacement
  const uMorph = { value: 0 };
  const uTime = { value: 0 };
  for (const l of letters) {
    const uSeed = { value: l.seed * 6.2831 };
    l.mesh.material.onBeforeCompile = (shader) => {
      shader.uniforms.uMorph = uMorph;
      shader.uniforms.uTime = uTime;
      shader.uniforms.uSeed = uSeed;
      shader.vertexShader = `
uniform float uMorph;
uniform float uTime;
uniform float uSeed;
${shader.vertexShader}`.replace(
        '#include <begin_vertex>',
        `
vec3 mPos = position;
float mAmp = uMorph;
float n1 = sin(mPos.x * 1.4 + uTime * 0.7 + uSeed) * sin(mPos.y * 1.7 + uTime * 0.55 + uSeed * 1.7);
float n2 = sin(mPos.y * 1.1 + uTime * 0.4 + uSeed * 2.3) * sin(mPos.z * 2.2 + uTime * 0.6);
mPos += normal * (n1 + n2 * 0.6) * mAmp * 0.3;
mPos.x += sin(mPos.y * 1.8 + uTime * 0.35 + uSeed) * mAmp * 0.25;
mPos.y += sin(mPos.x * 1.4 + uTime * 0.3 + uSeed * 3.1) * mAmp * 0.22;
vec3 transformed = mPos;`,
      );
    };
  }

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
    const fit = Math.min((worldW * (small ? 0.9 : 0.78)) / blockWidth, (worldH * 0.72) / (LEADING + 1.6));
    root.scale.setScalar(fit);
  }
  resize();
  window.addEventListener('resize', resize);

  // mouse tilt (desktop only)
  const tilt = new THREE.Vector2();
  if (!coarse) {
    hero.addEventListener('mousemove', (e) => {
      const r = hero.getBoundingClientRect();
      tilt.set(((e.clientX - r.left) / r.width - 0.5) * 2, ((e.clientY - r.top) / r.height - 0.5) * 2);
    });
    hero.addEventListener('mouseleave', () => tilt.set(0, 0));
  }

  // entrance: letters rise and settle
  let introDone = false;
  letters.forEach((l, i) => {
    const delay = 0.25 + i * 0.055;
    gsap.fromTo(
      l.mesh.position,
      { y: l.base.y - 1.1 },
      { y: l.base.y, duration: 1.15, ease: 'power4.out', delay },
    );
    gsap.fromTo(
      l.mesh.rotation,
      { x: -0.55 },
      { x: 0, duration: 1.15, ease: 'power4.out', delay },
    );
    gsap.to(l.mesh.material, {
      opacity: 1,
      duration: 0.5,
      ease: 'power2.out',
      delay,
      onComplete: () => {
        l.mesh.material.transparent = false;
      },
    });
  });
  const shadowIntro = { value: 0 };
  gsap.to(shadowIntro, { value: 1, duration: 1.4, ease: 'power2.out', delay: 1.0 });
  gsap.delayedCall(0.25 + letters.length * 0.055 + 1.2, () => {
    introDone = true;
  });
  function finishIntroEarly() {
    if (introDone) return;
    for (const l of letters) {
      gsap.killTweensOf(l.mesh.position);
      gsap.killTweensOf(l.mesh.rotation);
      gsap.killTweensOf(l.mesh.material);
      l.mesh.material.opacity = 1;
      l.mesh.material.transparent = false;
    }
    shadowIntro.value = 1;
    introDone = true;
  }

  // scroll: melt and drift into an abstract orbiting mass
  const scrollState = { p: 0 };
  ScrollTrigger.create({
    trigger: hero,
    start: 'top top',
    end: '+=130%',
    pin: true,
    scrub: 0.6,
    onUpdate: (self) => {
      scrollState.p = self.progress;
    },
  });

  let visible = true;
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
  }).observe(hero);

  const ease = (x: number) => x * x * (3 - 2 * x);
  const clock = new THREE.Clock();
  const tmpColor = new THREE.Color();
  const tmpQuat = new THREE.Quaternion();

  renderer.setAnimationLoop(() => {
    if (!visible || document.hidden) return;
    const t = clock.getElapsedTime();
    uTime.value = t;

    const p = scrollState.p;
    uMorph.value = ease(Math.min(p * 1.35, 1));
    if (p > 0.02) finishIntroEarly();

    for (const l of letters) {
      const k = ease(THREE.MathUtils.clamp((p - l.stagger * 0.25) / 0.7, 0, 1));

      tmpColor.copy(l.baseColor).lerp(l.morphColor, k);
      l.mesh.material.color.copy(tmpColor);
      l.mesh.material.emissive.copy(MOLTEN).multiplyScalar(k * 0.28);
      l.mesh.material.roughness = THREE.MathUtils.lerp(l.mesh.material.userData.baseRoughness ?? 0.32, 0.45, k);

      if (!introDone) continue; // the entrance tweens own the transforms

      if (k === 0) {
        // idle breathing while the name is intact
        l.mesh.position.set(l.base.x, l.base.y + Math.sin(t * 0.6 + l.seed * 6.2831) * 0.035, l.base.z);
        l.mesh.rotation.set(0, Math.sin(t * 0.3 + l.seed * 3) * 0.03, 0);
      } else {
        const ang = l.orbitAngle + t * 0.12;
        const breathe = 1 + Math.sin(t * 0.4 + l.seed * 6.2831) * 0.12;
        const ax = Math.cos(ang) * l.orbitRadius * breathe;
        const ay = l.orbitY * breathe + Math.sin(t * 0.5 + l.seed * 9) * 0.15;
        const az = Math.sin(ang) * l.orbitRadius * breathe * 0.6;
        l.mesh.position.set(
          THREE.MathUtils.lerp(l.base.x, ax, k),
          THREE.MathUtils.lerp(l.base.y, ay, k),
          THREE.MathUtils.lerp(l.base.z, az, k),
        );
        tmpQuat.setFromAxisAngle(l.spinAxis, t * l.spinSpeed * k + k * l.seed * 4);
        l.mesh.quaternion.copy(tmpQuat);
      }
    }

    // mouse tilt + slow ambient sway; key light follows so reflections travel
    const targetY = tilt.x * 0.14 + Math.sin(t * 0.2) * 0.02;
    const targetX = -tilt.y * 0.09 + Math.sin(t * 0.17) * 0.015;
    root.rotation.y += (targetY - root.rotation.y) * 0.06;
    root.rotation.x += (targetX - root.rotation.x) * 0.06;
    sun.position.x += (-4 + tilt.x * 5 - sun.position.x) * 0.05;
    sun.position.y += (6 - tilt.y * 3 - sun.position.y) * 0.05;

    shadowMat.opacity = shadowIntro.value * (1 - ease(Math.min(p * 1.5, 1)));

    renderer.render(scene, camera);
  });
}
