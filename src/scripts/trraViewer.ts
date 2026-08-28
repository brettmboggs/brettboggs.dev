// Orbit viewer for the TRRA MacArthur model. Two Draco GLBs (job scope and the
// full rebuilt network), six meshes each, one per material system. The controls
// isolate a system rather than hiding one, because the interesting question on a
// bid render is always "show me just the wall" and never "hide the ballast".
//
// Built on the three the site already ships. Rendering is paused whenever the
// canvas is off screen or the tab is hidden.

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { DRACOLoader } from 'three/examples/jsm/loaders/DRACOLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';

const PAPER = 0xf4eddf;
const INK = 0x33291c;

/** Material key -> how it should read in the paper palette. */
const LOOK: Record<string, { color: number; metal: number; rough: number }> = {
  steel: { color: 0x4b545f, metal: 0.8, rough: 0.45 },
  concrete: { color: 0xd2c7b0, metal: 0.0, rough: 0.85 },
  panel: { color: 0xb0a38a, metal: 0.0, rough: 0.75 },
  ballast: { color: 0x877560, metal: 0.0, rough: 0.95 },
  rail: { color: 0x7d6f5f, metal: 0.65, rough: 0.35 },
  tie: { color: 0x5c462c, metal: 0.0, rough: 0.9 },
};

/** X_steel.002 -> steel */
function systemOf(name: string): string {
  const m = /^X_([a-z]+)/i.exec(name);
  return m ? m[1].toLowerCase() : 'steel';
}

export interface ViewerHandle {
  /** '' shows everything, otherwise the system key to isolate */
  isolate(key: string): void;
  /** swap between the two models */
  setModel(url: string): void;
  dispose(): void;
}

export function mountTrraViewer(
  canvas: HTMLCanvasElement,
  initialUrl: string,
  onStatus?: (text: string) => void,
): ViewerHandle | null {
  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  } catch {
    onStatus?.('This viewer needs WebGL.');
    return null;
  }
  renderer.setClearColor(PAPER, 1);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.92;
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));

  const scene = new THREE.Scene();
  scene.fog = new THREE.Fog(PAPER, 900, 3400);

  const camera = new THREE.PerspectiveCamera(34, 1, 1, 8000);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.dampingFactor = 0.07;
  controls.maxPolarAngle = Math.PI * 0.495; // never go under the ground plane
  controls.autoRotate = !matchMedia('(prefers-reduced-motion: reduce)').matches;
  controls.autoRotateSpeed = 0.35;

  // The viewer sits in the middle of a page people are reading, so it must not
  // eat a scroll. One finger scrolls past it and the wheel only zooms once the
  // model has actually been grabbed.
  controls.enableZoom = false;
  controls.touches = { ONE: THREE.TOUCH.NONE, TWO: THREE.TOUCH.DOLLY_ROTATE };
  // OrbitControls writes touch-action: none as an inline style, which beats the
  // stylesheet and swallows one-finger scrolling. Put it back afterwards.
  canvas.style.touchAction = 'pan-y';

  let touched = false;
  const take = () => {
    controls.autoRotate = false;
    controls.enableZoom = true;
    touched = true;
  };
  canvas.addEventListener('pointerdown', take);

  // Mid morning from the north east, which is the sun the renders were lit with.
  const key = new THREE.DirectionalLight(0xfff0d2, 2.0);
  key.position.set(0.6, 0.72, 0.35).multiplyScalar(1000);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xc6d4e2, 0.7);
  fill.position.set(-0.7, 0.35, -0.5).multiplyScalar(1000);
  scene.add(fill);
  scene.add(new THREE.HemisphereLight(0xdfe9f2, 0x8a7c62, 0.6));

  // Ground, and a grid on it at a round metric interval so the model carries a
  // scale rather than floating at an unknown size.
  const ground = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshBasicMaterial({ color: 0xeae0ca }),
  );
  ground.rotation.x = -Math.PI / 2;
  scene.add(ground);

  let grid: THREE.GridHelper | null = null;
  function setGrid(span: number, y: number, cx: number, cz: number): void {
    if (grid) {
      scene.remove(grid);
      grid.geometry.dispose();
      (grid.material as THREE.Material).dispose();
    }
    // round the cell to 50 / 100 / 200 / 500 m, whichever keeps it readable
    const raw = span / 24;
    const step = [25, 50, 100, 200, 500, 1000].find((s) => s >= raw) ?? 1000;
    const divisions = Math.max(4, Math.round(span / step));
    grid = new THREE.GridHelper(divisions * step, divisions, INK, INK);
    const mat = grid.material as THREE.Material;
    mat.opacity = 0.16;
    mat.transparent = true;
    mat.depthWrite = false;
    grid.position.set(cx, y, cz);
    scene.add(grid);
  }

  const draco = new DRACOLoader().setDecoderPath('/draco/');
  const loader = new GLTFLoader().setDRACOLoader(draco);

  let current: THREE.Group | null = null;
  const parts = new Map<string, THREE.Mesh>();
  const tris = new Map<string, number>();
  let isolated = '';
  let disposed = false;

  function clear(): void {
    if (!current) return;
    scene.remove(current);
    current.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh) {
        m.geometry.dispose();
        (m.material as THREE.Material).dispose();
      }
    });
    current = null;
    parts.clear();
    tris.clear();
  }

  // Low oblique, off the long axis, so the structure reads as a structure.
  const DIR = new THREE.Vector3(0.58, 0.40, 0.71).normalize();

  let fitBox = new THREE.Box3();
  let fitCentre = new THREE.Vector3();

  // How far back the camera has to sit for every corner of the box to clear the
  // frustum. A bounding sphere is far too loose here: these runs are a kilometre
  // long and a hundred metres wide, so the sphere is mostly empty air and the
  // model ends up a thread across the middle of the canvas.
  function fitDistance(): number {
    const vFov = THREE.MathUtils.degToRad(camera.fov);
    const tanV = Math.tan(vFov / 2);
    const tanH = tanV * camera.aspect;

    const up = new THREE.Vector3(0, 1, 0);
    const right = new THREE.Vector3().crossVectors(up, DIR).normalize();
    const camUp = new THREE.Vector3().crossVectors(DIR, right).normalize();

    const q = new THREE.Vector3();
    let dist = 0;
    for (let i = 0; i < 8; i++) {
      q.set(
        i & 1 ? fitBox.max.x : fitBox.min.x,
        i & 2 ? fitBox.max.y : fitBox.min.y,
        i & 4 ? fitBox.max.z : fitBox.min.z,
      ).sub(fitCentre);
      const depth = q.dot(DIR);
      dist = Math.max(dist, depth + Math.abs(q.dot(right)) / tanH);
      dist = Math.max(dist, depth + Math.abs(q.dot(camUp)) / tanV);
    }
    return dist * 1.0;
  }

  // A move from one framing to the next, run in the tick loop. Snapping the
  // camera when a system is isolated loses the visitor; 0.7 s of travel keeps
  // the part they picked connected to where it sat in the whole.
  interface Glide {
    from: THREE.Vector3;
    to: THREE.Vector3;
    fromTarget: THREE.Vector3;
    toTarget: THREE.Vector3;
    t: number;
    min: number;
    max: number;
  }
  let glide: Glide | null = null;

  function place(animate: boolean): void {
    const dist = fitDistance();
    const to = fitCentre.clone().addScaledVector(DIR, dist);
    camera.near = Math.max(dist / 5000, 0.3);
    camera.far = dist * 10;
    camera.updateProjectionMatrix();
    scene.fog = new THREE.Fog(PAPER, dist * 0.85, dist * 2.8);

    const min = dist * 0.04;
    const max = dist * 2.6;

    if (!animate) {
      // a move already running would otherwise keep lerping back to the old
      // framing after the snap, which is what a fast model swap hits
      glide = null;
      camera.position.copy(to);
      controls.target.copy(fitCentre);
      controls.minDistance = min;
      controls.maxDistance = max;
      controls.update();
      return;
    }
    // the clamps are applied at the end of the move, or they fight the lerp
    controls.minDistance = 0;
    controls.maxDistance = Infinity;
    glide = {
      from: camera.position.clone(),
      to,
      fromTarget: controls.target.clone(),
      toTarget: fitCentre.clone(),
      t: 0,
      min,
      max,
    };
  }

  /** Frame whatever is currently visible. */
  function refit(animate: boolean): void {
    if (!current) return;
    fitBox.makeEmpty();
    const one = new THREE.Box3();
    for (const mesh of parts.values()) {
      if (!mesh.visible) continue;
      fitBox.union(one.setFromObject(mesh));
    }
    if (fitBox.isEmpty()) return;
    fitBox.getCenter(fitCentre);
    place(animate);
  }

  /** The ground and its grid follow the whole model, not the isolated part. */
  function setStage(model: THREE.Object3D): void {
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    const centre = box.getCenter(new THREE.Vector3());
    const span = Math.max(size.x, size.z);
    const floor = box.min.y - span * 0.001;
    ground.scale.set(span * 14, span * 14, 1);
    ground.position.set(centre.x, floor - span * 0.0015, centre.z);
    setGrid(span * 1.6, floor, centre.x, centre.z);
  }

  function apply(animate: boolean): void {
    let shown = 0;
    for (const [k, mesh] of parts) {
      mesh.visible = !isolated || k === isolated;
      if (mesh.visible) shown += tris.get(k) ?? 0;
    }
    onStatus?.(`${Math.round(shown).toLocaleString()} triangles`);
    refit(animate);
  }

  function load(url: string): void {
    onStatus?.('Loading');
    loader.load(
      url,
      (gltf) => {
        if (disposed) return;
        clear();
        const model = gltf.scene;

        model.traverse((o) => {
          const mesh = o as THREE.Mesh;
          if (!mesh.isMesh) return;
          const sys = systemOf(mesh.name);
          const look = LOOK[sys] ?? LOOK.steel;
          mesh.material = new THREE.MeshStandardMaterial({
            color: look.color,
            metalness: look.metal,
            roughness: look.rough,
            flatShading: false,
          });
          const idx = mesh.geometry.getIndex();
          const n = (idx ? idx.count : mesh.geometry.getAttribute('position').count) / 3;
          tris.set(sys, (tris.get(sys) ?? 0) + n);
          parts.set(sys, mesh);
        });

        scene.add(model);
        current = model;
        setStage(model);
        apply(false);
      },
      undefined,
      () => onStatus?.('Model failed to load.'),
    );
  }

  load(initialUrl);

  // Size to the element, not the window.
  const resize = (): void => {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    // aspect drives the fit, so a resize reframes until the visitor takes over
    if (current && !touched) refit(false);
  };
  const ro = new ResizeObserver(resize);
  ro.observe(canvas);
  resize();

  // Only run while on screen and the tab is in front.
  let onScreen = false;
  let raf = 0;
  const tick = (): void => {
    raf = requestAnimationFrame(tick);
    if (glide) {
      glide.t = Math.min(1, glide.t + 1 / 42); // about 0.7 s
      const e = 1 - Math.pow(1 - glide.t, 3);
      camera.position.lerpVectors(glide.from, glide.to, e);
      controls.target.lerpVectors(glide.fromTarget, glide.toTarget, e);
      if (glide.t >= 1) {
        controls.minDistance = glide.min;
        controls.maxDistance = glide.max;
        glide = null;
      }
    }
    controls.update();
    renderer.render(scene, camera);
  };
  const run = (): void => {
    const want = onScreen && !document.hidden && !disposed;
    if (want && !raf) raf = requestAnimationFrame(tick);
    if (!want && raf) {
      cancelAnimationFrame(raf);
      raf = 0;
    }
  };
  const io = new IntersectionObserver(
    ([e]) => {
      onScreen = e.isIntersecting;
      run();
    },
    { rootMargin: '200px' },
  );
  io.observe(canvas);
  document.addEventListener('visibilitychange', run);

  return {
    isolate(k) {
      isolated = k;
      apply(true);
    },
    setModel(url) {
      load(url);
    },
    dispose() {
      disposed = true;
      run();
      io.disconnect();
      ro.disconnect();
      clear();
      controls.dispose();
      draco.dispose();
      renderer.dispose();
    },
  };
}
