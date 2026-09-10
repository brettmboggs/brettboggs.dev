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

INK      = (0xF1, 0xE7, 0xD9)
INK_SOFT = (0xA8, 0x9A, 0x88)
EMBER    = (0xE8, 0xA0, 0x4E)
DEEP     = (0xC2, 0x70, 0x3A)
ROSE     = (0xCB, 0x78, 0x70)
DUSK     = (0x4A, 0x44, 0x5E)
NIGHT_T  = (0x1C, 0x14, 0x0E)
NIGHT_B  = (0x08, 0x07, 0x06)

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
    """One frame of a slow warm drift across the whole set."""
    bg = Image.new("RGB", (W, H))
    px = bg.load()
    for y in range(H):
        t = y / H
        base = tuple(int(NIGHT_T[i] + (NIGHT_B[i] - NIGHT_T[i]) * (t ** 0.75)) for i in range(3))
        for x in range(W):
            px[x, y] = base

    # The bloom walks left to right across the eight, so the strip is one field.
    phase = index / max(total - 1, 1)
    cx = W * (0.16 + 0.68 * phase)
    cy = H * (0.30 + 0.10 * math.sin(phase * math.pi))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gp = glow.load()
    radius = W * 1.05
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            d = math.hypot(x - cx, (y - cy) * 0.78) / radius
            if d >= 1:
                continue
            a = (1 - d) ** 2.6
            colour = EMBER if d < 0.35 else (DEEP if d < 0.6 else ROSE if d < 0.82 else DUSK)
            v = (colour[0], colour[1], colour[2], int(a * 128))
            for dy in (0, 1):
                for dx in (0, 1):
                    if x + dx < W and y + dy < H:
                        gp[x + dx, y + dy] = v
    glow = glow.filter(ImageFilter.GaussianBlur(9))
    bg = Image.alpha_composite(bg.convert("RGBA"), glow).convert("RGB")

    # Grain, the same 5% the site carries.
    random.seed(11 + index)
    noise = Image.new("L", (W // 2, H // 2))
    noise.putdata([random.gauss(128, 4) for _ in range(noise.size[0] * noise.size[1])])
    noise = noise.resize((W, H), Image.BILINEAR).convert("RGB")
    return Image.blend(bg, Image.blend(bg, noise, 0.5), 0.10)


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

    head = font(SERIF, 92, 500)
    small = font(SANS, 38)

    y = centred(d, headline, 168, head, INK, 108)
    w = d.textbbox((0, 0), sub, font=small)[2]
    if w > W - 150:
        small = font(SANS, 34)
        w = d.textbbox((0, 0), sub, font=small)[2]
    d.text(((W - w) / 2, y + 26), sub, font=small, fill=INK_SOFT)

    shot = Image.open(os.path.join(CAP, f"{name}.png")).convert("RGB")
    scale = 0.755
    dw = int(W * scale)
    dh = int(dw * shot.height / shot.width)
    shot = shot.resize((dw, dh), Image.LANCZOS)
    device = rounded(shot, int(165 * scale))

    top = 636
    # A soft drop, so the phone sits in the field rather than on it.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [(W - dw) // 2, top + 18, (W - dw) // 2 + dw, top + dh],
        radius=int(165 * scale), fill=(0, 0, 0, 150)
    )
    bg = Image.alpha_composite(bg.convert("RGBA"), shadow.filter(ImageFilter.GaussianBlur(38)))

    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    frame.paste(device, ((W - dw) // 2, top), device)
    bg = Image.alpha_composite(bg, frame)

    edge = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [(W - dw) // 2, top, (W - dw) // 2 + dw - 1, top + dh - 1],
        radius=int(165 * scale), outline=(0x4A, 0x3B, 0x2E, 210), width=4
    )
    bg = Image.alpha_composite(bg, edge)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{index + 1:02d}-{name}.png")
    bg.convert("RGB").save(path)
    return path


if __name__ == "__main__":
    for i, (name, head, sub) in enumerate(SHOTS):
        print("wrote", os.path.basename(compose(i, name, head, sub)))
