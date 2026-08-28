from PIL import Image
Image.MAX_IMAGE_PIXELS = None
import os, glob, re, json

SRC = r"C:\Users\brett\OneDrive\Desktop\Lunar Eclipse\Edits"
OUT = r"C:\Users\brett\dev\brettboggs.dev\public\photo\eclipse"
os.makedirs(os.path.join(OUT, 'stage'), exist_ok=True)
log = []

def save(im, name, w=None, q=88, fmt='WEBP'):
    if w and im.width != w:
        im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    p = os.path.join(OUT, name)
    if fmt == 'WEBP':
        im.save(p, 'WEBP', quality=q, method=6)
    else:
        im.save(p, 'JPEG', quality=q, optimize=True, progressive=True, subsampling=0)
    log.append((name, im.width, im.height, os.path.getsize(p)))

def op(f):
    return Image.open(os.path.join(SRC, f)).convert('RGB')

# hero: the plane transit, native 1536
im = op('01_plane_transit_22-42-06.tif')
save(im, 'plane-transit-1536.webp', 1536, 92)
save(im, 'plane-transit-760.webp', 760, 86)

# the ring, native 2040
im = op('02_eclipse_ring_HDR_22-44.tif')
save(im, 'ring-2040.webp', 2040, 92)
save(im, 'ring-1020.webp', 1020, 86)

# aircraft tracks, native 3200: the viewer gets the whole thing
for tag, f in (('a', '04_plane_track_22-42.tif'), ('b', '05_plane_track_22-36.tif')):
    im = op(f)
    save(im, f'plane-track-{tag}-3200.webp', 3200, 90)
    save(im, f'plane-track-{tag}-2400.webp', 2400, 88)
    save(im, f'plane-track-{tag}-1200.webp', 1200, 86)

# the arcs. 6000 is the in-viewer copy: 5.9 MP decodes on any phone.
# the 19610 original stays a download, it is 63 MP and browsers choke on it.
for tag, f in (('arc-even', '03_progression_arc_HDR_even.tif'),
               ('arc-true', '03b_progression_arc_HDR_physical.tif')):
    im = op(f)
    save(im, f'{tag}-6000.webp', 6000, 84)
    save(im, f'{tag}-2400.webp', 2400, 82)
    save(im, f'{tag}-1200.webp', 1200, 80)
    save(im, f'{tag}-full.jpg', 19610, 88, 'JPEG')

# the 21 stages, native 1360
stages = []
for f in sorted(glob.glob(os.path.join(SRC, 'Closeups', '*.tif'))):
    m = re.match(r'closeup_(\d\d)-(\d\d)_(\d+)lvl_([\d.]+)stops', os.path.basename(f))
    hh, mm, lvl, stops = m.group(1), m.group(2), int(m.group(3)), float(m.group(4))
    slug = f'{hh}{mm}'
    im = Image.open(f).convert('RGB')
    save(im, f'stage/{slug}-1360.webp', 1360, 90)
    save(im, f'stage/{slug}-560.webp', 560, 84)
    stages.append({'slug': slug, 'time': f'{hh}:{mm}', 'levels': lvl, 'stops': stops})

json.dump(stages, open('stages.json', 'w'), indent=1)
tot = sum(s for *_, s in log)
for n, w, h, s in log:
    print(f'{s/1e6:7.2f}MB {w:6d}x{h:<5d} {n}')
print(f'TOTAL {tot/1e6:.1f} MB across {len(log)} files')
