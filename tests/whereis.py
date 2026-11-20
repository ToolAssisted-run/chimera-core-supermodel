#!/usr/bin/env python3
"""whereis.py - where a colour is in a picture: the left-most x and the top y
of the pixels that have it, and how many there are ("none" if no pixel has).
Reads a 32-bit TGA, top row first, as the test runners write (pixel.py).

usage: whereis.py <picture.tga> <RRGGBB>"""
import struct
import sys

data = open(sys.argv[1], "rb").read()
w, h = struct.unpack_from("<HH", data, 12)
bpp = data[16] // 8
want = bytes.fromhex(sys.argv[2])
found = []
for y in range(h):
    row = data[18 + y * w * bpp: 18 + (y + 1) * w * bpp]
    for x in range(w):
        b, g, r = row[x * bpp + 0], row[x * bpp + 1], row[x * bpp + 2]
        if bytes((r, g, b)) == want:
            found.append((x, y))
if not found:
    print("none")
else:
    print(min(p[0] for p in found), min(p[1] for p in found), len(found))
