// One-off: convert the 2x render of the film's landing frame into the
// high-res poster the station menu zooms into.
// Run: node tools/make-endframe-2x.mjs
import sharp from 'sharp';

const SRC = 'C:/Users/brett/dev/ridge-film/frames5120/f_0192.png';
const OUT = 'public/film/poster-end-2x.webp';

const img = sharp(SRC);
const meta = await img.metadata();
if (meta.width !== 5120 || meta.height !== 2880) {
  console.error(`unexpected size ${meta.width}x${meta.height}, wanted 5120x2880`);
  process.exit(1);
}
// same counter-smoothing the xl tier gets, slightly lower quality to keep
// the file sane at four times the pixels
await img
  .sharpen({ sigma: 0.7, m1: 0.4, m2: 0.2 })
  .webp({ quality: 74 })
  .toFile(OUT);
const { size } = await import('node:fs').then((fs) => fs.promises.stat(OUT));
console.log(`wrote ${OUT} (${(size / 1024 / 1024).toFixed(2)} MB)`);
