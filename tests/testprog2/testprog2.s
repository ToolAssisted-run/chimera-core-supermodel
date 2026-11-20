; testprog2.s - this repository's Model 2 test program (no game's code).
;
; A Model 2A board boots its i960 from the program ROM at address 0: the
; first words are the system address table, the processor control block's
; address and the first instruction's. The program sets the board up, and
; then, once a frame (when the vertical blank is reported in the interrupt
; request register; no interrupt is taken, the processor runs at the top
; priority):
;
;   - counts the frame (work RAM 0x500000);
;   - reads the controls (the I/O board's ports B, C and D: coins, starts,
;     service and test; player 1's joystick and buttons; player 2's) on every
;     frame but each eighth, so every eighth frame is a lag frame;
;   - moves a white block with player 1's joystick (work RAM 0x500004 and
;     0x500008);
;   - draws, on the first tile layer: the block; the eight bits of each
;     control byte on rows 44 to 46 (red = pressed); the low eight bits of
;     the frame count on row 47 (red = 1); the low eight bits of the boot
;     count on row 43 (red = 1).
;
; At power-on it counts the boot in the backup RAM (0x1D00004), which a
; game's NVRAM keeps: a machine started with the NVRAM of an earlier run
; shows one more there, a new one 0.
;
; The tile layer is the System 24 tile chip's: a name table of 64 by 64
; words (a character, 0 to 127, with its colour in the high bits) and
; characters of 8 by 8 pixels of four bits. The picture's colours go
; through the board's colour tables, which the program sets to a straight
; line. Pen 0 of the first palette is the background.
;
; Assemble with i960asm.py (make-testprog2.py does, and zips the ROM).

.equ VARS, 0x00500000     ; frame, x, y, port B, port C, port D, boot count
.equ TILES, 0x01000000    ; the name table of tile layer 0 (a word each)
.equ CHARS, 0x01080000    ; the characters
.equ PAL, 0x01800000
.equ XLAT, 0x01810000     ; the colour tables
.equ IO, 0x01C00000
.equ INTREQ, 0x00E80000
.equ INTENA, 0x00E80004
.equ BACKUP, 0x01D00000

.org 0
	.word 0x00000040      ; the system address table (never used)
	.word 0x00000080      ; the processor control block
	.word 0
	.word start           ; the first instruction

.org 0x98                 ; the control block's interrupt stack: the stack pointer
	.word 0x00230000

.org 0x100
start:
	; the I/O board's ports B, C and D are inputs
	lda 0xFF, g0
	stob g0, IO + 0x10

	; the colour tables: 32 levels of each colour, a straight line from
	; the lowest level the picture shows to full
	lda XLAT + 0x80, g1
	lda XLAT + 0x4080, g4
	lda XLAT + 0x8080, g5
	lda 0x200, g6
	lda 64, g2
	lda 32, g0
tables:
	stos g2, 0(g1)
	stos g2, 0(g4)
	stos g2, 0(g5)
	addo g1, g6, g1
	addo g4, g6, g4
	addo g5, g6, g5
	addo 6, g2, g2
	subo 1, g0, g0
	cmpo 0, g0
	bne tables

	; the palette: the background, red, blue, green, white
	lda 0x2400, g0
	stos g0, PAL + 0
	lda 0x001F, g0
	stos g0, PAL + 2
	lda 0x7C00, g0
	stos g0, PAL + 4
	lda 0x03E0, g0
	stos g0, PAL + 6
	lda 0x7FFF, g0
	stos g0, PAL + 8

	; characters 1 to 4: a block of pen 1 (red), 2 (blue), 3 (green), 4 (white)
	lda CHARS + 32, g1
	lda 0x11111111, g0
	lda 0x11111111, g7
	lda 32, g9
	lda 4, g3
chars:
	st g0, 0(g1)
	st g0, 4(g1)
	st g0, 8(g1)
	st g0, 12(g1)
	st g0, 16(g1)
	st g0, 20(g1)
	st g0, 24(g1)
	st g0, 28(g1)
	addo g9, g1, g1
	addo g7, g0, g0
	subo 1, g3, g3
	cmpo 0, g3
	bne chars

	; the variables
	lda VARS, g13
	lda 0, g0
	st g0, 0(g13)
	lda 30, g0
	st g0, 4(g13)
	lda 24, g0
	st g0, 8(g13)

	; the boot count, in the backup RAM
	ld BACKUP + 4, g0
	addo 1, g0, g0
	st g0, BACKUP + 4
	st g0, 24(g13)

	; the vertical blank interrupt is reported
	lda 1, g0
	st g0, INTENA
	lda 0xFF, g14
	lda 63, g12

frame:
	; wait for the vertical blank, then acknowledge it
wait:
	ld INTREQ, g0
	and 1, g0, g0
	cmpo 0, g0
	be wait
	lda 0xFFFFFFFE, g0
	st g0, INTREQ

	ld 0(g13), g1
	addo 1, g1, g1
	st g1, 0(g13)

	; the controls, except on every eighth frame
	and 7, g1, g0
	cmpo 0, g0
	be noread
	ldob IO + 2, g0
	stob g0, 12(g13)
	ldob IO + 4, g0
	stob g0, 16(g13)
	ldob IO + 6, g0
	stob g0, 20(g13)
noread:

	; the block: out of its old place, moved, into its new one
	ld 4(g13), g2
	ld 8(g13), g3
	shlo 6, g3, g4
	addo g4, g2, g4
	shlo 1, g4, g4
	lda TILES, g5
	addo g5, g4, g4
	lda 0, g0
	stos g0, 0(g4)
	ldob 16(g13), g0
	xor g14, g0, g0          ; 1 = pressed
	shro 6, g0, g5           ; right
	and 1, g5, g5
	addo g5, g2, g2
	shro 7, g0, g5           ; left
	and 1, g5, g5
	subo g5, g2, g2
	and g12, g2, g2
	shro 4, g0, g5           ; down
	and 1, g5, g5
	addo g5, g3, g3
	shro 5, g0, g5           ; up
	and 1, g5, g5
	subo g5, g3, g3
	and g12, g3, g3
	st g2, 4(g13)
	st g3, 8(g13)
	shlo 6, g3, g4
	addo g4, g2, g4
	shlo 1, g4, g4
	lda TILES, g5
	addo g5, g4, g4
	lda 4, g0
	stos g0, 0(g4)

	; row 44: port B, row 45: port C, row 46: port D (1 = pressed)
	ldob 12(g13), g0
	xor g14, g0, g0
	lda TILES + 0x1602, g1
	lda 8, g2
rowb:
	and 1, g0, g3
	stos g3, 0(g1)
	shro 1, g0, g0
	addo 2, g1, g1
	subo 1, g2, g2
	cmpo 0, g2
	bne rowb

	ldob 16(g13), g0
	xor g14, g0, g0
	lda TILES + 0x1682, g1
	lda 8, g2
rowc:
	and 1, g0, g3
	stos g3, 0(g1)
	shro 1, g0, g0
	addo 2, g1, g1
	subo 1, g2, g2
	cmpo 0, g2
	bne rowc

	ldob 20(g13), g0
	xor g14, g0, g0
	lda TILES + 0x1702, g1
	lda 8, g2
rowd:
	and 1, g0, g3
	stos g3, 0(g1)
	shro 1, g0, g0
	addo 2, g1, g1
	subo 1, g2, g2
	cmpo 0, g2
	bne rowd

	; row 47: the frame count, row 43: the boot count (1 = red)
	ld 0(g13), g0
	lda TILES + 0x1782, g1
	lda 8, g2
rowf:
	and 1, g0, g3
	stos g3, 0(g1)
	shro 1, g0, g0
	addo 2, g1, g1
	subo 1, g2, g2
	cmpo 0, g2
	bne rowf

	ld 24(g13), g0
	lda TILES + 0x1582, g1
	lda 8, g2
rowboot:
	and 1, g0, g3
	stos g3, 0(g1)
	shro 1, g0, g0
	addo 2, g1, g1
	subo 1, g2, g2
	cmpo 0, g2
	bne rowboot

	b frame
