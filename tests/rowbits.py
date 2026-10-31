#!/usr/bin/env python3
"""rowbits.py - the bytes the test program shows on rows of tiles: eight
cells from column 2, red where a bit is 1 and blue where it is 0, bit 0
leftmost. Prints each row's byte as two hex digits, or "??" for a row that
is not such a row. usage: rowbits.py picture.tga ROW [ROW...]"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
w, h = struct.unpack_from("<HH", d, 12)
base = 18 + d[0]


def colour(x, y):
    off = base + (y * w + x) * 4
    return "%02x%02x%02x" % (d[off + 2], d[off + 1], d[off])


out = []
for row in sys.argv[2:]:
    y = int(row) * 8 + 2
    byte = 0
    for b in range(8):
        c = colour((2 + b) * 8 + 4, y)
        if c == "ff0000":
            byte |= 1 << b
        elif c != "0000ff":
            byte = None
            break
    out.append("??" if byte is None else "%02x" % byte)
print(" ".join(out))
