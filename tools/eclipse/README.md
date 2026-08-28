# /lab/eclipse data pipeline

Everything numeric on the page comes out of these four scripts, so the numbers can be
re-derived instead of trusted. Nothing here runs at build time. Run it by hand when the
source files change, commit the outputs.

Source: `C:\Users\brett\OneDrive\Desktop\Lunar Eclipse\` (194 CR3 + 1 MP4) and its
`Edits\` folder (the TIFF composites and the 21 stage closeups from the processing run).

Needs `rawpy`, `numpy`, `Pillow`. Run in order, from this directory:

```bash
python cr3exif.py "C:/Users/brett/OneDrive/Desktop/Lunar Eclipse" > exif.json
python photom.py
python mkdata.py
python assets.py
```

| Script | What it does |
|---|---|
| `cr3exif.py` | Parses EXIF straight out of the CR3 boxes (`CMT1` is IFD0, `CMT2` the Exif IFD, `CMT4` GPS). No exiftool needed. Writes `exif.json`. |
| `photom.py` | Aperture photometry on every raw frame: black level off, 2x2 Bayer bin, locate the disc, sum inside 1.45 radii, sky from a surrounding annulus, normalise by `N^2 / (f^2 * t * ISO)`. Writes `photom.json`. |
| `mkdata.py` | Turns both into `src/data/eclipse.json`: totals, the bursts, and the light curve. |
| `assets.py` | Renders `public/lab/eclipse/**` from the TIFFs. |

Two things the curve depends on, so do not quietly change them:

- **Only unclipped frames are plotted.** A frame where anything inside the aperture is
  within 1.5% of saturation reads too dim, because the surviving sunlit sliver is the
  part that blows. That filter is why the dots thin out after 22:45.
- **ISO 160 is dropped.** It is a pulled ISO on this body with non linear gain, and it
  sits about 0.8 stops off its neighbours in the same minute.

Frames excluded everywhere, matching the original processing run: `CAR67438`
(light painting), `CAR67455-57` (wide sky at 70 mm), `CAR67564` (defocused).
