#!/usr/bin/env python3
"""Generates the Mise app icon: a plate, seen from above, in black and white.

Three files, because iOS 18 and later asks for three: the default (black on
white), a dark variant (white on black), and a greyscale one the system
tints. Pure stdlib, analytic edges, so it stays reproducible with nothing to
install and stays crisp at 60pt.
"""
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
ICONSET = Path(__file__).resolve().parent.parent / "Mise/Assets.xcassets/AppIcon.appiconset"

# Geometry as fractions of the edge. The rim is the plate's edge; the well
# is the dip in the middle. A dot sits at the centre: the one thing on it.
CENTER = (0.5, 0.5)
RIM_OUTER = 0.400
RIM_INNER = 0.372
WELL = 0.262
WELL_WIDTH = 0.014
DOT = 0.032


def ring(d, inner, outer, aa):
    """Coverage of a ring between two radii at distance d, anti-aliased."""
    return max(0.0, min(1.0, (d - inner) / aa + 0.5)) * max(0.0, min(1.0, (outer - d) / aa + 0.5))


def disc(d, radius, aa):
    return max(0.0, min(1.0, (radius - d) / aa + 0.5))


def render(ink, paper):
    aa = 1.5 / SIZE
    rows = []
    for y in range(SIZE):
        row = bytearray()
        fy = (y + 0.5) / SIZE
        for x in range(SIZE):
            fx = (x + 0.5) / SIZE
            d = math.hypot(fx - CENTER[0], fy - CENTER[1])
            coverage = ring(d, RIM_INNER, RIM_OUTER, aa)
            coverage = max(coverage, ring(d, WELL - WELL_WIDTH / 2, WELL + WELL_WIDTH / 2, aa))
            coverage = max(coverage, disc(d, DOT, aa))
            r = round(paper[0] + (ink[0] - paper[0]) * coverage)
            g = round(paper[1] + (ink[1] - paper[1]) * coverage)
            b = round(paper[2] + (ink[2] - paper[2]) * coverage)
            row += bytes((r, g, b))
        rows.append(row)
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


if __name__ == "__main__":
    ICONSET.mkdir(parents=True, exist_ok=True)
    write_png(ICONSET / "icon-1024.png", render(ink=(0, 0, 0), paper=(255, 255, 255)))
    write_png(ICONSET / "icon-1024-dark.png", render(ink=(255, 255, 255), paper=(0, 0, 0)))
    # Tinted icons are greyscale on transparent in principle; iOS accepts an
    # opaque greyscale and applies the tint to the light parts.
    write_png(ICONSET / "icon-1024-tinted.png", render(ink=(235, 235, 235), paper=(40, 40, 40)))
    print(f"wrote 3 icons to {ICONSET.relative_to(ICONSET.parent.parent.parent)}")
