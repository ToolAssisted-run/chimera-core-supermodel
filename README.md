# chimera-core-supermodel

A core for [Chimera](https://github.com/ToolAssisted-run/chimera), the
frontend for tool-assisted speedruns, that runs **Sega Model 1, Model 2 and
Model 3** arcade games with **[Supermodel](https://github.com/trzy/supermodel)**.
It produces one file, `supermodel.chimeraCore`, that goes in Chimera's `cores`
folder. Chimera issues 354 (Model 3) and 627 (Model 1 and Model 2).

## Status

Published: a dated nightly is made once a day when `main` moved and its
tests pass. Chimera's Core Manager lists it. Chimera issue 354.

**Model 3**: tested on Linux with this repository's own Model 3 test program
(PowerPC and 68000 code written here: the 2D layer, a Real3D polygon, the sound
board, the controls, the wheel, pedals and light gun, the clock, the backup
RAM), and with real games: Virtua Fighter 3 (vf3: attract mode and a fight, the
same natively and in the sandbox, at about 18 frames a second in the sandbox on a
software OpenGL) and Scud Race (scud). On Windows, the published Chimera replays
the vf3 fight recorded on Linux to the same picture. The core follows Supermodel
as of 2026-11-19 (commit 596f154, 107 commits after the earlier pin): on Scud Race
a movie played by the earlier core plays on this one to the same pictures, the same
steps and the same cycles, with different sound (upstream changed the digital sound
board and the sound board's MIDI port); no other game could be tried after the
change, so another game's movie may not replay the same.

**Model 2**: tested on Linux with this repository's own Model 2 test program
(i960 code written here: the tile layer, the controls, the backup RAM, the sound
board's square wave, the frame loop). **No Model 2 game has been run**: there was
none to run (no Model 2 set was on the machine that built this). Only what that
program uses is proved; the 3D, the geometry processor, the games' own sound
programs, the light guns, the wheels and the rest are Supermodel's own code, built
into the core, never seen working here.

**Model 1**: only a start-up test (a set whose processor does nothing): the
machine starts, runs and saves in the sandbox as it does natively. **No Model 1
game has been run, and no Model 1 program either**; Model 1 is the least tested.

Nothing has run on Windows or macOS with the Model 1 and Model 2, and nothing
has run on a GPU (see [docs/PLAN.md](docs/PLAN.md), "Where this stands" and
the section of 2026-11-20).

- Supermodel's emulation with every board on one thread (the main board, the
  sound boards, the geometry processors, the drive boards), its clock counted
  in the machine's own cycles.
- The picture is drawn by Supermodel's renderers (New3D for the Model 3, one of
  its own for the Model 1 and Model 2) and its 2D layers on a software OpenGL
  inside the core (Mesa's llvmpipe, made to generate the same code on every
  computer), at the machines' own 496x384. No GPU is used.
- Savestates are the sandbox's: the whole machine, the OpenGL's state
  included.
- Every control a Model 1, Model 2 or Model 3 cabinet has: joysticks, fighting and soccer
  buttons, wheel, pedals and gear shifters, light guns (aimed across the
  picture, 0 to 65535), analog guns, twin sticks, the ski, fishing and truck
  controls, a throttle, flight view buttons and a second analog stick. A game
  shows only those its cabinet has.

## What you bring

The game's ROM set: a `.zip` named as Supermodel and MAME name it (`vf3.zip`,
`scud.zip`, `srally2.zip`...). A clone's set needs its parent's zip too, in
the project's "Parent ROM set" slot. None of the three machines has a BIOS of
its own.

A game runs on the machine it was made for, and the project's **Machine**
setting says which: Sega Model 3 (the default), Sega Model 2 or Sega Model 1.
A game for another machine than the setting is refused with a message that
names the right one. A zip opened with no project is a Model 3 game.

## Settings

- **Machine**: Sega Model 3, Model 2 or Model 1 (part of the machine: a movie
  needs the same value).
- **Starting Clock** (Model 3): the date the Model 3's real-time clock shows
  at power on (movies need the same value).
- **Idle Skip** (Model 3): upstream's skipping of the processor's idle loops,
  on by default as upstream has it (part of the machine).
- **Transparency** (Model 1 and Model 2): how translucent polygons are drawn,
  as upstream's `-transparency`: Original (a checkerboard of single pixels),
  Moire (the checkerboard of the original 496x384 grid, scaled) or Blend (half
  of each colour); the picture only.
- **Drawing Scale**: 1x (496x384) to 4x; the picture only.

Not offered: upstream's `-no-high-level-geometrizer` (the Model 1 and Model 2
geometry processor run as the board's own DSP programs, on a thread for each
chip as the computer allows). The core always uses the simulated geometry
processor, upstream's default, so that the machine does not depend on how many
processors the computer has.

What a game remembers (its EEPROM and backup RAM) goes in and out as
Supermodel's own NVRAM file, `<game>.nv`: Emulator > Export Save Data
writes it, a project's "Save data" slot takes it. RAM Watch and RAM Search
see the main RAM and the backup RAM in the PowerPC's byte order (Model 3), or the
RAM and the backup RAM as the machine has it, little-endian (Model 1 and Model 2).

## Building and testing

[docs/BUILDING.md](docs/BUILDING.md) has every step. [docs/PLAN.md](docs/PLAN.md)
is the design log: what was decided, why, and what was measured.

## Licence

This repository's own code is MIT. Supermodel is GPL-3.0-or-later, so the
built core is distributed under the GPL-3.0-or-later; Mesa is MIT, LLVM
Apache 2.0 with the LLVM exception, and the libraries inside Supermodel are
under their own permissive terms. The package carries every licence text.
See [LICENSE](LICENSE).
