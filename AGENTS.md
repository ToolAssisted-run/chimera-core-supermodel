# AGENTS.md - chimera-core-supermodel

Supermodel (Sega Model 3) as a Chimera core: the emulation on one thread,
drawn by its New3D renderer on Mesa's llvmpipe behind OSMesa inside the
core, with a frontend of the core's own. The user brings a game's ROM set
(a zip). Read Chimera's `docs/new-core.md` and this repository's
`docs/PLAN.md` first.

## Layout

- `extern/supermodel` - Supermodel, a submodule at a pinned commit. Never
  built in and never edited: `build-supermodel.sh` copies it to
  `build/supermodel-src` and applies `patches/` there.
- `patches/` - numbered patches to Supermodel, each a `SUPERMODEL_CHIMERA`
  build option or hook.
- `waterbox/core/` - the core: `chimera_core.cpp` (the calls Chimera makes,
  the start, memory domains), `chimera_osd.cpp` (OSMesa, the picture, the
  sound, no threads, no folders), `chimera_input.cpp` (Chimera's controls
  into Supermodel's inputs; its table `chimera_inputs.inc` is generated),
  `chimera_net.cpp` (the network the net board names: none),
  `chimera_wbx.c` (settings and slots).
- `waterbox/shim/` - headers found before upstream's (`SDLIncludes.h`,
  `GL/osmesa.h`).
- `waterbox/` - the scripts and the package's declarations
  (`waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json`, `languages/`), the harness (`gate-harness.h`,
  `run-native.c`, `run-wbx.c`, `input-names.h`), `run-gate.sh`.
- `tests/testprog/` - the test program: `testprog.s` (Model 3 PowerPC code
  of this repository's own: 2D layer, Real3D quad, controls, ADC, light
  gun, clock, backup RAM), `ppcasm.py` (its assembler), `make-testprog.py`
  (the 68000 sound program, the two ROM zips `chimeratest` and
  `chimeratestgun`, and `game.xml`, their entries in the core's game list).
- `tests/` - `run-frontend.sh` and its helpers, `pixel.py` (a pixel's
  colour), `rowbits.py` (the bytes the program shows as rows of tiles),
  `tone.py` (a sound's length, peak and pitch), `colours.py` (how many
  colours a picture holds: a drawn scene or a blank screen).
- `tools/gen-inputs.py` - the one list of controls.
- `build/` - every output. Ignored by git.

## Commands, in order

    mb=<chimera>/extern/chimera-common-minibox
    waterbox/build-llvm.sh native && waterbox/build-llvm.sh guest -m $mb
    waterbox/setup-mesa.sh -n && waterbox/setup-mesa.sh -m $mb
    waterbox/make-native-libm.sh $mb
    python3 tests/testprog/make-testprog.py build/tests
    waterbox/build-supermodel.sh native -m $mb && waterbox/build-supermodel.sh guest -m $mb
    waterbox/link-core.sh native -m $mb && waterbox/link-core.sh guest -m $mb
    waterbox/run-gate.sh -m $mb                      # the core's tests
    waterbox/build-package.sh -m $mb -o <folder>     # the package
    tests/run-frontend.sh --chimera-root <chimera> --qt <Qt lib folder>
    <chimera>/build/meson-linux/source/ui/test-packages <folder>

## Rules

- Nothing of the computer reaches the machine: no clock (the RTC is the
  Starting Clock and the frames, patch 0002), no thread (MultiThreaded is
  off and CThread refuses), no file but the project's, no network.
- The native reference links the sandbox's math (`make-native-libm.sh`).
- llvmpipe sees one baseline CPU everywhere (mesa-patches/0001).
- A change to the controls is made in `tools/gen-inputs.py` and its outputs
  committed; `run-gate.sh` refuses stale ones.
- A change to `tests/testprog/testprog.s` changes its CRC32: run
  `make-testprog.py` and commit `game.xml`.
- Patches: snapshot the file, edit a copy, `diff -u` (the sources have CRLF
  line ends; keep them).
- Every new test is broken on purpose once and seen to fail.
- No commercial ROM in the repository, its history or its tests; real game
  tests read `SUPERMODEL_ROMS` and SKIP without it.
- Names (Supermodel, Model 3, MAME, OpenGL, Chimera...) are never translated
  or given an ending in the language tables: a common noun goes beside the
  name instead. `tools/check-names.py` (the gate's "names" test) holds it;
  a new name in a text goes in its list.
- Write in plain language; prose is ASCII. Commits: `type(supermodel): what
  changed`, body with how it was tested, Chimera's trailers.
- Run builds and sandboxed runs under a memory cap (`systemd-run --user
  --scope -p MemoryMax=8G -p MemorySwapMax=0 ...`) and at most `-j4` on a
  shared machine.
