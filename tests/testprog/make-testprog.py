#!/usr/bin/env python3
"""make-testprog.py - builds this repository's Model 3 test program.

Assembles testprog.s into a 1 MiB program ROM (the top of the Model 3's
fixed program ROM window, 0xFFF00000-0xFFFFFFFF, where the reset vector
is), zips it as chimeratest.zip, and writes game.xml, the entry the core's
game list carries for it (build-supermodel.sh puts it in Games.xml), with
the ROM's CRC32. Supermodel finds a game's files by their CRC32, so the
entry and the zip must come from the same source: after a change to
testprog.s, run this and rebuild the core.

Usage: make-testprog.py <output folder>     (writes <folder>/chimeratest.zip)
"""
import os
import subprocess
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROM_NAME = "chimeratest-crom.bin"


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    rom = os.path.join(out, ROM_NAME)
    subprocess.check_call([sys.executable, os.path.join(HERE, "ppcasm.py"), os.path.join(HERE, "testprog.s"), rom, "0xFFF00000", "0x100000"])
    data = open(rom, "rb").read()
    crc = zlib.crc32(data) & 0xFFFFFFFF
    zpath = os.path.join(out, "chimeratest.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        info = zipfile.ZipInfo(ROM_NAME, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        z.writestr(info, data)
    xml = f"""  <!-- chimera-core-supermodel's own test program (tests/testprog), not a Sega game -->
  <game name="chimeratest">
    <identity>
      <title>Chimera Model 3 test program</title>
      <version>tests/testprog/testprog.s</version>
      <manufacturer>chimera-core-supermodel</manufacturer>
      <year>2026</year>
    </identity>
    <hardware>
      <platform>Sega Model 3</platform>
      <stepping>1.0</stepping>
      <inputs>
        <input type="common" />
        <input type="joystick1" />
        <input type="fighting" />
      </inputs>
    </hardware>
    <roms>
      <region name="crom" stride="4" chunk_size="4">
        <file offset="0" name="{ROM_NAME}" crc32="0x{crc:08X}" />
      </region>
    </roms>
  </game>
"""
    xml_path = os.path.join(HERE, "game.xml")
    if not os.path.exists(xml_path) or open(xml_path).read() != xml:
        open(xml_path, "w").write(xml)
        print(f"make-testprog: game.xml now names CRC32 0x{crc:08X}; rebuild the core")
    print(f"make-testprog: {zpath} (CRC32 0x{crc:08X})")


if __name__ == "__main__":
    main()
