#!/bin/bash
# run-gate.sh - the Supermodel core's tests: the native reference
# (run-native) and the sandbox (core.wbx through run-wbx) are the same
# machine. No Model 3 game may be shared, so most tests run this
# repository's own test program (tests/testprog: a PowerPC program that
# boots as a game's ROM does, draws with the tile generator, reads the
# controls and the real-time clock); a real game's tests run where a ROM set
# is (SUPERMODEL_ROMS names a folder; see "real games" below) and SKIP
# elsewhere.
#
# Every test says what it compared. The tests:
#   game list    the game list the core carries finds the test program by
#                its file's CRC32
#   equivalence  run-native and run-wbx: every frame's picture, the sound,
#                each step's length and lag, the PowerPC's cycle count
#   rerecord     the sandbox saved and loaded before every frame = without
#   session      saved at a frame, a new host, loaded, finished = without
#   turbo        the first half not drawn: the rest the same (pictures,
#                sound, steps, cycles), and the first half's pictures not
#                there; so drawing does not change the machine
#   teeth        the comparison sees a press one frame later
#   scale        Drawing Scale 2x: a 992x768 picture, native = sandbox, and
#                the same machine as at 1x (steps, sound, cycles, lag)
#   sound        the sound board's 68000 runs the program's sound program: a
#                441 Hz square wave from the SCSP, 766.6 samples a frame
#   3d           the Real3D's polygon (the program's one quad) is drawn by
#                New3D where its vertices put it, coloured as the program
#                sets it each frame, and nothing around it
#   controls     a press reaches the program through the Model 3's input
#                registers, and the controls a cabinet lacks are not shown
#   analog       in the wheel and gun cabinet (chimeratestgun), the wheel,
#                the pedals and the light gun's aim reach the program through
#                the analog channels and the gun's serial port with the
#                values upstream's inputs give them: at rest, at each end
#   lag          a frame in which the program did not read its controls (one
#                in eight, by design) is a lag frame, and only those
#   clock        the real-time clock is the Starting Clock and the frames
#                run; the computer stalling between frames changes nothing;
#                and the same test sees it when the clock is the computer's
#                (upstream's RTC72421.cpp linked in instead: the control)
#   save data    Export Save Data is the game's NVRAM file as upstream writes
#                it (<game>.nv: the EEPROM and the backup RAM), the same in
#                both builds and after a session; given back in a project it
#                is the machine's memory at power-on (the program counts its
#                boots in the backup RAM: 2, not 1); a file that is not one
#                is refused
#   refusals     a zip that holds no Model 3 game, and a project without a
#                game, each say why
#   names        no name is translated or bent in the 26 language tables
#   real games   (SKIP without SUPERMODEL_ROMS) on each ROM set named below
#                that is there: native = sandbox (with both speeds), saved
#                and loaded before every frame, a session, and the last
#                picture a drawn scene; vf3's movie plays a fight
#
# What the test program does not stand in for: the 3D renderer with a real
# game's models, textures, lights and fog (it draws one flat, unlit, untextured
# quad), the sound board as a game drives it (its program plays one looped
# square wave on one slot: no samples from ROM, no DSP effects, no MIDI from
# the PowerPC), the MPEG board, the drive boards, the analog controls, the
# light guns, and a real game's timing. The real game tests are where those
# are seen.
#
# usage: run-gate.sh -m <miniBox checkout>
set -u
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
mb="${MINIBOX_DIR:-}"
while getopts "m:" opt; do
	case "$opt" in
		m) mb="$OPTARG" ;;
		*) exit 2 ;;
	esac
done
[ -n "$mb" ] && [ -d "$mb" ] || { echo "pass -m <miniBox checkout>" >&2; exit 2; }
mb="$(cd "$mb" && pwd)"

echo "== build (miniBox $mb)"
mkdir -p "$root/build"
step() { # step <what> <log> <command...>
	local what="$1" log="$2"; shift 2
	if ! "$@" > "$log" 2>&1; then
		grep "error:" "$log" | head -10; tail -15 "$log"; echo "$what failed ($log)"; exit 1
	fi
}
step "the inputs' tables" "$root/build/gate-inputs.log" python3 "$root/tools/gen-inputs.py" --check
step "the test program" "$root/build/gate-testprog.log" python3 "$root/tests/testprog/make-testprog.py" "$root/build/tests"
if grep -q "game.xml changed" "$root/build/gate-testprog.log"; then
	echo "the test program changed: tests/testprog/game.xml was rewritten; commit it"
fi
step "the LLVM builds" "$root/build/gate-llvm.log" bash -c "bash '$here/build-llvm.sh' native && bash '$here/build-llvm.sh' guest -m '$mb'"
step "the Mesa builds" "$root/build/gate-mesa.log" bash -c "bash '$here/setup-mesa.sh' -m '$mb' && bash '$here/setup-mesa.sh' -n"
step "the sandbox's math for the native build" "$root/build/gate-libm.log" bash "$here/make-native-libm.sh" "$mb"
step "the native Supermodel build" "$root/build/gate-native.log" bash "$here/build-supermodel.sh" native -m "$mb"
step "the guest Supermodel build" "$root/build/gate-guest.log" bash "$here/build-supermodel.sh" guest -m "$mb"
step "the native link" "$root/build/gate-link-native.log" bash "$here/link-core.sh" native -m "$mb"
step "the guest link" "$root/build/gate-link-guest.log" bash "$here/link-core.sh" guest -m "$mb"
step "the clipper test's link" "$root/build/gate-link-clip.log" bash "$here/link-core.sh" clip-test -m "$mb"
native="$root/build/native/run-native"
wbx="$root/build/guest/run-wbx"
core="$root/build/guest/core.wbx"

# the control for the clock test: upstream's real-time clock, which reads the
# computer's, linked in place of the core's
hostclock="$root/build/native/run-native-hostclock"
step "the native build on the computer's clock" "$root/build/gate-hostclock.log" bash -c "
	g++ -O2 -std=c++17 -c -o '$root/build/native/RTC72421-upstream.o' '$root/extern/supermodel/Src/Model3/RTC72421.cpp' \
		-I'$root/extern/supermodel/Src' -I'$root/extern/supermodel/Src/OSD' -I'$root/extern/supermodel/Src/OSD/SDL' &&
	LINK_EXTRA='$root/build/native/RTC72421-upstream.o' LINK_OUT='$hostclock' bash '$here/link-core.sh' native -m '$mb'"

work="$root/build/gate"
rm -rf "$work"
mkdir -p "$work"
passed=0
fails=0
skipped=0
pass() { echo "PASS $*"; passed=$((passed + 1)); }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }
skip() { echo "SKIP $*"; skipped=$((skipped + 1)); }

# what a run says: its digests. A run that did not reach its last frame
# says nothing, and two such runs must not compare equal.
digests() { grep -E '^[A-Za-z]+=' "$1" | grep -v '^stateBytes=' || true; }
same() { # same <test> <a> <b> <what>
	digests "$2" > "$2.d"
	digests "$3" > "$3.d"
	if grep -q '^frames=' "$2.d" && cmp -s "$2.d" "$3.d"; then
		pass "$1: $4"
	else
		fail "$1: $4"; diff "$2.d" "$3.d" | head -20; grep -h 'loadError\|rror' "$2" "$3" | head -5
	fi
}
value() { digests "$1" | sed -n "s/^$2=//p"; }
pixel() { python3 "$root/tests/pixel.py" "$@"; }
S="$(printf '\037')"
mkwork() { # mkwork <dir> <zip> [<settings JSON>]
	mkdir -p "$work/$1"
	cp "$2" "$work/$1/"
	printf '{"game":["%s"]}' "$(basename "$2")" > "$work/$1/slots"
	printf '%s' "${3:-{\}}" > "$work/$1/settings"
}

# ---------------------------------------------------------------- the language tables
# no name (Supermodel, Model 3, MAME, OpenGL, Chimera's own...) translated or
# given an ending in any of the 26 tables (tools/check-names.py says which)
if python3 "$root/tools/check-names.py" > "$work/names.txt" 2>&1; then
	pass "names: $(tail -1 "$work/names.txt")"
else
	fail "names: a name is changed in the language tables"; head -20 "$work/names.txt"
fi

# ---------------------------------------------------------------- the test program
testzip="$root/build/tests/chimeratest.zip"
mkwork tp "$testzip"
frames=600
movie=(--press 40:P1Right:30 --press 100:P1Punch:200 --press 150:P1Up,P1Kick:20 --press 300:P1Start,P1Coin:3
       --press 400:P1Left,P1Down:25 --press 450:TestA,ServiceA:2 --press 500:P1Guard,P1Escape:40)
echo "== the test program ($frames frames: the joystick, buttons, coins, service)"
"$native" "$work/tp" --frames $frames "${movie[@]}" > "$work/n.txt" 2> "$work/n.err"
"$wbx" "$core" "$work/tp" --frames $frames "${movie[@]}" > "$work/w.txt" 2> "$work/w.err"
if grep -q "supermodel: Chimera Model 3 test program (chimeratest)" "$work/n.err"; then
	pass "game list: the test program is found in the core's game list by its ROM's CRC32"
else
	fail "game list: $(grep -m3 'error' "$work/n.err")"
fi
same equivalence "$work/n.txt" "$work/w.txt" "native = sandbox, $frames frames: every picture, the sound, the steps, the lag, the cycles"
"$wbx" "$core" "$work/tp" --frames $frames "${movie[@]}" --rerecord > "$work/r.txt" 2> "$work/r.err"
same rerecord "$work/r.txt" "$work/w.txt" "save+load before every frame = straight ($(sed -n 's/stateBytes=//p' "$work/r.err") state bytes)"
"$wbx" "$core" "$work/tp" --frames $frames "${movie[@]}" --session-at 160 > "$work/s.txt" 2> "$work/s.err"
same session "$work/s.txt" "$work/w.txt" "saved at frame 160 (Up and Kick held), loaded into a new host = straight"

"$native" "$work/tp" --frames $frames "${movie[@]}" --turbo > "$work/t.txt" 2> /dev/null
digests "$work/t.txt" | grep -v '^videoHash=' > "$work/t.d"
digests "$work/n.txt" | grep -v '^videoHash=' > "$work/n.d"
if grep -q '^frames=' "$work/t.d" && cmp -s "$work/t.d" "$work/n.d" && [ "$(value "$work/t.txt" videoHash)" != "$(value "$work/n.txt" videoHash)" ]; then
	pass "turbo: the first half not drawn - the second half's pictures, the sound, the steps and the PowerPC's cycles the same; the first half's pictures not there"
else
	fail "turbo"; diff "$work/t.d" "$work/n.d" | head
fi
late=(--press 41:P1Right:30 --press 100:P1Punch:200 --press 150:P1Up,P1Kick:20 --press 300:P1Start,P1Coin:3
      --press 400:P1Left,P1Down:25 --press 450:TestA,ServiceA:2 --press 500:P1Guard,P1Escape:40)
"$native" "$work/tp" --frames $frames "${late[@]}" > "$work/late.txt" 2> /dev/null
if [ -n "$(value "$work/late.txt" videoHash)" ] && [ "$(value "$work/late.txt" videoHash)" != "$(value "$work/n.txt" videoHash)" ]; then
	pass "teeth: Right one frame later is another run (the comparison sees it)"
else
	fail "teeth: Right one frame later gave the same pictures"
fi

echo "== drawing scale"
mkwork tp2x "$testzip" '{"drawingScale": "2x"}'
"$native" "$work/tp2x" --frames 300 "${movie[@]}" --screenshot 299:"$work/s2.tga" > "$work/s2n.txt" 2> /dev/null
"$wbx" "$core" "$work/tp2x" --frames 300 "${movie[@]}" > "$work/s2w.txt" 2> /dev/null
"$native" "$work/tp" --frames 300 "${movie[@]}" > "$work/s1n.txt" 2> /dev/null
same scale "$work/s2n.txt" "$work/s2w.txt" "Drawing Scale 2x: native = sandbox, 300 frames"
digests "$work/s2n.txt" | grep -v 'ideoHash=' > "$work/s2.d"
digests "$work/s1n.txt" | grep -v 'ideoHash=' > "$work/s1.d"
size2="$(od -An -tu2 -j12 -N4 "$work/s2.tga" 2>/dev/null | tr -s ' ' | sed 's/^ //')"
if grep -q '^frames=' "$work/s2.d" && cmp -s "$work/s2.d" "$work/s1.d" && [ "$size2" = "992 768" ]; then
	pass "scale: at 2x the picture is 992x768 and the machine is the one at 1x (steps, sound, cycles, lag)"
else
	fail "scale: picture $size2; $(diff "$work/s2.d" "$work/s1.d" | head -5 | tr '\n' ' ')"
fi

echo "== sound"
"$native" "$work/tp" --frames 120 --audio "$work/tone.raw" > /dev/null 2> /dev/null
tone="$(python3 "$root/tests/tone.py" "$work/tone.raw")"
hz="$(echo "$tone" | sed -n 's/.* hz=\([0-9]*\).*/\1/p')"; peak="$(echo "$tone" | sed -n 's/.* peak=\([0-9]*\) .*/\1/p')"
if echo "$tone" | grep -q "^samples=91996 " && [ "${peak:-0}" -gt 4000 ] && [ "${hz:-0}" -ge 438 ] && [ "${hz:-0}" -le 444 ]; then
	pass "sound: the sound board plays the program's square wave, $tone (120 frames are 91996 samples at 44100 Hz and 57.524 frames a second)"
else
	fail "sound: $tone (91996 samples, a 441 Hz tone)"
fi

echo "== 3d"
# the quad spans x 1 to 6, y 1 to 4 at z -10 in a 90-degree view: pixels 273
# to 396 across and 115 to 172 down; its red is the program's frame count
# times 4, its green full
"$native" "$work/tp" --frames 60 --screenshot 40:"$work/q40.tga" --screenshot 41:"$work/q41.tga" > /dev/null 2> /dev/null
q40="$(pixel "$work/q40.tga" 330 145)"; q41="$(pixel "$work/q41.tga" 330 145)"
qcorner="$(pixel "$work/q40.tga" 275 117)"; qout="$(pixel "$work/q40.tga" 268 145)$(pixel "$work/q40.tga" 330 178)"
if [ "${q40:2:4}" = ff00 ] && [ "${q41:2:4}" = ff00 ] && [ "$q40" != "$q41" ] && [ "${qcorner:2:4}" = ff00 ] && [ "$qout" = 000000000000 ]; then
	pass "3d: the Real3D's quad is drawn where its vertices put it (inside: $q40, then $q41 a frame later; outside: black)"
else
	fail "3d: inside $q40 and $q41 (..ff00, changing), corner $qcorner, outside $qout (black)"
fi

echo "== controls"
# The program shows each control byte's bits on rows 46 (coins, starts,
# service, test) and 47 (player 1), from column 2: blue where pressed, red
# where not. A press shows in the picture of the frame after it.
"$native" "$work/tp" --frames 130 --press 100:P1Punch:20 --press 110:P1Start:5 \
	--screenshot 99:"$work/c99.tga" --screenshot 101:"$work/c101.tga" --screenshot 112:"$work/c112.tga" --screenshot 125:"$work/c125.tga" > "$work/c.txt" 2> /dev/null
punch99="$(pixel "$work/c99.tga" 20 380)"; punch101="$(pixel "$work/c101.tga" 20 380)"; punch125="$(pixel "$work/c125.tga" 20 380)"
start112="$(pixel "$work/c112.tga" 52 372)"; start125="$(pixel "$work/c125.tga" 52 372)"
if [ "$punch99" = ff0000 ] && [ "$punch101" = 0000ff ] && [ "$punch125" = ff0000 ] && [ "$start112" = 0000ff ] && [ "$start125" = ff0000 ]; then
	pass "controls: P1 Punch (player 1's bit 0) and P1 Start (bit 4 of the coin bank) read as pressed while held, and not before or after"
else
	fail "controls: punch $punch99 $punch101 $punch125, start $start112 $start125 (pressed is 0000ff, not ff0000)"
fi
"$native" "$work/tp" --frames 60 --press 10:P1Right:40 --screenshot 55:"$work/m.tga" > /dev/null 2> /dev/null
if [ "$(pixel "$work/m.tga" 490 195)" = ffffff ] && [ "$(pixel "$work/m.tga" 242 195)" = 000000 ]; then
	pass "controls: P1 Right held 40 frames moves the block from column 30 to the right edge"
else
	fail "controls: the block is not at the right edge: $(pixel "$work/m.tga" 490 195)"
fi
active="$(sed -n 's/^activeButtons=//p' "$work/n.txt")"
axes="$(sed -n 's/^activeAxes=//p' "$work/n.txt")"
if [ "$active" = "P1Coin P1Start P2Coin P2Start ServiceA TestA ServiceB TestB P1Up P1Down P1Left P1Right P1Punch P1Kick P1Guard P1Escape P2Punch P2Kick P2Guard P2Escape " ] && [ -z "$axes" ]; then
	pass "controls: the test program's cabinet (common, joystick 1, fighting) shows its 20 buttons and no wheel, pedal, gun or other"
else
	fail "controls: shown: $active / axes: $axes"
fi

echo "== analog"
# the program shows, rows 38 to 43: steering, accelerator, brake, gun X low,
# gun Y low, and gun X high | gun Y high << 2 | off-screen << 4
mkwork gun "$root/build/tests/chimeratestgun.zip"
"$native" "$work/gun" --frames 40 --screenshot 25:"$work/gun-rest.tga" > "$work/gun-rest.txt" 2> /dev/null
"$native" "$work/gun" --frames 40 --press 10:P1Steering=-32768,P1Accelerator=32767,P1Brake=16384,P1GunX=65535,P1GunY=0,P1Offscreen:20 \
	--screenshot 25:"$work/gun-a.tga" > /dev/null 2> /dev/null
"$native" "$work/gun" --frames 40 --press 10:P1Steering=32767,P1GunX=0,P1GunY=65535:20 --screenshot 25:"$work/gun-b.tga" > /dev/null 2> /dev/null
rest="$(python3 "$root/tests/rowbits.py" "$work/gun-rest.tga" 38 39 40 41 42 43)"
ends="$(python3 "$root/tests/rowbits.py" "$work/gun-a.tga" 38 39 40 41 42 43)"
other="$(python3 "$root/tests/rowbits.py" "$work/gun-b.tga" 38 39 40 41 42 43)"
# rest: wheel 0x80, pedals 0, gun at 400, 272 (the middle of 150..651 and 80..465)
# ends: wheel 0, accelerator 0xFF, brake 0x7F, gun X 651 (0x28B), Y 80 (0x050), off-screen
# other: wheel 0xFF, gun X 150 (0x096), Y 465 (0x1D1)
if [ "$rest" = "80 00 00 90 10 05" ] && [ "$ends" = "00 ff 7f 8b 50 12" ] && [ "$other" = "ff 00 00 96 d1 04" ]; then
	pass "analog: the wheel, the pedals and the light gun reach the program as upstream's inputs give them (at rest: $rest; at the ends: $ends and $other)"
else
	fail "analog: at rest $rest (80 00 00 90 10 05), at the ends $ends (00 ff 7f 8b 50 12) and $other (ff 00 00 96 d1 04)"
fi
if grep -q "^activeAxes=P1Steering P1Accelerator P1Brake P1GunX P1GunY $" "$work/gun-rest.txt" && grep -q "^activeButtons=.*P1Trigger P1Offscreen $" "$work/gun-rest.txt"; then
	pass "analog: the wheel and gun cabinet shows the wheel, the pedals, the gun's aim, its trigger and off-screen, and no joystick"
else
	fail "analog: shown: $(grep '^active' "$work/gun-rest.txt" | tr '\n' ' ')"
fi

echo "== lag"
if [ "$(value "$work/n.txt" lagFrames)" = 75 ] && [ "$(value "$work/w.txt" lagFrames)" = 75 ]; then
	pass "lag: 75 of $frames frames are lag frames, the program's one frame in eight without a read of the controls"
else
	fail "lag: $(value "$work/n.txt" lagFrames) and $(value "$work/w.txt" lagFrames) lag frames, not 75"
fi

echo "== clock"
# the seconds' tens on row 2, column 3: digit d is drawn in colour 6 + d
"$native" "$work/tp" --frames 40 --screenshot 30:"$work/k0.tga" > /dev/null 2> /dev/null
mkwork tp25 "$testzip" '{"startTime": 946684825}'
"$native" "$work/tp25" --frames 40 --screenshot 30:"$work/k25.tga" > /dev/null 2> /dev/null
mkwork tp84 "$testzip" '{"startTime": 946684800}'
"$native" "$work/tp84" --frames 200 --screenshot 30:"$work/k84a.tga" --screenshot 62:"$work/k84b.tga" > /dev/null 2> /dev/null
t0="$(pixel "$work/k0.tga" 28 20)"; t25="$(pixel "$work/k25.tga" 28 20)"; o25="$(pixel "$work/k25.tga" 36 20)"
o0a="$(pixel "$work/k84a.tga" 36 20)"; o0b="$(pixel "$work/k84b.tga" 36 20)"
if [ "$t0" = 000052 ] && [ "$t25" = 000073 ] && [ "$o25" = 0041a4 ] && [ "$o0a" = 000052 ] && [ "$o0b" = 000062 ]; then
	pass "clock: the game reads 00:00:00 at the default Starting Clock, 00:00:25 at 946684825, and a second more at frame 62 (the hardware's 57.524 frames a second)"
else
	fail "clock: tens $t0 (000052) and $t25 (000073), ones $o25 (0041a4), at frames 30 and 62 $o0a (000052) $o0b (000062)"
fi
GATE_STALL_US=200000 "$wbx" "$core" "$work/tp" --frames 15 "${movie[@]}" > "$work/stall.txt" 2> /dev/null
"$wbx" "$core" "$work/tp" --frames 15 "${movie[@]}" > "$work/nostall.txt" 2> /dev/null
same clock "$work/stall.txt" "$work/nostall.txt" "the computer waiting 200 ms before each of 15 frames (3 s) changes nothing in the sandbox"
GATE_STALL_US=200000 "$native" "$work/tp" --frames 15 "${movie[@]}" > "$work/nstall.txt" 2> /dev/null
same clock "$work/nstall.txt" "$work/nostall.txt" "nor natively"
GATE_STALL_US=200000 "$hostclock" "$work/tp" --frames 15 "${movie[@]}" > "$work/hstall.txt" 2> /dev/null
"$hostclock" "$work/tp" --frames 15 "${movie[@]}" > "$work/hnostall.txt" 2> /dev/null
if grep -q '^frames=' "$work/hstall.txt" && [ "$(value "$work/hstall.txt" videoHash)" != "$(value "$work/hnostall.txt" videoHash)" ]; then
	pass "clock: the control - with upstream's clock (the computer's), the same 3 s stall changes the pictures"
else
	fail "clock: the control - upstream's clock with a stall gave the same pictures (the test could not see a clock)"
fi

echo "== save data"
mkdir -p "$work/sdn" "$work/sdw" "$work/sds"
"$native" "$work/tp" --frames 30 --savedata-out "$work/sdn" --screenshot 20:"$work/boot1.tga" > "$work/sdn.txt" 2> /dev/null
"$wbx" "$core" "$work/tp" --frames 30 --savedata-out "$work/sdw" > "$work/sdw.txt" 2> /dev/null
"$wbx" "$core" "$work/tp" --frames 30 --session-at 10 --savedata-out "$work/sds" > "$work/sds.txt" 2> /dev/null
if [ -s "$work/sdn/chimeratest.nv" ] && cmp -s "$work/sdn/chimeratest.nv" "$work/sdw/chimeratest.nv" && cmp -s "$work/sdn/chimeratest.nv" "$work/sds/chimeratest.nv" &&
   [ "$(find "$work/sdn" -type f | wc -l)" = 1 ] && head -c 64 "$work/sdn/chimeratest.nv" | grep -q "Supermodel NVRAM State" && grep -q "Backup RAM" "$work/sdn/chimeratest.nv" && grep -q "93C46" "$work/sdn/chimeratest.nv"; then
	pass "save data: Export Save Data is one file, chimeratest.nv, Supermodel's NVRAM format with the EEPROM and the backup RAM ($(stat -c %s "$work/sdn/chimeratest.nv") bytes); native = sandbox = a session"
else
	fail "save data: export: $(cd "$work/sdn" 2>/dev/null && find . -type f | tr '\n' ' ')"
fi
mkdir -p "$work/sdin"
cp "$testzip" "$work/sdn/chimeratest.nv" "$work/sdin/"
printf '{"game":["chimeratest.zip"],"savedata":["chimeratest.nv"]}' > "$work/sdin/slots"; printf '{}' > "$work/sdin/settings"
"$wbx" "$core" "$work/sdin" --frames 30 --screenshot 20:"$work/boot2.tga" > "$work/sdin.txt" 2> /dev/null
b1="$(pixel "$work/boot1.tga" 18 362)$(pixel "$work/boot1.tga" 26 362)"
b2="$(pixel "$work/boot2.tga" 18 362)$(pixel "$work/boot2.tga" 26 362)"
if [ "$b1" = ff00000000ff ] && [ "$b2" = 0000ffff0000 ]; then
	pass "save data: given back in a project (in the sandbox), the backup RAM is the earlier run's: the program counts its second boot, a new machine its first"
else
	fail "save data: boot counts: new $b1 (ff00000000ff), with the NVRAM $b2 (0000ffff0000)"
fi
mkdir -p "$work/sdbad"
cp "$testzip" "$work/sdbad/"; printf 'not an NVRAM file' > "$work/sdbad/other.nv"
printf '{"game":["chimeratest.zip"],"savedata":["other.nv"]}' > "$work/sdbad/slots"; printf '{}' > "$work/sdbad/settings"
"$native" "$work/sdbad" --frames 1 > "$work/sdbad.txt" 2> /dev/null
if grep -q "^loadError=error.save_not_nvram${S}other.nv" "$work/sdbad.txt"; then
	pass "save data: a file that is not an NVRAM file is refused, naming it"
else
	fail "save data: $(grep loadError "$work/sdbad.txt")"
fi

echo "== refusals"
mkdir -p "$work/notgame"
python3 -c "
import zipfile
z = zipfile.ZipFile('$work/notgame/other.zip', 'w'); z.writestr('readme.txt', 'not a Model 3 game'); z.close()"
printf '{"game":["other.zip"]}' > "$work/notgame/slots"; printf '{}' > "$work/notgame/settings"
"$native" "$work/notgame" --frames 1 > "$work/notgame.txt" 2> /dev/null
"$wbx" "$core" "$work/notgame" --frames 1 > "$work/notgamew.txt" 2> /dev/null
if grep -q "^loadError=error.not_a_game${S}" "$work/notgame.txt" && grep -q "^loadError=error.not_a_game${S}" "$work/notgamew.txt"; then
	pass "refusals: a zip with no Model 3 game in it: $(sed -n "s/^loadError=error.not_a_game${S}//p" "$work/notgame.txt")"
else
	fail "refusals: not a game: $(grep loadError "$work/notgame.txt" "$work/notgamew.txt")"
fi
mkdir -p "$work/nogame"
printf '{}' > "$work/nogame/slots"; printf '{}' > "$work/nogame/settings"
"$native" "$work/nogame" --frames 1 > "$work/nogame.txt" 2> /dev/null
if grep -q "^loadError=error.no_game" "$work/nogame.txt"; then
	pass "refusals: a project with no game says so"
else
	fail "refusals: no game: $(grep loadError "$work/nogame.txt")"
fi

echo "== real games"
# Each ROM set is a zip named as Supermodel and MAME name it, in the folder
# SUPERMODEL_ROMS names; a clone also needs its parent's zip there. Nothing
# of them is in this repository. Each runs from power-on with its movie,
# native against the sandbox, saved and loaded before every frame, and saved
# into a new host; the native run's pictures at the frames named are kept in
# build/gate (<set>-<frame>.tga) to be looked at, and the last one must be a
# drawn 3D scene (thousands of colours, not a black or blank screen).
#
# vf3 (Virtua Fighter 3): two coins (the default is two coins a credit)
# during the warning screen, Start once the title is up, the cursor one to
# the right and Punch to pick that fighter, then the fight (it begins about
# frame 1600): walks, punches, kicks, a guard, a crouch. 2400 frames.
# The other sets' movies only press coins, Start and a few directions: no
# one has run them yet.
real_movie() { # real_movie <set>: the presses, frames, session frame and pictures to keep
	case "$1" in
		vf3)
			movie=(--press 600:P1Coin:4 --press 620:P1Coin:4 --press 960:P1Start:4
				--press 1150:P1Right:6 --press 1200:P1Punch:6
				--press 1800:P1Right:40 --press 1860:P1Punch:3 --press 1890:P1Punch:3
				--press 1920:P1Kick:3 --press 1960:P1Left:30 --press 2000:P1Kick:3
				--press 2100:P1Guard:20 --press 2150:P1Down:20 --press 2200:P1Punch:3
				--press 2250:P1Kick:3 --press 2300:P1Right:30 --press 2340:P1Punch,P1Kick:3)
			frames="${SUPERMODEL_FRAMES:-2400}"; keep=(1000 1300 1650 1900 2200) ;;
		*)
			movie=(--press 600:P1Coin:4 --press 640:P1Start:4 --press 900:P1Start:4
				--press 1000:P1Right,P1Punch:30 --press 1200:P1Left:30)
			frames="${SUPERMODEL_FRAMES:-1800}"; keep=(600 1200) ;;
	esac
	session_at=$((frames * 5 / 6))
}
for set in vf3 scud srally2 lostwsga; do
	if [ -z "${SUPERMODEL_ROMS:-}" ] || [ ! -f "${SUPERMODEL_ROMS}/$set.zip" ]; then
		skip "real games: $set.zip (set SUPERMODEL_ROMS to a folder holding it)"
		continue
	fi
	real_movie "$set"
	mkwork "$set" "$SUPERMODEL_ROMS/$set.zip"
	shots=(--screenshot "$((frames - 1))":"$work/$set-last.tga")
	for f in "${keep[@]}"; do
		[ "$f" -lt "$frames" ] && shots+=(--screenshot "$f":"$work/$set-$f.tga")
	done
	t0=$(date +%s.%N)
	"$native" "$work/$set" --frames "$frames" "${movie[@]}" "${shots[@]}" > "$work/$set-n.txt" 2> "$work/$set-n.err"
	t1=$(date +%s.%N)
	"$wbx" "$core" "$work/$set" --frames "$frames" "${movie[@]}" > "$work/$set-w.txt" 2> "$work/$set-w.err"
	t2=$(date +%s.%N)
	speed="$(python3 -c "print(f'native {$frames / ($t1 - $t0):.1f}, sandbox {$frames / ($t2 - $t1):.1f} frames a second')")"
	same "real games" "$work/$set-n.txt" "$work/$set-w.txt" "$set: native = sandbox, $frames frames from power-on ($speed)"
	"$wbx" "$core" "$work/$set" --frames "$frames" "${movie[@]}" --rerecord > "$work/$set-r.txt" 2> "$work/$set-r.err"
	same "real games" "$work/$set-r.txt" "$work/$set-w.txt" "$set: saved and loaded before every frame = straight ($(sed -n 's/stateBytes=//p' "$work/$set-r.err") state bytes)"
	"$wbx" "$core" "$work/$set" --frames "$frames" "${movie[@]}" --session-at "$session_at" > "$work/$set-s.txt" 2> "$work/$set-s.err"
	same "real games" "$work/$set-s.txt" "$work/$set-w.txt" "$set: saved at frame $session_at, loaded into a new host = straight"
	colours="$(python3 "$root/tests/colours.py" "$work/$set-last.tga" 2> /dev/null || echo 0)"
	if [ "$colours" -gt 2000 ]; then
		pass "real games: $set: the last picture is drawn ($colours colours; pictures kept in $work/$set-*.tga)"
	else
		fail "real games: $set: the last picture holds $colours colours (black or blank?)"
	fi
done

# vf3's attract mode at frame 6900: a thin sliver whose quad weights came out
# NaN on llvmpipe drew a long white spike from the bottom left (issue 469,
# patch 0007). The corner's other white is the "Credit" text, about 255
# pixels; with the spike it was 963. The native build, pictures drawn from
# frame 3450 on (the turbo leg's half), about four minutes.
if [ -n "${SUPERMODEL_ROMS:-}" ] && [ -f "${SUPERMODEL_ROMS}/vf3.zip" ]; then
	"$native" "$work/vf3" --frames 6901 --turbo --screenshot 6900:"$work/vf3-6900.tga" > "$work/vf3-6900.txt" 2> "$work/vf3-6900.err"
	white="$(python3 "$root/tests/white-pixels.py" "$work/vf3-6900.tga" 0 300 200 384 2> /dev/null || echo 9999)"
	if [ "$white" -lt 400 ]; then
		pass "real games: vf3: no white spike at frame 6900 ($white white pixels in the bottom left corner, the text's)"
	else
		fail "real games: vf3: a white spike at frame 6900 ($white white pixels in the bottom left corner; the text has about 255)"
	fi
else
	skip "real games: vf3's frame 6900 (set SUPERMODEL_ROMS to a folder holding vf3.zip)"
fi

# llvmpipe's clipper on its own (issues 479 and 493): a value a shader asks
# for without perspective, at a corner from in front of the eye to just
# behind it. With issue 479's patch the clipper was still 3 pixels off at
# W = -0.000001 and 218 at -0.000000001, which smeared the floors and roads
# nearest the camera in scud, daytona2 and fvipers2; mesa-patches/0002 now
# takes each end's share from the W values. No game needed.
if clip_said="$("$root/build/native/noperspective-clip" 1 0.1 -0.01 -0.001 -0.0001 -0.00001 -0.000001 -0.0000001 -0.000000001 2>&1)"; then
	pass "llvmpipe: a value without perspective is right where a corner just behind the eye was clipped (worst $(echo "$clip_said" | awk '{print $7}' | sort -g | tail -1) pixels off)"
else
	fail "llvmpipe: a value without perspective is wrong where a corner just behind the eye was clipped: $(echo "$clip_said" | tr '\n' ';')"
fi

# vf3's subway floor (issue 479): a floor reaching behind the camera came out
# smeared, because llvmpipe's clipper measured where a new vertex lies on the
# wrong screen axis (mesa-patches/0002, made exact for issue 493). The
# movie: Test opens the test menu;
# Service and Test set Game Assignments' Stage Select to Challenger and leave
# both menus; two coins for each player; P1 Start and Punch pick Akira, P2
# Start and Punch pick Kage, and the challenger's Down and Punch pick the
# subway. At frame 4600 ("Round 1, Ready") the bottom left corner is floor.
# Its picture changes about 2.7 times as fast going down as going across when
# drawn right, and 1.5 times when smeared (down-across.py). The native build,
# pictures drawn from frame 4560 on, about a minute.
if [ -n "${SUPERMODEL_ROMS:-}" ] && [ -f "${SUPERMODEL_ROMS}/vf3.zip" ]; then
	m=(--press 300:TestA:4)
	for i in $(seq 0 8); do m+=(--press $((600 + i * 20)):ServiceA:4); done   # to Game Assignments
	m+=(--press 820:TestA:4)
	for i in $(seq 0 9); do m+=(--press $((1000 + i * 20)):ServiceA:4); done  # to Stage Select
	m+=(--press 1220:TestA:4)                                                   # Challenger
	for i in $(seq 0 5); do m+=(--press $((1260 + i * 20)):ServiceA:4); done  # to Exit
	m+=(--press 1400:TestA:4)
	for i in $(seq 0 5); do m+=(--press $((1480 + i * 20)):ServiceA:4); done  # to Exit
	m+=(--press 1620:TestA:4
		--press 2500:P1Coin:4 --press 2520:P1Coin:4 --press 2540:P2Coin:4 --press 2560:P2Coin:4
		--press 2700:P1Start:4 --press 3150:P1Punch:4 --press 3200:P2Start:4 --press 3850:P2Punch:4
		--press 4120:P2Down:4 --press 4160:P2Punch:4)
	"$native" "$work/vf3" --frames 4601 "${m[@]}" --draw-from 4560 --screenshot 4600:"$work/vf3-4600.tga" > "$work/vf3-4600.txt" 2> "$work/vf3-4600.err"
	ratio="$(python3 "$root/tests/down-across.py" "$work/vf3-4600.tga" 0 290 250 384 2> /dev/null || echo 0)"
	if [ "$ratio" -ge 210 ]; then
		pass "real games: vf3: the subway floor at frame 4600 is not smeared (it changes $ratio/100 times as fast going down as across; smeared it was 150)"
	else
		fail "real games: vf3: the subway floor at frame 4600 is smeared (it changes $ratio/100 times as fast going down as across; drawn right, about 270)"
	fi
else
	skip "real games: vf3's subway floor at frame 4600 (set SUPERMODEL_ROMS to a folder holding vf3.zip)"
fi

echo
echo "$passed passed, $fails failed, $skipped skipped"
[ "$fails" -eq 0 ]
