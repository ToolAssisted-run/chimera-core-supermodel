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
  glFinish (glReadPixels gave back zeros there), the sound mixed to stereo as upstream mixes for two speakers, no
  threads, no folders); `chimera_input.cpp` writes Chimera's controls into
  Supermodel's inputs before each frame (upstream's input polling is not
  used); `chimera_net.cpp` stands in for the network the net board names.
- **Patches** (each a `SUPERMODEL_CHIMERA` build option):
  0001 the game list can be handed over as text (the core carries
  Games.xml); 0002 the RTC72421 reads the machine's clock (Starting Clock
  plus frames, UTC); 0003 a read of the input registers is told to the core
  (lag frames); 0004 a clone's parent set is the file the core names (the
  project's "parent" file). (A patch 0005 that made New3D give the window
  back GL_FRONT instead of GL_BACK was made in this round and taken out
  the same day: see "The 3D test" below.)
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
  PowerPC byte at address A is the domain's byte A ^ 3). Patch 0005 (0006
  when it was made) gives the core their pointers. Chimera requires the five domain exports.
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
  memory domain exports (hence patch 0006, now 0005).
- The package is 31 MB (core.wbx 88 MB before packing).
- `waterbox/run-gate.sh` again after patch 0006 (now 0005): 16 passed, 0 failed, 4
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
  code (CModel3::SaveNVRAM) into memory no state holds (patch 0006, 0007
  when it was made, lets a block file be written into a stream: the
  sandbox has no folder). The
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

## The 3D test (2026-10-31)

The test program now draws with the Real3D too: at power-on it writes one
viewport node (a 90-degree frustum, 496x384, full ambient light), the base
matrix games use (which undoes the Real3D's axis order) and one polygon (a
flat, unlit, double-sided quad whose colour is in its header) into the
high culling RAM and the polygon RAM, with `stwbrx` (the Real3D is a
little-endian chip), and each frame it changes the quad's colour with the
frame count. The tile generator's colour 0 is now transparent, so the 3D
shows through the 2D layer. The quad is drawn by New3D on llvmpipe (its
OpenGL 4.1 shaders, its frame buffers, its geometry-shader quads) exactly
where its vertices say: pixels 273 to 396 across, 115 to 172 down.

Taken out: patch 0005 (New3D's `glDrawBuffer(GL_BACK)` made GL_FRONT). It
was made when the first pictures were black, but that had two other
causes: the test program wrote the tile generator's palette and name
tables in the wrong byte order, and `glReadPixels` gave back zeros (the
core reads OSMesa's buffer instead). With GL_BACK put back on purpose
(after both were fixed) the quad and the 2D layers were still drawn the
same, and the whole gate passes without the patch; on a context with no
back buffer, Mesa refuses GL_BACK and keeps drawing into the front buffer.
The later patches were renumbered (0006 is now 0005, 0007 now 0006).

Measured: `waterbox/run-gate.sh` 22 passed, 0 failed, 4 skipped, with 3D in
every comparison now (native = sandbox, save and load before every frame,
a session, turbo, 2x). The new 3d test checks the quad's inside (its
colour, changing a frame later), a corner and two pixels just outside.

## The sound test (2026-10-31)

The test program has a sound program now: a few hand-encoded 68000
instructions (in `make-testprog.py`) in the sound board's program ROM, which
write 100 samples of a square wave into the first SCSP's RAM, set slot 0 to
loop them at full level in the middle and key it on. The board plays a 441
Hz square wave, 8192 at its peak, on both sides; 120 frames give 91996
stereo samples (44100 / 57.524 a frame, the remainder carried). So every
comparison of the gate (native = sandbox, save and load before every frame,
a session, turbo, 2x) now compares real sound from the 68000 and the SCSP,
not silence. The new sound test measures the length, the peak and the
pitch. Seen to fail: the first version of the sound program branched into
the middle of an instruction (a 68000 dbra's displacement counts from the
word after the opcode) and stopped; that run measured peak 0 and 0 Hz.

Measured: `waterbox/run-gate.sh` 23 passed, 0 failed, 4 skipped.

## The RAM for the tools, in the PowerPC's byte order (2026-10-31)

Supermodel keeps the RAM in 32-bit words in the computer's byte order, so
a byte the PowerPC keeps at A is at A ^ 3, and a 32-bit value reads
little-endian. A person searching a big-endian machine's RAM expects the
game's own order. The core now publishes Main RAM and Backup RAM as buses
in the PowerPC's order (PeekBus, PokeBus, ReadBus in memory no state
holds), and keeps the two memory domains (which Chimera requires) under the
names "Main RAM words" and "Backup RAM words", hidden from the memory tools
(GetMemoryDomainHidden). (Awaiting the owner: whether the words should be
shown too; hidden is the default here, as the ares core hides the copy a
person should not search.)

Measured: `tests/run-frontend.sh` 6 ok (new: engine:memory, the program's
frame count after 300 frames reads 0000012c through chimera-run's dump of
the Main RAM bus, and 2c010000 in the hidden domain); with the bus's ^ 3
taken out on purpose it failed (the bus read 2c010000). Gate 23 passed;
contract tests 21 passed.

## CI (2026-10-31, written, not run)

`.github/workflows/chimera.yml` is the Godot core's, for this core: it
builds Chimera (and its Qt window), miniBox, LLVM and Mesa (cached), runs
`waterbox/run-gate.sh` and asks for each test by name, builds the package
stamped with the commit, runs `tests/run-frontend.sh` and Chimera's
contract tests, uploads `supermodel-<sha>` and calls Chimera's publishing
workflow. It has never run: this repository is local only, and creating
and publishing it are the owner's. On a runner the real game tests SKIP
(no ROM sets); everything else in the gate runs on the test program.

## Speed and size (2026-10-31, this machine, the test program)

600 frames (10.4 s of Model 3 time) took 7.1 s natively and 9.1 s in the
sandbox at 1x, 26.1 s in the sandbox at 2x; the sandboxed process peaked at
1.08 GB of memory (0.48 GB natively). A state of the test program is 31 MB
with the 3D, the sound and the backup RAM in use. A real game draws far
more polygons and textures than one quad, so these say nothing yet about a
game's speed on llvmpipe.

## The analog controls and the light gun (2026-10-31)

The test program also reads, on the frames it reads its controls, the
Model 3's analog channels (the ADC at 0xF004003C: steering, accelerator,
brake) and light gun 1 through the serial port (registers 0 to 3 and 8:
the aim's low and high bits and the off-screen bits), and shows them. It
is made into two sets now, told apart by the program ROM's last byte:
`chimeratest` (common, joystick 1, fighting) and `chimeratestgun` (common,
vehicle, gun 1), so each cabinet's inputs reach it (Supermodel fills the
ADC and the gun only for the cabinets that have them).

What it showed, and the analog test now checks: at rest the wheel is 0x80,
the pedals 0, the gun at 400, 272 (the middle of upstream's 150..651 and
80..465); with the wheel at -32768, the accelerator at 32767, the brake at
16384 and the gun at the right edge and the top, off-screen held: 0x00,
0xFF, 0x7F, 651 and 80 with the off-screen bit; with the wheel at 32767
and the gun at the left edge and the bottom: 0xFF, 150 and 465. The cabinet
shows the wheel, the pedals, the gun's aim, trigger and off-screen, and no
joystick. With the stick and the gun's scaling broken on purpose (every
value at rest or at the low end) the values read 80 ff 7f 96 50 10, which
the test refuses.

Not proved here: the analog guns (Ocean Hunter, LA Machineguns: the ADC
with upstream's per-game inversion), the twin sticks, the ski, the
truck's levers, the fishing controls and the drive boards' force
feedback (off): no test cabinet has them, and no game was tried.

Measured: `waterbox/run-gate.sh` 25 passed, 0 failed, 4 skipped.

## Awaiting the owner (2026-10-31)

Defaults were taken so the work could go on; each is the owner's to
confirm or change:

1. **Publishing.** A public repository (`chimera-core-supermodel`), its CI,
   a row in Chimera's roster and README, and the reply to issue 354.
   Nothing has left this machine.
2. **The pin.** Upstream's master at 036af1c (2026-10-29); upstream's last
   release (0.3a, 2017) is far behind. Master moves fast (several commits
   a week), so the pin will want moving with care.
3. **Idle Skip on by default**, as upstream has it. It is part of the
   machine (a movie names it); off would make the PowerPC run every pass of
   an idle loop: slower, and the same game.
4. **The RAM's word-order copies hidden.** The tools see Main RAM and Backup
   RAM in the PowerPC's byte order (buses); the domains in Supermodel's own
   word order are hidden. Showing both lists every byte twice.
5. **New3D only.** The Legacy3D renderer (OpenGL 2.1 with the fixed
   function pipeline) is not built. Upstream's default is New3D; Legacy3D
   is an option there for games New3D draws wrongly.
6. **A clone's parent set as a second slot** ("Parent ROM set"), not as
   firmware asked for by the game (the MAME core's way, `gameFirmware`).
   The slot is simpler and works for the 64 sets Supermodel knows; the
   firmware way would let the New Project window ask for exactly the
   parent's name.
7. **The two test sets in the shipped game list.** `chimeratest` and
   `chimeratestgun` (this repository's own program, not Sega's) are in the
   game list the package carries, so that the tests run on the package
   Chimera loads. They match only this repository's ROMs.
8. **The GPU bridge**, and when: the core draws on llvmpipe only. The
   bridge would make a game fast but gives the renderer a new OpenGL
   context at every load of a state, and New3D keeps textures and model
   caches that it would have to rebuild from the machine's memory.

## Where this stands (2026-10-31)

**Works, on the test program, on Linux, native = sandbox:** the Model 3
boots from its program ROM with every board on one thread; the PowerPC,
the tile generator's 2D layer, the Real3D drawing a quad through New3D on
llvmpipe (OpenGL 4.1 core inside the core), the sound board's 68000 and
SCSP playing a tone, the controls (switches with lag frames, the wheel,
pedals and light gun through the ADC and the serial port), the real-time
clock on the machine's own time, the backup RAM. Savestates (save and load
before every frame; a state loaded into a new host), turbo, Drawing Scale
1x to 4x, save data in upstream's NVRAM format, RAM in the PowerPC's byte
order for the tools. The package passes Chimera's contract tests and runs
in chimera-run and in Chimera's Qt window (headless), the window's picture
the native reference's to the pixel.

**Measured last** (Chimera 3f8ea7e2, miniBox 7216594, this machine):
`waterbox/run-gate.sh` 25 passed, 0 failed, 4 skipped (the real games);
`tests/run-frontend.sh` 6 ok; contract tests 21 passed;
`check-core-texts.py` 19 keys. Every test was broken on purpose once and
seen to fail (each section above says how).

**Not tried, and what each needs:**

- **A real game.** None was tried: no ROM set was on hand (none may be
  looked for on this machine). The gate runs vf3, scud, srally2 and
  lostwsga from `SUPERMODEL_ROMS` when they are there (native = sandbox
  for `SUPERMODEL_FRAMES` frames, 1800 by default, and a session); their
  movie only presses coins, Start and a few directions, so a first look
  should also be by eye (screenshots) and for speed. What a game brings
  that the program does not: textured, lit, fogged models; VROM models;
  the MPEG digital sound board (scud, srally2); the drive board's Z80
  (Wheel boards); the security board; the Real3D's DMA and ping-pong
  update buffers; real timing.
- **Speed of a game on llvmpipe.** The test program's 600 frames take 9.1 s
  in the sandbox; a game's scenes are far heavier. AVX2 code generation (as
  the Godot core has it as a setting) is not here yet.
- **Windows.** Not run. The Windows test would be the frontend test's
  scenario in the published Windows build: the test program (and a game)
  from a project, its pictures and sound the Linux native reference's,
  and a state loaded across sessions. What failed only on Windows in other
  cores was stacks; Supermodel has no coroutines of its own, so the risk is
  Mesa's and the guest's usual ones.
- **The GPU bridge.** Not started (owner's question 8).
- **Clones**: the "Parent ROM set" slot (patch 0004) has not been tried:
  no clone set was on hand.
- **The light gun's crosshair**: upstream draws one in its SDL frontend;
  the core does not (Chimera shows the pointer).

**Traps met (so the next person does not):**

- The tile generator and the Real3D are little-endian chips on the
  PowerPC's big-endian bus: the PowerPC's words reach them byte-reversed
  (palette entries, name-table pairs with the left entry in the second
  half; Real3D words with `stwbrx`).
- `glReadPixels` on the OSMesa context gave back zeros; the picture is read
  from OSMesa's own buffer after `glFinish`.
- A run-native screenshot path is relative to the work dir (it changes
  folder): give absolute paths, or an old picture is read.
- Upstream's sources have CRLF line ends; patches keep them.
- `__FILE__` is written into upstream's block files (NVRAM): the build
  maps the source paths away.
- A 68000 `dbra` counts its displacement from the word after the opcode.
- Godot's run-native cleared the environment before its harness read
  `GATE_STALL_US`, so its clock stall did not stall natively; this core's
  run-native keeps that one variable (the clock test was checked to stall:
  the control with the computer's clock fails under it).

**Next:** the owner's ROM sets (vf3 first, then scud and srally2, then
lostwsga) through the gate and by eye; then speed (AVX2 for llvmpipe,
measured); then the owner's answers above; then Windows; then the GPU
bridge if wanted.
