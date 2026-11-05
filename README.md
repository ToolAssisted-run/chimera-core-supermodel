# chimera-core-supermodel

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, that runs **Sega Model 3** arcade games
with **[Supermodel](https://github.com/trzy/supermodel)**. It produces one
file, `supermodel.chimeraCore`, that goes in Chimera's `cores` folder.
Chimera issue 354.

## Status

Published: a dated nightly is made once a day when `main` moved and its
tests pass. Chimera's Core Manager lists it. Chimera issue 354.

Tested on Linux with this repository's own Model 3 test program (PowerPC
and 68000 code written here: the 2D layer, a Real3D polygon, the sound
board, the controls, the wheel, pedals and light gun, the clock, the backup
RAM), and with one real game, Virtua Fighter 3 (vf3): attract mode and a
fight, the same natively and in the sandbox, at about 18 frames a second in
the sandbox on a software OpenGL. On Windows, the published Chimera replays
the vf3 fight recorded on Linux to the same picture. No other game has been
tried, and nothing has run on a GPU (see [docs/PLAN.md](docs/PLAN.md),
"Where this stands").

- Supermodel's emulation with every board on one thread (the PowerPC main
  board, the sound board, the digital sound board, the drive boards), its
  clock counted in the machine's own cycles.
- The picture is drawn by Supermodel's New3D renderer and its 2D layers on a
  software OpenGL inside the core (Mesa's llvmpipe, made to generate the same
  code on every computer), at the Model 3's own 496x384. No GPU is used.
- Savestates are the sandbox's: the whole machine, the OpenGL's state
  included.
- Every control a Model 3 cabinet has: joysticks, fighting and soccer
  buttons, wheel, pedals and gear shifters, light guns (aimed across the
  picture, 0 to 65535), analog guns, twin sticks, the ski, fishing and truck
  controls. A game shows only those its cabinet has.

## What you bring

The game's ROM set: a `.zip` named as Supermodel and MAME name it (`vf3.zip`,
`scud.zip`, `srally2.zip`...). A clone's set needs its parent's zip too, in
the project's "Parent ROM set" slot. The Model 3 has no BIOS of its own.

## Settings

- **Starting Clock**: the date the Model 3's real-time clock shows at power
  on (movies need the same value).
- **Idle Skip**: upstream's skipping of the processor's idle loops, on by
  default as upstream has it (part of the machine).
- **Drawing Scale**: 1x (the Model 3's 496x384) to 4x; the picture only.

What a game remembers (its EEPROM and backup RAM) goes in and out as
Supermodel's own NVRAM file, `<game>.nv`: Emulator > Export Save Data
writes it, a project's "Save data" slot takes it. RAM Watch and RAM Search
see the main RAM and the backup RAM in the PowerPC's byte order.

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT. Supermodel is GPL-3.0-or-later, so the
built core is distributed under the GPL-3.0-or-later; Mesa is MIT, LLVM
Apache 2.0 with the LLVM exception, and the libraries inside Supermodel are
under their own permissive terms. The package carries every licence text.
See [LICENSE](LICENSE).
