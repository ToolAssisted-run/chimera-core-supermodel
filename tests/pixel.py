#!/usr/bin/env python3
"""pixel.py - the colour of a pixel of a test harness picture (a 32-bit TGA,
top row first), as RRGGBB. usage: pixel.py picture.tga X Y"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
w, h = struct.unpack_from("<HH", d, 12)
x, y = int(sys.argv[2]), int(sys.argv[3])
off = 18 + d[0] + (y * w + x) * 4
b, g, r = d[off], d[off + 1], d[off + 2]
print(f"{r:02x}{g:02x}{b:02x}")
