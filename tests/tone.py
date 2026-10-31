#!/usr/bin/env python3
"""tone.py - what a run's sound is: its length in stereo samples, its
loudest sample, and its pitch from the zero crossings of the left channel's
second half. usage: tone.py sound.raw (16-bit stereo, as --audio writes)"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
s = struct.unpack("<%dh" % (len(d) // 2), d)
left = s[0::2]
half = left[len(left) // 2:]
crossings = sum(1 for i in range(1, len(half)) if (half[i - 1] < 0) != (half[i] < 0))
hz = crossings / 2 / len(half) * 44100 if half else 0
print(f"samples={len(left)} peak={max(abs(v) for v in s) if s else 0} hz={hz:.1f}")
