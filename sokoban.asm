.include "x16.inc"

; constants
;field = $100c; load for fields
ZP_PTR_FIELD = $28
temp = $30  ; used for temp 8/16 bit storage $30/$31

LOADSTART = $a000;
NEWLINE = $0D
UPPERCASE = $8E
CLEARSCREEN = 147
LEVELHEADER = 10

; screen 16x16bit tile width/height
SCREENWIDTH = 20
SCREENHEIGHT = 15

.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

; VERA Registers
VERA_LOW            = $9F20
VERA_MID            = $9F21
VERA_HIGH           = $9F22
VERA_DATA0          = $9F23
VERA_CTRL           = $9F25

   jmp start

; string constants
message:          .byte "press a key",0
selectmessage:    .byte "select a level (",0
selectendmessage: .byte "): ",0
errormessage:     .byte "error loading file",0
quitmessage:      .byte "press q to quit",0
filename:         .byte "levels.bin"
filename_end:
winstatement:     .byte "goal reached!",0

; variables that the program uses during execution
currentlevel:   .byte 1 ; will need to be filled somewhere in the future in the GUI, or asked from the user
no_levels:      .byte 0 ; will be read by initfield
no_goals:       .byte 0 ; will be read by initfield, depending on the currentlevel
no_goalsreached:.byte 0 ; static now, reset for each game
fieldwidth:     .byte 0 ; will be read by initfield, depending on the currentlevel
fieldheight:    .byte 0 ; will be read by initfield, depending on the currentlevel
vera_byte_low:  .byte 0
vera_byte_mid: .byte 0

; usage of zeropage pointers:
; ZP_PTR_1 - temporary pointer
; ZP_PTR_2 - temporary pointer
; ZP_PTR_3 - position of player

loadfield:
    ; loads all fields from the file 'LEVELS.BIN'
    lda #filename_end - filename
    ldx #<filename
    ldy #>filename
    jsr SETNAM
    lda #$01
    ldx #$08
    ldy #$01
    jsr SETLFS
    lda #$00 ; load to memory
    jsr LOAD
    ; sets carry flag on error, handled by upstream caller
    rts

start:
    ; force uppercase
    lda #UPPERCASE
    jsr CHROUT

    jsr loadfield
    bcc @next
    ; error
    lda #<errormessage
    sta ZP_PTR_1
    lda #>errormessage
    sta ZP_PTR_1+1
    jsr printline
    rts ; exit program
@next:
    jsr resetvars
    jsr loadtiles       ; load tiles from normal memory to VRAM
    jsr layerconfig     ; configure layer 0/1 on screen

    jsr selectlevel
    jsr initfield       ; load correct startup values for selected field
    jsr printfield2

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
    bne @checkquit
    jsr handleright
@checkquit:
    cmp #$51
    bne @done
    rts
@done:
    ; check if we have reached all goals
    lda no_goals
    cmp no_goalsreached
    bne @donenextkey
    jsr printwinstatement
    rts
@donenextkey:
    jmp keyloop

handleright:
    ; pointers
    ; 3 - player
    ; 2 - block to the right of the player
    ; 1 - block to the right of that block

    ; ZP_PTR_2 = ZP_PTR_3 + 1x position
    clc
    lda ZP_PTR_3
    adc #$1               ; 1x position
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    adc #$0
    sta ZP_PTR_2+1

    ; ZP_PTR_1 = ZP_PTR_1 + 2x position
    clc
    lda ZP_PTR_3
    adc #$2               ; 2x position
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    adc #$0
    sta ZP_PTR_1+1

    jsr handlemove
    rts

handleleft:
    ; pointers
    ; 3 - player
    ; 2 - block to the left of the player
    ; 1 - block to the left of that block

    ; ZP_PTR_2 = ZP_PTR_3 - 1x position
    sec
    lda ZP_PTR_3
    sbc #$1               ; 1x position
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    sbc #$0
    sta ZP_PTR_2+1

    ; ZP_PTR_1 = ZP_PTR_1 - 2x position
    sec
    lda ZP_PTR_3
    sbc #$2               ; 2x position
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    sbc #$0
    sta ZP_PTR_1+1

    jsr handlemove

@done:
    rts
handleup:
    ; pointers
    ; 3 - player
    ; 2 - block to the top of the player
    ; 1 - block to the top of that block

    ; ZP_PTR_2 = ZP_PTR_3 - 1xFIELDWIDTH
    lda fieldwidth
    sta temp
    sec
    lda ZP_PTR_3
    sbc temp
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    sbc #$0
    sta ZP_PTR_2+1

    ; ZP_PTR_1 = ZP_PTR_1 - 2xFIELDWIDTH
    lda fieldwidth
    asl ; 2x
    sta temp
    sec
    lda ZP_PTR_3
    sbc temp
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    sbc #$0
    sta ZP_PTR_1+1

    jsr handlemove

@done:
    rts

handledown:
    ; pointers
    ; 3 - player
    ; 2 - block to the bottom of the player
    ; 1 - block to the bottom of that block

    ; ZP_PTR_2 = ZP_PTR_3 + 1xFIELDWIDTH
    lda fieldwidth
    sta temp
    clc
    lda ZP_PTR_3
    adc temp
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    adc #$0
    sta ZP_PTR_2+1

    ; ZP_PTR_1 = ZP_PTR_1 + 2xFIELDWIDTH
    lda fieldwidth
    asl ; 2x
    sta temp
    clc
    lda ZP_PTR_3
    adc temp
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    adc #$0
    sta ZP_PTR_1+1

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
    beq @moveplayertopoint2
    cmp #'.' ; goal position next to player?
    beq @moveplayertopoint2
    bra @next ; no ' ' or '.' found next to player, is it a crate or a wall?
@moveplayertopoint2:
    ; move player to pointer 2
    jsr moveplayeronfield
    jsr moveplayerposition

    jsr cls
;    jsr printfield
    jsr printfield2

    rts
@next:
    ldy #0
    lda (ZP_PTR_2),y
    cmp #'$' ; crate next to player?
    beq @combinedmovecheck
    cmp #'*' ; crate on goal next to player?
    beq @combinedmovecheck
    bra @done ; something else not able to push
@combinedmovecheck:
    lda (ZP_PTR_1),y
    cmp #' ' ; space after crate?
    beq @combinedmove
    cmp #'.' ; goal after crate?
    beq @combinedmove
    bra @done ; nothing to move
@combinedmove:
    jsr movecrateonfield
    jsr moveplayeronfield
    jsr moveplayerposition

    jsr printfield2
@done:
    rts

moveplayerposition:
    ; moves pointer 3 to position of pointer 2
    lda ZP_PTR_2
    sta ZP_PTR_3
    lda ZP_PTR_2+1
    sta ZP_PTR_3+1
    rts

movecrateonfield:
    ; copies (ZP_PTR_2) to (ZP_PTR_1)
    ; and handles different crate move options (normal / crate on goal)
    ldy #0
    lda (ZP_PTR_2),y
    ; was there a goal underneath the crate?
    cmp #'*'
    bne @crateonly
    ; do we move to a goal position? (from goal to goal..)
    lda (ZP_PTR_1),y
    cmp #'.'
    bne @movetonormalposition
@movetogoalposition:
    lda #'*' ; crate on goal symbol
    sta (ZP_PTR_1),y
    lda #'.'
    sta (ZP_PTR_2),y
    bra @done
@movetonormalposition:
    dec no_goalsreached ; -1 win points
    lda #'$'; crate symbol
    sta (ZP_PTR_1),y
    lda #'.'
    sta (ZP_PTR_2),y
    bra @done
@crateonly:
    ; is the destination a goal?
    lda (ZP_PTR_1),y
    cmp #'.'
    bne @crateonly_nongoal
    ; crate moves to goal, from a non-goal position
    inc no_goalsreached ; +1 to win
    lda #'*'
    sta (ZP_PTR_1),y
    lda #' '
    sta (ZP_PTR_2),y
    bra @done
@crateonly_nongoal:
    lda #'$'
    sta (ZP_PTR_1),y
    lda #' '; empty space to move the player in next
    sta (ZP_PTR_2),y
@done:
    rts

moveplayeronfield:
    ; copies (ZP_PTR_3) to (ZP_PTR_2)
    ; and handles multiple player move options (normal / on goal)
    ldy #0
    lda (ZP_PTR_3),y
    ; was there a goal underneath the player?
    cmp #'+'
    bne @playeronly
    ; do we move to a goal position? (from goal to goal..)
    lda (ZP_PTR_2),y
    cmp #'.'
    bne @movetonormalposition
@movetogoalposition:
    lda #'+' ; player on goal symbol
    sta (ZP_PTR_2),y
    lda #'.'
    sta (ZP_PTR_3),y
    bra @done
@movetonormalposition:
    lda #'@'; crate symbol
    sta (ZP_PTR_2),y
    lda #'.'
    sta (ZP_PTR_3),y
    bra @done
@playeronly:
    ; is the destination a goal?
    lda (ZP_PTR_2),y
    cmp #'.'
    bne @playeronly_nongoal
    ; player moves to goal, from a non-goal position
    lda #'+'
    sta (ZP_PTR_2),y
    lda #' '
    sta (ZP_PTR_3),y
    bra @done
@playeronly_nongoal:
    lda #'@'
    sta (ZP_PTR_2),y
    lda #' '; empty space
    sta (ZP_PTR_3),y
@done:
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

printwinstatement:
    lda #<winstatement
    sta ZP_PTR_1
    lda #>winstatement
    sta ZP_PTR_1+1
    jsr printline
    rts

printdecimal:
    ; prints decimal from A register
    ldy #$2f
    ldx #$3a
    sec
@loop1:
    iny
    sbc #100
    bcs @loop1
@loop2:
    dex
    adc #10
    bmi @loop2
    adc #$2f

    ; Y = hundreds, X = tens, A = ones
    pha
    txa
    pha
    tya
    cmp #$30 ; is it a '0' petscii?
    beq @tens
    jsr CHROUT ; print Y
@tens:
    pla
    cmp #$30 ; is it a '0' petscii?
    beq @ones
    jsr CHROUT ; print X
@ones:
    pla
    jsr CHROUT ; print A

    rts

selectlevel:
    lda #1 ; start out with first level
    sta currentlevel

@mainloop:
    jsr cls
    ; print selection message
    lda #<selectmessage
    sta ZP_PTR_1
    lda #>selectmessage
    sta ZP_PTR_1+1
    jsr print
    ; print range
    jsr CHROUT
    lda #'1'
    jsr CHROUT
    lda #'-'
    jsr CHROUT
    lda no_levels
    jsr printdecimal
    lda #<selectendmessage
    sta ZP_PTR_1
    lda #>selectendmessage
    sta ZP_PTR_1+1
    jsr print
    ; print level number
    lda currentlevel
    jsr printdecimal

@charloop:
    jsr GETIN
@checkdown:
    cmp #$11 ; down pressed
    beq @down
    cmp #$9d ; left pressed
    beq @down
    bra @checkup
@down:
    ; down key pressed
    lda currentlevel
    cmp #1
    beq @charloop   ; lowest value == 1
    dec currentlevel
    bra @mainloop
@checkup:
    cmp #$91 ; up pressed
    beq @up
    cmp #$1d ; right pressed
    beq @up
    bra @checkreturnkey
@up:
    ; up key pressed
    lda currentlevel
    cmp no_levels
    beq @charloop   ; maximum value reached
    inc currentlevel
    bra @mainloop
@checkreturnkey:
    cmp #$0d
    bne @charloop
    ; return key pressed - select this level
    jsr cls
    rts

resetvars:
    ; reset goals
    lda #0
    sta no_goalsreached

    ; load field pointer to first address at LOADSTART
    ; load 1st pointer to temp pointer ZP_PTR_1
    lda #<LOADSTART
    sta ZP_PTR_1
    lda #>LOADSTART
    sta ZP_PTR_1+1

    ; load number of levels, pointed to by ZP_PTR_1,0
    ldy #0
    lda (ZP_PTR_1),y
    sta no_levels

    rts

initfield:
    ; load field pointer to first address at LOADSTART
    ; load 1st pointer to temp pointer ZP_PTR_1
    lda #<LOADSTART
    sta ZP_PTR_1
    lda #>LOADSTART
    sta ZP_PTR_1+1

    ; skip to the first header, two bytes next
    clc
    lda ZP_PTR_1
    adc #2
    sta ZP_PTR_1

    ; now advance pointer (currentlevel - 1) * HEADERSIZE to advance to the correct payload pointer to that level
    lda currentlevel
    tax ; x contains the currentlevel now and will act as a counter
@loop:
    dex
    beq @fieldptrdone 
    ; advance the field payload pointer
    lda ZP_PTR_1
    clc
    adc #LEVELHEADER
    sta ZP_PTR_1
    bcc @loop   ; nothing to do for the high byte
    lda ZP_PTR_1+1
    adc #$0     ; increase the high byte
    sta ZP_PTR_1+1
    bra @loop
@fieldptrdone:
    ldy #0  ; index to the payload pointer itself
    lda (ZP_PTR_1),y
    sta ZP_PTR_FIELD
    iny
    lda (ZP_PTR_1),y
    sta ZP_PTR_FIELD+1
    ldy #2  ; index from payload pointer to width variable (low byte)
    lda (ZP_PTR_1),y 
    sta fieldwidth
    ldy #4  ; index from payload pointer to height variable (low byte)
    lda (ZP_PTR_1),y
    sta fieldheight
    ldy #6  ; index from payload pointer to goals in this level (low byte)
    lda (ZP_PTR_1),y
    sta no_goals
    ldy #8  ; index from payload pointer to player ptr in this level
    lda (ZP_PTR_1),y
    sta ZP_PTR_3
    iny
    lda (ZP_PTR_1),y
    sta ZP_PTR_3+1

    rts

printfield:
    ; no clearscreen, just print the field to screen on current position
    ; depends only on
    ; - field label for start of field

    lda ZP_PTR_FIELD
    sta ZP_PTR_1
    lda ZP_PTR_FIELD+1
    sta ZP_PTR_1+1
    ldx #0 ; row counter
@nextrow:
    ldy #0 ; column counter
@row:
    lda (ZP_PTR_1),y
    cmp #'@'
    beq @character
    cmp #'+'
    beq @character
    bra @normalcolor
@character:
    pha
    lda #$9e ; YELLOW
    jsr CHROUT
    pla
    jsr CHROUT
    lda #$05 ; WHITE
    jsr CHROUT
    iny
    cpy fieldwidth
    bne @row
    bra @endline
@normalcolor:
    jsr CHROUT
    iny
    cpy fieldwidth
    bne @row
@endline:
    lda #NEWLINE
    jsr CHROUT
    
    ; advance pointer to next row
    lda ZP_PTR_1
    clc
    adc fieldwidth
    sta ZP_PTR_1
    bcc @checklastrow ; no carry, don't increment high byte on pointer
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    clc
    adc #1
    sta ZP_PTR_1+1
@checklastrow:
    ; last row?
    inx
    cpx fieldheight
    bne @nextrow

    ; print quit message at the end of the field
    lda #NEWLINE
    jsr CHROUT
    lda #<quitmessage
    sta ZP_PTR_1
    lda #>quitmessage
    sta ZP_PTR_1+1
    jsr printline

    rts

cls:
    lda #CLEARSCREEN
    jsr CHROUT
    rts

loadtiles:
; Build  16x16 256 color tiles in VRAM location $12000
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$11
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 1
    lda #$20
    sta VERA_MID                        ; Set Middle Byte to $20
    stz VERA_LOW                        ; Set Low Byte to $00

    ldx #0
:   lda tiledata,x                      ; index 0 / black tile
    sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    inx
    bne :-
    ; load Brick data
    ldx #0
:   lda Brick,x                         ; index 1 / brick
    sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    inx
    bne :-
    ; load player data
    ldx #0
:   lda player,x                        ; index 2 / player
    sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    inx
    bne :-
    ; load crate data
    ldx #0
:   lda crate,x                         ; index 3 / crate (normal)
    sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    inx
    bne :-
    ; load goal data
    ldx #0
:   lda goal,x                         ; index 4 / goal (normal)
    sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    inx
    bne :-
    ; load crateongoal data
    ldx #0
:   lda crateongoal,x                   ; index 5 / crate on goal
    sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    inx
    bne :-
    
    rts

layerconfig:
; Configure Layer 0
    lda #%00000011                      ; 32 x 32 tiles, 8 bits per pixel
    sta $9F2D
    lda #$20                            ; $20 points to $4000 in VRAM
    sta $9F2E                           ; Store to Map Base Pointer

    lda #$93                            ; $48 points to $12000, Width and Height 16 pixel
    sta $9F2F                           ; Store to Tile Base Pointer

; Fill the Layer 0 with all zeros (black)
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    lda #$40
    sta VERA_MID                        ; Set Middle Byte to $40
    lda #$0
    sta VERA_LOW                        ; Set Low Byte to $00

    lda #0
    sta VERA_DATA0
    sta VERA_DATA0

    ldy #32
    lda #0
:   ldx #32
:   sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    sta VERA_DATA0                      ; Write Attribute
    dex
    bne :-
    dey
    bne :--

; Turn on Layer 0
    lda $9F29
    ora #%00110000                      ; Bits 4 and 5 are set to 1
    sta $9F29                           ; So both Later 0 and 1 are turned on

; Change Layer 1 to 256 Color Mode
    lda $9F34
    ora #%001000                        ; Set bit 3 to 1, rest unchanged
    sta $9F34

; Clear Layer 1
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    stz VERA_MID                        ; Set Middle Byte to $00
    stz VERA_LOW                        ; Set Low Byte to $00

    lda #30
    sta $02                             ; save counter for rows
    ldy #$01                            ; Color Attribute white on black background
    lda #$20                            ; Blank character
    ldx #0
:   sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    sty VERA_DATA0                      ; Write Attribute
    inx
    bne :-
    dec $02
    bne :-

; Scale Display x2 for resolution of 320 x 240 pixels
    lda #$40
    sta $9F2A
    sta $9F2B

    rts

printfield2:
; prep variables for vera med/high bytes
;    topleft address for first tile is 0x04000
    lda #$40
    sta vera_byte_mid
    stz vera_byte_low

; shift to the right (SCREENWIDTH - fieldwidth) /2 positions *2 to compensate for attribute
    lda #SCREENWIDTH
    sec
    sbc fieldwidth
    sta vera_byte_low

; shift down number of rows (SCREENHEIGHT - fieldheight) /2 positions
    lda #SCREENHEIGHT
    sec
    sbc fieldheight
    lsr ; /2
    tax ; transfer to counter
@loop:
    cpx #$0
    beq @done ; exit loop when x == 0
    lda vera_byte_low
    clc
    adc #$40    ; add row ADDRESS height for exactly one row down
    sta vera_byte_low
    bcc @decrement  ; no need to change the high byte
    lda vera_byte_mid
    adc #$0     ; add carry (so +1)
    sta vera_byte_mid
@decrement: ; next row
    dex
    bra @loop
@done:

; First, prepare the pointers to the back-end field data
    lda ZP_PTR_FIELD
    sta ZP_PTR_1
    lda ZP_PTR_FIELD+1
    sta ZP_PTR_1+1

    ldx #0 ; row counter
@nextrow:
    ldy #0 ; column counter
    ; prepare vera pointers for this row
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    lda vera_byte_mid
    sta VERA_MID                        ; Set Middle Byte to $40
    lda vera_byte_low
    sta VERA_LOW                        ; Set Low Byte to $00

@row:
    lda (ZP_PTR_1),y
    cmp #'@'
    beq @player
    cmp #'+'
    beq @player
    cmp #'$'
    beq @crate
    cmp #'.'
    beq @goal
    cmp #'*'
    beq @crateongoal
    cmp #' '
    beq @ignore
    cmp #0
    beq @ignore
    bra @wall
@ignore:
    ; ignore
    lda #$0 ; black tile
    sta VERA_DATA0
    stz VERA_DATA0
    iny
    cpy fieldwidth
    bne @row
    bra @endline
@player:
    lda #$2
    sta VERA_DATA0
    stz VERA_DATA0
    iny
    cpy fieldwidth
    bne @row
    bra @endline
@crate:
    lda #$3
    sta VERA_DATA0
    stz VERA_DATA0
    iny
    cpy fieldwidth
    bne @row
    bra @endline
@crateongoal:
    lda #$5
    sta VERA_DATA0
    stz VERA_DATA0
    iny
    cpy fieldwidth
    bne @row
    bra @endline
@goal:
    lda #$4
    sta VERA_DATA0
    stz VERA_DATA0
    iny
    cpy fieldwidth
    bne @row
    bra @endline

@wall:
    lda #$1 ; load tile 1 ; brick
    sta VERA_DATA0
    stz VERA_DATA0

    iny
    cpy fieldwidth
    bne @row
@endline:
    ; advance pointer to next row
    lda ZP_PTR_1
    clc
    adc fieldwidth
    sta ZP_PTR_1
    bcc @checklastrow ; no carry, don't increment high byte on pointer
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    clc
    adc #1
    sta ZP_PTR_1+1
@checklastrow:
    ; last row?
    ; increment vera pointer to next row
    lda vera_byte_low
    clc
    adc #$40    ; add 40 - address to next row
    sta vera_byte_low
    bcc @next3  ; no need to change the high byte
    lda vera_byte_mid
    adc #$0     ; add carry (so +1)
    sta vera_byte_mid
@next3:
    inx
    cpx fieldheight
    beq @nextsection

    jmp @nextrow
@nextsection:
    rts

printdecimal2:
    ; on entry A = value to print to standard out
    ldx #$ff
    sec
@prdec100:
    inx
    sbc #100
    bcs @prdec100
    adc #100
    jsr @prdecdigit
    ldx #$ff
    sec
@prdec10:
    inx
    sbc #10
    bcs @prdec10
    adc #10
    jsr @prdecdigit
    tax
@prdecdigit:
    pha
    txa
    ora #'0'
    jsr CHROUT
    pla
    rts

tiledata:
black:
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
Brick:
    .byte 8,8,8,8,8,8,8,229,8,8,8,8,8,8,8,8
    .byte 42,42,42,42,42,42,41,229,8,42,42,42,42,42,42,42
    .byte 42,42,42,42,42,42,41,229,8,42,44,42,42,42,42,42
    .byte 42,42,44,44,42,42,41,229,8,42,42,42,42,42,42,42
    .byte 42,42,42,42,42,42,41,229,8,42,42,42,42,42,42,42
    .byte 42,42,42,42,42,42,41,229,8,42,42,42,42,41,41,42
    .byte 41,41,41,41,41,41,41,229,8,41,41,41,41,41,41,41
    .byte 229,229,229,229,229,229,229,229,229,229,229,229,229,229,229,229
    .byte 229,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8
    .byte 229,8,8,42,44,44,42,42,42,42,42,42,42,42,42,41
    .byte 229,8,42,42,42,42,42,42,42,42,42,42,42,42,42,41
    .byte 229,8,42,42,42,42,41,41,42,42,42,42,42,42,42,41
    .byte 229,8,42,42,42,42,42,42,42,42,42,42,42,41,42,41
    .byte 229,8,42,42,42,42,42,42,42,42,42,42,42,42,42,41
    .byte 229,8,41,41,41,41,41,41,41,41,41,41,41,41,41,41
    .byte 229,229,229,229,229,229,229,229,229,229,229,229,229,229,229,229
player:
.incbin "player.bin"
crate:
.incbin "crate.bin"
goal:
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,$72,$72,$72,$72,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,$72,$72,$72,$72,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,$72,$72,$72,$72,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,$72,$72,$72,$72,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
    .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
crateongoal:
.incbin "crateongoal.bin"
