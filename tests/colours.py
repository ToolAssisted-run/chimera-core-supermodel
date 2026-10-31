#!/usr/bin/env python3
"""colours.py - how many different colours a test harness picture (a 32-bit
TGA) holds. A black or blank picture holds one or two; a textured, lit 3D
scene thousands. usage: colours.py picture.tga"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
w, h = struct.unpack_from("<HH", d, 12)
px = d[18 + d[0]:18 + d[0] + w * h * 4]
print(len({px[i:i + 3] for i in range(0, len(px), 4)}))
