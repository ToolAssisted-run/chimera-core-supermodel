/* disasm.cpp - reads the Model 2 test program back with Supermodel's own i960
 * disassembler, so that a wrong encoding in i960asm.py shows as "?" (an
 * instruction the disassembler does not know) or as another instruction than
 * the one written.
 *
 * usage: i960dis <program ROM> <from> <to>    (addresses in the ROM)
 * One line a instruction: address, then the disassembler's text.
 */
#include "CPU/I960/I960Disasm.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

int main(int argc, char **argv)
{
	if (argc != 4)
		return 2;
	FILE *f = fopen(argv[1], "rb");
	if (!f)
		return 2;
	std::vector<uint8_t> rom(0x10000 + 8);
	size_t n = fread(rom.data(), 1, rom.size(), f);
	fclose(f);
	(void)n;
	const uint32_t from = strtoul(argv[2], 0, 0), to = strtoul(argv[3], 0, 0);
	for (uint32_t pc = from; pc < to;)
	{
		uint32_t op = rom[pc] | rom[pc + 1] << 8 | rom[pc + 2] << 16 | (uint32_t)rom[pc + 3] << 24;
		uint32_t next = rom[pc + 4] | rom[pc + 5] << 8 | rom[pc + 6] << 16 | (uint32_t)rom[pc + 7] << 24;
		unsigned length = 4;
		std::string text = CI960Disassembler::Disassemble(pc, op, next, &length);
		printf("%04x: %s\n", pc, text.c_str());
		pc += length;
	}
	return 0;
}
