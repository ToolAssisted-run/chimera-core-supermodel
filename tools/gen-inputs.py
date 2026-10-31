#!/usr/bin/env python3
"""gen-inputs.py - the core's controls, from one list.

Writes, from the table below:
  waterbox/core/chimera_inputs.inc   the C++ table chimera_input.cpp walks
  waterbox/input-names.h             the test harness's tokens
  the "input" object of waterbox/waterbox.config (the rest of the file is
  kept as it is)

Every control is one of Supermodel's inputs (Src/Inputs/Inputs.cpp), by the
game flags that say which cabinets have it (Game::INPUT_*, from each game's
<inputs> in Games.xml). A game shows only the controls its cabinet has
(IsButtonActive, IsAxisActive). Values are written straight into the
input's value as Supermodel's own polling would leave it.

Usage: tools/gen-inputs.py            (writes the three)
       tools/gen-inputs.py --check    (says whether they are up to date)
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (name, game flags, what it writes, mnemonic)
#   sw:<member>        a switch: 1 while held
#   gear:<1-4|0|up|down>  the 4-speed shifter (and the up/down shifter's switch)
#   trig:<player>      the light gun's trigger and the analog gun's left one
#   off:<player>       the light gun pointed off the screen (reload)
BUTTONS = [
    ("P1 Coin", "COMMON", "sw:coin[0]", "c"),
    ("P1 Start", "COMMON", "sw:start[0]", "S"),
    ("P2 Coin", "COMMON", "sw:coin[1]", "c"),
    ("P2 Start", "COMMON", "sw:start[1]", "S"),
    ("Service A", "COMMON", "sw:service[0]", "v"),
    ("Test A", "COMMON", "sw:test[0]", "t"),
    ("Service B", "COMMON", "sw:service[1]", "V"),
    ("Test B", "COMMON", "sw:test[1]", "T"),

    ("P1 Up", "JOYSTICK1", "sw:up[0]", "U"),
    ("P1 Down", "JOYSTICK1", "sw:down[0]", "D"),
    ("P1 Left", "JOYSTICK1", "sw:left[0]", "L"),
    ("P1 Right", "JOYSTICK1", "sw:right[0]", "R"),
    ("P2 Up", "JOYSTICK2", "sw:up[1]", "U"),
    ("P2 Down", "JOYSTICK2", "sw:down[1]", "D"),
    ("P2 Left", "JOYSTICK2", "sw:left[1]", "L"),
    ("P2 Right", "JOYSTICK2", "sw:right[1]", "R"),

    ("P1 Punch", "FIGHTING", "sw:punch[0]", "P"),
    ("P1 Kick", "FIGHTING", "sw:kick[0]", "K"),
    ("P1 Guard", "FIGHTING", "sw:guard[0]", "G"),
    ("P1 Escape", "FIGHTING", "sw:escape[0]", "E"),
    ("P2 Punch", "FIGHTING", "sw:punch[1]", "P"),
    ("P2 Kick", "FIGHTING", "sw:kick[1]", "K"),
    ("P2 Guard", "FIGHTING", "sw:guard[1]", "G"),
    ("P2 Escape", "FIGHTING", "sw:escape[1]", "E"),

    ("P1 Shift", "SPIKEOUT", "sw:shift", "h"),
    ("P1 Beat", "SPIKEOUT", "sw:beat", "B"),
    ("P1 Charge", "SPIKEOUT", "sw:charge", "H"),
    ("P1 Jump", "SPIKEOUT", "sw:jump", "J"),

    ("P1 Short Pass", "SOCCER", "sw:shortPass[0]", "p"),
    ("P1 Long Pass", "SOCCER", "sw:longPass[0]", "l"),
    ("P1 Shoot", "SOCCER", "sw:shoot[0]", "o"),
    ("P2 Short Pass", "SOCCER", "sw:shortPass[1]", "p"),
    ("P2 Long Pass", "SOCCER", "sw:longPass[1]", "l"),
    ("P2 Shoot", "SOCCER", "sw:shoot[1]", "o"),

    ("P1 Shift Up", "SHIFTUPDOWN|SHIFT4", "gear:up", "+"),
    ("P1 Shift Down", "SHIFTUPDOWN|SHIFT4", "gear:down", "-"),
    ("P1 Gear 1", "SHIFT4", "gear:1", "1"),
    ("P1 Gear 2", "SHIFT4", "gear:2", "2"),
    ("P1 Gear 3", "SHIFT4", "gear:3", "3"),
    ("P1 Gear 4", "SHIFT4", "gear:4", "4"),
    ("P1 Gear Neutral", "SHIFT4", "gear:0", "N"),
    ("P1 View Change", "VIEWCHANGE", "sw:viewChange", "V"),
    ("P1 View 1", "VR4", "sw:vr[0]", "5"),
    ("P1 View 2", "VR4", "sw:vr[1]", "6"),
    ("P1 View 3", "VR4", "sw:vr[2]", "7"),
    ("P1 View 4", "VR4", "sw:vr[3]", "8"),
    ("P1 Hand Brake", "HANDBRAKE", "sw:handBrake", "b"),
    ("P1 Music Select", "HARLEY", "sw:musicSelect", "m"),

    ("P1 Left Stick Up", "TWIN_JOYSTICKS", "sw:twinJoyUp1", "Q"),
    ("P1 Left Stick Down", "TWIN_JOYSTICKS", "sw:twinJoyDown1", "A"),
    ("P1 Left Stick Left", "TWIN_JOYSTICKS", "sw:twinJoyLeft1", "Z"),
    ("P1 Left Stick Right", "TWIN_JOYSTICKS", "sw:twinJoyRight1", "X"),
    ("P1 Right Stick Up", "TWIN_JOYSTICKS", "sw:twinJoyUp2", "y"),
    ("P1 Right Stick Down", "TWIN_JOYSTICKS", "sw:twinJoyDown2", "n"),
    ("P1 Right Stick Left", "TWIN_JOYSTICKS", "sw:twinJoyLeft2", "f"),
    ("P1 Right Stick Right", "TWIN_JOYSTICKS", "sw:twinJoyRight2", "g"),
    ("P1 Left Shot", "TWIN_JOYSTICKS", "sw:twinJoyShot1", "e"),
    ("P1 Right Shot", "TWIN_JOYSTICKS", "sw:twinJoyShot2", "r"),
    ("P1 Left Turbo", "TWIN_JOYSTICKS", "sw:twinJoyTurbo1", "i"),
    ("P1 Right Turbo", "TWIN_JOYSTICKS", "sw:twinJoyTurbo2", "j"),

    ("P1 Stick Trigger 1", "ANALOG_JOYSTICK", "sw:analogJoyTrigger1", "!"),
    ("P1 Stick Trigger 2", "ANALOG_JOYSTICK", "sw:analogJoyTrigger2", "@"),
    ("P1 Event 1", "ANALOG_JOYSTICK", "sw:analogJoyEvent1", "#"),
    ("P1 Event 2", "ANALOG_JOYSTICK", "sw:analogJoyEvent2", "$"),

    ("P1 Trigger", "GUN1|ANALOG_GUN1", "trig:0", "F"),
    ("P1 Trigger 2", "ANALOG_GUN1", "sw:analogTriggerRight[0]", "%"),
    ("P1 Off-screen", "GUN1", "off:0", "O"),
    ("P2 Trigger", "GUN2|ANALOG_GUN2", "trig:1", "F"),
    ("P2 Trigger 2", "ANALOG_GUN2", "sw:analogTriggerRight[1]", "%"),
    ("P2 Off-screen", "GUN2", "off:1", "O"),

    ("P1 Ski Pole Left", "SKI", "sw:skiPollLeft", "<"),
    ("P1 Ski Pole Right", "SKI", "sw:skiPollRight", ">"),
    ("P1 Ski Select 1", "SKI", "sw:skiSelect1", "["),
    ("P1 Ski Select 2", "SKI", "sw:skiSelect2", "^"),
    ("P1 Ski Select 3", "SKI", "sw:skiSelect3", "]"),

    ("P1 Pedal", "MAGTRUCK", "sw:magicalPedal1", "d"),
    ("P2 Pedal", "MAGTRUCK", "sw:magicalPedal2", "d"),

    ("P1 Cast", "FISHING", "sw:fishingCast", "C"),
    ("P1 Select", "FISHING", "sw:fishingSelect", "s"),
]

# An axis's range on Chimera's side:
#   signed  -32768 (left, up) to 32767 (right, down), at rest 0: a stick, a wheel
#   pedal   0 (let go) to 32767 (all the way)
#   place   0 (left, top edge of the picture) to 65535 (right, bottom edge),
#           a light gun's aim (Chimera's absolute axes)
# and what it writes: one or more of Supermodel's inputs, each with the
# (min, rest, max) values Supermodel gives it (Src/Inputs/Inputs.cpp). A
# "place" or "signed" axis goes from min to max across its range, passing
# rest in the middle; a pedal from min to max.
AXES = [
    ("P1 Steering", "VEHICLE", "signed", "Steer", [("steering", 0x00, 0x80, 0xFF)]),
    ("P1 Accelerator", "VEHICLE", "pedal", "Accel", [("accelerator", 0x00, 0x00, 0xFF)]),
    ("P1 Brake", "VEHICLE", "pedal", "Brake", [("brake", 0x00, 0x00, 0xFF)]),
    ("P1 Rear Brake", "HARLEY", "pedal", "RBrk", [("rearBrake", 0x00, 0x00, 0xFF)]),
    ("P1 Joystick X", "ANALOG_JOYSTICK", "signed", "JoyX", [("analogJoyX", 0x00, 0x80, 0xFF)]),
    ("P1 Joystick Y", "ANALOG_JOYSTICK", "signed", "JoyY", [("analogJoyY", 0x00, 0x80, 0xFF)]),
    ("P1 Gun X", "GUN1|ANALOG_GUN1", "place", "GunX", [("gunX[0]", 150, 400, 651), ("analogGunX[0]", 0x00, 0x80, 0xFF)]),
    ("P1 Gun Y", "GUN1|ANALOG_GUN1", "place", "GunY", [("gunY[0]", 80, 272, 465), ("analogGunY[0]", 0xFF, 0x80, 0x00)]),
    ("P2 Gun X", "GUN2|ANALOG_GUN2", "place", "GunX", [("gunX[1]", 150, 400, 651), ("analogGunX[1]", 0x00, 0x80, 0xFF)]),
    ("P2 Gun Y", "GUN2|ANALOG_GUN2", "place", "GunY", [("gunY[1]", 80, 272, 465), ("analogGunY[1]", 0xFF, 0x80, 0x00)]),
    ("P1 Ski X", "SKI", "signed", "SkiX", [("skiX", 0xFF, 0x80, 0x00)]),
    ("P1 Ski Y", "SKI", "signed", "SkiY", [("skiY", 0x00, 0x80, 0xFF)]),
    ("P1 Lever", "MAGTRUCK", "signed", "Lever", [("magicalLever1", 0xFF, 0x80, 0x00)]),
    ("P2 Lever", "MAGTRUCK", "signed", "Lever", [("magicalLever2", 0xFF, 0x80, 0x00)]),
    ("P1 Rod X", "FISHING", "signed", "RodX", [("fishingRodX", 0x00, 0x80, 0xFF)]),
    ("P1 Rod Y", "FISHING", "signed", "RodY", [("fishingRodY", 0x00, 0x80, 0xFF)]),
    ("P1 Stick X", "FISHING", "signed", "StkX", [("fishingStickX", 0x00, 0x80, 0xFF)]),
    ("P1 Stick Y", "FISHING", "signed", "StkY", [("fishingStickY", 0x00, 0x80, 0xFF)]),
    ("P1 Reel", "FISHING", "pedal", "Reel", [("fishingReel", 0x00, 0x00, 0xFF)]),
    ("P1 Tension", "FISHING", "pedal", "Tens", [("fishingTension", 0x00, 0x00, 0xFF)]),
]

RANGES = {
    "signed": (-32768, 32767, 0),
    "pedal": (0, 32767, 0),
    "place": (0, 65535, 32768),
}


def flags_expr(flags):
    return " | ".join("Game::INPUT_" + f for f in flags.split("|"))


def token(name):
    return name.replace(" ", "").replace("-", "")


def write_inc():
    out = ["/* chimera_inputs.inc - written by tools/gen-inputs.py; do not edit. */", ""]
    out.append("static const ButtonDef kButtons[] = {")
    for name, flags, what, _ in BUTTONS:
        kind, arg = what.split(":", 1)
        if kind == "sw":
            out.append(f'\t{{ "{name}", {flags_expr(flags)}, BTN_SWITCH, [](CInputs *i) -> CInput * {{ return i->{arg}.get(); }}, 0 }},')
        elif kind == "gear":
            n = {"up": "GEAR_UP", "down": "GEAR_DOWN"}.get(arg, arg)
            out.append(f'\t{{ "{name}", {flags_expr(flags)}, BTN_GEAR, nullptr, {n} }},')
        elif kind == "trig":
            out.append(f'\t{{ "{name}", {flags_expr(flags)}, BTN_TRIGGER, nullptr, {arg} }},')
        elif kind == "off":
            out.append(f'\t{{ "{name}", {flags_expr(flags)}, BTN_OFFSCREEN, nullptr, {arg} }},')
        else:
            raise SystemExit(f"unknown kind {kind}")
    out.append("};")
    out.append("")
    out.append("static const AxisDef kAxes[] = {")
    for name, flags, rng, _, targets in AXES:
        lo, hi, neutral = RANGES[rng]
        ts = ", ".join(f"{{ [](CInputs *i) -> CInput * {{ return i->{m}.get(); }}, {a}, {b}, {c} }}" for m, a, b, c in targets)
        if len(targets) == 1:
            ts += ", { nullptr, 0, 0, 0 }"
        out.append(f'\t{{ "{name}", {flags_expr(flags)}, AXIS_{rng.upper()}, {neutral}, {{ {ts} }} }},')
    out.append("};")
    return "\n".join(out) + "\n"


def write_names():
    out = ["/* input-names.h - written by tools/gen-inputs.py; do not edit.",
           " * The test harness's tokens: waterbox.config's control names without",
           " * spaces or dashes, in its order. */",
           "#ifndef INPUT_NAMES_H", "#define INPUT_NAMES_H", ""]
    out.append(f"#define GATE_BTN_COUNT {len(BUTTONS)}")
    out.append(f"#define GATE_AXIS_COUNT {len(AXES)}")
    out.append("static const char *const gate_button_tokens[GATE_BTN_COUNT] = {")
    out += [f'\t"{token(b[0])}",' for b in BUTTONS]
    out.append("};")
    out.append("static const char *const gate_axis_tokens[GATE_AXIS_COUNT] = {")
    out += [f'\t"{token(a[0])}",' for a in AXES]
    out.append("};")
    out.append("static const int gate_axis_neutral[GATE_AXIS_COUNT] = {")
    out += [f"\t{RANGES[a[2]][2]}," for a in AXES]
    out.append("};")
    out += ["", "#endif"]
    return "\n".join(out) + "\n"


def input_decl():
    p1 = [b[0] for b in BUTTONS if b[0].startswith("P1 ")] + [a[0] for a in AXES if a[0].startswith("P1 ")]
    p2 = [b[0] for b in BUTTONS if b[0].startswith("P2 ")] + [a[0] for a in AXES if a[0].startswith("P2 ")]
    return {
        "name": "Model 3 Cabinet",
        "_comment": "Every control at least one Model 3 cabinet has, by Supermodel's own inputs. A game shows only those its cabinet has (its <inputs> in Supermodel's game list); the others leave the input roll. Service and Test are the cabinet's service buttons. Gear 1 to 4 and Neutral set the 4-speed shifter; Shift Up and Down move it a gear, or work the up/down shifter. Trigger is a light gun's trigger (and an analog gun's left one); Off-screen points a light gun away from the screen, to reload.",
        "buttons": [b[0] for b in BUTTONS],
        "mnemonics": {b[0]: b[3] for b in BUTTONS},
        "axes": [{"name": a[0], "min": RANGES[a[2]][0], "max": RANGES[a[2]][1], "neutral": RANGES[a[2]][2], "header": a[3]} for a in AXES],
        "_comment_axes": "A wheel, a stick or a lever runs from -32768 (left, up) to 32767 (right, down), at rest 0; a pedal from 0 (let go) to 32767 (all the way). A gun's aim is where it points on the picture: 0 at the left or top edge, 65535 at the other.",
        "players": [p1, p2],
    }


def main():
    check = "--check" in sys.argv
    files = {
        os.path.join(ROOT, "waterbox/core/chimera_inputs.inc"): write_inc(),
        os.path.join(ROOT, "waterbox/input-names.h"): write_names(),
    }
    cfg_path = os.path.join(ROOT, "waterbox/waterbox.config")
    if os.path.exists(cfg_path):
        cfg = json.load(open(cfg_path))
        cfg["input"] = input_decl()
        files[cfg_path] = json.dumps(cfg, indent=2, ensure_ascii=True) + "\n"
    stale = []
    for path, text in files.items():
        old = open(path).read() if os.path.exists(path) else None
        if old != text:
            stale.append(path)
            if not check:
                open(path, "w").write(text)
    if check and stale:
        print("gen-inputs: out of date: " + ", ".join(os.path.relpath(p, ROOT) for p in stale))
        return 1
    print("gen-inputs: " + ("up to date" if check else f"{len(BUTTONS)} buttons, {len(AXES)} axes"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
