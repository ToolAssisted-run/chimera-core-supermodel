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
#   controls     a press reaches the program through the Model 3's input
#                registers, and the controls a cabinet lacks are not shown
#   lag          a frame in which the program did not read its controls (one
#                in eight, by design) is a lag frame, and only those
#   clock        the real-time clock is the Starting Clock and the frames
#                run; the computer stalling between frames changes nothing;
#                and the same test sees it when the clock is the computer's
#                (upstream's RTC72421.cpp linked in instead: the control)
#   refusals     a zip that holds no Model 3 game, and a project without a
#                game, each say why
#   real games   (SKIP without SUPERMODEL_ROMS) native = sandbox and a
#                session, on each ROM set named below that is there
#
# What the test program does not stand in for: the 3D renderer (it draws no
# polygons), the sound board's sound (it gives the sound board no program,
# so the sound is silence, compared all the same), the MPEG board, the
# drive boards, the analog controls, the light guns, and a real game's
# timing. The real game tests are where those are seen.
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
if grep -q "game.xml now names" "$root/build/gate-testprog.log"; then
	echo "the test program changed: tests/testprog/game.xml was rewritten; commit it"
fi
step "the LLVM builds" "$root/build/gate-llvm.log" bash -c "bash '$here/build-llvm.sh' native && bash '$here/build-llvm.sh' guest -m '$mb'"
step "the Mesa builds" "$root/build/gate-mesa.log" bash -c "bash '$here/setup-mesa.sh' -m '$mb' && bash '$here/setup-mesa.sh' -n"
step "the sandbox's math for the native build" "$root/build/gate-libm.log" bash "$here/make-native-libm.sh" "$mb"
step "the native Supermodel build" "$root/build/gate-native.log" bash "$here/build-supermodel.sh" native -m "$mb"
step "the guest Supermodel build" "$root/build/gate-guest.log" bash "$here/build-supermodel.sh" guest -m "$mb"
step "the native link" "$root/build/gate-link-native.log" bash "$here/link-core.sh" native -m "$mb"
step "the guest link" "$root/build/gate-link-guest.log" bash "$here/link-core.sh" guest -m "$mb"
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
# of them is in this repository. Each runs from power-on with coins and
# Start pressed, native against the sandbox and saved into a new host.
real_frames="${SUPERMODEL_FRAMES:-1800}"
real_movie=(--press 600:P1Coin:4 --press 640:P1Start:4 --press 900:P1Start:4 --press 1000:P1Right,P1Punch:30 --press 1200:P1Left:30)
for set in vf3 scud srally2 lostwsga; do
	if [ -z "${SUPERMODEL_ROMS:-}" ] || [ ! -f "${SUPERMODEL_ROMS}/$set.zip" ]; then
		skip "real games: $set.zip (set SUPERMODEL_ROMS to a folder holding it)"
		continue
	fi
	mkwork "$set" "$SUPERMODEL_ROMS/$set.zip"
	"$native" "$work/$set" --frames "$real_frames" "${real_movie[@]}" --screenshot "$((real_frames - 1))":"$work/$set-last.tga" > "$work/$set-n.txt" 2> "$work/$set-n.err"
	"$wbx" "$core" "$work/$set" --frames "$real_frames" "${real_movie[@]}" > "$work/$set-w.txt" 2> "$work/$set-w.err"
	same "real games" "$work/$set-n.txt" "$work/$set-w.txt" "$set: native = sandbox, $real_frames frames from power-on"
	"$wbx" "$core" "$work/$set" --frames "$real_frames" "${real_movie[@]}" --session-at "$((real_frames / 2))" > "$work/$set-s.txt" 2> "$work/$set-s.err"
	same "real games" "$work/$set-s.txt" "$work/$set-w.txt" "$set: saved at frame $((real_frames / 2)), loaded into a new host = straight"
done

echo
echo "$passed passed, $fails failed, $skipped skipped"
[ "$fails" -eq 0 ]
