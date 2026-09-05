#!/usr/bin/env python3
"""Generates Hush's 1024pt app icon.

An abstract warm horizon: no moon, no musical notes, nothing literal. Pure
stdlib so it stays reproducible with no toolchain to install.
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "Hush/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def lerp(a, b, t):
    return a + (b - a) * t


def stops_at(stops, t):
    """Interpolate a list of (position, (r,g,b), alpha) stops."""
    if t <= stops[0][0]:
        return stops[0][1], stops[0][2]
    if t >= stops[-1][0]:
        return stops[-1][1], stops[-1][2]
    for i in range(len(stops) - 1):
        p0, c0, a0 = stops[i]
        p1, c1, a1 = stops[i + 1]
        if p0 <= t <= p1:
            f = (t - p0) / (p1 - p0) if p1 > p0 else 0.0
            colour = tuple(lerp(c0[j], c1[j], f) for j in range(3))
            return colour, lerp(a0, a1, f)
    return stops[-1][1], stops[-1][2]


def over(dst, src, alpha):
    return tuple(lerp(dst[j], src[j], alpha) for j in range(3))


GROUND = [
    (0.00, (0x17, 0x10, 0x09), 1.0),
    (0.55, (0x0E, 0x0A, 0x07), 1.0),
    (1.00, (0x0A, 0x07, 0x05), 1.0),
]

GLOW = [
    (0.00, (0xF2, 0xB4, 0x5E), 0.95),
    (0.26, (0xD9, 0x8A, 0x3C), 0.62),
    (0.58, (0x9A, 0x4F, 0x27), 0.26),
    (1.00, (0x6B, 0x2F, 0x18), 0.00),
]

CORE = [
    (0.00, (0xFF, 0xD9, 0xA0), 0.90),
    (1.00, (0xF0, 0xA4, 0x4E), 0.00),
]

# Three settling bands: centre y, left x, right x, opacity. Thick enough to
# still read as a mark at 60pt on a home screen, which is the only size that
# really matters.
BANDS = [
    (0.560, 0.150, 0.850, 0.62),
    (0.655, 0.245, 0.755, 0.42),
    (0.745, 0.350, 0.650, 0.24),
]
BAND_INK = (0xF7, 0xE8, 0xD2)
BAND_HALF_HEIGHT = 11.0  # pixels

GLOW_CENTER = (0.50, 0.80)
GLOW_RADIUS = 0.58
CORE_RADIUS = 0.24


def build():
    rows = bytearray()
    cx, cy = GLOW_CENTER

    for y in range(SIZE):
        rows.append(0)  # PNG filter type: none
        fy = (y + 0.5) / SIZE
        base_colour, _ = stops_at(GROUND, fy)
        veil = 0.55 * fy * fy

        # Only bands whose capsule can reach this row are worth testing.
        active = [
            (cy_b * SIZE, x0 * SIZE, x1 * SIZE, alpha)
            for cy_b, x0, x1, alpha in BANDS
            if abs((y + 0.5) - cy_b * SIZE) <= BAND_HALF_HEIGHT + 1.5
        ]

        for x in range(SIZE):
            fx = (x + 0.5) / SIZE
            dx = fx - cx
            dy = fy - cy
            dist = math.sqrt(dx * dx + dy * dy)

            pixel = base_colour

            colour, alpha = stops_at(GLOW, min(dist / GLOW_RADIUS, 1.0))
            if alpha > 0:
                pixel = over(pixel, colour, alpha)

            colour, alpha = stops_at(CORE, min(dist / CORE_RADIUS, 1.0))
            if alpha > 0:
                pixel = over(pixel, colour, alpha)

            for band_y, bx0, bx1, band_alpha in active:
                px, py = x + 0.5, y + 0.5
                if px < bx0:
                    d = math.hypot(px - bx0, py - band_y)
                elif px > bx1:
                    d = math.hypot(px - bx1, py - band_y)
                else:
                    d = abs(py - band_y)
                # One pixel of feathering keeps the rounded caps clean.
                coverage = max(0.0, min(1.0, (BAND_HALF_HEIGHT - d) / 1.5 + 0.5))
                if coverage > 0:
                    pixel = over(pixel, BAND_INK, band_alpha * coverage)

            if veil > 0:
                pixel = over(pixel, (0x0A, 0x07, 0x05), veil)

            rows.append(max(0, min(255, int(pixel[0] + 0.5))))
            rows.append(max(0, min(255, int(pixel[1] + 0.5))))
            rows.append(max(0, min(255, int(pixel[2] + 0.5))))

    return bytes(rows)


def chunk(tag, payload):
    body = tag + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(raw, path):
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8-bit truecolour
    data = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


if __name__ == "__main__":
    write_png(build(), OUT)
    print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB)")
