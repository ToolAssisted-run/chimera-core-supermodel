# Building and testing the Supermodel core

## Requirements

- Linux on x86-64, with GCC 14 (the guest kit's compiler is the system's,
  over miniBox's sysroot), Python 3, git, curl, `patch`, make, binutils.
- meson, ninja, cmake and Python's `mako` and `packaging` (LLVM's and
  Mesa's builds; `setup-mesa.sh` makes a private venv when they are missing).
- A Chimera checkout beside this one, with miniBox built: its host library
  (`meson-linux`) and its C++ guest toolchain (`meson-cpp`):

      mb=<chimera>/extern/chimera-common-minibox
      meson setup "$mb/build/meson-linux" "$mb" && meson compile -C "$mb/build/meson-linux"
      meson setup "$mb/build/meson-cpp" "$mb" -Dguest_cpp=true && meson compile -C "$mb/build/meson-cpp"

- For the frontend test: Chimera built (its `chimera-run` and its window).
  The window runs headless and needs no display; it needs the Qt 6 it was
  built against (`--qt <Qt's lib folder>` when the system does not find it).

## Sources

    git clone --recursive <this repository>
    git submodule update --init extern/supermodel

`extern/supermodel` is Supermodel at a pinned master commit (see
docs/PLAN.md). It is never built in: every build copies it to
`build/supermodel-src` and applies `patches/` there.

## The steps

All from the repository's root, with `-m <chimera>/extern/chimera-common-minibox`:

1. `waterbox/build-llvm.sh native` and `waterbox/build-llvm.sh guest -m
   <mb>`: LLVM 18.1.8 for llvmpipe (downloads the source once into
   `build/deps`; most of an hour each). Then `waterbox/setup-mesa.sh -n` and
   `waterbox/setup-mesa.sh -m <mb>`: Mesa 24.0.9's llvmpipe and OSMesa for
   this computer and the guest. The scripts are the Ikemen GO core's; where
   that core's `build/llvm-native`, `build/llvm-guest` and `build/mesa`
   already exist on the same machine (built against the same miniBox), a
   copy of them into this repository's `build/` saves the hours (the
   scripts see them built and stop).
2. `waterbox/make-native-libm.sh <mb>`: the sandbox's own math functions for
   the native build (`build/native-libm`).
3. `python3 tests/testprog/make-testprog.py build/tests`: the test program
   (`build/tests/chimeratest.zip`). It also rewrites
   `tests/testprog/game.xml`, the test program's entry in the core's game
   list, when the program changed.
4. `waterbox/build-supermodel.sh native -m <mb>` and
   `waterbox/build-supermodel.sh guest -m <mb>`: Supermodel and the core's
   frontend as static libraries (`build/<flavour>/obj`), at most 4 jobs
   (`-j N` for more).
5. `waterbox/link-core.sh native -m <mb>`: `build/native/run-native`, the
   native reference. `waterbox/link-core.sh guest -m <mb>`:
   `build/guest/core.wbx`, checked by miniBox's `check-wbx.sh`, and
   `build/guest/run-wbx`, which runs it in the sandbox.
6. `waterbox/build-package.sh -m <mb> -o <folder>` (or `-r <chimera>` to
   install it in that checkout's `build/Cores`): `supermodel.chimeraCore`.

A change to the controls is made in `tools/gen-inputs.py`, which writes
`waterbox/core/chimera_inputs.inc`, `waterbox/input-names.h`,
`waterbox/default_keybinds.json` and waterbox.config's `input`.

## The tests

- `waterbox/run-gate.sh -m <mb>`: builds everything, then the core's tests
  on the test program (native against sandbox, savestates, turbo, the
  controls, lag, the clock, the refusals). Each test says what it compared.
  `SUPERMODEL_ROMS=<folder>` adds the real game tests for the ROM sets named
  in the script that the folder holds (`SUPERMODEL_FRAMES` sets how long;
  vf3's movie plays a fight in 2400 frames, the others 1800 by default).
  The native run's pictures at a few frames stay in `build/gate`
  (`<set>-<frame>.tga`; `tools/tga2png.py` makes PNGs of them).
- `tests/run-frontend.sh --chimera-root <chimera> [--qt <Qt lib folder>]`:
  the package through `chimera-run` and through Chimera's window, headless.
  It writes nothing in the Chimera checkout. With `SUPERMODEL_ROMS` naming
  a folder that holds vf3.zip it also plays vf3's fight from a project,
  replays the movie chimera-run recorded in a new process, and opens the
  project in the window.
- Chimera's contract tests, against a folder holding only the package:

      <chimera>/build/meson-linux/source/ui/test-packages <folder>

- `python3 <chimera>/tools/check-core-texts.py <this repository>`: every key
  the code names is in the English table, and every key of it is named.

The runners take a work folder holding what Chimera would mount: the zip, a
`slots` file (`{"game":["chimeratest.zip"]}`) and a `settings` file. A movie
for them is a file of lines naming what is held each frame (`--movie`), or
`--press AT:TOKENS:LEN`; the names are waterbox.config's without spaces or
dashes (`P1Punch`, `P1Offscreen`), and axes are `NAME=value`
(`P1GunX=32768`).

## Troubleshooting

- Every picture black: the picture must be read from OSMesa's buffer after
  glFinish (EndFrameVideo); glReadPixels gave back zeros there.
- "missing required export Init": the core's library was not linked whole.
- The test program not found in the game list: `tests/testprog/game.xml`
  names another CRC32 than the zip; run make-testprog.py and rebuild.
- A build that stops early with no error: `patches/` did not apply, or
  `build/supermodel-src/.chimera-source` is stale; remove that folder.
