#!/usr/bin/env python3
"""white-pixels.py - how many pixels of a test harness picture (a TGA, as
the harness writes them) are white or nearly (every channel above 235)
inside a rectangle, counted from the picture's top left.
usage: white-pixels.py picture.tga x0 y0 x1 y1   (x1 and y1 not included)"""
import struct
import sys

path, x0, y0, x1, y1 = sys.argv[1], *map(int, sys.argv[2:6])
d = open(path, "rb").read()
w, h = struct.unpack_from("<HH", d, 12)
n, top_first = d[16] // 8, d[17] & 0x20
px = d[18 + d[0]:]
count = 0
for y in range(y0, min(y1, h)):
    row = y if top_first else h - 1 - y
    for x in range(x0, min(x1, w)):
        i = (row * w + x) * n
        if min(px[i], px[i + 1], px[i + 2]) > 235:
            count += 1
print(count)
