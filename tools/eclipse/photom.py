import rawpy, numpy as np, json, os, glob, math

src = r"C:\Users\brett\OneDrive\Desktop\Lunar Eclipse"
exif = {e['file']: e for e in json.load(open('exif.json'))}
SKIP = {'CAR67438.CR3', 'CAR67455.CR3', 'CAR67456.CR3', 'CAR67457.CR3', 'CAR67564.CR3'}
out = []

for f in sorted(glob.glob(os.path.join(src, '*.CR3'))):
    name = os.path.basename(f)
    if name in SKIP:
        continue
    e = exif[name]
    with rawpy.imread(f) as raw:
        a = raw.raw_image_visible.astype(np.float32)
        blk = float(np.mean(raw.black_level_per_channel))
        white = float(raw.white_level)
    h, w = a.shape
    a = a - blk
    sat = white - blk
    # 2x2 bin (Bayer cell) -> luminance proxy
    b = a[: h // 2 * 2, : w // 2 * 2].reshape(h // 2, 2, w // 2, 2).sum(axis=(1, 3))
    smax = a[: h // 2 * 2, : w // 2 * 2].reshape(h // 2, 2, w // 2, 2).max(axis=(1, 3))
    bh, bw = b.shape
    # coarse locate: 16x16 block means
    cb = b[: bh // 16 * 16, : bw // 16 * 16].reshape(bh // 16, 16, bw // 16, 16).mean(axis=(1, 3))
    cy, cx = np.unravel_index(np.argmax(cb), cb.shape)
    cy, cx = cy * 16 + 8, cx * 16 + 8
    # refine with centroid in a window
    R = 152 * e['focal'] / 200.0 / 2.0      # moon radius in binned px
    win = int(R * 2.2)
    y0, y1 = max(0, cy - win), min(bh, cy + win)
    x0, x1 = max(0, cx - win), min(bw, cx + win)
    sub = b[y0:y1, x0:x1]
    thr = np.percentile(sub, 60)
    m = np.clip(sub - thr, 0, None)
    if m.sum() > 0:
        yy, xx = np.mgrid[y0:y1, x0:x1]
        cy = float((yy * m).sum() / m.sum()); cx = float((xx * m).sum() / m.sum())
    yy, xx = np.ogrid[:bh, :bw]
    d2 = (yy - cy) ** 2 + (xx - cx) ** 2
    ap = d2 <= (R * 1.45) ** 2
    ann = (d2 > (R * 2.0) ** 2) & (d2 <= (R * 3.0) ** 2)
    bg = float(np.median(b[ann])) if ann.sum() > 100 else float(np.median(b))
    flux = float((b[ap] - bg).sum())
    clip = float((smax[ap] >= sat * 0.985).sum()) / int(ap.sum())
    edge = cx - R * 3 < 0 or cy - R * 3 < 0 or cx + R * 3 >= bw or cy + R * 3 >= bh
    # scene radiance proxy: total flux scales with entrance pupil area (f/N)^2
    rad = flux * (e['fnumber'] ** 2) / ((e['focal'] ** 2) * e['exposure'] * e['iso'])
    out.append({'file': name, 'dt': e['dt'], 'subsec': e['subsec'], 'flux': flux, 'rad': rad,
                'clip': clip, 'bg': bg, 'cx': cx, 'cy': cy, 'R': R, 'edge': bool(edge),
                't': e['exposure'], 'iso': e['iso'], 'N': e['fnumber'], 'focal': e['focal']})
json.dump(out, open('photom.json', 'w'))
print('done', len(out))
