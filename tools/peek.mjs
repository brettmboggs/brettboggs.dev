// Makes the stills the index rows show on hover: public/peek/<id>.webp, all
// 720x480, all cropped to cover, and the plates the spread layout shows while
// an index is short: public/peek/<id>-lg.webp at 1200x800. Some come from pictures already in the repo;
// the rest are captured from a local preview with headless Chrome driven over
// the DevTools protocol, so a film that only exists at a scroll position can be
// scrolled to it before the frame is taken.
//
//   npm run build && npx astro preview     (in another terminal)
//   node tools/peek.mjs [--base http://localhost:4321] [--only bridge,keepsake]
//
// Assets are committed; this is a one-off tool, not part of the build.
import { spawn } from 'node:child_process';
import { mkdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import sharp from 'sharp';

const arg = (name) => (process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : null);
const base = arg('--base') ?? 'http://localhost:4321';
const only = arg('--only')?.split(',') ?? null;
// try a different scroll position for the targets of --only without editing the table
const scrollOverride = arg('--scroll') ? Number(arg('--scroll')) : null;

const CHROME = [
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
];

const OUT = path.resolve('public/peek');
const W = 720;
const H = 480;

// file: crop an existing picture. url: capture a page (scrolled to `scroll` if
// given), then cut a 3:2 window `top` pixels down from a 1440-wide render;
// `left` and `width` narrow the window, otherwise it is the middle 1200px.
const shots = {
  // the mark alone on Datum's ink: the render reads soft at plate size
  datum: { mark: 'tools/datum-mark-cream.png', bg: '#1e2022', size: 0.36 },
  photography: { file: 'public/photo/ked/flare.webp' },
  eclipse: { file: 'public/photo/eclipse/plane-transit-760.webp' },
  'live-music': { file: 'public/photo/stone-sugar/f02.webp' },
  commercial: { file: 'public/photo/ked/estate.webp' },
  product: { file: 'public/photo/product/hero.webp' },
  trra: { file: 'public/lab/trra/hero-1200.webp' },
  ridge: { file: 'public/lab/ridge/still.webp' },
  field: { url: '/lab/field/', top: 300 },
  keepsake: { url: '/lab/keepsake/', top: 290, left: 312, width: 800 },
  'sprout-siege': { url: '/lab/sprout-siege/', top: 80 },
  underground: { url: '/lab/underground/', top: 420 },
  bridge: { url: '/lab/bridge/', top: 250, scroll: 3400 },
  'drafting-film': { url: '/lab/drafting-film/', top: 250, scroll: 8000 },
};

async function chrome() {
  for (const c of CHROME) {
    try {
      await readFile(c);
      return c;
    } catch {
      /* try the next */
    }
  }
  throw new Error('no Chrome or Edge found for captures');
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// a headless Chrome and one DevTools session on its first tab
async function openBrowser() {
  const bin = await chrome();
  const port = 9333;
  const profile = path.join(tmpdir(), `peek-chrome-${process.pid}`);
  const proc = spawn(
    bin,
    [
      '--headless=new',
      '--hide-scrollbars',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
      '--window-size=1440,1400',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${profile}`,
      'about:blank',
    ],
    { stdio: 'ignore' },
  );
  let page = null;
  for (let i = 0; i < 50 && !page; i++) {
    await sleep(200);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
      page = list.find((t) => t.type === 'page');
    } catch {
      /* not up yet */
    }
  }
  if (!page) throw new Error('Chrome did not come up');
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((res, rej) => {
    ws.onopen = res;
    ws.onerror = rej;
  });
  let id = 0;
  const waiting = new Map();
  const events = [];
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    if (msg.id && waiting.has(msg.id)) {
      const { res, rej } = waiting.get(msg.id);
      waiting.delete(msg.id);
      msg.error ? rej(new Error(msg.error.message)) : res(msg.result);
    } else if (msg.method) {
      events.forEach((fn) => fn(msg));
    }
  };
  const send = (method, params = {}) =>
    new Promise((res, rej) => {
      waiting.set(++id, { res, rej });
      ws.send(JSON.stringify({ id, method, params }));
    });
  const once = (method) =>
    new Promise((res) => {
      const fn = (msg) => {
        if (msg.method === method) {
          events.splice(events.indexOf(fn), 1);
          res(msg.params);
        }
      };
      events.push(fn);
    });
  await send('Page.enable');
  await send('Runtime.enable');
  const close = async () => {
    ws.close();
    proc.kill();
    await sleep(300);
    await rm(profile, { recursive: true, force: true });
  };
  return { send, once, close };
}

async function capture(browser, url, scroll) {
  const loaded = browser.once('Page.loadEventFired');
  await browser.send('Page.navigate', { url });
  await loaded;
  await sleep(2500);
  if (scroll) {
    // scrub films follow the scroll with easing, so give them a moment to arrive
    await browser.send('Runtime.evaluate', { expression: `window.scrollTo(0, ${scroll})` });
    await sleep(2500);
  }
  const shot = await browser.send('Page.captureScreenshot', { format: 'png' });
  return Buffer.from(shot.data, 'base64');
}

await mkdir(OUT, { recursive: true });
let browser = null;

for (const [id, shot] of Object.entries(shots)) {
  if (only && !only.includes(id)) continue;
  const out = path.join(OUT, `${id}.webp`);
  const large = path.join(OUT, `${id}-lg.webp`);
  if (shot.mark) {
    // a logo set on a flat ground, at both sizes
    for (const [w, h, file] of [[W, H, out], [W * 2, H * 2, large]]) {
      const mark = await sharp(path.resolve(shot.mark)).resize({ height: Math.round(h * shot.size) }).toBuffer();
      await sharp({ create: { width: w, height: h, channels: 3, background: shot.bg } })
        .composite([{ input: mark, gravity: 'centre' }])
        .webp({ quality: 82 })
        .toFile(file);
    }
    console.log(`peek: ${id} from ${shot.mark}`);
    continue;
  }
  if (shot.file) {
    const src = sharp(path.resolve(shot.file));
    await src.clone().resize(W, H, { fit: 'cover', position: 'attention' }).webp({ quality: 78 }).toFile(out);
    await src.clone().resize(W * 2, H * 2, { fit: 'cover', position: 'attention' }).webp({ quality: 80 }).toFile(large);
    console.log(`peek: ${id} from ${shot.file}`);
    continue;
  }
  browser ??= await openBrowser();
  const png = await capture(browser, `${base}${shot.url}`, scrollOverride ?? shot.scroll);
  const width = shot.width ?? 1200;
  const cut = sharp(png).extract({ left: shot.left ?? 120, top: shot.top, width, height: Math.round((width * 2) / 3) });
  await cut.clone().resize(W, H).webp({ quality: 78 }).toFile(out);
  await cut.clone().resize(W * 2, H * 2, { withoutEnlargement: true }).webp({ quality: 80 }).toFile(large);
  console.log(`peek: ${id} captured from ${shot.url}${shot.scroll ? ` at ${shot.scroll}px` : ''}`);
}

if (browser) await browser.close();
