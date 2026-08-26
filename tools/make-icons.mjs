// Builds the favicon / app-icon set from the header wordmark.
// Run: node tools/make-icons.mjs
//
// The mark is the collapsed wordmark: roman B, italic B, sunflower period.
// Letterforms are baked to outlines so nothing depends on Fraunces loading.
//
// It sits on a solid espresso tile rather than being drawn transparent. A
// transparent mark has to commit to one ink colour, and whichever it picks
// disappears against half the tab strips in the world: paper letters vanish on
// Chrome's light tabs, ink letters vanish on a dark theme. A tile carries its
// own contrast everywhere and reads as the site's paper-on-ink pairing.
//
// Tracking is set per size rather than once. The header's -0.04em is right at
// display sizes and welds the two B's into one blob at 16px, so small renders
// open the letterspacing up and give back the counters. Fraunces is an optical
// -size family; this is the same idea applied to the mark.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import sharp from 'sharp';
import { pathData } from './glyph-path.mjs';

const require = createRequire(import.meta.url);
const opentype = require('opentype.js');

const INK = '#33291C';
const PAPER = '#F4EDDF';
const SUNFLOWER = '#D9971E';
const UPEM = 2000;

const toArrayBuffer = (b) => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
const load = (style) =>
  opentype.parse(
    toArrayBuffer(
      readFileSync(`node_modules/@fontsource/fraunces/files/fraunces-latin-600-${style}.woff`),
    ),
  );

const roman = load('normal');
const italic = load('italic');

const MARK = [
  { font: roman, ch: 'B', fill: PAPER },
  { font: italic, ch: 'B', fill: PAPER },
  { font: roman, ch: '.', fill: SUNFLOWER },
];

// `inset` is the share of the tile kept as margin, `track` the letterspacing in em
function svg(size, { inset, track }) {
  let x = 0;
  const pieces = MARK.map((piece) => {
    const path = piece.font.getPath(piece.ch, x, 0, UPEM);
    x += piece.font.charToGlyph(piece.ch).advanceWidth + track * UPEM;
    return { path, fill: piece.fill };
  });

  // union of the inked area, so the mark centres on what is visible rather
  // than on font metrics (which would hang it off the sidebearings)
  const box = pieces.reduce(
    (acc, p) => {
      const b = p.path.getBoundingBox();
      return {
        x1: Math.min(acc.x1, b.x1),
        y1: Math.min(acc.y1, b.y1),
        x2: Math.max(acc.x2, b.x2),
        y2: Math.max(acc.y2, b.y2),
      };
    },
    { x1: Infinity, y1: Infinity, x2: -Infinity, y2: -Infinity },
  );

  const w = box.x2 - box.x1;
  const h = box.y2 - box.y1;
  const usable = size * (1 - inset * 2);
  const scale = Math.min(usable / w, usable / h);
  const dx = (size - w * scale) / 2 - box.x1 * scale;
  const dy = (size - h * scale) / 2 - box.y1 * scale;

  const body = pieces.map((p) => `<path fill="${p.fill}" d="${pathData(p.path)}"/>`).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}"><rect width="${size}" height="${size}" fill="${INK}"/><g transform="translate(${dx.toFixed(2)} ${dy.toFixed(2)}) scale(${scale.toFixed(5)})">${body}</g></svg>`;
}

// treatments, loosest tracking where the render is smallest
const TINY = { inset: 0.05, track: 0.045 };
const SMALL = { inset: 0.07, track: 0.02 };
const DISPLAY = { inset: 0.14, track: -0.04 };

// render at 512 then downsample: lets the resampler do the antialiasing rather
// than the SVG rasteriser guessing at 16px
const png = (treatment, size) =>
  sharp(Buffer.from(svg(512, treatment))).resize(size, size).png({ compressionLevel: 9 }).toBuffer();

// PNG-encoded ICO. Everything still in service reads PNG entries, and writing
// the container here keeps a third-party encoder out of the build.
function ico(images) {
  const head = Buffer.alloc(6);
  head.writeUInt16LE(0, 0); // reserved
  head.writeUInt16LE(1, 2); // type: icon
  head.writeUInt16LE(images.length, 4);
  let offset = 6 + images.length * 16;
  const dir = [];
  for (const { size, data } of images) {
    const e = Buffer.alloc(16);
    e.writeUInt8(size >= 256 ? 0 : size, 0); // 0 means 256
    e.writeUInt8(size >= 256 ? 0 : size, 1);
    e.writeUInt8(0, 2); // palette
    e.writeUInt8(0, 3); // reserved
    e.writeUInt16LE(1, 4); // planes
    e.writeUInt16LE(32, 6); // bpp
    e.writeUInt32LE(data.length, 8);
    e.writeUInt32LE(offset, 12);
    dir.push(e);
    offset += data.length;
  }
  return Buffer.concat([head, ...dir, ...images.map((i) => i.data)]);
}

// tabs render the SVG small, so it gets the small treatment
writeFileSync('public/favicon.svg', svg(64, TINY));

writeFileSync(
  'public/favicon.ico',
  ico([
    { size: 16, data: await png(TINY, 16) },
    { size: 32, data: await png(SMALL, 32) },
    { size: 48, data: await png(SMALL, 48) },
  ]),
);

writeFileSync('public/apple-touch-icon.png', await png(DISPLAY, 180));
writeFileSync('public/icon-192.png', await png(DISPLAY, 192));
writeFileSync('public/icon-512.png', await png(DISPLAY, 512));
// Android crops maskable icons hard, so the mark retreats into the safe zone
writeFileSync('public/icon-maskable-512.png', await png({ inset: 0.26, track: -0.04 }, 512));

console.log('icons written');
