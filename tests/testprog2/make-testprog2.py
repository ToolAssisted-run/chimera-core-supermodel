#!/usr/bin/env python3
"""make-testprog2.py - builds this repository's Model 2 test program.

Assembles testprog2.s with i960asm.py into the program ROM, takes the sound
board's 68000 program from the Model 3 test program (the Model 2 has the same
board), makes the other three ROMs a Model 2 set must have (the data ROM, the
polygon ROM and the geometry processor's function tables: a few bytes each, the
program never reads them), zips the five as chimeratest2.zip, and writes game.xml,
the entry the core's game list carries for it (build-supermodel.sh puts it
in Games.xml), with the ROMs' CRC32s. Supermodel finds a game's files by
their CRC32, so the entry and the zip must come from the same source: after
a change to testprog2.s, run this and rebuild the core.

Usage: make-testprog2.py <output folder>     (writes <folder>/chimeratest2.zip)
"""
import importlib.util
import os
import subprocess
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "chimeratest2"
PROGRAM = "chimeratest2-program.bin"
SOUND = "chimeratest2-sound.bin"


def sound_program():
    """The sound board's 68000 program: the Model 3 test program's (a 441 Hz
    square wave on the first SCSP), its bytes in the order a Model 2 sound
    ROM file has. The Model 2's sound board is the same one, so the same
    program runs."""
    path = os.path.join(HERE, "..", "testprog", "make-testprog.py")
    spec = importlib.util.spec_from_file_location("make_testprog", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = module.sound_program()
    # the Model 2's sound ROM files are as the board reads them, a byte of
    # each 16-bit word swapped (MAME loads them with ROM_LOAD16_WORD_SWAP), where
    # the Model 3 test's region swaps them in the game list
    return b"".join(data[i + 1:i + 2] + data[i:i + 1] for i in range(0, len(data), 2))


# the ROMs the program does not use, each with its own contents
OTHERS = [
    ("main_data", "chimeratest2-data.bin", b"chimera-core-supermodel: Model 2 data ROM\0" * 4),
    ("polygons", "chimeratest2-polygons.bin", b"chimera-core-supermodel: Model 2 polygon ROM\0" * 4),
    ("copro_tables", "chimeratest2-tables.bin", b"chimera-core-supermodel: Model 2 function tables\0" * 4),
]


def entry(crcs):
    regions = "\n".join(
        f'      <region name="{region}" stride="1" chunk_size="1">\n'
        f'        <file offset="0" name="{fname}" crc32="0x{crcs[fname]:08X}" />\n'
        f"      </region>"
        for region, fname in [("program", PROGRAM), ("sound_program", SOUND)] + [(r, f) for r, f, _ in OTHERS])
    return f"""  <!-- chimera-core-supermodel's own test program (tests/testprog2), not a Sega game -->
  <game name="{NAME}">
    <identity>
      <title>Chimera Model 2 test program</title>
      <version>tests/testprog2/testprog2.s</version>
      <manufacturer>chimera-core-supermodel</manufacturer>
      <year>2026</year>
    </identity>
    <hardware>
      <platform>Sega Model 2</platform>
      <stepping>2A</stepping>
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
    rom = os.path.join(out, PROGRAM)
    subprocess.check_call([sys.executable, os.path.join(HERE, "i960asm.py"), os.path.join(HERE, "testprog2.s"), rom, "0x1000"])
    files = [(PROGRAM, open(rom, "rb").read()), (SOUND, sound_program())] + [(f, body) for _, f, body in OTHERS]
    crcs = {f: zlib.crc32(body) & 0xFFFFFFFF for f, body in files}
    zpath = os.path.join(out, NAME + ".zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for fname, body in files:
            info = zipfile.ZipInfo(fname, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, body)
    print(f"make-testprog2: {zpath} (program CRC32 0x{crcs[PROGRAM]:08X})")
    xml = entry(crcs)
    xml_path = os.path.join(HERE, "game.xml")
    if not os.path.exists(xml_path) or open(xml_path).read() != xml:
        open(xml_path, "w").write(xml)
        print("make-testprog2: game.xml changed; rebuild the core")


if __name__ == "__main__":
    main()
