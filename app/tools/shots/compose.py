#!/usr/bin/env python3
"""Composes the App Store screenshots: 1320 x 2868, the 6.9 inch size.

Needs Pillow (`pip3 install pillow`); it is the one tool here that is not
stdlib, because resampling and blurring a two-megapixel canvas by hand is not
worth the purity. Run `tools/shots/capture.sh` first to fill `raw/`.

The captions are set in New York, which is the same face the app renders its
own titles in, so the words above the phone and the words inside it are one
typeface rather than two. The background is a single warm field sampled across
the set, so scrolling the strip in the App Store reads as one image drifting
rather than eight unrelated cards.
"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, random, os

W, H = 1320, 2868
CAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

SERIF = "/System/Library/Fonts/NewYork.ttf"
SANS = "/System/Library/Fonts/SFNS.ttf"

# The light half of the palette. The app is dark, the page it sits on is not.
#
# The first version put a dark app on a dark ground and the whole strip read as
# one brown smudge at the size the App Store actually shows it. Oat paper with
# espresso type is the same brand, and a dark phone on it separates at any
# size.
PAPER_TOP = (0xF7, 0xF0, 0xE3)
PAPER_BOT = (0xE8, 0xDB, 0xC4)
INK       = (0x2B, 0x22, 0x18)
INK_SOFT  = (0x7A, 0x6B, 0x57)
EMBER     = (0xE8, 0xA0, 0x4E)
DEEP      = (0xC2, 0x70, 0x3A)
ROSE      = (0xCB, 0x78, 0x70)

SHOTS = [
    ("tonight",  "Sound that\nnever repeats.",      "Thirty-three of the thirty-five are made as they play."),
    ("breathe",  "Breathing\nyou can see.",         "The screen fills on the inhale and empties on the exhale."),
    ("sounds",   "Thirty-five sounds.\nSix at once.", "Each one has a level and two controls that reach inside it."),
    ("routine",     "One tap for\nthe whole night.",   "A breath, then the sound, then the sleep timer."),
    ("wake",        "Wake to light,\nnot to a siren.", "Sound that climbs out of silence before the alarm."),
    ("rest",     "Two weeks\nof nights.",           "Kept on the phone. There is nowhere else for them to go."),
    ("bedside",     "A clock at\ntwo percent.",        "Bedside mode hides everything until you touch it."),
    ("settings", "No account.\nNo server.",         "There is no network code in the app at all."),
]


def font(path, size, weight=None):
    f = ImageFont.truetype(path, size)
    if weight is not None:
        try:
            f.set_variation_by_axes([weight])
        except Exception:
            pass
    return f


def background(index, total):
    """Warm paper, with one slow bloom drifting across the whole set."""
    bg = Image.new("RGB", (W, H))
    px = bg.load()
    for y in range(H):
        t = (y / H) ** 0.9
        base = tuple(int(PAPER_TOP[i] + (PAPER_BOT[i] - PAPER_TOP[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = base

    # The bloom walks left to right across the eight, so scrolling the strip
    # reads as one field moving rather than eight unrelated cards.
    phase = index / max(total - 1, 1)
    cx = W * (0.14 + 0.72 * phase)
    cy = H * (0.20 + 0.08 * math.sin(phase * math.pi))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gp = glow.load()
    radius = W * 1.15
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            d = math.hypot(x - cx, (y - cy) * 0.82) / radius
            if d >= 1:
                continue
            a = (1 - d) ** 2.4
            colour = EMBER if d < 0.4 else (DEEP if d < 0.68 else ROSE)
            v = (colour[0], colour[1], colour[2], int(a * 74))
            for dy in (0, 1):
                for dx in (0, 1):
                    if x + dx < W and y + dy < H:
                        gp[x + dx, y + dy] = v
    glow = glow.filter(ImageFilter.GaussianBlur(11))
    bg = Image.alpha_composite(bg.convert("RGBA"), glow).convert("RGB")

    # Paper grain, the same five percent the site carries.
    random.seed(11 + index)
    noise = Image.new("L", (W // 2, H // 2))
    noise.putdata([random.gauss(128, 5) for _ in range(noise.size[0] * noise.size[1])])
    noise = noise.resize((W, H), Image.BILINEAR).convert("RGB")
    return Image.blend(bg, Image.blend(bg, noise, 0.5), 0.09)


def rounded(im, radius):
    mask = Image.new("L", (im.width * 2, im.height * 2), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, im.width * 2 - 1, im.height * 2 - 1], radius=radius * 2, fill=255
    )
    mask = mask.resize(im.size, Image.LANCZOS)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im.convert("RGBA"), (0, 0), mask)
    return out


def centred(draw, text, y, fnt, fill, spacing):
    for line in text.split("\n"):
        w = draw.textbbox((0, 0), line, font=fnt)[2]
        draw.text(((W - w) / 2, y), line, font=fnt, fill=fill)
        y += spacing
    return y


def compose(index, name, headline, sub):
    bg = background(index, len(SHOTS))
    d = ImageDraw.Draw(bg)

    # A headline, at headline size. The first pass set these at 92px in a light
    # weight, which reads as a caption under a picture rather than as the thing
    # you are supposed to read first.
    head = font(SERIF, 112, 650)
    small = font(SANS, 42)

    y = centred(d, headline, 152, head, INK, 126)
    w = d.textbbox((0, 0), sub, font=small)[2]
    while w > W - 140 and small.size > 30:
        small = font(SANS, small.size - 2)
        w = d.textbbox((0, 0), sub, font=small)[2]
    d.text(((W - w) / 2, y + 30), sub, font=small, fill=INK_SOFT)

    shot = Image.open(os.path.join(CAP, f"{name}.png")).convert("RGB")
    scale = 0.78
    dw = int(W * scale)
    dh = int(dw * shot.height / shot.width)
    shot = shot.resize((dw, dh), Image.LANCZOS)
    corner = int(165 * scale)
    device = rounded(shot, corner)

    top = H - dh - 46
    left = (W - dw) // 2

    # A real drop, so a dark phone reads as sitting above light paper rather
    # than as a hole cut into it.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left + 8, top + 26, left + dw - 8, top + dh],
        radius=corner, fill=(0x3A, 0x2C, 0x1C, 120)
    )
    bg = Image.alpha_composite(bg.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(44)))

    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    frame.paste(device, (left, top), device)
    bg = Image.alpha_composite(bg, frame)

    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [left, top, left + dw - 1, top + dh - 1],
        radius=corner, outline=(0x1A, 0x14, 0x0E, 235), width=5
    )
    bg = Image.alpha_composite(bg, edge)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{index + 1:02d}-{name}.png")
    bg.convert("RGB").save(path)
    return path


if __name__ == "__main__":
    for i, (name, head, sub) in enumerate(SHOTS):
        print("wrote", os.path.basename(compose(i, name, head, sub)))
