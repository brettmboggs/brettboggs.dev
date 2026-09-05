#!/usr/bin/env python3
"""Generates Nightjar's 1024pt app icon: the orb, and nothing else.

Pure stdlib so it stays reproducible with no toolchain to install. Same
colours as the shader, so the icon and the app are the same object.
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "Nightjar/Assets.xcassets/AppIcon.appiconset/icon-1024.png"


def lerp(a, b, t):
    return a + (b - a) * t


def stops_at(stops, t):
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


GROUND_TOP = (0x12, 0x0E, 0x0B)
GROUND_BOTTOM = (0x0A, 0x08, 0x06)

# Outer body: ember into rose into dusk, fading to nothing.
HALO = [
    (0.00, (0xE3, 0x9A, 0x4A), 0.92),
    (0.30, (0xD0, 0x7E, 0x5C), 0.70),
    (0.55, (0x9C, 0x5E, 0x6A), 0.34),
    (0.78, (0x5E, 0x55, 0x7C), 0.12),
    (1.00, (0x3A, 0x36, 0x52), 0.00),
]

CORE = [
    (0.00, (0xFB, 0xE8, 0xCC), 1.00),
    (0.55, (0xF3, 0xC0, 0x84), 0.75),
    (1.00, (0xE3, 0x9A, 0x4A), 0.00),
]

CENTER = (0.50, 0.50)
HALO_RADIUS = 0.68
CORE_RADIUS = 0.23


def wobble(angle):
    """A slightly organic edge, so it is a body and not a disc."""
    return 1 + 0.035 * math.sin(3 * angle + 0.4) + 0.022 * math.sin(5 * angle + 2.1)


def build():
    rows = bytearray()
    cx, cy = CENTER
    for y in range(SIZE):
        rows.append(0)
        fy = (y + 0.5) / SIZE
        base = tuple(lerp(GROUND_TOP[j], GROUND_BOTTOM[j], fy) for j in range(3))
        for x in range(SIZE):
            fx = (x + 0.5) / SIZE
            dx = fx - cx
            dy = fy - cy
            dist = math.sqrt(dx * dx + dy * dy)
            angle = math.atan2(dy, dx)
            w = wobble(angle)

            pixel = base
            colour, alpha = stops_at(HALO, min(dist / (HALO_RADIUS * w), 1.0))
            if alpha > 0:
                pixel = over(pixel, colour, alpha)
            colour, alpha = stops_at(CORE, min(dist / (CORE_RADIUS * w), 1.0))
            if alpha > 0:
                pixel = over(pixel, colour, alpha)

            rows.append(max(0, min(255, int(pixel[0] + 0.5))))
            rows.append(max(0, min(255, int(pixel[1] + 0.5))))
            rows.append(max(0, min(255, int(pixel[2] + 0.5))))
    return bytes(rows)


def chunk(tag, payload):
    body = tag + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_png(raw, path):
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
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
