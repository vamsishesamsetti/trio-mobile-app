#!/usr/bin/env python3
"""Generates assets/icon.png (1024x1024) with no third-party deps.

Design: brand-indigo background with three ascending rounded white bars,
representing Trio's three trackers (Money / Split / Hours).
Run: python3 tool/generate_icon.py
"""
import os
import struct
import zlib

SIZE = 1024
BRAND = (79, 109, 245)      # #4F6DF5
BRAND_DK = (60, 86, 210)    # subtle gradient bottom
WHITE = (255, 255, 255)

def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))

def rounded_rect(px, x0, y0, x1, y1, r, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            # corner rounding
            cx = min(max(x, x0 + r), x1 - r - 1)
            cy = min(max(y, y0 + r), y1 - r - 1)
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r or (x0 + r <= x < x1 - r) or (y0 + r <= y < y1 - r):
                px[y][x] = color

def build():
    # vertical gradient background
    px = [[lerp(BRAND, BRAND_DK, y / SIZE) for _ in range(SIZE)] for y in range(SIZE)]

    # three ascending bars
    bar_w = 150
    gap = 70
    total_w = bar_w * 3 + gap * 2
    start_x = (SIZE - total_w) // 2
    base_y = 740
    heights = [300, 430, 560]
    radius = 60
    for i, h in enumerate(heights):
        x0 = start_x + i * (bar_w + gap)
        rounded_rect(px, x0, base_y - h, x0 + bar_w, base_y, radius, WHITE)
    return px

def write_png(px, path):
    raw = bytearray()
    for row in px:
        raw.append(0)  # filter type 0
        for (r, g, b) in row:
            raw += bytes((r, g, b))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))

if __name__ == "__main__":
    os.makedirs("assets", exist_ok=True)
    px = build()
    write_png(px, "assets/icon.png")
    print("Wrote assets/icon.png")
