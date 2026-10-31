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
;     6 to 15) and minutes on row 2; the low bits of the boot count on
;     row 45 (red = 1, blue = 0);
;   - colours the Real3D's one polygon, a quad in the upper right of the
;     picture, with the frame (red rising, full green);
;   - on the frames it reads the controls, also reads the analog channels
;     (the ADC: steering, accelerator, brake) and light gun 1 through the
;     serial port (X and Y, low 8 and high 2 bits, the off-screen bits), and
;     shows them on rows 38 to 43, as the control bytes are shown (red = 1).
;
; The 3D scene is one viewport, its base matrix and one polygon, written
; to the Real3D's memories at power-on (tables at the end). The Real3D is a
; little-endian chip: its words are written with stwbrx.
;
; At power-on it counts the boot in the backup RAM (0xF00C0004), which a
; game's NVRAM keeps: a machine started with the NVRAM of an earlier run
; shows 2 there, a new one 1.
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
.equ BACKUP, 0xF00C0000
.equ CULLHI, 0x8E000000   ; the Real3D's high culling RAM
.equ POLYRAM, 0x98000000  ; its polygon RAM
.equ POLYCOLOUR, 0x98000050 ; the polygon's colour word (polygon RAM word 0x14)

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
	li r3, 0
	stw r3, 24(r31)
	stw r3, 28(r31)

	; the boot count, in the backup RAM
	lis r3, BACKUP@h
	lwz r4, 4(r3)
	addi r4, r4, 1
	stw r4, 4(r3)
	stw r4, 20(r31)

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

	; the 3D scene
	lis r3, vpnode@h
	ori r3, r3, vpnode@l
	lis r4, CULLHI@h
	li r5, 40
	bl r3dcopy
	lis r3, matrix0@h
	ori r3, r3, matrix0@l
	lis r4, CULLHI@h
	ori r4, r4, 0x0400  ; word 0x100
	li r5, 12
	bl r3dcopy
	lis r3, quad@h
	ori r3, r3, quad@l
	lis r4, POLYRAM@h
	ori r4, r4, 0x0040  ; word 0x10
	li r5, 23
	bl r3dcopy

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

	; the analog channels from 0: steering, accelerator, brake
	li r3, 0
	stb r3, 0x3C(r29)
	lbz r10, 0x3C(r29)
	stb r10, 24(r31)
	lbz r10, 0x3C(r29)
	stb r10, 25(r31)
	lbz r10, 0x3C(r29)
	stb r10, 26(r31)
	; light gun 1: X low, Y low, then X high | Y high << 2 | off-screen << 4
	li r3, 2
	bl gunreg
	stb r10, 27(r31)
	li r3, 0
	bl gunreg
	stb r10, 28(r31)
	li r3, 3
	bl gunreg
	mr r11, r10
	li r3, 1
	bl gunreg
	slwi r10, r10, 2
	or r11, r11, r10
	li r3, 8
	bl gunreg
	slwi r10, r10, 4
	or r11, r11, r10
	stb r11, 29(r31)
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

	; the polygon's colour: red is the frame times 4, green full
	lwz r3, 0(r31)
	slwi r3, r3, 26
	oris r3, r3, 0x00FF
	lis r4, POLYCOLOUR@h
	ori r4, r4, POLYCOLOUR@l
	stwbrx r3, r0, r4

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
	lbz r10, 23(r31)    ; the boot count's low byte (red where 1)
	li r11, 45
	bl bits
	li r23, 0           ; the analog channels and the gun, rows 38 to 43
anal:
	addi r24, r23, 24
	add r24, r24, r31
	lbz r10, 0(r24)
	addi r11, r23, 38
	bl bits
	addi r23, r23, 1
	cmpwi r23, 6
	blt anal

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

; gunreg: the light gun register r3 (0-8) through the serial port into r10:
; the register number to FIFO 2, command 0x00 (select it), command 0x87
; (read it), the value from FIFO 2
gunreg:
	stb r3, 0x28(r29)
	li r9, 0
	stb r9, 0x24(r29)
	li r9, 0x87
	stb r9, 0x24(r29)
	lbz r10, 0x30(r29)
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

; r3dcopy: r5 words from r3 to the Real3D at r4, byte-reversed
r3dcopy:
	mtctr r5
r3dl:
	lwz r6, 0(r3)
	stwbrx r6, r0, r4
	addi r3, r3, 4
	addi r4, r4, 4
	bdnz r3dl
	blr

; tbbbbbgggggrrrrr: transparent (so the 3D shows), red, green, blue, white,
; yellow, then ten for the digits (from dark blue to cyan); byte-reversed,
; as the chip reads them
colours:
	.word 0x00800000, 0x1F000000, 0xE0030000, 0x007C0000, 0xFF7F0000, 0xFF030000
	.word 0x00280000, 0x00300000, 0x00380000, 0x00400000, 0x80480000, 0x00510000, 0x80590000, 0x00620000, 0x806A0000, 0x00730000

; The viewport node (high culling RAM word 0): no next viewport, its child
; the model at polygon RAM word 0x10; a 90-degree frustum (cv, cw, io, jo
; 0.5); 496x384 (in 14.2); base matrix at culling word 0x100; full ambient
; light; no fog, no spotlight.
vpnode:
	.word 0x00000000, 0x01000000, 0x01000010
	.float 1.0
	.word 0, 0, 0, 0
	.float 0.5, 0.5, 0.5, 0.5
	.word 0, 0, 0, 0, 0, 0, 0, 0
	.word 0x060007C0, 0x00000000, 0x00800100, 0x00000000
	.word 0, 0, 0, 0, 0, 0, 0, 0
	.word 0
	.float 1.0
	.word 0, 0, 0x0000FF00, 0, 0, 0
; The base matrix as games give it (translation, then three rows): it
; undoes the Real3D's axis order, so the model is in OpenGL's view space.
matrix0:
	.float 0.0, 0.0, 0.0
	.float 0.0, 0.0, -1.0
	.float 1.0, 0.0, 0.0
	.float 0.0, -1.0, 0.0
; One quad: no shared vertices; its normal +Z; double-sided, its colour in
; the header, the last polygon; opaque, unlit. Then four vertices of x, y,
; z in 17.7 fixed point (Step 1.0) shifted up 8 bits, and no texture: x 1
; to 6, y 1 to 4, z -10.
quad:
	.word 0x00000040, 0x00000016, 0x00000000, 0x40000000, 0xFFFF0000, 0x00000000, 0x00810000
	.word 0x00008000, 0x00008000, 0xFFFB0000, 0
	.word 0x00030000, 0x00008000, 0xFFFB0000, 0
	.word 0x00030000, 0x00020000, 0xFFFB0000, 0
	.word 0x00008000, 0x00020000, 0xFFFB0000, 0
