// Convert rendered film frames into web-ready WebP sequences (three tiers).
// Run: node tools/build-film.mjs
import sharp from 'sharp';
import { readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SRC = 'C:/Users/brett/dev/ridge-film/frames2560';
const OUT = 'public/film';
const STEP = 2;

const TIERS = [
  { name: 'xl', width: 2560, height: 1440, quality: 78 },
  { name: 'lg', width: 1600, height: 900, quality: 76 },
  { name: 'sm', width: 960, height: 540, quality: 70 },
];

const files = readdirSync(SRC).filter((f) => f.endsWith('.png')).sort();
if (!files.length) {
  console.error('no frames found in ' + SRC);
  process.exit(1);
}
const picked = files.filter((_, i) => i % STEP === 0);
console.log(`source ${files.length} frames -> ${picked.length} web frames x ${TIERS.length} tiers`);

for (const t of TIERS) mkdirSync(join(OUT, t.name), { recursive: true });

let i = 0;
for (const f of picked) {
  const src = join(SRC, f);
  const n = String(i).padStart(3, '0');
  for (const t of TIERS) {
    let img = sharp(src).resize(t.width, t.height);
    // counteract WebP's smoothing of fine grass/grain detail on the hero tier
    if (t.name === 'xl') img = img.sharpen({ sigma: 0.7, m1: 0.4, m2: 0.2 });
    await img.webp({ quality: t.quality }).toFile(join(OUT, t.name, `${n}.webp`));
  }
  i++;
}

await sharp(join(SRC, files[0])).resize(TIERS[0].width, TIERS[0].height).webp({ quality: 80 }).toFile(join(OUT, 'poster.webp'));
await sharp(join(SRC, files[files.length - 1])).resize(TIERS[0].width, TIERS[0].height).webp({ quality: 80 }).toFile(join(OUT, 'poster-end.webp'));

writeFileSync(join(OUT, 'manifest.json'), JSON.stringify({ count: picked.length, tiers: TIERS.map((t) => t.name) }));
console.log(`done: ${picked.length} frames x ${TIERS.length} tiers + posters`);
