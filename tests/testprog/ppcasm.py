#!/usr/bin/env python3
"""ppcasm.py - a small PowerPC assembler for this repository's test program.

Enough of the 32-bit PowerPC instruction set to write a program that boots
on the Model 3 as a game's ROM does: integer loads and stores, arithmetic
and logic, compares, branches with labels, the special registers an
interrupt handler needs (SRR0/1, SPRG0-3, MSR) and rfi. Big-endian output.

A source line is "label:", or "mnemonic operands", or ".org ADDRESS",
".word VALUE[, VALUE...]", ".equ NAME, VALUE"; ";" or "#" starts a comment.
Registers are r0..r31; numbers are decimal or 0x hex; an expression may use
labels, .equ names, + - * << >> | & and parentheses, and @h / @ha / @l on a
value (high half, high half adjusted for a signed low half, low half).

Usage: ppcasm.py source.s out.bin BASE SIZE
  BASE is the address the first byte of out.bin is at; SIZE its length
  (the rest is zero).
"""
import re
import struct
import sys

SPR = {"xer": 1, "lr": 8, "ctr": 9, "dsisr": 18, "dar": 19, "dec": 22,
       "srr0": 26, "srr1": 27, "sprg0": 272, "sprg1": 273, "sprg2": 274,
       "sprg3": 275, "hid0": 1008}


class Asm:
    def __init__(self):
        self.sym = {}
        self.out = {}

    def reg(self, s):
        s = s.strip().lower()
        m = re.fullmatch(r"r(\d+)", s)
        if not m or int(m.group(1)) > 31:
            raise ValueError(f"not a register: {s}")
        return int(m.group(1))

    def val(self, s, pc, final):
        s = s.strip()
        suffix = None
        m = re.fullmatch(r"(.*)@(ha|h|l)", s)
        if m:
            s, suffix = m.group(1), m.group(2)
        expr = re.sub(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", lambda mm: self.name(mm.group(1), final), s)
        v = int(eval(expr, {"__builtins__": {}}))
        if suffix == "l":
            v &= 0xFFFF
        elif suffix == "h":
            v = (v >> 16) & 0xFFFF
        elif suffix == "ha":
            v = ((v + 0x8000) >> 16) & 0xFFFF
        return v

    def name(self, n, final):
        if n in self.sym:
            return str(self.sym[n])
        if final:
            raise ValueError(f"unknown name: {n}")
        return "0"

    def emit(self, pc, word):
        self.out[pc] = word & 0xFFFFFFFF

    def assemble(self, text, final):
        pc = 0
        for lineno, raw in enumerate(text.splitlines(), 1):
            line = re.split(r"[;#]", raw, 1)[0].strip()
            if not line:
                continue
            try:
                while True:
                    m = re.match(r"([A-Za-z_][A-Za-z0-9_]*):\s*(.*)", line)
                    if not m:
                        break
                    if not final:
                        if m.group(1) in self.sym and self.sym[m.group(1)] != pc:
                            raise ValueError(f"label {m.group(1)} defined twice")
                    self.sym[m.group(1)] = pc
                    line = m.group(2).strip()
                if not line:
                    continue
                op, _, rest = line.partition(" ")
                args = [a.strip() for a in rest.split(",")] if rest.strip() else []
                op = op.lower()
                if op == ".org":
                    pc = self.val(args[0], pc, True)
                    continue
                if op == ".equ":
                    self.sym[args[0]] = self.val(args[1], pc, final)
                    continue
                if op == ".word":
                    for a in args:
                        self.emit(pc, self.val(a, pc, final))
                        pc += 4
                    continue
                self.emit(pc, self.encode(op, args, pc, final))
                pc += 4
            except Exception as e:
                raise SystemExit(f"line {lineno}: {raw.strip()}: {e}")

    def encode(self, op, a, pc, final):
        R, V = self.reg, lambda s: self.val(s, pc, final)

        def d_form(opc, rt, ra, imm):
            return (opc << 26) | (rt << 21) | (ra << 16) | (imm & 0xFFFF)

        def mem(s):
            m = re.fullmatch(r"(.*)\((r\d+)\)", s.strip())
            if not m:
                raise ValueError(f"not an address: {s}")
            return V(m.group(1) or "0"), R(m.group(2))

        def x_form(opc, rt, ra, rb, xo, rc=0):
            return (opc << 26) | (rt << 21) | (ra << 16) | (rb << 11) | (xo << 1) | rc

        dloads = {"lwz": 32, "lbz": 34, "stw": 36, "stb": 38, "lhz": 40, "sth": 44, "lwzu": 33, "stwu": 37}
        if op in dloads:
            off, ra = mem(a[1])
            return d_form(dloads[op], R(a[0]), ra, off)
        if op == "li":
            return d_form(14, R(a[0]), 0, V(a[1]))
        if op == "lis":
            return d_form(15, R(a[0]), 0, V(a[1]))
        if op in ("addi", "addis"):
            return d_form(14 if op == "addi" else 15, R(a[0]), R(a[1]), V(a[2]))
        if op in ("ori", "oris", "xori", "andi.", "andis."):
            opc = {"ori": 24, "oris": 25, "xori": 26, "andi.": 28, "andis.": 29}[op]
            return d_form(opc, R(a[1]), R(a[0]), V(a[2]))  # rS, rA swapped in the encoding
        if op == "mulli":
            return d_form(7, R(a[0]), R(a[1]), V(a[2]))
        if op == "cmpwi":
            return (11 << 26) | (R(a[0]) << 16) | (V(a[1]) & 0xFFFF)
        if op == "cmplwi":
            return (10 << 26) | (R(a[0]) << 16) | (V(a[1]) & 0xFFFF)
        if op == "cmpw":
            return x_form(31, 0, R(a[0]), R(a[1]), 0)
        if op == "cmplw":
            return x_form(31, 0, R(a[0]), R(a[1]), 32)
        xo = {"add": 266, "subf": 40, "mullw": 235, "divwu": 459}
        if op in xo:
            return (31 << 26) | (R(a[0]) << 21) | (R(a[1]) << 16) | (R(a[2]) << 11) | (xo[op] << 1)
        if op == "sub":  # sub rD, rA, rB = subf rD, rB, rA
            return (31 << 26) | (R(a[0]) << 21) | (R(a[2]) << 16) | (R(a[1]) << 11) | (40 << 1)
        logic = {"and": 28, "or": 444, "xor": 316, "slw": 24, "srw": 536, "nor": 124}
        if op in logic:
            return x_form(31, R(a[1]), R(a[0]), R(a[2]), logic[op])
        if op == "mr":
            return x_form(31, R(a[1]), R(a[0]), R(a[1]), 444)
        if op == "rlwinm":
            return (21 << 26) | (R(a[1]) << 21) | (R(a[0]) << 16) | (V(a[2]) << 11) | (V(a[3]) << 6) | (V(a[4]) << 1)
        if op == "slwi":
            n = V(a[2])
            return (21 << 26) | (R(a[1]) << 21) | (R(a[0]) << 16) | (n << 11) | (0 << 6) | ((31 - n) << 1)
        if op == "srwi":
            n = V(a[2])
            return (21 << 26) | (R(a[1]) << 21) | (R(a[0]) << 16) | (((32 - n) & 31) << 11) | (n << 6) | (31 << 1)
        if op in ("b", "bl"):
            d = V(a[0]) - pc
            return (18 << 26) | (d & 0x3FFFFFC) | (1 if op == "bl" else 0)
        conds = {"beq": (12, 2), "bne": (4, 2), "blt": (12, 0), "bge": (4, 0), "bgt": (12, 1), "ble": (4, 1)}
        if op in conds:
            bo, bi = conds[op]
            d = V(a[0]) - pc
            if final and not -0x8000 <= d < 0x8000:
                raise ValueError("branch too far")
            return (16 << 26) | (bo << 21) | (bi << 16) | (d & 0xFFFC)
        if op == "bdnz":
            d = V(a[0]) - pc
            return (16 << 26) | (16 << 21) | (d & 0xFFFC)
        if op == "blr":
            return 0x4E800020
        if op == "bctr":
            return 0x4E800420
        if op == "rfi":
            return 0x4C000064
        if op == "sync":
            return 0x7C0004AC
        if op == "isync":
            return 0x4C00012C
        if op == "nop":
            return 0x60000000
        if op in ("mtspr", "mfspr", "mtlr", "mflr", "mtctr", "mfctr", "mtsrr0", "mtsrr1", "mfsrr0", "mfsrr1"):
            if op in ("mtspr", "mfspr"):
                spr = SPR[a[0].lower()] if op == "mtspr" else SPR[a[1].lower()]
                r = R(a[1]) if op == "mtspr" else R(a[0])
                to = op == "mtspr"
            else:
                spr = SPR[op[2:]]
                r = R(a[0])
                to = op.startswith("mt")
            sprf = ((spr & 31) << 5) | (spr >> 5)
            return (31 << 26) | (r << 21) | (sprf << 11) | ((467 if to else 339) << 1)
        if op == "mtmsr":
            return x_form(31, R(a[0]), 0, 0, 146)
        if op == "mfmsr":
            return x_form(31, R(a[0]), 0, 0, 83)
        raise ValueError(f"no such instruction here: {op}")


def main():
    src, out, base, size = sys.argv[1], sys.argv[2], int(sys.argv[3], 0), int(sys.argv[4], 0)
    text = open(src).read()
    asm = Asm()
    asm.assemble(text, False)
    asm.out = {}
    asm.assemble(text, True)
    image = bytearray(size)
    for addr, word in asm.out.items():
        off = addr - base
        if not 0 <= off <= size - 4:
            raise SystemExit(f"0x{addr:08x} is outside the image")
        image[off:off + 4] = struct.pack(">I", word)
    open(out, "wb").write(image)


if __name__ == "__main__":
    main()
