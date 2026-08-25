// One-time converter: Fraunces WOFF -> three.js typeface JSON (subset).
// Run: node tools/make-typeface.mjs
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const require = createRequire(import.meta.url);
const opentype = require('opentype.js');

const CHARS = 'Bretogs.';

function toArrayBuffer(buf) {
  return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
}

function convert(srcPath, outPath) {
  const font = opentype.parse(toArrayBuffer(readFileSync(srcPath)));
  const res = font.unitsPerEm;

  const glyphs = {};
  for (const ch of CHARS) {
    const g = font.charToGlyph(ch);
    const parts = [];
    for (const c of g.path.commands) {
      if (c.type === 'M') parts.push('m', Math.round(c.x), Math.round(c.y));
      else if (c.type === 'L') parts.push('l', Math.round(c.x), Math.round(c.y));
      else if (c.type === 'Q')
        parts.push('q', Math.round(c.x), Math.round(c.y), Math.round(c.x1), Math.round(c.y1));
      else if (c.type === 'C')
        parts.push(
          'b',
          Math.round(c.x), Math.round(c.y),
          Math.round(c.x1), Math.round(c.y1),
          Math.round(c.x2), Math.round(c.y2),
        );
    }
    glyphs[ch] = {
      ha: Math.round(g.advanceWidth),
      x_min: Math.round(g.xMin ?? 0),
      x_max: Math.round(g.xMax ?? g.advanceWidth),
      o: parts.join(' '),
    };
  }

  const kern = {};
  for (const a of CHARS) {
    for (const b of CHARS) {
      const v = font.getKerningValue(font.charToGlyph(a), font.charToGlyph(b));
      if (v) kern[a + b] = Math.round(v);
    }
  }

  const json = {
    glyphs,
    kern,
    familyName: font.names.fullName?.en ?? 'Fraunces',
    ascender: font.ascender,
    descender: font.descender,
    underlinePosition: -100,
    underlineThickness: 50,
    boundingBox: {
      xMin: font.tables.head.xMin,
      yMin: font.tables.head.yMin,
      xMax: font.tables.head.xMax,
      yMax: font.tables.head.yMax,
    },
    resolution: res,
    original_font_information: {},
  };
  writeFileSync(outPath, JSON.stringify(json));
  console.log(`${outPath}: ${Object.keys(glyphs).length} glyphs, ${Object.keys(kern).length} kern pairs, upem ${res}`);
}

mkdirSync('src/assets', { recursive: true });
convert(
  'node_modules/@fontsource/fraunces/files/fraunces-latin-600-normal.woff',
  'src/assets/fraunces-600.typeface.json',
);
convert(
  'node_modules/@fontsource/fraunces/files/fraunces-latin-600-italic.woff',
  'src/assets/fraunces-600-italic.typeface.json',
);
