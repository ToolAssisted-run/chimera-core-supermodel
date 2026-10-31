; testprog.s - this repository's Model 3 test program (no game's code).
;
; It boots as a Model 3 game does, from the program ROM's reset vector
; (0xFFF00100), and then, once a frame (when the tile generator's IRQ 0x02
; is pending; no interrupt is taken):
;
;   - counts the frame (RAM 0x1000);
;   - reads the controls (0xF0040004: coins, starts, service, test;
;     0xF0040008: player 1's joystick and buttons) on every frame but each
;     eighth, so every eighth frame is a lag frame;
;   - moves a white block with player 1's joystick (RAM 0x1004, 0x1008);
;   - draws, on tile layer A: the block; a green mark on row 0 at column
;     (frame mod 62); the eight bits of each control byte on rows 46 and 47
;     (blue = pressed); the real-time clock's seconds (two digits, as tiles
;     6 to 15) and minutes on row 2.
;
; Assemble with ppcasm.py (make-testprog.py does, and zips the ROM).

.equ RAMVARS, 0x1000      ; frame, x, y, P1 byte, bank 0 byte
.equ SHADOW, 0x10000      ; the name table, 64 x 48 entries, in RAM first
.equ VRAM, 0xF1000000
.equ NAMEA, 0xF10F8000    ; layer A's name table
.equ MASK, 0xF10F7000
.equ PAL, 0xF1100000
.equ TGREG, 0xF1180000
.equ INPUTS, 0xF0040000
.equ SYSREG, 0xF0100000
.equ RTC, 0xF0140000

.org 0xFFF00100
reset:
	lis r31, RAMVARS@h
	ori r31, r31, RAMVARS@l
	lis r30, SYSREG@h
	lis r29, INPUTS@h
	lis r28, RTC@h
	lis r27, SHADOW@h
	ori r27, r27, SHADOW@l

	; the variables
	li r3, 0
	stw r3, 0(r31)
	li r3, 30
	stw r3, 4(r31)
	li r3, 24
	stw r3, 8(r31)
	li r3, 0xFF
	stb r3, 12(r31)
	stb r3, 16(r31)

	; the palette's first sixteen colours, from the table below
	lis r3, PAL@h
	lis r4, colours@h
	ori r4, r4, colours@l
	li r5, 16
	mtctr r5
pal:
	lwz r6, 0(r4)
	stw r6, 0(r3)
	addi r3, r3, 4
	addi r4, r4, 4
	bdnz pal

	; patterns 0 to 15: pattern k is eight rows of pixel value k
	lis r3, VRAM@h
	li r5, 0          ; k * 0x11111111
	lis r7, 0x1111
	ori r7, r7, 0x1111
	li r8, 16
	mtctr r8
patterns:
	li r9, 8
patrow:
	stw r5, 0(r3)
	addi r3, r3, 4
	addi r9, r9, -1
	cmpwi r9, 0
	bne patrow
	add r5, r5, r7
	bdnz patterns

	; the stencil mask: every line shows layers A and B, not A' and B'
	lis r3, MASK@h
	ori r3, r3, MASK@l
	li r4, -1
	li r5, 512
	mtctr r5
maskl:
	stw r4, 0(r3)
	addi r3, r3, 4
	bdnz maskl

	; the tile generator: layer A 4-bit, above the 3D; layer A on, no scroll
	lis r3, TGREG@h
	lis r4, 0x0011      ; 0x00001100 as the chip sees it
	stw r4, 0x20(r3)
	li r4, 0x0080       ; 0x80000000 as the chip sees it: on
	stw r4, 0x60(r3)
	li r4, 0
	stw r4, 0x64(r3)
	stw r4, 0x68(r3)
	stw r4, 0x6C(r3)

main:
	; wait for the frame's IRQ 0x02, then take it away
wait:
	lbz r3, 0x18(r30)
	andi. r3, r3, 2
	beq wait
	li r3, 2
	stb r3, 0x18(r30)

	; the frame
	lwz r3, 0(r31)
	addi r3, r3, 1
	stw r3, 0(r31)

	; the controls, but on each eighth frame
	andi. r4, r3, 7
	cmpwi r4, 7
	beq noread
	lbz r5, 4(r29)
	stb r5, 16(r31)
	lbz r6, 8(r29)
	stb r6, 12(r31)
noread:

	; the block moves with the joystick (low = held): bit 5 up, 4 down,
	; 7 left, 6 right
	lbz r6, 12(r31)
	lwz r7, 4(r31)
	lwz r8, 8(r31)
	andi. r9, r6, 0x20
	bne noup
	addi r8, r8, -1
noup:
	andi. r9, r6, 0x10
	bne nodown
	addi r8, r8, 1
nodown:
	andi. r9, r6, 0x80
	bne noleft
	addi r7, r7, -1
noleft:
	andi. r9, r6, 0x40
	bne noright
	addi r7, r7, 1
noright:
	cmpwi r7, 0
	bge xlo
	li r7, 0
xlo:
	cmpwi r7, 61
	ble xhi
	li r7, 61
xhi:
	cmpwi r8, 3
	bge ylo
	li r8, 3
ylo:
	cmpwi r8, 45
	ble yhi
	li r8, 45
yhi:
	stw r7, 4(r31)
	stw r8, 8(r31)

	; the shadow name table, cleared
	mr r3, r27
	li r4, 0
	li r5, 1536
	mtctr r5
clr:
	stw r4, 0(r3)
	addi r3, r3, 4
	bdnz clr

	; the block: pattern 4 (white)
	lwz r3, 8(r31)
	lwz r4, 4(r31)
	li r5, 4
	bl cell

	; the frame's mark: pattern 2 (green) on row 0
	lwz r3, 0(r31)
	li r4, 62
	divwu r5, r3, r4
	mullw r5, r5, r4
	sub r4, r3, r5
	li r3, 0
	li r5, 2
	bl cell

	; the control bytes, bit 0 leftmost: pattern 3 (blue) where pressed
	lbz r10, 16(r31)
	li r11, 46
	bl bits
	lbz r10, 12(r31)
	li r11, 47
	bl bits

	; the clock: seconds' tens and ones, minutes' tens and ones on row 2,
	; each digit d as pattern 6 + d
	li r12, 0
	lbz r5, 4(r28)      ; RTC register 1: seconds' tens
	andi. r5, r5, 0x0F
	addi r5, r5, 6
	li r3, 2
	li r4, 3
	bl cell
	lbz r5, 0(r28)      ; RTC register 0: seconds' ones
	andi. r5, r5, 0x0F
	addi r5, r5, 6
	li r3, 2
	li r4, 4
	bl cell
	lbz r5, 12(r28)     ; RTC register 3: minutes' tens
	andi. r5, r5, 0x0F
	addi r5, r5, 6
	li r3, 2
	li r4, 0
	bl cell
	lbz r5, 8(r28)      ; RTC register 2: minutes' ones
	andi. r5, r5, 0x0F
	addi r5, r5, 6
	li r3, 2
	li r4, 1
	bl cell

	; the shadow to layer A's name table, a pair of entries a word
	mr r3, r27
	lis r4, NAMEA@h
	ori r4, r4, NAMEA@l
	li r5, 1536
	mtctr r5
copy:
	lwz r6, 0(r3)
	stw r6, 0(r4)
	addi r3, r3, 4
	addi r4, r4, 4
	bdnz copy

	b main

; cell: row r3, column r4, pattern r5 (0..15) into the shadow table. A 4-bit
; name entry for pattern k with no colour bits is ((k & 1) << 15) | (k >> 1).
; The tile generator is a little-endian chip on a big-endian bus: a word the
; PowerPC writes reaches it byte-reversed, so an entry is written with its
; bytes swapped, and the pair's left entry in the word's second half.
cell:
	slwi r6, r3, 6
	xori r9, r4, 1      ; the chip's pairs hold the right entry first
	add r6, r6, r9
	slwi r6, r6, 1
	add r6, r6, r27
	andi. r7, r5, 1
	slwi r7, r7, 15
	srwi r8, r5, 1
	or r7, r7, r8
	rlwinm r8, r7, 8, 16, 23   ; and each entry little endian
	rlwinm r9, r7, 24, 24, 31
	or r7, r8, r9
	sth r7, 0(r6)
	blr

; bits: the eight bits of r10 on row r11, from column 2, pattern 3 where
; the bit is 0 (pressed), else pattern 1 (red)
bits:
	mflr r20
	li r21, 0
bitl:
	srw r22, r10, r21
	andi. r22, r22, 1
	li r5, 1
	bne bitset
	li r5, 3
bitset:
	mr r3, r11
	addi r4, r21, 2
	bl cell
	addi r21, r21, 1
	cmpwi r21, 8
	blt bitl
	mtlr r20
	blr

; tbbbbbgggggrrrrr: black, red, green, blue, white, yellow, then ten for the
; digits (from dark blue to cyan); byte-reversed, as the chip reads them
colours:
	.word 0x00000000, 0x1F000000, 0xE0030000, 0x007C0000, 0xFF7F0000, 0xFF030000
	.word 0x00280000, 0x00300000, 0x00380000, 0x00400000, 0x80480000, 0x00510000, 0x80590000, 0x00620000, 0x806A0000, 0x00730000
