# The Supermodel core: plan and design log

Chimera issue 354 asks for Supermodel, the Sega Model 3 arcade emulator
(https://github.com/trzy/supermodel). What was decided, why, and what was
measured. Newest last.

## The answers before any code (2026-10-31)

These answer section 1 of Chimera's `docs/new-core.md`, read from upstream's
source at the commit this repository pins (`extern/supermodel`,
036af1c8d6640c5a60709c1f99144635ed82a184, 2026-10-29, "Add skip idle
function for faster powerpc emulation"). Upstream has no recent release
(0.3a is from 2017 and is far behind); its master branch is what everybody
builds, so the core pins a master commit.

- **A new core?** Yes. No core here emulates the Model 3. MAME has a Model 3
  driver, but it is marked not working in MAME and the MAME core does not
  build it; Supermodel is the emulator that plays these games.
- **Licence.** Supermodel is GPL-3.0-or-later (`Docs/LICENSE.txt`). The
  packages it carries in `Src/Pkgs` are permissive: GLEW (modified BSD and
  MIT), minizip/unzip (zlib licence), tinyxml2 (zlib licence), minimp3 (CC0),
  Dear ImGui (MIT, not built here). Musashi, the 68000 core, carries
  Supermodel's GPL header ("Permission was obtained from Karl Stenerud to
  apply the GPL license to this code"); the Z80 core is Frank D. Cringle's,
  adapted, under Supermodel's GPL header as well. Binary and modified redistribution are allowed under the GPL
  when the source goes with it: this repository is the source, its patches
  are the changes. The package carries every text. Mesa (MIT) and LLVM
  (Apache-2.0 with the LLVM exception) come in for the software OpenGL; both
  may be combined with GPL-3 code.
- **One thread on one clock?** Yes. Supermodel runs every board on threads of
  its own by default (the PowerPC main board, the sound board, the drive
  board, the billboard), but `-no-threads` (config `MultiThreaded=0`) runs
  them all in turn on one thread, once a frame: `CModel3::RunFrame` then
  runs the main board for a frame, syncs the graphics chips, draws, runs the
  sound board for a frame (`44100 / 57.524` samples, the remainder carried),
  then the drive board and the billboard. Time inside is counted in emulated
  cycles: the PowerPC gets `frequency / 57.524160` cycles a frame (66, 100 or
  166 MHz by board stepping), the 68000 of the sound board 256 cycles a
  sample. Nothing in the emulation reads the computer's clock except:
  `CThread::GetTicks` for timing statistics only (never fed back), and the
  RTC72421 real-time clock chip, which reads `time()` and `localtime()`: a
  patch makes it read the machine's own clock (a Starting Clock setting plus
  the frames run). Crypto's `rand()` in `Pkgs/crypt.h` is minizip's for
  writing encrypted zips, which is never reached.
- **The picture.** Supermodel draws only with OpenGL: its "New3D" renderer
  (the default) needs OpenGL 4.1 core with geometry shaders, the "Legacy3D"
  renderer OpenGL 2.1; the 2D tile layers are drawn with GL shaders too. So
  the route is the software OpenGL inside the core, as the Godot and Ikemen
  GO cores have it: Mesa 24.0.9's llvmpipe behind OSMesa, LLVM 18.1.8, with
  the patch that tells llvmpipe of one baseline x86-64 CPU on every computer
  (the code it makes for a shader, and so every picture, is the same bytes
  everywhere, and it starts no threads). llvmpipe offers OpenGL 4.5 core.
  The picture is read back with glReadPixels after each frame. The GPU
  bridge comes later (not in this round) and never as the only renderer.
  The picture does not feed the machine: the Real3D's status bits are timed
  in cycles by the emulation, not by the renderer. This has to be proved
  (instruction count with drawing on and off), and the core gate does.
- **A recompiler?** No. Supermodel's PowerPC 603e core (`Src/CPU/PowerPC`,
  from MAME's old ppc core) is an interpreter; the 68000 is Musashi (an
  interpreter); the Z80 an interpreter. Upstream's newest commit adds an
  "idle skip" that jumps over idle loops polling RAM: it is deterministic
  (it reads the machine's own state) but changes how many cycles a game
  spends, so it is part of the machine and off unless a setting turns it on.
- **What the user must bring.** The game's ROM set, a zip named as MAME
  names it (vf3.zip, scud.zip, srally2.zip...), whose files Supermodel finds
  by their CRC32 through its game list (`Config/Games.xml`, 64 games and
  clones, carried in the core). A clone's set needs its parent's zip too
  (the parent as a second file of the project). No BIOS: the Model 3 has
  none outside each game's own ROMs. Nothing of any game is in this
  repository.
- **What CI can run.** There is no free Model 3 software. CI can prove the
  builds (native and sandbox), the sandbox's rules (check-wbx), the package
  (Chimera's contract tests), and a test program this repository makes
  itself: a small PowerPC program assembled by a script here, with its own
  entry in a test game list, which boots on the Model 3 as a game's ROM does,
  draws with the 2D tile generator (through the OpenGL renderer), reads the
  controls and runs the sound board. What it cannot stand in for: the 3D
  renderer with a real game's models and textures, the MPEG sound board
  (DSB), the drive boards, and a real game's timing. Those tests run where a
  ROM set is (an environment variable names it), and SKIP with the reason
  where it is not.
- **Size.** Supermodel takes one pool of about 250 MiB for the machine (8 MiB
  RAM, the 8 MiB and 128 MiB program ROM windows, 64 MiB of video ROM, 16
  MiB of samples, 16 MiB of MPEG ROM and small blocks), plus the Real3D's
  memories (polygon, texture, culling RAM) and the renderers' buffers, plus
  Mesa's. The first layout gives 1 GiB of heap and 3 GiB of mmap space.

The answer: feasible, with the software OpenGL first. The owner's questions
are listed at the end of this file.

## The core, first round (2026-10-31)

- **The build.** `waterbox/build-supermodel.sh` copies the submodule to
  `build/supermodel-src`, applies `patches/`, generates the 68000 core with
  upstream's own generator, and compiles the emulation and the core's
  frontend (`waterbox/core/`) with `waterbox/supermodel.mk`, for the native
  reference and for the sandbox. Not built: upstream's SDL frontend (the
  core is the frontend), the network, the debugger, Dear ImGui, the Pro-1000
  board, and the Legacy3D renderer (OpenGL 2.1 with GLU; New3D, upstream's
  default, is the renderer). zlib (for the zips) is the one Mesa's build
  carries, in both builds.
- **LLVM and Mesa** are the Ikemen GO core's: the same scripts
  (`build-llvm.sh`, `setup-mesa.sh`, `mesa-patches/0001`), LLVM 18.1.8 and
  Mesa 24.0.9; on this machine the built trees were copied from
  `chimera-cores/ikemen/build` instead of building LLVM again (the scripts
  build them from the pinned tarballs where they are not there, as CI
  would).
- **The frontend** (`waterbox/core/`): `chimera_core.cpp` does what upstream's
  Main.cpp does to start a game (the game list, the zip, the Model 3, the
  renderers) with the core's configuration (one thread, no network, the
  hardware's 57.524 Hz); `chimera_osd.cpp` answers Supermodel's OSD calls
  (OSMesa as the window, the picture read from OSMesa's buffer after
  glFinish, the sound mixed to stereo as upstream mixes for two speakers, no
  threads, no folders); `chimera_input.cpp` writes Chimera's controls into
  Supermodel's inputs before each frame (upstream's input polling is not
  used); `chimera_net.cpp` stands in for the network the net board names.
- **Patches** (each a `SUPERMODEL_CHIMERA` build option):
  0001 the game list can be handed over as text (the core carries
  Games.xml); 0002 the RTC72421 reads the machine's clock (Starting Clock
  plus frames, UTC); 0003 a read of the input registers is told to the core
  (lag frames); 0004 a clone's parent set is the file the core names (the
  project's "parent" file); 0005 New3D gives the window back its front
  buffer, not GL_BACK (OSMesa's window has no back buffer: every picture
  was black until this).
- **The controls** are one list, `tools/gen-inputs.py`, which writes the
  C++ table, the test harness's names and waterbox.config's input
  declaration: 79 buttons and 20 axes, every control a Model 3 cabinet has,
  each tied to the cabinets (Games.xml's input types) that have it, so a
  game shows only its own (IsButtonActive, IsAxisActive). Wheels, sticks and
  levers are -32768..32767, pedals 0..32767, a gun's aim 0..65535 across the
  picture (Chimera's absolute axes), mapped onto the ranges upstream gives
  each input (a light gun's 150..651 and 80..465 among them).
- **The test program** (`tests/testprog`): Model 3 PowerPC code written for
  this repository and assembled by its own small assembler (`ppcasm.py`),
  with an entry of its own in the core's game list ("chimeratest", Step
  1.0). It waits for the tile generator's IRQ 0x02 each frame, reads the
  controls (but on one frame in eight), moves a block with the joystick,
  shows the control bytes' bits and the real-time clock's minutes and
  seconds as tiles. Learnt making it: the tile generator is a
  little-endian chip on the big-endian bus, so the PowerPC writes palette
  entries and name-table entries byte-reversed, and the pair's left entry
  in the word's second half.

Measured (2026-10-31, on this machine, against Chimera at
~/chimera-scratch-bump 3f8ea7e2, miniBox 7216594):

- `waterbox/run-gate.sh`: 16 passed, 0 failed, 4 skipped (the four real
  game tests, no ROM sets here). The test program, 600 frames with the
  joystick, buttons, coins and service pressed: native = sandbox in every
  picture, the sound, every step, the lag frames and the PowerPC's cycle
  count (344,094,960 cycles over 300 frames: 66 MHz / 57.524); saving and
  loading before every frame, and saving at frame 160 into a new host, land
  where the straight run does; a state is 17.7 MB. Turbo (no drawing for
  the first half) leaves the steps, the sound and the cycle count as they
  are: drawing does not change the machine.
- Broken on purpose once, in one build: the controls not written, the lag
  hook always reporting a read, and turbo ignored. Failed exactly turbo,
  teeth, both control tests and lag (11 passed, 5 failed). The clock test
  carries its own control: upstream's RTC72421.cpp (the computer's clock)
  linked into a second native build, where a 3-second stall changes the
  pictures.
- Speed: the test program runs 300 frames in 3.4 s natively and 5.9 s in the
  sandbox (llvmpipe drawing two 496x384 layers a frame).

## The package and the frontend test (2026-10-31)

- **What it declares.** System id `Model3` ("Sega Model 3"); the picture
  496x384 at 57.524 frames a second (57524/1000); stereo sound at 44100 Hz,
  766 or 767 samples a frame; lag frames from the input hook; two settings,
  Starting Clock (a date, 2000-01-01 by default) and Idle Skip (upstream's
  default, on); two file slots, the game's zip and a clone's parent zip; no
  firmware (the Model 3 has no BIOS apart from each game's ROMs). The
  controls, the mnemonics, the players' groups and the default bindings are
  generated by `tools/gen-inputs.py`: upstream's default keys (1 and 2
  start, 3 and 4 coins, 5 to 8 service and test, the arrows and A S D F),
  the first and second game controllers as the two players' panels, wheel
  and pedals on the first controller's stick and triggers, the light gun on
  the mouse.
- **Memory domains**: Main RAM (8 MiB) and Backup RAM (128 KiB), as
  Supermodel keeps them (32-bit words in the computer's byte order: a
  PowerPC byte at address A is the domain's byte A ^ 3). Patch 0006 gives
  the core their pointers. Chimera requires the five domain exports.
- **Texts**: 14 keys, in Chimera's 26 languages; English written here, the
  other 25 translated from it by an AI model (Claude), as the other cores'
  were; nobody who speaks them has read them yet.
- **Licences**: the package carries the texts of this repository (MIT),
  Supermodel (GPL-3.0-or-later), GLEW, minizip, TinyXML-2, minimp3 (the
  licence comments of Supermodel's copies, extracted into
  `waterbox/licenses/`), Mesa, the zlib Mesa's build makes (it reads the
  zips) and LLVM. Mesa's expat is built but not linked into the core
  (checked with nm).

Measured (2026-10-31, Chimera 3f8ea7e2):

- Chimera's contract tests on the package alone: 21 passed, 0 failed. With
  one binding broken on purpose (P1 Up bound to "UpArrow", which no key is
  called) the keys test failed and named it.
- `check-core-texts.py`: 14 keys, every one named, every name a key.
- `tests/run-frontend.sh` with Chimera's window (Qt 6.12, headless): 5 ok, 0
  failed. 300 frames of the test program from a movie made into a project by
  chimera-run, the same movie in a hand-written project, and the same
  project opened in the window: each last picture is the native reference's,
  every pixel; the 79 controls the window lists carry the package's
  bindings. The first run found that Chimera refuses a core without the
  memory domain exports (hence patch 0006).
- The package is 31 MB (core.wbx 88 MB before packing).
- `waterbox/run-gate.sh` again after patch 0006: 16 passed, 0 failed, 4
  skipped.

## Drawing Scale (2026-10-31)

The issue mentions upstream's `-res` (a larger internal resolution). The
core has it as a setting, Drawing Scale: 1x (the Model 3's own 496x384, the
default), 2x, 3x or 4x, the picture that many times wider and taller (the
2D layers scaled up bilinearly, as upstream does at any size but 1x). The
package's picture capacity is 4x (1984x1536); the live size is reported
each frame. It changes the picture only: the gate's scale test compares a
2x run with a 1x run in everything but the pictures (steps, sound, cycles,
lag: the same) and native with the sandbox at 2x; with the setting ignored
on purpose its size check failed (496x384, not 992x768). On llvmpipe, 2x is
four times the pixels to draw.

Measured: `waterbox/run-gate.sh` 18 passed, 0 failed, 4 skipped; contract
tests 21 passed.

## Save data (2026-10-31)

What a Model 3 game remembers (its settings, records, bookkeeping) is in
its EEPROM and its backup RAM, which upstream keeps per game in its NVRAM
folder as `<game>.nv`, a block file. The core keeps that format, so a file
goes between Supermodel and Chimera as it is:

- **Export Save Data** is one file, `<game>.nv`, written by upstream's own
  code (CModel3::SaveNVRAM) into memory no state holds (patch 0007 lets a
  block file be written into a stream: the sandbox has no folder). The
  stream is an `fmemopen` over that memory; the C library allocates and
  frees its small FILE record while the export runs.
- **A project's "Save data" slot** takes such a file; it is loaded after
  the Model 3 is built and before it is reset, as upstream does at start.
  A file that is not one is refused, naming it.
- The build leaves the sources' paths out of the objects
  (`-ffile-prefix-map`): upstream writes `__FILE__` into each block's
  comment, and an export would otherwise name the folder the core was built
  in.
- The test program now counts its boots in the backup RAM.

Measured: `waterbox/run-gate.sh` 21 passed, 0 failed, 4 skipped. The new
tests: the export is one file in upstream's format, with the EEPROM and
backup RAM blocks, the same bytes natively, in the sandbox and after a
session; given back, the program counts its second boot (a new machine its
first); a file that is not an NVRAM file is refused. With upstream's
SaveNVRAM and LoadNVRAM taken out on purpose, the first two failed (19
passed, 2 failed). `tests/run-frontend.sh` 5 ok; contract tests 21 passed;
check-core-texts 19 keys.
