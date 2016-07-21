;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
;
; The Uni Games: https://github.com/ricardoquesada/c64-the-uni-games
;
; High Scores screen
;
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;

; from utils.s
.import ut_clear_color, ut_get_key, ut_clear_screen

; from main.s
.import sync_timer_irq
.import menu_read_events
.import mainscreen_colors

UNI1_ROW = 10                           ; unicyclist #1 x,y
UNI1_COL = 0
UNI2_ROW = 37                           ; unicylists #2 x,y
UNI2_COL = 10


;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Macros
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.macpack cbm                            ; adds support for scrcode

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; Constants
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.include "c64.inc"                      ; c64 constants
.include "myconstants.inc"


.segment "HI_CODE"

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_init
;------------------------------------------------------------------------------;
.export scores_init
.proc scores_init
        sei
        lda #0
        sta score_counter

        lda #%00000000                  ; enable only PAL/NTSC scprite
        sta VIC_SPR_ENA

        lda #$01
        jsr ut_clear_color

        lda #$20
        jsr ut_clear_screen

        jsr scores_init_screen
        cli


scores_mainloop:
        lda sync_timer_irq
        bne play_music

        jsr menu_read_events
        cmp #%00010000                  ; space or button
        bne scores_mainloop
        rts                             ; return to caller (main menu)
play_music:
        dec sync_timer_irq
        jsr $1003
        jsr paint_score
        jmp scores_mainloop
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; scores_init_screen
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc scores_init_screen

        ldx #0
l0:
        lda hiscores_map,x
        sta SCREEN0_BASE,x
        tay
        lda mainscreen_colors,y
        sta $d800,x

        inx
        cpx #240
        bne l0


        ldx #39
:       lda categories,x                ; displays the  category: "10k road racing"
        sta SCREEN0_BASE + 280,x
        dex
        bpl :-

        ldx #<(SCREEN0_BASE + 40 * 10 + 6)  ; init "save" pointer
        ldy #>(SCREEN0_BASE + 40 * 10 + 6)  ; start writing at 10th line
        stx zp_hs_ptr_lo
        sty zp_hs_ptr_hi
        rts
.endproc

;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
; paint_score
; entries:
;       X = score to draw
;=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-;
.proc paint_score

        dec delay
        beq paint
        rts

paint:
        lda #$04
        sta delay

        ldx score_counter
        cpx #8                          ; paint only 8 scores
        beq @end

        jsr @print_highscore_entry

        clc                             ; pointer to the next line in the screen
        lda zp_hs_ptr_lo 
        adc #(40 * 2)                   ; skip one line
        sta zp_hs_ptr_lo
        bcc :+
        inc zp_hs_ptr_hi
:
        inc score_counter

@end:
        rts

@print_highscore_entry:
        txa                             ; x has the high score entry index

        ldy #$00                        ; y = screen idx

        pha
        clc
        adc #$01                        ; positions start with 1, not 0

        cmp #10                         ; print position
        bne @print_second_digit

        lda #$31                        ; hack: if number is 10, print '1'. $31 = '1'
        sta (zp_hs_ptr_lo),y            ; otherwise, skip to second number
        ora #$40
        iny
        lda #00                         ; second digit is '0'
        jmp :+

@print_second_digit:
        iny
:
        clc
        adc #$30                        ; A = high_score entry.
        sta (zp_hs_ptr_lo),y
        iny

        lda #$2e                        ; print '.'
        sta (zp_hs_ptr_lo),y
        iny


        lda #10                         ; print name. 10 chars
        sta @tmp_counter

        txa                             ; multiply x by 16, since each entry has 16 bytes
        asl
        asl
        asl
        asl
        tax                             ; x = high score pointer

:       lda entries,x                   ; points to entry[i].name
        sta (zp_hs_ptr_lo),y            ; pointer to screen
        iny
        inx
        dec @tmp_counter
        bne :-


        lda #6                          ; print score. 6 digits
        sta @tmp_counter

        tya                             ; advance some chars
        clc
        adc #8
        tay

:       lda entries,x                   ; points to entry[i].score
        clc
        adc #$30
        sta (zp_hs_ptr_lo),y            ; pointer to screen
        iny
        inx
        dec @tmp_counter
        bne :-

        pla
        tax
        rts

@tmp_counter:
        .byte 0
.endproc


                ;0123456789|123456789|123456789|123456789|
categories:
        scrcode "                road race               "
        scrcode "               cyclo cross              "
        scrcode "              cross country             "

entries:
        ; high score entry:
        ;     name: 10 bytes in PETSCII
        ;     score: 6 bytes
        ;        0123456789
        scrcode "tom       "
        .byte  9,0,0,0,0,0
        scrcode "chris     "
        .byte  8,0,0,0,0,0
        scrcode "dragon    "
        .byte  7,0,0,0,0,0
        scrcode "corbin    "
        .byte  6,0,0,0,0,0
        scrcode "jimbo     "
        .byte  5,0,0,0,0,0
        scrcode "ashley    "
        .byte  4,0,0,0,0,0
        scrcode "josh      "
        .byte  3,0,0,0,0,0
        scrcode "michele   "
        .byte  2,0,0,0,0,0

score_counter: .byte 0                  ; score that has been drawn
delay:         .byte $10                ; delay used to print the scores

hiscores_map:
        .incbin "hiscores-map.bin"      ; 40 * 6
