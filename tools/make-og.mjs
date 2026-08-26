// Builds the social preview card. Run: node tools/make-og.mjs
//
// Composited with sharp from font outlines rather than screenshotted out of a
// browser, so it is deterministic and needs no runtime. The layout echoes the
// page it stands for: paper, a 2px rule, the wordmark set the way the header
// sets it, and the ridge left along the bottom the way the site leaves it.
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import sharp from 'sharp';
import { pathData, setRun } from './glyph-path.mjs';

const require = createRequire(import.meta.url);
const opentype = require('opentype.js');

const W = 1200;
const H = 630;
const PAD = 78;
const PAPER = '#F4EDDF';
const INK = '#33291C';
const INK_SOFT = '#6B5D48';
const SUNFLOWER = '#D9971E';
const RUST = '#8F3F22';

const toArrayBuffer = (b) => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
const parse = (p) => opentype.parse(toArrayBuffer(readFileSync(p)));

const fraunces = parse('node_modules/@fontsource/fraunces/files/fraunces-latin-600-normal.woff');
const frauncesIt = parse('node_modules/@fontsource/fraunces/files/fraunces-latin-600-italic.woff');
const mono = parse(
  'node_modules/@fontsource/spline-sans-mono/files/spline-sans-mono-latin-500-normal.woff',
);

const paint = (run, fill) =>
  run.glyphs.map((g) => `<path fill="${fill}" d="${pathData(g.path)}"/>`).join('');

// the wordmark, set the way the header sets it: no space between the names,
// italic second B, sunflower period, tight display tracking
const NAME_SIZE = 104;
const NAME_TRACK = -0.04;
const NAME_Y = 322;
let x = PAD;
const brett = setRun(fraunces, 'Brett', x, NAME_Y, NAME_SIZE, NAME_TRACK);
x += brett.width + NAME_TRACK * NAME_SIZE;
const bigB = setRun(frauncesIt, 'B', x, NAME_Y, NAME_SIZE, NAME_TRACK);
x += bigB.width + NAME_TRACK * NAME_SIZE;
const oggs = setRun(fraunces, 'oggs', x, NAME_Y, NAME_SIZE, NAME_TRACK);
x += oggs.width + NAME_TRACK * NAME_SIZE;
const dot = setRun(fraunces, '.', x, NAME_Y, NAME_SIZE, NAME_TRACK);

const eyebrow = setRun(mono, 'BRETTBOGGS.DEV', PAD, 196, 23, 0.18);
const lede = setRun(fraunces, 'Work and experiments.', PAD, 402, 38);

// transparent: the ridge composited underneath has to show through
const card = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  ${paint(eyebrow, RUST)}
  <rect x="${PAD}" y="238" width="${W - PAD * 2}" height="2" fill="${INK}"/>
  ${paint(brett, INK)}${paint(bigB, INK)}${paint(oggs, INK)}${paint(dot, SUNFLOWER)}
  ${paint(lede, INK_SOFT)}
</svg>`;

// the ridge along the bottom. sharp's composite has no opacity option, so the
// density is baked into the gradient that masks it.
const RIDGE_H = Math.round(H * 0.62);
const PEAK = 0.3;
const ridge = await sharp('public/film/poster-end.webp')
  .resize(W, RIDGE_H, { position: 'bottom' })
  .toBuffer();

const veil = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${RIDGE_H}"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0"/><stop offset="0.46" stop-color="#fff" stop-opacity="${PEAK * 0.4}"/><stop offset="0.88" stop-color="#fff" stop-opacity="${PEAK}"/></linearGradient></defs><rect width="${W}" height="${RIDGE_H}" fill="url(#g)"/></svg>`,
);

const ridgeMasked = await sharp(ridge)
  .composite([{ input: veil, blend: 'dest-in' }])
  .png()
  .toBuffer();

await sharp({ create: { width: W, height: H, channels: 4, background: PAPER } })
  .composite([
    { input: ridgeMasked, top: H - RIDGE_H, left: 0 },
    { input: Buffer.from(card), top: 0, left: 0 },
  ])
  .png({ compressionLevel: 9 })
  .toFile('public/og.png');

console.log('og card written');
