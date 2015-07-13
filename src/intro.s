;
; The MUni Race
; Intro file
;
; Zero Page global registers:
;     ** MUST NOT be modifed by any other functions **
;   $f9/$fa -> charset
;
;
; Zero Page: modified by the program, but can be modified by other functions
;   $fb/$fc -> screen pointer (upper)


; exported by the linker
.import __CHARSET_LOAD__, __SIDMUSIC_LOAD__, __CODEINTRO_LOAD__, __GFX_LOAD__

; from utils.s
.import clear_screen, color_screen

;--------------------------------------------------------------------------
; Constants
;--------------------------------------------------------------------------

DEBUG = 0			; Use 1 to enable music-raster debug

RASTER_START = 50

SCROLL_1_AT_LINE = 18
ROWS_PER_CHAR = 7

SCREEN_TOP = $0400 + SCROLL_1_AT_LINE * 40


MUSIC_INIT = __SIDMUSIC_LOAD__
MUSIC_PLAY = __SIDMUSIC_LOAD__ + 3

; SPEED must be between 0 and 7. 0=Stop, 7=Max speed
SCROLL_SPEED = 6
ANIM_SPEED = 1

BITMAP_DATA = __GFX_LOAD__
CHARMEM_DATA = BITMAP_DATA + $1f40
COLORMEM_DATA = BITMAP_DATA + $2328
BACKGROUND_DATA = BITMAP_DATA + $2710

;--------------------------------------------------------------------------
; Macros
;--------------------------------------------------------------------------
.macpack cbm			; adds support for scrcode

;--------------------------------------------------------------------------
; STABILIZE_RASTER
; Double-IRQ Stable raster routine
; code and comments taken from: http://codebase64.org/doku.php?id=base:stable_raster_routine
;--------------------------------------------------------------------------
.macro STABILIZE_RASTER
	; A Raster Compare IRQ is triggered on cycle 0 on the current $d012 line
	; The MPU needs to finish it's current OP code before starting the Interrupt Handler,
	; meaning a 0 -> 7 cycles delay depending on OP code.
	; Then a 7 cycle delay is spent invoking the Interrupt Handler (Push SR/PC to stack++)
	; Then 13 cycles for storing registers (pha, txa, pha, tya, pha)
	
	; prev cycle count: 20~27
	lda #<@irq_stable	; +2, 2
	ldx #>@irq_stable	; +2, 4
	sta $fffe		; +4, 8
	stx $ffff		; +4, 12
	inc $d012		; +6, 18
	asl $d019		; +6, 24
	tsx			; +2, 26
	cli			; +2, 28

.repeat 10
	; Next IRQ will be triggered while executing these nops
	nop			; +2 * 8, 44.
.endrepeat
	; cycle count: 64~71. New raster already triggered at this point
	
@irq_stable:
	; cycle count: 7~8 .7 cycles for the interrupt handler + 0~1 cycle Jitter for the NOP
	txs			; +2, 9~10

	; 42 cycles
	ldx #$08		; +2, 11~12
	dex			; +2 * 8, 27~28
	bne *-1			; +3 * 7, +2, 50~51
	bit $00			; +3, 53~54

;.repeat 21
;	nop			; 2 * 21
;.endrepeat

	lda $d012		; +4, 57~58
	cmp $d012		; +4, 61~62
	beq *+2			; +2/+3, 64

.endmacro


.segment "CODE"
	jmp __CODEINTRO_LOAD__

.segment "CODEINTRO"

;--------------------------------------------------------------------------
; _main
;--------------------------------------------------------------------------
	jsr init


mainloop:
	lda #0
	sta sync
:	cmp sync
	beq :-

	jsr scroll
	jsr anim_char
	jsr anim_rasterbar
	jmp mainloop

;	jmp *

irq1:
	pha			; saves A, X, Y
	txa
	pha
	tya
	pha

	STABILIZE_RASTER

	; char mode
	lda #%00011011		; +2
	sta $d011		; +4

.repeat 23
	nop
.endrepeat

	; two lines of colors
	lda #$08		; +2
	sta $d020		; +4
	sta $d021		; +4


	; waste some cycles so we can change colors 
	; and horizontal scroll at the correct time
	; and with enough time that we can do it
	; when the cycles are invisible
.repeat 58
	nop
.endrepeat

	; paint 2 lines with different color
	ldx #15			; Grey 2
	stx $d020
	stx $d021

	lda smooth_scroll_x
	sta $d016

	; raster bars
	ldx #$00

	; 8 chars of 8 raster lines
.repeat ROWS_PER_CHAR-1
	; 7 "Good" lines: I must consume 63 cycles
	.repeat 7
		lda raster_colors,x	; +4
		sta $d021		; +4
		inx			; +2
		.repeat 25
			nop		; +2 * 25
		.endrepeat
		bit $00			; +3 = 63 cycles
	.endrepeat
	; 1 "Bad lines": I must consume ~20 cycles
	lda raster_colors,x		; +4
	sta $d021			; +4
	inx				; +2
	.repeat 5
		nop			; +2 * 5 = 20 cycles
	.endrepeat
.endrepeat
	; 1 char of 7 raster lines
.repeat 7
	lda raster_colors,x	; +4
	sta $d021		; +4
	inx			; +2
	.repeat 25
		nop		; +2 * 25
	.endrepeat
	bit $00			; +3 = 63 cycles
.endrepeat

	; paint 2 raster lines with different color
	lda #$08
	sta $d020
	sta $d021

.repeat 58
	nop
.endrepeat

	; color
	lda BACKGROUND_DATA
	sta $d020
	sta $d021

	; no scroll, multi-color
	lda #%00011000
	sta $d016

	; hires bitmap mode
	lda #%00111011
	sta $d011

	inc sync

.if (DEBUG=1)
	inc $d020
.endif
	jsr MUSIC_PLAY
.if (DEBUG=1)
	dec $d020
.endif

	; we have to re-schedule irq1 from irq1 basically because
	; we are using a double IRQ
	lda #<irq1
	sta $fffe
	lda #>irq1
	sta $ffff

	lda #RASTER_START+SCROLL_1_AT_LINE*8-4
	sta $d012

	asl $d019

	pla			; restores A, X, Y
	tay
	pla
	tax
	pla
	rti			; restores previous PC, status


;--------------------------------------------------------------------------
; scroll(void)
; main scroll function
;--------------------------------------------------------------------------
.proc scroll
	; speed control

	sec
	lda smooth_scroll_x
	sbc #SCROLL_SPEED
	and #07
	sta smooth_scroll_x
	bcc :+
	rts

:
	jsr scroll_screen

	lda chars_scrolled
	cmp #%10000000
	bne :+

	; A and current_char will contain the char to print
	; $f9/$fa points to the charset definition of the char
	jsr setup_charset

:
	; basic setup
	ldx #<(SCREEN_TOP+7*40+39)
	ldy #>(SCREEN_TOP+7*40+39)
	stx $fb
	sty $fc

	; should not be bigger than 7 (8 rows)
	ldy #.min(ROWS_PER_CHAR,7)


@loop:
	ldx #0

	lda ($f9),y
	and chars_scrolled
	beq @empty_char

;	 lda current_char
	; char to display
	lda #$fd
	sta ($fb,x)

	bne :+

@empty_char:
	lda #$ff		; empty char
	sta ($fb,x)

:
	; next line for top scroller
	sec
	lda $fb
	sbc #40
	sta $fb
	bcs :+
	dec $fc

:

	dey			; next charset definition
	bpl @loop

	lsr chars_scrolled
	bcc @endscroll

	lda #128
	sta chars_scrolled

	clc
	lda scroller_text_ptr_low
	adc #1
	sta scroller_text_ptr_low
	bcc @endscroll
	inc scroller_text_ptr_hi

@endscroll:
	rts
.endproc


;--------------------------------------------------------------------------
; scroll_screen(void)
;--------------------------------------------------------------------------
; args: -
; modifies: A, X, Status
;--------------------------------------------------------------------------
scroll_screen:
	; move the chars to the left and right
	ldx #0

	; doing a cpy #$ff
	ldy #38

@loop:
.repeat ROWS_PER_CHAR,i
	lda SCREEN_TOP+40*i+1,x
	sta SCREEN_TOP+40*i+0,x
.endrepeat

	inx
	dey
	bpl @loop
	rts

;--------------------------------------------------------------------------
; setup_charset(void)
;--------------------------------------------------------------------------
; Args: -
; Modifies A, X, Status
; returns A: the character to print
;--------------------------------------------------------------------------
.proc setup_charset
	; put next char in column 40

	; supports a scroller with more than 255 chars
	clc
	lda #<scroller_text
	adc scroller_text_ptr_low
	sta address
	lda #>scroller_text
	adc scroller_text_ptr_hi
	sta address+1

address = *+1
	; self changing value
	lda scroller_text
	cmp #$ff
	bne :+

        ; reached $ff. Then start from the beginning
	lda #%10000000
	sta chars_scrolled
	lda #0
	sta scroller_text_ptr_low
	sta scroller_text_ptr_hi
	lda scroller_text
:
	sta current_char

	tax

	; address = CHARSET + 8 * index
	; multiply by 8 (LSB)
	asl
	asl
	asl
	clc
	adc #<__CHARSET_LOAD__
	sta $f9

	; multiply by 8 (MSB)
	; 256 / 8 = 32
	; 32 = %00100000
	txa
	lsr
	lsr
	lsr
	lsr
	lsr

	clc
	adc #>__CHARSET_LOAD__
	sta $fa

	rts
.endproc

;--------------------------------------------------------------------------
; anim_char(void)
;--------------------------------------------------------------------------
; Args: -
; Modifies A, X, Status
; returns A: the character to print
;--------------------------------------------------------------------------
ANIM_TOTAL_FRAMES = 4
.proc anim_char

	sec
	lda anim_speed
	sbc #ANIM_SPEED
	and #07
	sta anim_speed
	bcc @animation

	rts

@animation:
	lda anim_char_idx
	asl			; multiply by 8 (next char)
	asl
	asl
	tay

	ldx #7			; 8 rows
@loop:
	lda char_frames,y
	sta $3800 + $fd * 8,x
	eor #$ff
	sta $3800 + $fe * 8,x

	iny
	dex
	bpl @loop

	dec anim_char_idx
	bpl :+

	; reset anim_char_idx
	lda #ANIM_TOTAL_FRAMES-1
	sta anim_char_idx
:
	rts
.endproc

;--------------------------------------------------------------------------
; anim_rasterbar(void)
;--------------------------------------------------------------------------
; Args: -
; A Color washer routine
;--------------------------------------------------------------------------
.proc anim_rasterbar

	; washer top
	lda raster_colors_top
	sta save_color_top

	ldx #0
:	lda raster_colors_top+1,x
	sta raster_colors_top,x
	inx
	cpx #TOTAL_RASTER_LINES
	bne :-

save_color_top = *+1
	lda #00			; This value will be overwritten
	sta raster_colors_top+TOTAL_RASTER_LINES-1

	; washer bottom
	lda raster_colors_bottom+TOTAL_RASTER_LINES-1
	sta save_color_bottom

	cpx #TOTAL_RASTER_LINES-1
:	lda raster_colors_bottom,x
	sta raster_colors_bottom+1,x
	dex
	bpl :-

save_color_bottom = *+1
	lda #00			; This value will be overwritten
	sta raster_colors_bottom
	rts
.endproc

;--------------------------------------------------------------------------
; init(void)
;--------------------------------------------------------------------------
; Args: -
; Clear screen, interrupts, charset and others
;--------------------------------------------------------------------------
.proc init
	lda #$07
	jsr clear_screen
	lda #3
	jsr color_screen

	; init koala colors
	jsr init_koala_colors

	jsr init_scroll_colors

	jsr init_charset

	; no sprites please
	lda #$00
	sta $d015

	; init music
	lda #0
	jsr MUSIC_INIT

	; colors
	lda #0
	sta $d020
	sta $d021

	; default is:
	;    %00010101
	lda #%00011110
	sta $d018		; charset at $3800

	; no interrups
	sei

	; turn off cia interrups
	lda #$7f
	sta $dc0d
	sta $dd0d

	; enable raster irq
	lda #01
	sta $d01a


	;default is:
	;    %00011011
	lda #%00011011
	sta $d011

	; turn off BASIC + Kernal. More RAM
	lda #$35
	sta $01

	; bank 0
;	lda $dd00
;	and #$fc
;	ora #3
;	sta $dd00

	;
	; irq handler
	;
	lda #<irq1
	sta $fffe
	lda #>irq1
	sta $ffff

	; raster interrupt
	lda #RASTER_START+SCROLL_1_AT_LINE*8-3
	sta $d012

	; clear interrupts and ACK irq
	lda $dc0d
	lda $dd0d
	asl $d019


	; enable interrups again
	cli

	rts
.endproc

;--------------------------------------------------------------------------
; init_koala_colors(void)
;--------------------------------------------------------------------------
; Args: -
; puts the koala colors in the correct address
; Assumes that bimap data is already in the correct position
;--------------------------------------------------------------------------
.proc init_koala_colors

	ldx #$00
@loop:
	; $0400
	lda CHARMEM_DATA,x
	sta $0400,x
	lda CHARMEM_DATA+$0100,x
	sta $0400+$0100,x
	lda CHARMEM_DATA+$0200,x
	sta $0400+$0200,x
	lda CHARMEM_DATA+$02e8,x
	sta $0400+$02e8,x

	; $d800
	lda COLORMEM_DATA,x
	sta $d800,x
	lda COLORMEM_DATA+$0100,x
	sta $d800+$100,x
	lda COLORMEM_DATA+$0200,x
	sta $d800+$200,x
	lda COLORMEM_DATA+$02e8,x
	sta $d800+$02e8,x

	inx
	bne @loop
	rts
.endproc

;--------------------------------------------------------------------------
; init_scroll_colors(void)
;--------------------------------------------------------------------------
; Args: -
;--------------------------------------------------------------------------
.proc init_scroll_colors
	; foreground RAM color for scroll lines
	ldx #0
	; 9 lines: 40 * 9 = 360. 256 + 104
@loop:
	; clear color
	lda #15
	sta $d800 + SCROLL_1_AT_LINE * 40,x
	sta $d800 + SCROLL_1_AT_LINE * 40 + (ROWS_PER_CHAR*40-256),x

	; clear char
	lda #$ff
	sta $0400 + SCROLL_1_AT_LINE * 40,x
	sta $0400 + SCROLL_1_AT_LINE * 40 + (ROWS_PER_CHAR*40-256),x

	inx
	bne @loop
	rts
.endproc

;--------------------------------------------------------------------------
; init_charset(void)
;--------------------------------------------------------------------------
; Args: -
; copies 3 custom chars to the correct address
;--------------------------------------------------------------------------
.proc init_charset
	ldx #$07
@loop:
	lda #$ff
	sta $3ff8,x
	dex
	bpl @loop
	rts
.endproc

;--------------------------------------------------------------------------
; variables
;--------------------------------------------------------------------------

; IMPORTANT: raster_colors must be at the beginning of the page in order to avoid extra cycles.
.segment "DATAINTRO"
raster_colors:
raster_colors_top:
	; Color washer palette taken from: Dustlayer intro
	; https://github.com/actraiser/dust-tutorial-c64-first-intro/blob/master/code/data_colorwash.asm
	.byte $09,$09,$02,$02,$08,$08,$0a,$0a
	.byte $0f,$0f,$07,$07,$01,$01,$01,$01
	.byte $01,$01,$01,$01,$01,$01,$01,$01
	.byte $07,$07,$0f,$0f,$0a,$0a,$08,$08
	.byte $02,$02,$09,$09

raster_colors_bottom:
	.byte $09,$09,$02,$02
	.byte $08,$08,$0a,$0a,$0f,$0f,$07,$07
	.byte $01,$01,$01,$01,$01,$01,$01,$01
	.byte $01,$01,$01,$01,$07,$07,$0f,$0f
	.byte $0a,$0a,$08,$08,$02,$02,$09,$09
	; FIXME: ignore, for overflow
	.byte 0

TOTAL_RASTER_LINES = raster_colors_bottom-raster_colors_top

sync:			.byte 1
smooth_scroll_x:	.byte 7
chars_scrolled:		.byte 128
current_char:		.byte 0
anim_speed:		.byte 7
anim_char_idx:		.byte ANIM_TOTAL_FRAMES-1
scroller_text_ptr_low:	.byte 0
scroller_text_ptr_hi:	.byte 0

scroller_text:
	scrcode "   'the muni race': the best mountain unicycle racing game for the "
	.byte 64
	scrcode "64. in fact it is the best mountain unicycle racing game ever written!!!"
	scrcode "people said about this game: 'awesome graphics', 'impressive physics', "
	scrcode "'best sound ever', 'i want to ride a real unicycle now', "
	scrcode "'bikes? what a waste of resources!', 'can i play basketball on unicycles?' "
	scrcode "and much more! "
	scrcode "what are you waiting for? just press f1 to start riding!!!...      "
	.byte $ff

char_frames:
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00011000
	.byte %00011000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00011000
	.byte %00111100
	.byte %00111100
	.byte %00011000
	.byte %00000000
	.byte %00000000


	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00011000
	.byte %00011000
	.byte %00000000
	.byte %00000000
	.byte %00000000

	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000
	.byte %00000000

.segment "CHARSET"
	; last 3 chars reserved
;        .incbin "res/scrap_writer_iii_16.64c",2,(2048-8*3)
	.incbin "res/1-writer.64c",2,(2048-8*3)
;	.incbin "res/blue_max.64c",2
;	.incbin "res/combat_leader.64c",2

.segment "SIDMUSIC"
         .incbin "res/music.sid",$7e

.segment "GFX"
	 .incbin "res/muni-320x200x16.prg"
