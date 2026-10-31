#!/usr/bin/env bash
# Builds Supermodel's emulation and the core's frontend as static libraries,
# for the native reference or for the sandbox:
#
#   build-supermodel.sh native -m <miniBox>   build/native/libsupermodel.a ...
#   build-supermodel.sh guest  -m <miniBox>   build/guest/libsupermodel.a ...
#
# extern/supermodel is never built in and never edited: it is copied once to
# build/supermodel-src and patches/ are applied there (all of them or none: a
# copy that already has them is used as it is). The 68000 core is generated
# there by upstream's own generator (m68kmake), built for this computer.
#
# The guest's flags are miniBox's: musl through its specs, the large code
# model, no PIC, no red zone, no stack protector through %fs, no CET. The
# native flavour is the same code with the computer's own C library; it
# links the sandbox's maths (make-native-libm.sh) so both compute alike.
#
# Usage: ./build-supermodel.sh native|guest -m <miniBox checkout> [-j N]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
flavour="${1:-}"
shift || true
minibox="${MINIBOX_DIR:-}"
jobs=4
while getopts "m:j:" opt; do
	case "$opt" in
		m) minibox="$OPTARG" ;;
		j) jobs="$OPTARG" ;;
		*) exit 2 ;;
	esac
done
case "$flavour" in native | guest) ;; *) echo "usage: $0 native|guest -m <miniBox> [-j N]" >&2; exit 2 ;; esac
[ -n "$minibox" ] || { echo "build-supermodel: pass -m <miniBox checkout>" >&2; exit 2; }
minibox="$(cd "$minibox" && pwd)"

upstream="$root/extern/supermodel"
[ -f "$upstream/Src/Model3/Model3.cpp" ] || { echo "build-supermodel: extern/supermodel is empty (git submodule update --init)" >&2; exit 1; }
top="$(git -C "$upstream" rev-parse --show-toplevel 2>/dev/null || true)"
[ "$top" = "$upstream" ] || { echo "build-supermodel: extern/supermodel is not its own checkout ($top)" >&2; exit 1; }

# ---- the patched copy ----
src="$root/build/supermodel-src"
stamp="$src/.chimera-source"
want="$(git -C "$upstream" rev-parse HEAD) $(find "$root/patches" -maxdepth 1 -name '*.patch' | sort | xargs -r cat | sha1sum | cut -c1-40)"
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$want" ]; then
	rm -rf "$src"
	mkdir -p "$src"
	git -C "$upstream" archive HEAD | tar -x -C "$src"
	for p in "$root"/patches/*.patch; do
		[ -f "$p" ] || continue
		echo "build-supermodel: applying $(basename "$p")"
		patch -d "$src" -p1 --quiet --no-backup-if-mismatch < "$p"
	done
	echo "$want" > "$stamp"
	# a new source tree makes every object stale
	rm -rf "$root/build/native/obj" "$root/build/guest/obj"
fi

# ---- the 68000 core, generated ----
gen="$src/gen"
if [ ! -f "$gen/m68kops.c" ]; then
	mkdir -p "$gen"
	gcc -O1 -o "$gen/m68kmake" "$src/Src/CPU/68K/Musashi/m68kmake.c"
	(cd "$src" && "$gen/m68kmake" "$gen" Src/CPU/68K/Musashi/m68k_in.c)
fi

# ---- the game list the core carries: upstream's, and this repository's
# test program's entry (tests/testprog/game.xml) before its end ----
python3 - "$src/Config/Games.xml" "$root/tests/testprog/game.xml" "$gen/games_xml.inc" <<'PYXML'
import os, sys
games, extra, out = sys.argv[1:4]
text = open(games, "rb").read()
if os.path.exists(extra):
    end = text.rindex(b"</games>")
    text = text[:end] + open(extra, "rb").read() + text[end:]
body = ",".join(str(b) for b in text)
new = ("/* games_xml.inc - written by build-supermodel.sh: Supermodel's Games.xml */\n"
       "static const char games_xml[] = {" + body + ",0};\n")
if not os.path.exists(out) or open(out).read() != new:
    open(out, "w").write(new)
PYXML

common="-O2 -g -fno-strict-aliasing -fcf-protection=none -Wno-unused-result -Wno-format-truncation"
case "$flavour" in
	native)
		cc=gcc
		cxx=g++
		cflags="$common"
		cxxflags="$common -std=c++17"
		kit="$here/native-shim:$minibox/source/guest/include:$minibox/extern/jsmn"
		;;
	guest)
		sr="$minibox/build/meson-cpp/guest-sysroot"
		[ -f "$sr/lib/musl-gcc.specs" ] || { echo "build-supermodel: no guest sysroot at $sr (build miniBox's meson-cpp)" >&2; exit 1; }
		gccver="$(basename "$(ls -d "$sr"/include/c++/* | head -1)")"
		cc="gcc -specs $sr/lib/musl-gcc.specs"
		cxx="g++ -specs $sr/lib/musl-gcc.specs"
		wbx="-mcmodel=large -mno-red-zone -mstack-protector-guard=global -fno-stack-protector -fno-pic -fno-pie"
		cflags="$common $wbx"
		cxxflags="$common $wbx -std=c++17 -I$sr/include/c++/$gccver -I$sr/include/c++/$gccver/x86_64-linux-musl"
		kit="$minibox/extern/emulibc:$minibox/source/guest/include:$minibox/extern/jsmn"
		;;
esac

out="$root/build/$flavour/obj"
mkdir -p "$out"
make -s -f "$here/supermodel.mk" -j "$jobs" \
	SRC="$src" OUT="$out" GEN="$gen" WB="$here" KIT="$kit" MESA="$root/build/mesa" \
	CC="$cc" CXX="$cxx" CFLAGS="$cflags" CXXFLAGS="$cxxflags"
echo "build-supermodel: $out/libsupermodel.a $out/libchimeracore.a"
