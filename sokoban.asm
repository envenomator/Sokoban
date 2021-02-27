.include "x16.inc"

.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

   jmp start

message: .byte "press a key",0
up:   .byte "up",0
down: .byte "down",0
left: .byte "left",0
right:.byte "right",0
other:.byte "other",0

field:
;     01234567890123  4
.byte"       ####   "
.byte"########  ##  "
.byte"#          ###"
;.byte"# @$$ ##   ..#"
.byte"#    #  $@   #"
.byte"# $$   ##  ..#"
.byte"#         ####"
.byte"###########   "

XPOS = 9 ; fixed value for now, need to read in later. zero-based value
YPOS = 3 ; same

FIELDWIDTH = 14
FIELDHEIGHT = 7
NEWLINE = $0D
UPPERCASE = $8E
CLEARSCREEN = 147

; usage of zeropage pointers:
; ZP_PTR_1 - temporary pointer
; ZP_PTR_2 - temporary pointer
; ZP_PTR_3 - position of player
; ZP_PTR_4 - use as height/width

start:
    ; force uppercase
    lda #UPPERCASE
    jsr CHROUT
    
    jsr initfield
    jsr cls
    jsr printfield

keyloop:
    jsr GETIN
@checkdown:
    cmp #$11
    bne @checkup
    jsr handledown
    bra @done
@checkup:
    cmp #$91
    bne @checkleft
    jsr handleup
    bra @done
@checkleft:
    cmp #$9d
    bne @checkright
    jsr handleleft
    bra @done
@checkright:
    cmp #$1d
    bne @done
    jsr handleright
@done:
    jmp keyloop

handleright:
    ; pointers
    ; 3 - player
    ; 2 - block to the right of the player
    ; 1 - block to the right of that block
    lda ZP_PTR_3+1
    sta ZP_PTR_2+1
    sta ZP_PTR_1+1
    lda ZP_PTR_3
    sta ZP_PTR_2
    sta ZP_PTR_1
    inc ZP_PTR_2
    inc ZP_PTR_1
    inc ZP_PTR_1

    jsr handlemove
    rts

handleleft:
    ; pointers
    ; 3 - player
    ; 2 - block to the left of the player
    ; 1 - block to the left of that block
    lda ZP_PTR_3+1
    sta ZP_PTR_2+1
    sta ZP_PTR_1+1
    lda ZP_PTR_3
    sta ZP_PTR_2
    sta ZP_PTR_1
    dec ZP_PTR_2
    dec ZP_PTR_1
    dec ZP_PTR_1

    jsr handlemove

@done:
    rts
handleup:
    ; pointers
    ; 3 - player
    ; 2 - block to the top of the player
    ; 1 - block to the top of that block
    lda ZP_PTR_3+1
    sta ZP_PTR_2+1
    sta ZP_PTR_1+1
    lda ZP_PTR_3
    sta ZP_PTR_2
    sta ZP_PTR_1

    ldx #FIELDWIDTH
@loop:
    dec ZP_PTR_2
    dec ZP_PTR_1
    dec ZP_PTR_1
    dex
    bne @loop
    
    jsr handlemove

@done:
    rts

handledown:
    ; pointers
    ; 3 - player
    ; 2 - block to the bottom of the player
    ; 1 - block to the bottom of that block
    lda ZP_PTR_3+1
    sta ZP_PTR_2+1
    sta ZP_PTR_1+1
    lda ZP_PTR_3
    sta ZP_PTR_2
    sta ZP_PTR_1

    ldx #FIELDWIDTH
@loop:
    inc ZP_PTR_2
    inc ZP_PTR_1
    inc ZP_PTR_1
    dex
    bne @loop
    
    jsr handlemove
    rts

handlemove:
    ; pointers
    ; 3 - points to the player position
    ; 2 - points to the next block at the indicated direction
    ; 1 - points to the block after that block

    ldy #0
    lda (ZP_PTR_2),y
    cmp #' ' ; empty block next to player?
    bne @next
    ; move player to pointer 2
    jsr move3to2
    jsr moveplayerposition

    jsr cls
    jsr printfield

    rts
@next:
    ldy #0
    lda (ZP_PTR_2),y
    cmp #'$' ; crate next to player?
    bne @done

    lda (ZP_PTR_1),y
    cmp #' ' ; space after crate?
    bne @done
    
    jsr move2to1
    jsr move3to2
    jsr moveplayerposition

    jsr cls
    jsr printfield
@done:
    rts

moveplayerposition:
    ; moves pointer 3 to position of pointer 2
    lda ZP_PTR_2
    sta ZP_PTR_3
    lda ZP_PTR_2+1
    sta ZP_PTR_3+1
    rts

move2to1:
    ; copies (ZP_PTR_2) to (ZP_PTR_1)
    ; and copies ' ' to last position in (Z_PTR_2)
    ldy #0
    lda (ZP_PTR_2),y
    sta (ZP_PTR_1),y
    lda #' '
    sta (ZP_PTR_2),y
    rts

move3to2:
    ; copies (ZP_PTR_3) to (ZP_PTR_2)
    ; and copies ' ' to last position in (Z_PTR_3)
    ldy #0
    lda (ZP_PTR_3),y
    sta (ZP_PTR_2),y
    lda #' '
    sta (ZP_PTR_3),y
    rts

print:
    ; print from address ZP_PTR_1
    ; don't end with newline character
    ldy #0
@loop:
    lda (ZP_PTR_1),y ; load character from address
    beq @done        ; end at 0 character
    jsr CHROUT 
    iny
    bra @loop
@done:
    rts

printline:
    ; print from address ZP_PTR_1
    ; end with newline character
    jsr print
    lda #NEWLINE
    jsr CHROUT
    rts

initfield:
    ;skeleton code for now
    ; fixed (2,2) player position for now
   
    ; advance to start of field
    lda #<field
    sta ZP_PTR_3
    lda #>field
    sta ZP_PTR_3+1
    ; add x,y position to the pointer
    lda ZP_PTR_3
    clc
    adc #XPOS
    sta ZP_PTR_3
    ; check carry to high byte
    bcc @ypos
    lda ZP_PTR_3+1 ; store carry to high byte
    clc
    adc #1
    sta ZP_PTR_3+1
@ypos:
    lda ZP_PTR_3
    clc
    adc #(YPOS * FIELDWIDTH)
    sta ZP_PTR_3
    ; check for carry to high byte
    bcc @done
    lda ZP_PTR_3+1
    clc
    adc #1
    sta ZP_PTR_3+1
@done:
   rts

printfield:
    ; no clearscreen, just print the field to screen on current position
    ; depends only on
    ; - field label for start of field
    ; - FIELDHEIGHT constant
    ; - FIELDWIDTH constant

    lda #<field
    sta ZP_PTR_1
    lda #>field
    sta ZP_PTR_1+1
    ldx #0 ; row counter
@nextrow:
    ldy #0 ; column counter
@row:
    lda (ZP_PTR_1),y
    jsr CHROUT
    iny
    cpy #FIELDWIDTH
    bne @row
@endline:
    lda #NEWLINE
    jsr CHROUT
    
    ; advance pointer to next row
    lda ZP_PTR_1
    clc
    adc #FIELDWIDTH
    sta ZP_PTR_1
    bcc @checklastrow ; no carry, don't increment high byte on pointer
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    clc
    adc #1
    sta ZP_PTR_1+1
@checklastrow:
    ; last row?
    inx
    cpx #FIELDHEIGHT
    bne @nextrow
    rts

cls:
    lda #CLEARSCREEN
    jsr CHROUT
    rts
