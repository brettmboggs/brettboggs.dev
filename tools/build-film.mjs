// Convert rendered film frames into web-ready WebP sequences.
// Run: node tools/build-film.mjs [tier ...]   (no args = every tier)
import sharp from 'sharp';
import { readdirSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const SRC = 'C:/Users/brett/dev/ridge-film/frames2560';
const OUT = 'public/film';
const STEP = 2;
const MASTER = { width: 2560, height: 1440 };

// `portrait` is a centre crop of the master, not a resize: the camera tracks the
// structure through frame centre, so the tall crop keeps the whole flight. Phones
// cover-fill a 16:9 tier at ~3.5x, which is what made the hero look like mush.
const TIERS = [
  { name: 'xl', width: 2560, height: 1440, quality: 78, sharpen: true },
  { name: 'lg', width: 1600, height: 900, quality: 76 },
  { name: 'sm', width: 960, height: 540, quality: 70 },
  { name: 'portrait', crop: { width: 664, height: 1440 }, quality: 72, sharpen: true },
];

const want = process.argv.slice(2);
const tiers = want.length ? TIERS.filter((t) => want.includes(t.name)) : TIERS;
if (!tiers.length) {
  console.error(`no such tier: ${want.join(', ')}`);
  process.exit(1);
}

const files = readdirSync(SRC).filter((f) => f.endsWith('.png')).sort();
if (!files.length) {
  console.error('no frames found in ' + SRC);
  process.exit(1);
}
const picked = files.filter((_, i) => i % STEP === 0);
console.log(`source ${files.length} frames -> ${picked.length} web frames x ${tiers.length} tier(s)`);

// a tier either resizes the whole master or crops a window out of its centre
function shape(img, t) {
  if (!t.crop) return img.resize(t.width, t.height);
  return img.extract({
    left: Math.round((MASTER.width - t.crop.width) / 2),
    top: Math.round((MASTER.height - t.crop.height) / 2),
    width: t.crop.width,
    height: t.crop.height,
  });
}

for (const t of tiers) mkdirSync(join(OUT, t.name), { recursive: true });

let i = 0;
for (const f of picked) {
  const src = join(SRC, f);
  const n = String(i).padStart(3, '0');
  for (const t of tiers) {
    let img = shape(sharp(src), t);
    // counteract WebP's smoothing of fine grass/grain detail where we can't spare it
    if (t.sharpen) img = img.sharpen({ sigma: 0.7, m1: 0.4, m2: 0.2 });
    await img.webp({ quality: t.quality }).toFile(join(OUT, t.name, `${n}.webp`));
  }
  i++;
}

async function poster(srcFile, tier, out) {
  await shape(sharp(join(SRC, srcFile)), tier).webp({ quality: 80 }).toFile(join(OUT, out));
}
const wide = TIERS[0];
const tall = TIERS.find((t) => t.name === 'portrait');
const last = files[files.length - 1];
if (tiers.includes(wide)) {
  await poster(files[0], wide, 'poster.webp');
  await poster(last, wide, 'poster-end.webp');
}
if (tiers.includes(tall)) {
  await poster(files[0], tall, 'poster-portrait.webp');
  await poster(last, tall, 'poster-end-portrait.webp');
}

writeFileSync(
  join(OUT, 'manifest.json'),
  JSON.stringify({ count: picked.length, tiers: TIERS.map((t) => t.name) }),
);
console.log(`done: ${picked.length} frames x ${tiers.map((t) => t.name).join(', ')} + posters`);
