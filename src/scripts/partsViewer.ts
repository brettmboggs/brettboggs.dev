// Orbit viewer for printed parts. One canvas per part, GLB in, warm studio
// light, soft shadow on the paper. Built on the three the site already ships;
// no component library. Rendering pauses when a viewer scrolls out of view.

import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';

const PAPER = 0xf4eddf;

export function mountPartViewer(canvas: HTMLCanvasElement, url: string): void {
  let renderer: THREE.WebGLRenderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
  } catch {
    canvas.replaceWith(note('This viewer needs WebGL.'));
    return;
  }
  renderer.setClearColor(PAPER, 1);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.85;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.55;

  const camera = new THREE.PerspectiveCamera(38, 1, 0.001, 50);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.enablePan = false;
  controls.autoRotate = !matchMedia('(prefers-reduced-motion: reduce)').matches;
  controls.autoRotateSpeed = 0.9;
  canvas.addEventListener('pointerdown', () => {
    controls.autoRotate = false;
  });

  // golden-hour key, cool fill; the room env carries the rest
  const key = new THREE.DirectionalLight(0xffd898, 1.7);
  key.castShadow = true;
  key.shadow.mapSize.set(1024, 1024);
  scene.add(key);
  scene.add(new THREE.DirectionalLight(0xbcc8d4, 0.5));

  new GLTFLoader().load(url, (gltf) => {
    const model = gltf.scene;
    model.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) {
        o.castShadow = true;
        o.receiveShadow = true;
      }
    });
    scene.add(model);

    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const r = Math.max(size.x, size.y, size.z) / 2;

    model.position.x -= center.x;
    model.position.z -= center.z;
    model.position.y -= box.min.y;

    controls.target.set(0, size.y / 2, 0);
    camera.position.set(r * 2.1, size.y / 2 + r * 1.1, r * 2.1);
    camera.near = r / 50;
    camera.far = r * 40;
    camera.updateProjectionMatrix();
    controls.minDistance = r * 1.3;
    controls.maxDistance = r * 6;

    key.position.set(r * 3, r * 4, r * 2);
    const s = key.shadow.camera;
    s.left = -r * 2.5;
    s.right = r * 2.5;
    s.top = r * 2.5;
    s.bottom = -r * 2.5;
    s.far = r * 12;
    key.shadow.camera.updateProjectionMatrix();

    const ground = new THREE.Mesh(
      new THREE.CircleGeometry(r * 4),
      new THREE.ShadowMaterial({ opacity: 0.22 }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);
  });

  let visible = true;
  new IntersectionObserver((entries) => {
    visible = entries[0].isIntersecting;
  }).observe(canvas);

  const resize = () => {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  };
  resize();
  new ResizeObserver(resize).observe(canvas);

  const frame = () => {
    requestAnimationFrame(frame);
    if (!visible || document.hidden) return;
    controls.update();
    renderer.render(scene, camera);
  };
  requestAnimationFrame(frame);
}

function note(text: string): HTMLElement {
  const p = document.createElement('p');
  p.className = 'empty-note';
  p.textContent = text;
  return p;
}
