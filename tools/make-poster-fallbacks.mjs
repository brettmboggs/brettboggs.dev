// JPEG twins of the film posters. Run: node tools/make-poster-fallbacks.mjs
//
// Safari only learned webp in iOS 14. Older iPads decode none of the film, and
// without these the hero is a blank frame rather than a still. The 96 scrub
// frames stay webp-only on purpose: those browsers skip the scrub entirely, so
// shipping a second copy of the sequence would buy nothing.
import sharp from 'sharp';

for (const name of ['poster', 'poster-portrait', 'poster-end', 'poster-end-portrait']) {
  await sharp(`public/film/${name}.webp`)
    .jpeg({ quality: 82, mozjpeg: true, progressive: true })
    .toFile(`public/film/${name}.jpg`);
}
console.log('poster fallbacks written');
