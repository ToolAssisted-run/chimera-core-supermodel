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
(GetMemoryDomainHidden), as the ares core hides the copy a person should
not search. (The owner kept them hidden: see "The owner's answers".)

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

## The owner's answers (user-decided, 2026-10-31)

The owner accepted every default the first round took while waiting for an
answer. None of them changes the core: each was already how it was built.

1. **The upstream version.** The core builds Supermodel's master branch at
   036af1c (2026-10-29), not the 0.3a release of 2017. It is moved only on
   purpose, with the tests run again, since master changes several times a
   week.
2. **Idle Skip on by default**, as upstream has it. It is part of the
   machine, so a movie names it.
3. **The RAM in the PowerPC's byte order is what the memory tools show.**
   The two copies in Supermodel's own word order ("Main RAM words",
   "Backup RAM words") stay hidden.
4. **New3D only.** The older Legacy3D renderer is not built.
5. **A clone's parent zip stays a second file of the project** (the
   "Parent ROM set" slot), not a firmware file the game asks for.
6. **The two test sets stay in the game list the package carries**
   (`chimeratest`, `chimeratestgun`: this repository's own program, which
   matches only this repository's ROMs).
7. **The GPU bridge comes after real games.** First real games are run and
   their speed on llvmpipe (the software OpenGL) measured; then the bridge.
8. **Publishing comes after vf3** (Virtua Fighter 3), and if possible scud
   (Scud Race), has run with the native build and the sandbox the same and
   looks right by eye. Until then the repository stays on this machine.

## Names are never translated or bent (owner's rule, 2026-10-31)

The owner's rule for every language table: a name (Supermodel, Model 3,
MAME, OpenGL, Chimera and any other program, chip, machine, game or
company) is written as it is, in every language. A language that puts
endings on names says the sentence with a common noun beside the name
instead ("emulatoru Supermodel", "Model 3 -koneen", "NVRAM-mappen i
Supermodel"). Particles in Korean and Japanese,
in their own script, leave the name whole.

- Fixed by hand: 33 texts in ten tables. Czech and Polish had case endings
  ("Supermodelu", "Supermodela"); Danish, Norwegian and Swedish a genitive
  "s" ("Supermodels", "Model 3:s", "Model 3s"); Finnish case endings after
  a colon ("Model 3:n", "Supermodelin"); Hungarian and
  Romanian endings after a hyphen ("Model 3-at", "OpenGL-je", "OpenGL-ul");
  Turkish endings after an apostrophe ("Supermodel'in", "MAME'nin"); German
  wrote "Model-3-Spiel".
- `tools/check-names.py` checks the 26 tables: every name an English text
  holds is in its translations as written, and no letter (Latin, Greek or
  Cyrillic), no apostrophe or colon with letters, and no hyphen with one to
  three letters is attached to a name. A hyphen with a longer word is a
  compound with a common noun ("Model 3-spel") and is allowed, as Chimera's
  own tables have "Chimera-ohjelman". The names are the core's coreName
  (from waterbox.config), the names its texts use, and those Chimera's
  `tools/check-proper-nouns.py` knows.
- The test script runs it as the "names" test (CI asks for it by name).

Measured: the check found 44 problems (33 texts; a text missing a name is
also counted as bent). With every text fixed but one (Swedish
`setting.starttime.about`, "Model 3:s"), `waterbox/run-gate.sh` gave 25
passed, 1 failed (names, naming that text), 4 skipped; with it fixed, 26
passed, 0 failed, 4 skipped. Chimera's own `check-proper-nouns.py` run on
these tables: 0 problems.

## AVX2 drawing code, measured and not added (2026-10-31)

The Godot cores let llvmpipe make AVX2 code (256-bit vectors) on a computer
that has all of x86-64-v3, as the Drawing Code setting (their
mesa-patches/0002 and a `chimera_llvmpipe_avx2` function in the core). To
see whether this core should have it, the patch was applied to this
repository's Mesa build for one experiment, both builds were linked with
and without the function returning yes, and then the patch was taken out
again: nothing of it is committed.

Measured on this computer (Intel Core Ultra 7 265KF), the test program, 600
frames with the gate's movie, times in seconds (two runs at 1x):

| | Baseline (128 bits) | AVX2 (256 bits) |
|---|---|---|
| sandbox, 1x | 9.8, 9.5, 9.5 | 8.5, 8.4, 9.1 |
| native, 1x | 7.9, 7.4, 7.9 | 7.4, 6.7, 7.2 |
| sandbox, 2x | 27.6 | 24.9 |
| native, 2x | 25.6 | 22.6 |

- With AVX2 the sandbox and the native build were still the same machine
  (every digest: pictures, sound, steps, lag, cycles), at 1x and at 2x.
- At 1x the pictures were the same with and without AVX2 (the program's
  flat colours); at 2x they were not (the 2D layers are scaled up
  bilinearly): a movie's pictures would differ between a computer with
  AVX2 and one without. The steps, the sound and the cycles were the same.
- About a tenth faster on this program, at the price of a setting, a Mesa
  patch, its tests, 26 tables of texts, and pictures that depend on the
  computer. That is not a plain win, so it is not added. It should be
  measured again on a real game (vf3), whose textured, lit scenes give
  llvmpipe far more shader work than one flat quad.

Trap: this repository's `build/mesa` was copied from the Ikemen GO core's,
and its `build.ninja` still names that core's folders (for LLVM and for
re-running meson). Rebuilding it in place with ninja compiled this
repository's sources and wrote nothing in the other checkout, but its
libOSMesa.so does not link (as setup-mesa.sh expects: the core links the
archives).

## The first real game: vf3 (2026-10-31)

The owner gave the first ROM set, vf3 (Virtua Fighter 3, Japan, Revision
D: Model 3 Step 1.0, a billboard drive board, no MPEG sound board). It is
the first real game this core has run. Its zip stays outside the
repository; the tests copy it from the folder `SUPERMODEL_ROMS` names.

**What was done.** The gate's real game tests (`waterbox/run-gate.sh`,
"real games") now give each set a movie of its own. vf3's plays a fight:
two coins during the warning screen (the game's default is two coins a
credit), Start once the title is up (frame 960; Start before about frame
900 is ignored), the cursor one to the right and Punch to pick that
fighter, then from frame 1800 walks, punches, kicks, a guard and a crouch;
the fight itself begins about frame 1600. 2400 frames. For each set that
is there the gate runs native = sandbox (and prints both speeds), saved
and loaded before every frame (new for real games), saved at 5/6 of the
movie into a new host, and checks that the last picture is a drawn scene
(`tests/colours.py`: more than 2000 colours; a black or blank screen has
one or two). It keeps the native run's pictures at a few frames in
`build/gate/vf3-*.tga` to be looked at. The frontend test
(`tests/run-frontend.sh`) has three vf3 checks with `SUPERMODEL_ROMS` set,
each SKIP without it: the fight as a project in chimera-run, which also
records the movie it played; that recording made into a new project and
played by a new chimera-run process; and the first project opened in
Chimera's window (headless).

**What it looks like, by eye** (native pictures at 496x384, looked at
every 50 to 100 frames from power-on to frame 4000):

- Frames 0 to about 300 black, then a white screen: the boot.
- Frames about 400 to 900: the warning text, white on black, readable.
- About 950 on: the attract mode. The white SEGA logo screen with "Insert
  Coin(s)" and "Credit 0/2"; after the coins "Credit 2/2" and "Press
  Start Button". Then the attract scenes: close-ups of fighters and
  fights on a beach stage, textured and lit, with sky, clouds, sea, sand
  and palm trees, the SEGA copyright line at the bottom right.
- After Start (a run with Start at 1060): the fighter select screen
  (frame about 1200), the 12 portraits, the large textured portrait and
  the fighter's profile text, the countdown; P1 Right moved the cursor
  one portrait, Punch picked (the countdown went to 00). Then the "FIRST
  MATCH" screen with the opponent's face, and the fight on the beach
  stage: the two energy bars, the timer with hundredths, the names, the
  stage number, a line of Japanese text at the top right, shadows on the
  sand, the sea, the palm trees, hit sparks; "Excellent!!" on a round
  won, a replay with black bars, round 2.
- Inputs reach the game: the picked fighter walks, punches, kicks and
  knocks the opponent down when the movie says so; with no input in the
  fight (an earlier run) the fighter stands and loses the round.
- Nothing was seen drawn wrong. Every picture has a black border two
  pixels wide: upstream's own window clips the same two pixels (Main.cpp,
  "due to the 2D layer compensation"), and the core does as upstream
  does. A line of text sliding in is cut at the screen's edge mid-slide
  (frame 1300, "FIRST MATC"), as a slide is. What could not be judged
  here: whether colours, fog and lighting match a real cabinet (there is
  none to compare with), and the sound by ear.
- The sound: not silent. Over 2400 frames of the fight movie, the first
  8 seconds are silent (the boot and warning screen), then the attract
  mode's and the fight's sound, peaks up to 14903 of 32767 and a loudness
  (RMS) of 900 to 1900 in each 4-second stretch. Nobody has listened to
  it.

**Nothing in the core had to be fixed** for vf3: no patch was added, and
no change was made to the core's code this round.

**Measured** (this machine, an Intel Core Ultra 7 265KF shared with other
jobs; load average 3 to 11 during the timed runs; llvmpipe at its one
baseline CPU (128-bit vectors); the 2400-frame fight movie, no
screenshots; the Model 3 runs 57.524 frames a second):

| | run 1 | run 2 | share of full speed |
|---|---|---|---|
| native | 23.1 fps (104.0 s) | 22.6 fps (106.0 s) | about 40% |
| sandbox | 17.7 fps (135.4 s) | 18.1 fps (132.7 s) | about 31% |

- Memory: the native process peaks at 0.52 GB, the sandboxed one at 1.19
  GB. A state is 21.6 MB at frame 100 and 78.9 MB during the fight.
  Saving and loading before every frame costs about 15 ms a frame.
- AVX2 again (the earlier experiment's two builds of each, the same core
  code with the drawing code's choice the only difference): native 22.8
  fps without, 27.5 with (+21%); sandbox 18.3 without, 20.9 with (+14%).
  On vf3 the pictures with AVX2 are different from those without at 1x
  too (another video digest; the steps and the sound the same). So a
  movie's pictures would depend on the computer, as at 2x on the test
  program. It is still not added: it is the owner's to decide whether a
  seventh faster is worth that (see "AVX2 drawing code" above).
- Lag frames (frames the game did not read its controls in): 63 in the
  2400 frames of the fight, the same 63 as in the first 1800 frames of a
  run with no input, so none came after frame 1800.

**The tests** (Chimera main cb46d2b7 at ~/chimera-scratch-bump, miniBox
7216594): `waterbox/run-gate.sh` with `SUPERMODEL_ROMS` 30 passed, 0
failed, 3 skipped (scud, srally2, lostwsga: not here); vf3's four: native
= sandbox over 2400 frames (every picture, the sound, the steps, the lag,
the cycles), saved and loaded before every frame = straight, saved at
frame 2000 and loaded into a new host = straight, the last picture drawn
(64645 colours). `tests/run-frontend.sh` 9 ok, 0 failed: engine:vf3 (the
last picture of the fight from a project, every pixel the native
reference's), engine:vf3-replay (the recorded movie, 2400 entries with
the presses in it, replayed in a new process: the same picture),
window:vf3 (after 2400 frames in Chimera's window, the same picture).
Seen to fail: the recorded movie with the walk to the right at frames
2300 to 2329 taken out, made into a project and played, gave a last
picture with 380 of 384 rows different, which the comparison refuses;
the colour check gives 2 colours for the white boot screen (frame 299),
under its 2000.

## Where this stands (2026-10-31, after vf3)

**Works, on Linux, native = sandbox:** the test program (every board on
one thread, the tile generator, the Real3D through New3D on llvmpipe, the
sound board, the controls, the clock, the backup RAM) and now **vf3
(Virtua Fighter 3), the first real game**: from power-on through the
warning screen, the attract mode, coins, Start, the fighter select and a
fight with punches, kicks, a guard and a crouch, 2400 frames. Proved for
vf3: native = sandbox in every picture, the sound, the steps, the lag and
the cycles; saved and loaded before every frame, and saved into a new
host at frame 2000, the same as straight; the fight from a project in
chimera-run, the movie chimera-run recorded replayed by a new process,
and the project in Chimera's window (headless), each last picture the
native reference's to the pixel; by eye, the pictures right in every
screen looked at (see "The first real game: vf3"). Not proved for vf3:
the sound by ear, colours and lighting against a real cabinet, more than
the first round of the first fight, the other stages and fighters,
Windows, a GPU. Savestates, turbo, Drawing Scale, save data, RAM for the
tools, the package (Chimera's contract tests) as before.

**Speed of vf3 on llvmpipe:** native about 23 frames a second, sandbox
about 18 (40% and 31% of the Model 3's 57.524); AVX2 drawing code would
make them about 27.5 and 21 but makes the pictures depend on the
computer, and is not added (the owner's to decide).

**Measured last** (2026-10-31, Chimera main cb46d2b7 at
~/chimera-scratch-bump, miniBox 7216594, this machine):
`waterbox/run-gate.sh` with `SUPERMODEL_ROMS` holding vf3.zip: 30 passed,
0 failed, 3 skipped (scud, srally2, lostwsga: no ROM sets);
`tests/run-frontend.sh` with `SUPERMODEL_ROMS` (chimera-run and Chimera's
Qt window, headless): 9 ok, 0 failed; Chimera's contract tests on a
folder holding only the package: 21 passed, 0 failed;
`check-core-texts.py` 19 keys, every one named; `tools/check-names.py`
and Chimera's `check-proper-nouns.py` 0 names changed (no text was
added this round). Every new test was seen to fail once (see the vf3
section).

**The owner's answers** (2026-10-31) kept every default; see "The owner's
answers" above. Publishing waits for vf3 (done, as above) "and if possible
scud": the owner's to decide.

**Not tried, and what each needs:**

- **The other ROM sets**: scud (Scud Race: the MPEG digital sound board,
  the drive board's Z80), srally2 (Sega Rally 2: also the MPEG board and
  the wheel), lostwsga (The Lost World: light guns). Not on hand; the
  gate runs them when they are in `SUPERMODEL_ROMS` (the frontend test
  runs vf3 only; their movies only press coins, Start and a few directions until
  someone writes one per game, as vf3's).
- **Windows.** Not run. The test would be the frontend test's scenario in
  the published Windows build: vf3's fight from a project, its pictures
  and sound the Linux native reference's, and a state loaded across
  sessions.
- **The GPU bridge.** Not started: the owner wanted it after real games
  run and their speed on llvmpipe is measured. Both are now done for vf3.
- **Clones**: the "Parent ROM set" slot has not been tried (no clone set).
- **The light gun's crosshair**: upstream draws one in its SDL frontend;
  the core does not (Chimera shows the pointer).

**Traps met (so the next person does not):**

- vf3 takes two coins a credit by default, and ignores Start until the
  warning screen is over (about frame 900); coins during it are counted.
- The tile generator and the Real3D are little-endian chips on the
  PowerPC's big-endian bus: the PowerPC's words reach them byte-reversed.
- `glReadPixels` on the OSMesa context gave back zeros; the picture is read
  from OSMesa's own buffer after `glFinish`.
- A run-native screenshot path is relative to the work dir (it changes
  folder): give absolute paths, or an old picture is read.
- Upstream's sources have CRLF line ends; patches keep them.
- `__FILE__` is written into upstream's block files (NVRAM): the build
  maps the source paths away.
- A 68000 `dbra` counts its displacement from the word after the opcode.
- Godot's run-native cleared the environment before its harness read
  `GATE_STALL_US`; this core's run-native keeps that one variable.
- Every picture has a 2-pixel black border: upstream's, not a bug.

**Next:** scud, srally2 and lostwsga when the owner has them (a movie for
each, by eye, speed); Windows; publishing (the owner's: the repository,
the roster, issue 354); then the GPU bridge, whose first measure should
be vf3's fight against these llvmpipe numbers.


## Published (user-decided, 2026-10-31)

The owner decided to publish once vf3 ran, without waiting for Scud Race
("No wait, go ahead with publish"), and to leave the AVX2 drawing code out.
The main session made the repository public (ToolAssisted-run/chimera-core-
supermodel), the first CI run passed (26 passed, 0 failed, 4 skipped: the
real-game tests, which need ROM sets), and the first published build is
"Development build 79e038b8 (made 2026-10-31 17:30 CET)". Chimera lists the
core (chimera 46c463ed), and so does the website's Tools page.

Windows, run by the main session before publishing: the vf3 fight recorded
by chimera-run on Linux (build/frontend/vf3/recorded.log), made into a
project and played for 2400 frames by chimera-run.exe of the published
Chimera for Windows (Development build cb46d2b7), ends on the native
reference's picture, every pixel (and byte for byte the Linux replay's).
Sound was not compared on Windows.



## White spikes and triangles, issue 469 (user-decided, 2026-11-02)

Issue 469: in vf3a, srally2, von2 and scud, white triangles were drawn over
the picture that upstream Supermodel, on the reporter's graphics card, does
not draw. The owner chose to fix the software drawing (the GPU bridge stays
a later step).

Reproduced here with vf3's attract mode, no inputs: at frame 6900 a long
thin white spike from the bottom left corner, natively (no sandbox), so
the core's drawing and not Windows. Found by drawing the quad shader's
fragments in colours by what they computed (the native build, a test
harness drawing only the last 30 frames, which gave the same picture to
the pixel):

- With QuadRendering off (New3D's triangles) there is no spike, but the
  triangles are slower here (17.6 frames a second over vf3's first 2400
  frames, against 21.3 with quads) and give a slightly different picture
  (about 48,000 pixels of the frame), so quads stay, as upstream has them.
- The spike's fragments belong to an ordinary quad, every corner well in
  front of the camera, whose screen-space vectors to the corners (the
  shader's noperspective inputs) llvmpipe interpolates to NaN for a thin
  sliver; NaN passes the shader's discard test, since every comparison
  with NaN is false, and the fragment is lit white.
- Not the cause, tried and taken out again: GLSL `precise` fma made fused
  in llvmpipe (it is split into a multiply and an add on every CPU), and
  the clipper taking a clipped noperspective value from the nearer end.
  Neither changed the spike.

The fix is patch 0007: the quad shader checks its four weights first, and
weights that are not numbers, or far outside the quad's own (0 to 1 inside
it; -1 to 2 is let through), make the fragment take the attributes the
triangle interpolated, as upstream already does on a quad's edges. vf3's
frame 6900 then has no spike (the corner's white is the "Credit" text's,
255 pixels, against 963 with the spike) and differs from the old picture in
1,510 pixels, the spike and a few slivers. At frames 3300, 6900 and 7800 of
vf3's attract mode every other quad fragment's weights stayed within -0.05
to 1.05, but for 6 pixels a frame outside -1 to 2, which now take the
triangle's attributes too.

The gate checks frame 6900 when SUPERMODEL_ROMS holds vf3.zip (the native
build, about four minutes); on the old build's picture the check reads 963
and fails. Not tried: srally2, von2 and scud (no ROM sets here), whose
triangles were far larger than vf3's spike and may have another cause.
