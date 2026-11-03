#!/usr/bin/env python3
"""down-across.py - how fast a test harness picture (a TGA, as the harness
writes them) changes down the screen against across it, inside a rectangle
counted from the picture's top left: the mean colour difference between a
pixel and the one below it, over the mean difference between a pixel and
the one to its right, times 100. A texture smeared down the screen (issue
479: vf3's floor near the camera) changes less going down and gives about
150; the floor drawn right gives about 270.
usage: down-across.py picture.tga x0 y0 x1 y1   (x1 and y1 not included)"""
import struct
import sys

path, x0, y0, x1, y1 = sys.argv[1], *map(int, sys.argv[2:6])
d = open(path, "rb").read()
w, h = struct.unpack_from("<HH", d, 12)
n, top_first = d[16] // 8, d[17] & 0x20
px = d[18 + d[0]:]


def at(x, y):
    row = y if top_first else h - 1 - y
    i = (row * w + x) * n
    return px[i:i + 3]


down = across = 0
for y in range(y0, min(y1, h) - 1):
    for x in range(x0, min(x1, w) - 1):
        a, b, c = at(x, y), at(x, y + 1), at(x + 1, y)
        down += sum(abs(a[k] - b[k]) for k in range(3))
        across += sum(abs(a[k] - c[k]) for k in range(3))
print(100 * down // max(across, 1))
