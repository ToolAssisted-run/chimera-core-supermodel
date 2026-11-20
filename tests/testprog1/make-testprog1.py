#!/usr/bin/env python3
"""make-testprog1.py - builds this repository's Model 1 test set.

This is a start-up test, not a program: it only shows that a Model 1 starts
and runs in the sandbox as it does natively. The Model 1's processor (an NEC
V60) starts at 0xFFFFFFF0, the last 16 bytes of the boot ROM, and the set's
boot ROM holds, there, one instruction that jumps to itself (BR16 with a
displacement of 0, bytes 7A 00 00), and NOPs (CD) everywhere else. So the
processor runs, every frame, nothing: it reads no control, draws nothing and
plays nothing. What does run is the rest of the machine: the video board, the
tile layers drawn through the OpenGL renderer, the sound board's 68000 (with no
program), the I/O board, the clock and the frame loop.

The set has the other three ROMs a Model 1 must have (the geometry
processor's function tables and polygon ROM: a few bytes each). It is zipped
as chimeratest1.zip, and game.xml is its entry in the core's game list
(build-supermodel.sh puts it in Games.xml), with the ROMs' CRC32s.

Usage: make-testprog1.py <output folder>     (writes <folder>/chimeratest1.zip)
"""
import os
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "chimeratest1"


def boot_rom():
    rom = bytearray(b"\xCD" * 0x80000)          # NOP
    rom[0x7FFF0:0x7FFF3] = b"\x7A\x00\x00"      # BR16 to itself
    return bytes(rom)


FILES = [
    ("rom_boot", "chimeratest1-boot.bin", boot_rom()),
    ("copro_tables", "chimeratest1-tables.bin", b"chimera-core-supermodel: Model 1 function tables\0" * 4),
    ("polygons", "chimeratest1-polygons.bin", b"chimera-core-supermodel: Model 1 polygon ROM\0" * 4),
]


def entry(crcs):
    regions = "\n".join(
        f'      <region name="{region}" stride="1" chunk_size="1">\n'
        f'        <file offset="0" name="{fname}" crc32="0x{crcs[fname]:08X}" />\n'
        f"      </region>"
        for region, fname, _ in FILES)
    return f"""  <!-- chimera-core-supermodel's own start-up test (tests/testprog1), not a Sega game -->
  <game name="{NAME}">
    <identity>
      <title>Chimera Model 1 start-up test</title>
      <version>tests/testprog1/make-testprog1.py</version>
      <manufacturer>chimera-core-supermodel</manufacturer>
      <year>2026</year>
    </identity>
    <hardware>
      <platform>Sega Model 1</platform>
      <inputs>
        <input type="common" />
        <input type="joystick1" />
        <input type="joystick2" />
        <input type="fighting" />
      </inputs>
    </hardware>
    <roms>
{regions}
    </roms>
  </game>
"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    crcs = {f: zlib.crc32(body) & 0xFFFFFFFF for _, f, body in FILES}
    zpath = os.path.join(out, NAME + ".zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for _, fname, body in FILES:
            info = zipfile.ZipInfo(fname, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, body)
    print(f"make-testprog1: {zpath}")
    xml = entry(crcs)
    xml_path = os.path.join(HERE, "game.xml")
    if not os.path.exists(xml_path) or open(xml_path).read() != xml:
        open(xml_path, "w").write(xml)
        print("make-testprog1: game.xml changed; rebuild the core")


if __name__ == "__main__":
    main()
