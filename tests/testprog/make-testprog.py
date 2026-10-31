#!/usr/bin/env python3
"""make-testprog.py - builds this repository's Model 3 test program.

Assembles testprog.s into a 1 MiB program ROM (the top of the Model 3's
fixed program ROM window, 0xFFF00000-0xFFFFFFFF, where the reset vector
is), makes the sound board's program (sound_program below: a few 68000
instructions that play a square wave on the first SCSP), zips both as
chimeratest.zip, and writes game.xml, the entry the core's game list
carries for it (build-supermodel.sh puts it in Games.xml), with the ROMs'
CRC32s. Supermodel finds a game's files by their CRC32, so the
entry and the zip must come from the same source: after a change to
testprog.s, run this and rebuild the core.

Two sets are made from the one program, told apart by the program ROM's
last byte: chimeratest (a joystick and fighting buttons) and chimeratestgun
(a wheel, pedals and a light gun), so that each cabinet's inputs reach it.

Usage: make-testprog.py <output folder>     (writes <folder>/chimeratest.zip
                                             and chimeratestgun.zip)
"""
import os
import subprocess
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROM_NAME = "chimeratest-crom.bin"
SND_NAME = "chimeratest-snd.bin"


def sound_program():
    """The sound board's 68000 program, big-endian, at 0x600000 in its
    address space (the board copies its first 16 bytes, the reset vectors,
    to RAM at 0). It writes 100 samples of a square wave (50 high, 50 low:
    441 Hz at the SCSP's 44100 Hz) into SCSP 1's RAM at 0x10000, sets up
    slot 0 to loop them at full volume in the middle, keys it on, and
    stops in a loop. Hand-encoded: each line is an instruction."""
    w = []

    def op(*words):
        w.extend(words)

    def long(v):
        return [(v >> 16) & 0xFFFF, v & 0xFFFF]

    op(*long(0x000FFF00), *long(0x00600100))          # reset vectors: SSP, PC
    w.extend([0] * ((0x100 - len(w) * 2) // 2))
    op(0x41F9, *long(0x00010000))                     # lea $10000,a0
    op(0x303C, 49)                                    # move.w #49,d0
    op(0x30FC, 0x4000)                                # .hi: move.w #$4000,(a0)+
    op(0x51C8, (-6) & 0xFFFF)                         # dbra d0,.hi (to PC + 2 - 6)
    op(0x303C, 49)                                    # move.w #49,d0
    op(0x30FC, 0xC000)                                # .lo: move.w #$C000,(a0)+
    op(0x51C8, (-6) & 0xFFFF)                         # dbra d0,.lo
    op(0x33FC, 0x000F, *long(0x00100400))             # move.w #$000F,$100400 (master volume)
    op(0x43F9, *long(0x00100000))                     # lea $100000,a1 (slot 0)
    for off, val in ((0x02, 0x0000),                  # SA low: 0x10000 with the 1 below
                     (0x04, 0x0000),                  # LSA
                     (0x06, 100),                     # LEA
                     (0x08, 0x001F),                  # AR 31
                     (0x0A, 0x001F),                  # RR 31
                     (0x0C, 0x0000),                  # TL 0
                     (0x0E, 0x0000),
                     (0x10, 0x0000),                  # OCT 0, FNS 0: 44100 Hz
                     (0x12, 0x0000),
                     (0x14, 0x0000),
                     (0x16, 0xE000)):                 # DISDL 7, DIPAN 0
        op(0x337C, val, off)                          # move.w #val,off(a1)
    op(0x32BC, 0x1821)                                # move.w #$1821,(a1): KEYONEX, KEYONB, loop, SA high 1
    op(0x60FE)                                        # bra.s *
    data = b"".join(x.to_bytes(2, "big") for x in w)
    return data + b"\0" * (0x1000 - len(data))


# The two cabinets the program is tested in: (set name, title, the last byte
# of the program ROM, which only tells the two sets apart, the input types)
CABINETS = [
    ("chimeratest", "Chimera Model 3 test program", 0, ["common", "joystick1", "fighting"]),
    ("chimeratestgun", "Chimera Model 3 test program (wheel, pedals and light gun)", 1, ["common", "vehicle", "gun1"]),
]


def entry(name, title, crc, snd_crc, inputs):
    ins = "\n".join(f'        <input type="{i}" />' for i in inputs)
    return f"""  <!-- chimera-core-supermodel's own test program (tests/testprog), not a Sega game -->
  <game name="{name}">
    <identity>
      <title>{title}</title>
      <version>tests/testprog/testprog.s</version>
      <manufacturer>chimera-core-supermodel</manufacturer>
      <year>2026</year>
    </identity>
    <hardware>
      <platform>Sega Model 3</platform>
      <stepping>1.0</stepping>
      <inputs>
{ins}
      </inputs>
    </hardware>
    <roms>
      <region name="crom" stride="4" chunk_size="4">
        <file offset="0" name="{ROM_NAME}" crc32="0x{crc:08X}" />
      </region>
      <region name="sound_program" stride="2" chunk_size="2">
        <file offset="0" name="{SND_NAME}" crc32="0x{snd_crc:08X}" />
      </region>
    </roms>
  </game>
"""


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    rom = os.path.join(out, ROM_NAME)
    subprocess.check_call([sys.executable, os.path.join(HERE, "ppcasm.py"), os.path.join(HERE, "testprog.s"), rom, "0xFFF00000", "0x100000"])
    program = open(rom, "rb").read()
    snd = sound_program()
    snd_crc = zlib.crc32(snd) & 0xFFFFFFFF
    xml = ""
    for name, title, last, inputs in CABINETS:
        data = program[:-1] + bytes([last])
        crc = zlib.crc32(data) & 0xFFFFFFFF
        zpath = os.path.join(out, name + ".zip")
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            for fname, body in ((ROM_NAME, data), (SND_NAME, snd)):
                info = zipfile.ZipInfo(fname, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                z.writestr(info, body)
        xml += entry(name, title, crc, snd_crc, inputs)
        print(f"make-testprog: {zpath} (CRC32s 0x{crc:08X}, 0x{snd_crc:08X})")
    xml_path = os.path.join(HERE, "game.xml")
    if not os.path.exists(xml_path) or open(xml_path).read() != xml:
        open(xml_path, "w").write(xml)
        print("make-testprog: game.xml changed; rebuild the core")


if __name__ == "__main__":
    main()
