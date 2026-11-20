#!/usr/bin/env python3
"""i960asm.py - a small assembler for the Intel i960 (the Sega Model 2's
main processor), only as much of it as the Model 2 test program (testprog2.s)
uses. Written for this repository; the encodings are Intel's, and
`check-asm.sh` reads the result back with Supermodel's own disassembler.

Usage: i960asm.py <source.s> <output.bin> <size>

Syntax: one instruction a line, `label:`, `; comment`; the directives
`.org <address>`, `.word <value>`, `.equ <name>, <value>`. A value is a
number, a name, a label, and `+` or `-` of them. Registers are g0 to g14 and
fp; a literal (0 to 31) is allowed as a source of an arithmetic instruction.

Instructions:
  lda  <value>, <reg>
  ld ldob ldos <memory>, <reg>        st stob stos <reg>, <memory>
        memory: <value> (an absolute address), or <offset>(<reg>) with an
        offset of 0 to 4095
  addo subo and or xor shlo shro  <src1>, <src2>, <dst>   (dst = src2 op src1;
        shlo and shro: dst = src2 shifted by src1)
  cmpo <src1>, <src2>                 mov <src>, <dst>
  b be bne bg bge bl ble <label>
  .byte is not needed: the program's data is written with .word
"""
import re
import struct
import sys

REGS = {f"g{i}": 16 + i for i in range(15)}
REGS["fp"] = 31

# the REG format: the opcode's two parts
REG_OPS = {
    "and": (0x58, 0x1), "xor": (0x58, 0x6), "or": (0x58, 0x7),
    "addo": (0x59, 0x0), "subo": (0x59, 0x2), "shro": (0x59, 0x8), "shlo": (0x59, 0xC),
    "cmpo": (0x5A, 0x0), "mov": (0x5C, 0xC),
}
MEM_OPS = {"ldob": 0x80, "stob": 0x82, "ldos": 0x88, "stos": 0x8A, "lda": 0x8C, "ld": 0x90, "st": 0x92}
BRANCH_OPS = {"b": 0x08, "bg": 0x11, "be": 0x12, "bge": 0x13, "bl": 0x14, "bne": 0x15, "ble": 0x16}


class Asm:
    def __init__(self):
        self.symbols = {}

    def value(self, text, final):
        total, sign = 0, 1
        for tok in re.findall(r"[+-]|[^+\-\s]+", text.strip()):
            if tok == "+":
                sign = 1
            elif tok == "-":
                sign = -1
            else:
                if re.match(r"^(0x[0-9A-Fa-f]+|\d+)$", tok):
                    v = int(tok, 0)
                elif tok in self.symbols:
                    v = self.symbols[tok]
                elif final:
                    raise SystemExit(f"i960asm: unknown name {tok}")
                else:
                    v = 0
                total += sign * v
                sign = 1
        return total

    def operand(self, text):
        """(kind, number): a register, or a literal"""
        text = text.strip()
        if text in REGS:
            return "reg", REGS[text]
        return "lit", self.value(text, True)

    def reg_instruction(self, mnem, ops):
        opc, opc2 = REG_OPS[mnem]
        if mnem == "cmpo":
            (k1, s1), (k2, s2), (kd, d) = self.operand(ops[0]), self.operand(ops[1]), ("reg", 0)
        elif mnem == "mov":
            (k1, s1), (k2, s2), (kd, d) = self.operand(ops[0]), ("reg", 0), self.operand(ops[1])
        else:
            (k1, s1), (k2, s2), (kd, d) = self.operand(ops[0]), self.operand(ops[1]), self.operand(ops[2])
        if kd != "reg":
            raise SystemExit(f"i960asm: {mnem}: the destination is a register")
        word = (opc << 24) | (d << 19) | (s2 << 14) | (opc2 << 7) | s1
        if k1 == "lit":
            if not 0 <= s1 < 32:
                raise SystemExit(f"i960asm: {mnem}: literal {s1} is not 0 to 31")
            word |= 1 << 11
        if k2 == "lit":
            if not 0 <= s2 < 32:
                raise SystemExit(f"i960asm: {mnem}: literal {s2} is not 0 to 31")
            word |= 1 << 12
        return struct.pack("<I", word)

    def memory(self, mnem, ops, final):
        op = MEM_OPS[mnem]
        if mnem in ("st", "stob", "stos"):
            reg, mem = ops[0].strip(), ops[1].strip()
        else:
            mem, reg = ops[0].strip(), ops[1].strip()
        if reg not in REGS:
            raise SystemExit(f"i960asm: {mnem}: {reg} is not a register")
        r = REGS[reg]
        m = re.match(r"^(.*)\((g\d+|fp)\)$", mem)
        if m:
            off = self.value(m.group(1) or "0", final)
            if not 0 <= off < 4096:
                raise SystemExit(f"i960asm: {mnem}: offset {off} is not 0 to 4095")
            return struct.pack("<I", (op << 24) | (r << 19) | (REGS[m.group(2)] << 14) | (1 << 13) | off)
        disp = self.value(mem, final) & 0xFFFFFFFF
        return struct.pack("<II", (op << 24) | (r << 19) | (0xC << 10), disp)

    def assemble(self, lines, size):
        out = None
        for final in (False, True):
            image = bytearray(size)
            pc = 0
            for raw in lines:
                line = raw.split(";")[0].strip()
                while True:
                    m = re.match(r"^([A-Za-z_][\w]*):\s*(.*)$", line)
                    if not m:
                        break
                    self.symbols[m.group(1)] = pc
                    line = m.group(2)
                if not line:
                    continue
                head, _, rest = line.partition(" ")
                ops = [o for o in rest.split(",")] if rest.strip() else []
                if head == ".org":
                    pc = self.value(rest, final)
                    continue
                if head == ".equ":
                    self.symbols[ops[0].strip()] = self.value(",".join(ops[1:]), final)
                    continue
                if head == ".word":
                    data = struct.pack("<I", self.value(rest, final) & 0xFFFFFFFF)
                elif head in REG_OPS:
                    data = self.reg_instruction(head, ops)
                elif head in MEM_OPS:
                    data = self.memory(head, ops, final)
                elif head in BRANCH_OPS:
                    disp = (self.value(rest, final) - pc) if final else 0
                    if disp % 4 or not -(1 << 23) <= disp < (1 << 23):
                        raise SystemExit(f"i960asm: {head}: cannot reach {rest.strip()}")
                    data = struct.pack("<I", (BRANCH_OPS[head] << 24) | (disp & 0x00FFFFFC))
                else:
                    raise SystemExit(f"i960asm: unknown instruction: {line}")
                if final:
                    image[pc:pc + len(data)] = data
                pc += len(data)
            out = image
        return out


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    lines = open(sys.argv[1]).read().splitlines()
    image = Asm().assemble(lines, int(sys.argv[3], 0))
    open(sys.argv[2], "wb").write(bytes(image))


if __name__ == "__main__":
    main()
