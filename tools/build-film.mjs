// Convert rendered film frames into web-ready WebP sequences.
// Run: node tools/build-film.mjs
import sharp from 'sharp';
import { readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SRC = 'C:/Users/brett/dev/ridge-film/frames';
const OUT = 'public/film';
const STEP = 2; // every 2nd rendered frame; scrub stays smooth

const files = readdirSync(SRC).filter((f) => f.endsWith('.png')).sort();
if (!files.length) {
  console.error('no frames found in ' + SRC);
  process.exit(1);
}
const picked = files.filter((_, i) => i % STEP === 0);
console.log(`source ${files.length} frames -> ${picked.length} web frames`);

mkdirSync(join(OUT, 'lg'), { recursive: true });
mkdirSync(join(OUT, 'sm'), { recursive: true });

let i = 0;
for (const f of picked) {
  const src = join(SRC, f);
  const n = String(i).padStart(3, '0');
  await sharp(src).resize(1600, 900).webp({ quality: 72 }).toFile(join(OUT, 'lg', `${n}.webp`));
  await sharp(src).resize(960, 540).webp({ quality: 68 }).toFile(join(OUT, 'sm', `${n}.webp`));
  i++;
}

// posters: first frame (instant paint) and final frame (content backdrop)
await sharp(join(SRC, files[0])).resize(1600, 900).webp({ quality: 78 }).toFile(join(OUT, 'poster.webp'));
await sharp(join(SRC, files[files.length - 1])).resize(1600, 900).webp({ quality: 78 }).toFile(join(OUT, 'poster-end.webp'));

writeFileSync(join(OUT, 'manifest.json'), JSON.stringify({ count: picked.length }));
console.log(`done: ${picked.length} frames x2 sizes + posters`);
