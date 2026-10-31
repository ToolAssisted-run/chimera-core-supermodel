#!/bin/bash
# The frontend half of the tests: the package, as Chimera loads it, playing
# this repository's Model 3 test program (tests/testprog, made by
# make-testprog.py) - so it needs no game of anyone's and runs anywhere.
#
# - chimera-run (the engine, no window): a movie from a file and the same
#   movie in a hand-written project. The last picture must be the native
#   reference's (run-native) at that frame.
# - Chimera's window, run headless (no display needed): the same project
#   opened and played through Lua, its last picture compared with the
#   reference's; and the package's bindings becoming Chimera's defaults.
#
# - A real game, where SUPERMODEL_ROMS names a folder holding vf3.zip
#   (Virtua Fighter 3; SKIP without it): a fight (two coins, Start, a fighter
#   picked, punches and kicks), 2400 frames, played by chimera-run from a
#   project, which also records the movie it played; that recording made
#   into a new project and played in a new chimera-run process; and the
#   first project opened in Chimera's window. Each last picture must be the
#   native reference's.
#
# Nothing is written under the Chimera checkout: the window's settings, its
# cache and recovery files, the Base path and the sandbox's log are all in
# build/frontend.
#
# Usage: tests/run-frontend.sh --chimera-root <chimera checkout> [-m <miniBox dir>] [--qt <Qt's lib folder>]
#   --qt (or CHIMERA_QT_LIB) names the folder of the Qt 6 libraries the window
#   was built against, when they are not where the system looks.
# Needs: the native reference built (waterbox/build-supermodel.sh native and
# waterbox/link-core.sh native), and
# Chimera built (its window and chimera-run).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
wb="$root/waterbox"
chimera_root=""
mb="${MINIBOX_DIR:-}"
qt_lib="${CHIMERA_QT_LIB:-}"
while [ $# -gt 0 ]; do
	case "$1" in
		--chimera-root) chimera_root="$2"; shift ;;
		-m) mb="$2"; shift ;;
		--qt) qt_lib="$2"; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done
[ -n "$chimera_root" ] && [ -d "$chimera_root" ] || { echo "say where Chimera is: --chimera-root <chimera checkout>" >&2; exit 2; }
chimera_root="$(cd "$chimera_root" && pwd)"
[ -n "$mb" ] || mb="$chimera_root/extern/chimera-common-minibox"

chimera_exe="$chimera_root/build/meson-linux/source/ui/chimera"
crun="$chimera_root/build/dll/chimera-run"
[ -x "$crun" ] || crun="$chimera_root/build/meson-linux/chimera-run"
rn="$root/build/native/run-native"
game="$root/build/tests/chimeratest.zip"
work="$root/build/frontend"
rm -rf "$work"
mkdir -p "$work/data" "$work/native"

ok=0
failed=0
skipped=0
report() {
	printf "%-22s %-6s %s\n" "$1" "$2" "$3"
	case "$2" in PASS) ok=$((ok+1)) ;; SKIP) skipped=$((skipped+1)) ;; *) failed=$((failed+1)) ;; esac
}
printf "%-22s %-6s %s\n" "Check" "Result" "Detail"
printf "%-22s %-6s %s\n" "-----" "------" "------"

[ -x "$rn" ] || { echo "the native reference is not built: $rn (waterbox/link-core.sh native)" >&2; exit 1; }
python3 "$here/testprog/make-testprog.py" "$root/build/tests" > "$work/testprog.log" 2>&1 || { echo "the test program could not be made" >&2; exit 1; }

# ---------------------------------------------------------------- the package
if bash "$wb/build-package.sh" -m "$mb" -o "$work/pkg" > "$work/package.log" 2>&1; then
	report "package" PASS "$(grep 'package sha1' "$work/package.log")"
else
	report "package" FAIL "see build/frontend/package.log"; echo; echo "$ok ok, $failed failed"; exit 1
fi
pkg="$work/pkg/supermodel.chimeraCore"

# The movie: P1 Right moves the block from frame 40 to 70, P1 Up from 150
# to 170, P1 Punch is held from 100 on, P1 Start at 200. The last frame is
# 299: the block moved, the punch bit and the clock on the screen.
frames=300
cp "$game" "$work/native/"
printf '{"game":["%s"]}' "$(basename "$game")" > "$work/native/slots"
printf '{}' > "$work/native/settings"
"$rn" "$work/native" --frames "$frames" --press 40:P1Right:30 --press 150:P1Up:20 --press 100:P1Punch:200 --press 200:P1Start:3 \
	--screenshot "$((frames - 1)):$work/native.last.tga" > "$work/native.txt" 2> "$work/native.err"
mkdir -p "$work/proj"
cp "$game" "$work/proj/"
python3 "$here/make-project.py" "$pkg" "$work/proj/test.chimeraProject" "$frames" \
	"press=P1 Right:40:30" "press=P1 Up:150:20" "press=P1 Punch:100:200" "press=P1 Start:200:3" log="$work/test.log" \
	-- "game=$work/proj/$(basename "$game")"

# ---------------------------------------------------------------- chimera-run
if [ ! -x "$crun" ]; then
	report "engine" SKIP "no chimera-run at $crun"
else
	# a game runs only in a project (Chimera, 2026-10-26): the game and the movie
	# made into one by chimera-run
	( cd "$work" && "$crun" --new-project "$work/movie.chimeraProject" "$pkg" "$game" test.log > "$work/movie.make.log" 2>&1 \
		&& timeout 900 "$crun" --project "$work/movie.chimeraProject" "$pkg" --files "$(dirname "$game")" --frames "$frames" \
		--screenshot "$((frames - 1))=$work/run.last.tga" --meta "$work/run.meta" > "$work/run.log" 2>&1 )
	if grep -q '^status=OK' "$work/run.meta" 2>/dev/null &&
	   python3 "$here/compare-pictures.py" "$work/native.last.tga" "$work/run.last.tga" > "$work/run.pic" 2>&1; then
		report "engine:movie" PASS "$frames frames from a movie made into a project (the block moved, Punch held): the last picture is the reference's, $(cat "$work/run.pic")"
	else
		report "engine:movie" FAIL "$(grep -m1 detail= "$work/run.meta" 2>/dev/null) $(cat "$work/run.pic" 2>/dev/null) (build/frontend/run.log)"
	fi

	( cd "$work" && timeout 900 "$crun" --project "$work/proj/test.chimeraProject" "$pkg" --files "$work/proj" --frames "$frames" \
		--screenshot "$((frames - 1))=$work/proj.last.tga" --dump "Main RAM@1000+4=$work/frame.bus" \
		--dump "Main RAM words=$work/ram.words" --meta "$work/proj.meta" > "$work/proj.log" 2>&1 )
	if grep -q '^status=OK' "$work/proj.meta" 2>/dev/null &&
	   python3 "$here/compare-pictures.py" "$work/native.last.tga" "$work/proj.last.tga" > "$work/proj.pic" 2>&1; then
		report "engine:project" PASS "the same movie in a project, the zip in its slot: the same last picture"
	else
		report "engine:project" FAIL "$(grep -m1 detail= "$work/proj.meta" 2>/dev/null) $(cat "$work/proj.pic" 2>/dev/null) (build/frontend/proj.log)"
	fi
	# the program counts its frames at RAM 0x1000: the Main RAM bus reads it in
	# the PowerPC's byte order, the hidden domain in Supermodel's own
	bus="$(od -An -tx1 "$work/frame.bus" 2>/dev/null | tr -d ' \n')"
	words="$(od -An -tx1 -j 4096 -N 4 "$work/ram.words" 2>/dev/null | tr -d ' \n')"
	want="$(printf '%08x' "$frames")"
	if [ "$bus" = "$want" ] && [ "$words" = "$(echo "$want" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')" ]; then
		report "engine:memory" PASS "after $frames frames the program's frame count reads $bus on the Main RAM bus (the PowerPC's order) and $words in the hidden domain"
	else
		report "engine:memory" FAIL "the frame count reads '$bus' on the bus and '$words' in the domain, not $want"
	fi
fi

# ---------------------------------------------------------------- a real game: vf3
# The fight the core's gate plays (waterbox/run-gate.sh, real_movie vf3),
# here as a project. Each entry: control:first frame:frames held.
vf3_frames=2400
vf3_presses=("P1 Coin:600:4" "P1 Coin:620:4" "P1 Start:960:4" "P1 Right:1150:6" "P1 Punch:1200:6"
	"P1 Right:1800:40" "P1 Punch:1860:3" "P1 Punch:1890:3" "P1 Kick:1920:3" "P1 Left:1960:30"
	"P1 Kick:2000:3" "P1 Guard:2100:20" "P1 Down:2150:20" "P1 Punch:2200:3" "P1 Kick:2250:3"
	"P1 Right:2300:30" "P1 Punch:2340:3" "P1 Kick:2340:3")
vf3_zip="${SUPERMODEL_ROMS:-}/vf3.zip"
have_vf3=0
if [ -n "${SUPERMODEL_ROMS:-}" ] && [ -f "$vf3_zip" ]; then
	have_vf3=1
	mkdir -p "$work/vf3/native" "$work/vf3/proj"
	cp "$vf3_zip" "$work/vf3/native/"; cp "$vf3_zip" "$work/vf3/proj/"
	printf '{"game":["vf3.zip"]}' > "$work/vf3/native/slots"; printf '{}' > "$work/vf3/native/settings"
	native_press=(); project_press=()
	for p in "${vf3_presses[@]}"; do
		IFS=: read -r name at len <<< "$p"
		native_press+=(--press "$at:${name// /}:$len")
		project_press+=("press=$name:$at:$len")
	done
	"$rn" "$work/vf3/native" --frames "$vf3_frames" "${native_press[@]}" \
		--screenshot "$((vf3_frames - 1)):$work/vf3/native.last.tga" > "$work/vf3/native.txt" 2> "$work/vf3/native.err"
	python3 "$here/make-project.py" "$pkg" "$work/vf3/proj/vf3.chimeraProject" "$vf3_frames" "${project_press[@]}" \
		-- "game=$work/vf3/proj/vf3.zip" > "$work/vf3/project.log" 2>&1
fi
if [ "$have_vf3" = 0 ]; then
	report "engine:vf3" SKIP "no vf3.zip (set SUPERMODEL_ROMS to a folder holding it)"
elif [ ! -x "$crun" ]; then
	report "engine:vf3" SKIP "no chimera-run at $crun"
else
	# the project played, and the movie the engine recorded while playing it
	( cd "$work/vf3" && timeout 1800 "$crun" --project "$work/vf3/proj/vf3.chimeraProject" "$pkg" --files "$work/vf3/proj" \
		--frames "$vf3_frames" --record "$work/vf3/recorded.log" \
		--screenshot "$((vf3_frames - 1))=$work/vf3/run.last.tga" --meta "$work/vf3/run.meta" > "$work/vf3/run.log" 2>&1 )
	if grep -q '^status=OK' "$work/vf3/run.meta" 2>/dev/null &&
	   python3 "$here/compare-pictures.py" "$work/vf3/native.last.tga" "$work/vf3/run.last.tga" > "$work/vf3/run.pic" 2>&1; then
		report "engine:vf3" PASS "Virtua Fighter 3, a fight from a project, $vf3_frames frames: the last picture is the native reference's, $(cat "$work/vf3/run.pic")"
	else
		report "engine:vf3" FAIL "$(grep -m1 detail= "$work/vf3/run.meta" 2>/dev/null) $(cat "$work/vf3/run.pic" 2>/dev/null) (build/frontend/vf3/run.log)"
	fi
	# the recorded movie made into a new project and played by a new process
	( cd "$work/vf3" && "$crun" --new-project "$work/vf3/replay.chimeraProject" "$pkg" "$vf3_zip" "$work/vf3/recorded.log" > "$work/vf3/replay.make.log" 2>&1 \
		&& timeout 1800 "$crun" --project "$work/vf3/replay.chimeraProject" "$pkg" --files "$SUPERMODEL_ROMS" --frames "$vf3_frames" \
		--screenshot "$((vf3_frames - 1))=$work/vf3/replay.last.tga" --meta "$work/vf3/replay.meta" > "$work/vf3/replay.log" 2>&1 )
	if grep -q '^status=OK' "$work/vf3/replay.meta" 2>/dev/null &&
	   python3 "$here/compare-pictures.py" "$work/vf3/native.last.tga" "$work/vf3/replay.last.tga" > "$work/vf3/replay.pic" 2>&1; then
		report "engine:vf3-replay" PASS "the movie chimera-run recorded, made into a new project and replayed in a new process: the same last picture"
	else
		report "engine:vf3-replay" FAIL "$(grep -m1 detail= "$work/vf3/replay.meta" 2>/dev/null) $(cat "$work/vf3/replay.pic" 2>/dev/null) (build/frontend/vf3/replay.log)"
	fi
fi

# ---------------------------------------------------------------- Chimera itself
if [ ! -x "$chimera_exe" ]; then
	report "window" SKIP "Chimera's window is not built ($chimera_exe)"
	echo; echo "$ok ok, $failed failed, $skipped skipped"; [ "$failed" -eq 0 ]; exit
fi
# the window run headless: the cores a folder of the run's own holds (this
# package alone), its settings, cache and recovery files the run's own, and
# nothing carried over from a Chimera installed on this machine; nothing is
# written in the Chimera checkout
mkdir -p "$work/cores"
cp "$pkg" "$work/cores/"
export ALSOFT_DRIVERS=null CHIMERA_CORES_DIR="$work/cores" CHIMERA_QT_CACHE="$work/qt-cache" CHIMERA_QT_RECOVERY="$work/qt-recovery" \
	CHIMERA_QT_HASHES="$work/qt-file-hashes.txt" CHIMERA_QT_CHIMERA_SETTINGS="$work/no-chimera-config.ini"
export MINIBOX_LOG="$work/minibox.log"
[ -n "$qt_lib" ] && export LD_LIBRARY_PATH="$qt_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# settings of its own, with the Base path (and so every folder Chimera
# writes by default) in the work dir
config="$work/settings.json"
python3 -c 'import json, sys; json.dump({"paths.base": sys.argv[2]}, open(sys.argv[1], "w"), indent=2)' "$config" "$work"

gui() {
	# gui <tag> <config> <project> <frames>
	local tag="$1" cfg="$2" project="$3" nframes="$4"
	mkdir -p "$work/$tag"
	printf 'frames=%s\nmeta=%s\nshot=%s\n' "$nframes" "$work/$tag/meta.txt" "$work/$tag/last.png" > "$work/$tag/job.txt"
	( cd "$work" && MINIHAWK_JOB="$work/$tag/job.txt" timeout 900 "$chimera_exe" --headless "--config=$cfg" \
		"--core=$pkg" "--project=$project" "--lua=$here/frontend.lua" ) > "$work/$tag.log" 2>&1
}
meta() { sed -n "s/^$2=//p" "$work/$1/meta.txt" 2>/dev/null; }

# the movie's last frame is shown after frame 299 has run: the window has
# advanced 300 frames
gui gui "$config" "$work/proj/test.chimeraProject" "$frames"
if [ "$(meta gui status)" = "OK" ] && python3 "$here/compare-pictures.py" "$work/native.last.tga" "$work/gui/last.png" > "$work/gui.pic" 2>&1; then
	report "window:project" PASS "the project opened in Chimera: after $(meta gui frames) frames, $(meta gui width)x$(meta gui height), the picture is the reference's"
else
	report "window:project" FAIL "status $(meta gui status) $(meta gui detail); $(cat "$work/gui.pic" 2>/dev/null) (build/frontend/gui.log)"
fi

# the real game's project opened in the window
if [ "$have_vf3" = 1 ]; then
	gui gui-vf3 "$config" "$work/vf3/proj/vf3.chimeraProject" "$vf3_frames"
	if [ "$(meta gui-vf3 status)" = "OK" ] && python3 "$here/compare-pictures.py" "$work/vf3/native.last.tga" "$work/gui-vf3/last.png" > "$work/gui-vf3.pic" 2>&1; then
		report "window:vf3" PASS "the vf3 fight's project opened in Chimera: after $(meta gui-vf3 frames) frames, $(meta gui-vf3 width)x$(meta gui-vf3 height), the picture is the reference's"
	else
		report "window:vf3" FAIL "status $(meta gui-vf3 status) $(meta gui-vf3 detail); $(cat "$work/gui-vf3.pic" 2>/dev/null) (build/frontend/gui-vf3.log)"
	fi
else
	report "window:vf3" SKIP "no vf3.zip (set SUPERMODEL_ROMS to a folder holding it)"
fi

# the bindings the package ships are the machine's when nobody changed them
# (the window keeps only the keys a person changed; fresh settings have none)
mkdir -p "$work/keys"
printf 'out=%s/keys/controls.json\nmeta=%s/keys/meta.txt\n' "$work" "$work" > "$work/keys/job.txt"
( cd "$work" && MINIHAWK_JOB="$work/keys/job.txt" timeout 900 "$chimera_exe" --headless "--config=$work/settings.keys.json" \
	"--core=$pkg" "--project=$work/proj/test.chimeraProject" "--lua=$here/dump-controls.lua" ) > "$work/keys.log" 2>&1
if grep -q "^status=OK" "$work/keys/meta.txt" 2>/dev/null && python3 "$here/check-keybinds.py" "$work/keys/controls.json" "$wb/default_keybinds.json" "Model 3 Cabinet" "P1 Punch" > "$work/keys.txt" 2>&1; then
	report "window:keybinds" PASS "$(cat "$work/keys.txt")"
else
	report "window:keybinds" FAIL "$(head -1 "$work/keys.txt" 2>/dev/null) (build/frontend/keys.log)"
fi

echo
echo "$ok ok, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
