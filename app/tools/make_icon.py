#!/usr/bin/env python3
"""Generates Slumbio's app icon: a sun on a horizon, at the last of the light.

Three files, because iOS 18 and later asks for three: the default, a dark
variant, and a greyscale one the system tints. `Contents.json` next to them
maps each to its appearance.

Pure stdlib, so it stays reproducible with no toolchain to install. Every
edge is analytic rather than blurred, which is what lets it stay stdlib and
also what keeps the 60pt version crisp: a downsampled blur goes to mush at
that size, a mathematical falloff does not.
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
ICONSET = Path(__file__).resolve().parent.parent / "Nightjar/Assets.xcassets/AppIcon.appiconset"

# Geometry, as fractions of the edge. Tuned at 60pt, not at 1024.
SUN_CENTER = (0.500, 0.545)
SUN_RADIUS = 0.300
HORIZON = 0.680
GLOW_RADIUS = 0.740

CREAM = (0xFD, 0xF0, 0xD8)
WARM = (0xF9, 0xD2, 0x92)
EMBER = (0xE8, 0xA0, 0x4E)
DEEP = (0xC2, 0x70, 0x3A)
CLAY = (0xC9, 0x77, 0x3E)
ROSE = (0xCB, 0x78, 0x70)
DUSK = (0x5E, 0x64, 0x87)

SKY_TOP = (0x19, 0x13, 0x0E)
SKY_LOW = (0x0C, 0x09, 0x07)
LAND_NEAR = (0x33, 0x21, 0x16)
LAND_FAR = (0x0B, 0x09, 0x07)

GLOW = [
    (0.00, EMBER, 0.92),
    (0.16, EMBER, 0.71),
    (0.38, DEEP, 0.38),
    (0.66, ROSE, 0.14),
    (1.00, DUSK, 0.00),
]

SUN = [
    (0.00, CREAM, 1.0),
    (0.32, WARM, 1.0),
    (0.74, EMBER, 1.0),
    (1.00, CLAY, 1.0),
]


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c0, c1, t):
    return tuple(lerp(c0[i], c1[i], t) for i in range(3))


def smoothstep(edge0, edge1, x):
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def ramp(stops, t):
    if t <= stops[0][0]:
        return stops[0][1], stops[0][2]
    if t >= stops[-1][0]:
        return stops[-1][1], stops[-1][2]
    for i in range(len(stops) - 1):
        p0, c0, a0 = stops[i]
        p1, c1, a1 = stops[i + 1]
        if p0 <= t <= p1:
            f = (t - p0) / (p1 - p0) if p1 > p0 else 0.0
            return mix(c0, c1, f), lerp(a0, a1, f)
    return stops[-1][1], stops[-1][2]


def over(dst, src, alpha):
    return mix(dst, src, alpha)


def dither(x, y):
    """Half a step of fixed noise. Same reason as the shader: a warm falloff
    across a dark field crosses hundreds of 8-bit steps and rings without it."""
    h = (x * 73856093) ^ (y * 19349663)
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h >> 16) / 65535.0 - 0.5) * 1.4


def shade(fx, fy, transparent=False):
    """One pixel, as linear-ish 0..255 RGB plus coverage."""
    cx, cy = SUN_CENTER
    dx, dy = fx - cx, fy - cy
    dist = math.hypot(dx, dy)

    if transparent:
        pixel = (0.0, 0.0, 0.0)
        cover = 0.0
    else:
        pixel = mix(SKY_TOP, SKY_LOW, smoothstep(0.0, 1.0, fy))
        cover = 1.0

    colour, alpha = ramp(GLOW, min(dist / GLOW_RADIUS, 1.0))
    if alpha > 0:
        pixel = over(pixel, colour, alpha)
        cover = cover + (1 - cover) * alpha

    # The sun, with an edge one pixel wide so it stays a circle at 60pt.
    edge = 1.0 / SIZE
    disc = 1.0 - smoothstep(SUN_RADIUS - edge, SUN_RADIUS + edge, dist)
    if disc > 0:
        inner = math.hypot(dx, fy - (cy - SUN_RADIUS * 0.3)) / (SUN_RADIUS * 1.15)
        colour, _ = ramp(SUN, min(inner, 1.0))
        pixel = over(pixel, colour, disc)
        cover = cover + (1 - cover) * disc

    # The land. Opaque in every variant: it is the half of the silhouette
    # that makes the sun read as a sun and not as a dot.
    land = smoothstep(HORIZON - edge * 1.5, HORIZON + edge * 1.5, fy)
    if land > 0:
        depth = min((fy - HORIZON) / max(1 - HORIZON, 1e-6) * 1.8, 1.0)
        pixel = over(pixel, mix(LAND_NEAR, LAND_FAR, depth), land)
        cover = cover + (1 - cover) * land

    # The last of the light along the horizon.
    line = math.exp(-(((fy - (HORIZON - 0.0015)) / 0.0105) ** 2)) * 0.62
    if line > 0.002:
        pixel = over(pixel, (0xFF, 0xD6, 0x96), line)
        cover = cover + (1 - cover) * line

    return pixel, min(cover, 1.0)


def build(variant):
    """variant: 'light', 'dark' or 'tinted'."""
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        fy = (y + 0.5) / SIZE
        for x in range(SIZE):
            fx = (x + 0.5) / SIZE
            pixel, cover = shade(fx, fy, transparent=(variant == "tinted"))

            if variant == "dark":
                # Deeper sky, the same fire. iOS puts this on a dark desktop.
                pixel = tuple(c * 0.86 for c in pixel)
            elif variant == "tinted":
                # The system supplies the hue; all it wants from us is shape.
                luma = 0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]
                pixel = (luma, luma, luma)

            noise = dither(x, y)
            if variant == "tinted":
                value = max(0, min(255, int(pixel[0] * cover + noise + 0.5)))
                rows += bytes((value, value, value, max(0, min(255, int(cover * 255 + 0.5)))))
            else:
                rows += bytes(
                    max(0, min(255, int(pixel[i] + noise + 0.5))) for i in range(3)
                )
    return bytes(rows)


def chunk(tag, payload):
    body = tag + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(raw, path, alpha=False):
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6 if alpha else 2, 0, 0, 0)
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


CONTENTS = """{
  "images" : [
    {
      "filename" : "icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-1024-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-1024-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

if __name__ == "__main__":
    for variant, name in (
        ("light", "icon-1024.png"),
        ("dark", "icon-1024-dark.png"),
        ("tinted", "icon-1024-tinted.png"),
    ):
        path = ICONSET / name
        write_png(build(variant), path, alpha=(variant == "tinted"))
        print(f"wrote {name} ({path.stat().st_size // 1024} KB)")
    (ICONSET / "Contents.json").write_text(CONTENTS)
    print("wrote Contents.json")
