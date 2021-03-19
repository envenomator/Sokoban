.include "x16.inc"

; constants
NEWLINE = $0D
UPPERCASE = $8E
CLEARSCREEN = 147
LEVELHEADER = 12
MAXUNDO = 10
SCREENWIDTH = 40        ; screen width/height in 16x16 tiles
SCREENHEIGHT = 30
RAMBANK = $a000         ; Ram Bank 0

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
quitaskmessage:      .byte "really quit? y/n",0
selectmessage:    .byte "select a level (1-",0
selectendmessage: .byte "): ",0
resetmessage:     .byte "really reset level? y/n",0
quitmessage:      .byte "press q to quit",0
winstatement:     .byte "level complete! new level? y/n",0
help0:            .byte "(c)2021 venom",0
help1:            .byte "keyboard shortcuts:",0
help2:            .byte "cursor - moves player",0
help3:            .byte "     q - quit",0
help4:            .byte "     u - undo move(s)",0
help5:            .byte "     r - reset level",0

; variables that the program uses during execution
currentlevel:   .byte 0 ; will need to be filled somewhere in the future in the GUI, or asked from the user
no_levels:      .byte 0 ; will be read by initfield
no_goals:       .byte 0 ; will be read by initfield, depending on the currentlevel
no_goalsreached:.byte 0 ; static now, reset for each game
fieldwidth:     .byte 0 ; will be read by initfield, depending on the currentlevel
fieldheight:    .byte 0 ; will be read by initfield, depending on the currentlevel
vera_byte_low:  .byte 0
vera_byte_mid:  .byte 0
undostack:      .byte 0,0,0,0,0,0,0,0,0,0
undoindex:      .byte 0
undocounter:    .byte 0

; usage of zeropage address space:
; ZP_PTR_1 - temporary pointer
; ZP_PTR_2 - temporary pointer
; ZP_PTR_3 - position of player
ZP_PTR_FIELD = $28
temp = $30  ; used for temp 8/16 bit storage $30/$31
ZP_PTR_UNDO = $32 ; used to point to the 'undo stack'

start:
    ; force uppercase
    lda #UPPERCASE
    jsr CHROUT

    jsr loadtiles       ; load tiles from normal memory to VRAM
    jsr layerconfig     ; configure layer 0/1 on screen

    jsr resetvars
    jsr cleartiles

    jsr displaytitlescreen
    jsr selectlevel
    jsr cleartiles      ; cls tiles

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
    bne @checkundo
    jsr handleright
    bra @done
@checkundo:
    cmp #$55 ; 'u'
    bne @checkreset
    jsr handle_undocommand
    bra @done
@checkreset:
    cmp #$52 ; 'r'
    bne @checkquit
    jsr askreset
    bcs @resetgame
    jsr cls
    jsr cleartiles
    jsr printfield2
    bra @done
@resetgame:
    jsr cls
    jsr cleartiles
    jsr resetvars
    jsr initfield
    jsr printfield2
    bra keyloop
@checkquit:
    cmp #$51 ; 'q'
    bne @done
    jsr askquit
    bcs @exit
    jsr cls
    jsr cleartiles
    jsr printfield2
    bra @done
@exit:
    jsr resetlayerconfig
    rts
@done:
    ; check if we have reached all goals
    lda no_goals
    cmp no_goalsreached
    bne @donenextkey
    jsr asknewlevel
    bcs @exit
    jmp start   ; reset game / let user decide on new level
@donenextkey:
    jmp keyloop

handle_undocommand:
    jsr pull_undostack
    ; x now contains previous move
    ;   as #%000MUDRL - Multiple move / Up / Down / Right / Left
    ; we will give x to the handle_undo_**** routine, so it can see the combined bit (4) and act on it
@checkup:
    txa
    and #%00001000
    beq @checkdown
    jsr handle_undo_up
    rts
@checkdown:
    txa
    and #%00000100
    beq @checkright
    jsr handle_undo_down
    rts
@checkright:
    txa
    and #%00000010
    beq @checkleft
    jsr handle_undo_right
    rts
@checkleft:
    txa
    and #%00000001
    beq @emptystack
    jsr handle_undo_left
    rts
@emptystack:
    ; do nothing
    rts

asknewlevel:
    ; ask if the user would like to play a new level, and return clear carry on 'y'
    lda #<winstatement
    sta ZP_PTR_1
    lda #>winstatement
    sta ZP_PTR_1+1
    jsr displaymessagescreen

@keyloop:
    jsr GETIN
@checkyes:
    cmp #$59 ; Y
    bne @checkno
    clc
    rts
@checkno:
    cmp #$4e ; N
    bne @keyloop
    sec
    rts

askquit:
    ; ask if the user would like to quit, and return carry on 'y'
    lda #<quitaskmessage
    sta ZP_PTR_1
    lda #>quitaskmessage
    sta ZP_PTR_1+1
    jsr displaymessagescreen

@keyloop:
    jsr GETIN
@checkyes:
    cmp #$59 ; Y
    bne @checkno
    sec
    rts
@checkno:
    cmp #$4e ; N
    bne @keyloop
    clc
    rts

askreset:
    ; ask if the user would like to reset, and return carry on 'y'
    lda #<resetmessage
    sta ZP_PTR_1
    lda #>resetmessage
    sta ZP_PTR_1+1
    jsr displaymessagescreen

@keyloop:
    jsr GETIN
@checkyes:
    cmp #$59 ; Y
    bne @checkno
    sec
    rts
@checkno:
    cmp #$4e ; N
    bne @keyloop
    clc
    rts

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

    ldx #%00000010 ; right direction
    jsr handlemove
    rts

handle_undo_right:
    ; 3 - player

    phx ; store x to stack
    ; point 1 to player

    lda ZP_PTR_3
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    sta ZP_PTR_1+1

    ; pointer 2 will point to the left of the player
    ; so the player will move back to the left
    sec
    lda ZP_PTR_3
    sbc #$1
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    sbc #$0
    sta ZP_PTR_2+1

    jsr moveplayeronfield
    jsr moveplayerposition

    ; check crate move, and if so, move it using pointer 2 -> 1
    plx
    txa
    and #%00010000 ; was a crate moved in this move?
    beq @done

    ; load pointer 2 to the right of the previous player's position
    clc
    lda ZP_PTR_1
    adc #$1
    sta ZP_PTR_2
    lda ZP_PTR_1+1
    adc #$0
    sta ZP_PTR_2+1
    
    jsr movecrateonfield
@done:
    jsr cls
    jsr printfield2
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

    ldx #%00000001 ; left direction
    jsr handlemove

@done:
    rts

handle_undo_left:
    ; 3 - player

    phx ; store x to stack

    ; point 1 to player
    lda ZP_PTR_3
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    sta ZP_PTR_1+1

    ; pointer 2 will point to the right of the player
    ; so the player will move back to the right
    clc
    lda ZP_PTR_3
    adc #$1
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    adc #$0
    sta ZP_PTR_2+1

    jsr moveplayeronfield
    jsr moveplayerposition

    ; check crate move, and if so, move it using pointer 2 -> 1
    plx
    txa
    and #%00010000 ; was a crate moved in this move?
    beq @done

    ; load pointer 2 to the left of the previous player's position
    sec
    lda ZP_PTR_1
    sbc #$1
    sta ZP_PTR_2
    lda ZP_PTR_1+1
    sbc #$0
    sta ZP_PTR_2+1
    
    jsr movecrateonfield
@done:
    jsr cls
    jsr printfield2
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

    ldx #%00001000 ; up direction
    jsr handlemove

    rts

handle_undo_up:
    ; 3 - player

    phx ; store x to stack

    ; point 1 to player
    lda ZP_PTR_3
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    sta ZP_PTR_1+1

    ; pointer 2 will point to the position down of the player
    ; so the player will move back down
    clc
    lda ZP_PTR_3
    adc fieldwidth
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    adc #$0
    sta ZP_PTR_2+1

    jsr moveplayeronfield
    jsr moveplayerposition

    ; check crate move, and if so, move it using pointer 2 -> 1
    plx
    txa
    and #%00010000 ; was a crate moved in this move?
    beq @done

    ; load pointer 2 to the top of the previous player's position
    sec
    lda ZP_PTR_1
    sbc fieldwidth
    sta ZP_PTR_2
    lda ZP_PTR_1+1
    sbc #$0
    sta ZP_PTR_2+1
    
    jsr movecrateonfield
@done:
    jsr cls
    jsr printfield2
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

    ldx #%00000100 ; down direction
    jsr handlemove
    
    rts

handle_undo_down:
    ; 3 - player

    phx ; store x to stack

    ; point 1 to player
    lda ZP_PTR_3
    sta ZP_PTR_1
    lda ZP_PTR_3+1
    sta ZP_PTR_1+1

    ; pointer 2 will point to the position up of the player
    ; so the player will move back up
    sec
    lda ZP_PTR_3
    sbc fieldwidth
    sta ZP_PTR_2
    lda ZP_PTR_3+1
    sbc #$0
    sta ZP_PTR_2+1

    jsr moveplayeronfield
    jsr moveplayerposition

    ; check crate move, and if so, move it using pointer 2 -> 1
    plx
    txa
    and #%00010000 ; was a crate moved in this move?
    beq @done

    ; load pointer 2 to the bottom of the previous player's position
    clc
    lda ZP_PTR_1
    adc fieldwidth
    sta ZP_PTR_2
    lda ZP_PTR_1+1
    adc #$0
    sta ZP_PTR_2+1
    
    jsr movecrateonfield
@done:
    jsr cls
    jsr printfield2
    rts

handlemove:
    ; pointers
    ; 3 - points to the player position
    ; 2 - points to the next block at the indicated direction
    ; 1 - points to the block after that block

    phx ; push x to stack with stored direction

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

    plx ; pull direction from the stack
    jsr push_undostack
    bra @movecomplete
@next:
    ldy #0
    lda (ZP_PTR_2),y
    cmp #'$' ; crate next to player?
    beq @combinedmovecheck
    cmp #'*' ; crate on goal next to player?
    beq @combinedmovecheck
    bra @ignore ; something else not able to push
@combinedmovecheck:
    lda (ZP_PTR_1),y
    cmp #' ' ; space after crate?
    beq @combinedmove
    cmp #'.' ; goal after crate?
    beq @combinedmove
    bra @ignore ; nothing to move
@combinedmove:
    jsr movecrateonfield
    jsr moveplayeronfield
    jsr moveplayerposition

    ; record combined move to undo stack
    pla
    ora #%00010000   ; set 'combined' bit 4
    tax
    jsr push_undostack

@movecomplete:
    jsr printfield2
    jsr cls
    rts

@ignore: ; nothing to move
    plx  ; don't forget to remove the stacked x move
    rts

push_undostack:
    ; record single move to undo stack
    ; x contains direction and single/multiple move
    ; x = 0%000MUDRL - Multiple / Up / Down / Right / Left
    ;
    ; the stack index 'pointer' undoindex points to a new entry each time
    txa
    ldy undoindex
    sta (ZP_PTR_UNDO),y

    cpy #MAXUNDO-1 ; at last physical item in memory? then loop around
    beq @loopindex
    inc undoindex
    bra @checkmaxcount
 @loopindex:
    stz undoindex
 @checkmaxcount:
    lda undocounter
    cmp #MAXUNDO
    beq @done ; maximum count reached / stack will loop around
    inc undocounter
 @done:
    rts

pull_undostack:
    ; remove single move from undo stack
    ; afterwards, x contains direction and single/multiple move
    ; x = 0%000MUDRL - Multiple / Up / Down / Right / Left

    lda undocounter ; check if we have any moves pushed to the stack
    bne @stackedmoves
    ldx #$0 ; empty move, nothing in the stack
    rts

@stackedmoves:
    dec undocounter ; reduce the number pushed to the stack with 1
    ldy undoindex
    cpy #$0 ; index at first position?
    bne @normalindex
    ldy #MAXUNDO-1 ; move it to the 'previous' index position in a circular manner
    bra @next
@normalindex:
    dey ; move it to the 'previous' index position
@next:
    sty undoindex
    ; y now points to the previous move, as an index to the stack memory
    lda (ZP_PTR_UNDO),y
    tax
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
    lda #'@'; player symbol
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
    ; console routines only
    ; print from address ZP_PTR_1
    ; don't end with newline character
    phy
    ldy #0
@loop:
    lda (ZP_PTR_1),y ; load character from address
    beq @done        ; end at 0 character
    jsr CHROUT 
    iny
    bra @loop
@done:
    ply
    rts

printline:
    ; console routines only
    ; print from address ZP_PTR_1
    ; end with newline character
    jsr print
    lda #NEWLINE
    jsr CHROUT
    rts

printwinstatement:
    ; console routines only
    lda #<winstatement
    sta ZP_PTR_1
    lda #>winstatement
    sta ZP_PTR_1+1
    jsr printline
    rts

printdecimal:
    ; prints decimal from A register
    ; VERA control needs to be set up previously
    phx
    phy
    stx temp    ; keep color to print in
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
;    jsr CHROUT ; print Y
    sta VERA_DATA0
    lda temp
    sta VERA_DATA0
@tens:
    pla
    cmp #$30 ; is it a '0' petscii?
    beq @ones
;    jsr CHROUT ; print X
    sta VERA_DATA0
    lda temp
    sta VERA_DATA0
@ones:
    pla
;    jsr CHROUT ; print A
    sta VERA_DATA0
    lda temp
    sta VERA_DATA0

    ply
    plx
    rts

selectlevel:
    lda #1 ; start out with first level
    sta currentlevel

@mainloop:
    ; text prep to VERA
    stz VERA_CTRL
    ldx #$9 ; color brown
    lda #$10
    sta VERA_HIGH
    lda #<selectmessage
    sta ZP_PTR_1
    lda #>selectmessage
    sta ZP_PTR_1+1
    lda #45
    sta VERA_MID
    lda #10*2
    sta VERA_LOW
    jsr printverastring

    ; print range
    lda no_levels
    jsr printdecimal
    lda #<selectendmessage
    sta ZP_PTR_1
    lda #>selectendmessage
    sta ZP_PTR_1+1
    jsr printverastring
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

    ; reset undo stack
    lda #<undostack
    sta ZP_PTR_UNDO
    lda #>undostack
    sta ZP_PTR_UNDO+1

    stz undoindex
    stz undocounter
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

    ldy #2  ; index from payload pointer to width variable (low byte)
    lda (ZP_PTR_1),y 
    sta fieldwidth
    ldy #4  ; index from payload pointer to height variable (low byte)
    lda (ZP_PTR_1),y
    sta fieldheight
    ldy #6  ; index from payload pointer to goals in this level (low byte)
    lda (ZP_PTR_1),y
    sta no_goals
    ldy #8  ; index from payload pointer to goals taken in this level (low byte)
    lda (ZP_PTR_1),y
    sta no_goalsreached
    ldy #10  ; index from payload pointer to player offset in this level

    lda (ZP_PTR_1),y
    clc
    adc #<RAMBANK
    sta ZP_PTR_3
    iny
    lda (ZP_PTR_1),y
    adc #>RAMBANK
    sta ZP_PTR_3+1
    ; ZP_PTR_3 now contains the actual address in memory of the player, not only the offset from the data

    ; now copy the field data to the RAM bank
    lda fieldheight
    tax ; create counter
    ; clear temp counter
    stz temp
    stz temp+1

@multiply:
    ; add fieldwidth variable to temp at each iteration - temp = temp + (width * height)
    lda temp
    clc
    adc fieldwidth
    sta temp
    lda temp+1 ; don't forget the high byte
    adc #0
    sta temp+1
    dex
    bne @multiply

    ; copy (temp) amount of bytes from current field pointer to Ram bank 0

    ; currently ZP_PTR_1 is pointing to the selected field HEADER
    ; retrieve the field pointer from it, and let ZP_PTR_FIELD to that
    ldy #0
    lda (ZP_PTR_1),y
    sta ZP_PTR_FIELD
    iny
    lda (ZP_PTR_1),y
    sta ZP_PTR_FIELD+1
    ; now let this pointer start counting from LOADSTART, just as the offset in the input file references
    lda ZP_PTR_FIELD
    clc
    adc #<LOADSTART
    sta ZP_PTR_FIELD
    lda ZP_PTR_FIELD+1
    adc #>LOADSTART
    sta ZP_PTR_FIELD+1

    ; set up destination pointer
    lda #<RAMBANK
    sta ZP_PTR_2
    lda #>RAMBANK
    sta ZP_PTR_2+1

    ldy #0
@copybyte:
    ; copy one byte of data
    lda (ZP_PTR_FIELD),y
    sta (ZP_PTR_2),y

    ; temp = temp -1
    lda temp
    sec
    sbc #1
    sta temp
    lda temp+1
    sbc #0
    sta temp+1

    ; if temp==0 done
    lda temp+1
    bne @copynextbyte
    lda temp
    bne @copynextbyte
    bra @done
@copynextbyte:
    lda ZP_PTR_FIELD
    clc
    adc #1
    sta ZP_PTR_FIELD
    lda ZP_PTR_FIELD+1
    adc #0
    sta ZP_PTR_FIELD+1
    lda ZP_PTR_2
    clc
    adc #1
    sta ZP_PTR_2
    lda ZP_PTR_2+1
    adc #0
    sta ZP_PTR_2+1
    bra @copybyte
@done:
    
    ; prep the field pointer
    lda #<RAMBANK
    sta ZP_PTR_FIELD
    lda #>RAMBANK
    sta ZP_PTR_FIELD+1
    rts

printfield:
    ; console routines only
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


displaymessagescreen:
    ; temp store pointer to the requested text
    lda ZP_PTR_1
    pha
    lda ZP_PTR_1+1
    pha

    lda #<messagescreen
    sta ZP_PTR_1
    lda #>messagescreen
    sta ZP_PTR_1+1
    jsr displaytileset
    ; now display the string at ZP_PTR_1 in the middle and return
    pla
    sta ZP_PTR_1+1
    pla
    sta ZP_PTR_1
    stz VERA_CTRL
    ;lda #%00100000
    lda #$10
    sta VERA_HIGH
    lda #28
    sta VERA_MID
    lda #28*2
    sta VERA_LOW
    ldx #$9 ; color brown
    jsr printverastring
    rts

printverastring:
    ; ZP_PTR_1 is pointing to the string
    ; x contains color of the text
    ldy #0
@loop:
    lda (ZP_PTR_1),y
    beq @end
    cmp #$40    
    bcc @output
@AZ:
    sec
    sbc #$40
@output:
    sta VERA_DATA0
    stx VERA_DATA0
    iny
    bra @loop
@end:
    rts

displaytileset:
; Fill the Layer 0 with the tileset pointed to by ZP_PTR_1
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    lda #$40
    sta VERA_MID                        ; Set Middle Byte to $40
    lda #$0
    sta VERA_LOW                        ; Set Low Byte to $00

    ldy #32
@outerloop:
    ldx #64
@innerloop:
    phy
    ldy #0
    lda (ZP_PTR_1),y                    ; load byte from tileset
    sta VERA_DATA0
    stz VERA_DATA0                      ; zero it's attribute
    ply

    ; increase pointer to next byte in the set
    lda ZP_PTR_1
    clc
    adc #$2
    sta ZP_PTR_1
    lda ZP_PTR_1+1
    adc #$0
    sta ZP_PTR_1+1

    dex
    bne @innerloop
    dey
    bne @outerloop

    rts

displaytitlescreen:
    lda #<titlescreen
    sta ZP_PTR_1
    lda #>titlescreen
    sta ZP_PTR_1+1
    jsr displaytileset

    stz VERA_CTRL
    ldx #$9 ; color brown
    lda #$10
    sta VERA_HIGH

    lda #<help0
    sta ZP_PTR_1
    lda #>help0
    sta ZP_PTR_1+1
    lda #23
    sta VERA_MID
    lda #50*2
    sta VERA_LOW
    jsr printverastring

    lda #<help1
    sta ZP_PTR_1
    lda #>help1
    sta ZP_PTR_1+1
    lda #30
    sta VERA_MID
    lda #50*2
    sta VERA_LOW
    jsr printverastring

    lda #<help2
    sta ZP_PTR_1
    lda #>help2
    sta ZP_PTR_1+1
    lda #32
    sta VERA_MID
    lda #50*2
    sta VERA_LOW
    jsr printverastring

    lda #<help3
    sta ZP_PTR_1
    lda #>help3
    sta ZP_PTR_1+1
    lda #33
    sta VERA_MID
    lda #50*2
    sta VERA_LOW
    jsr printverastring

    lda #<help4
    sta ZP_PTR_1
    lda #>help4
    sta ZP_PTR_1+1
    lda #34
    sta VERA_MID
    lda #50*2
    sta VERA_LOW
    jsr printverastring

    lda #<help5
    sta ZP_PTR_1
    lda #>help5
    sta ZP_PTR_1+1
    lda #35
    sta VERA_MID
    lda #50*2
    sta VERA_LOW
    jsr printverastring
    rts

cleartiles:
; Fill the Layer 0 with all zeros (black)
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    lda #$40
    sta VERA_MID                        ; Set Middle Byte to $40
    lda #$0
    sta VERA_LOW                        ; Set Low Byte to $00

    ldy #32
    lda #0
:   ldx #64
:   sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    sta VERA_DATA0                      ; Write Attribute
    dex
    bne :-
    dey
    bne :--

    rts

resetlayerconfig:
; Change Layer 1 to 8 Color Mode
    lda $9F34
    and #%11110111                        ; Set bit 3 to 0, rest unchanged
    sta $9F34

    jsr cls
    rts

layerconfig:
; Configure Layer 0
    lda #%01010011                      ; 64 x 64 tiles, 8 bits per pixel
    sta $9F2D
    lda #$20                            ; $20 points to $4000 in VRAM
    sta $9F2E                           ; Store to Map Base Pointer

    lda #$93                            ; $48 points to $12000, Width and Height 16 pixel
    sta $9F2F                           ; Store to Tile Base Pointer

    jsr cleartiles

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
;    lda #$40
;    sta $9F2A
;    sta $9F2B

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
    lsr ; /2
    asl ; *2 - so uneven widths result in an even address and we don't end up in parameter space of the TILEMAP 
    sta vera_byte_low

; shift down number of rows (SCREENHEIGHT - fieldheight) /2 positions
    lda #SCREENHEIGHT
    sec
    sbc fieldheight
    lsr ; /2
    tax ; transfer number of rows down to counter
@loop:
    cpx #$0 ; any rows down (left)?
    beq @done ; exit loop when x == 0
    ; go 64 tiles further down - 64 * (1 address + 1 parameter of tile) = 128 / $80
    lda vera_byte_low
    clc
    adc #$80    ; add row <<<ADDRESS>>> height for exactly one row down
    sta vera_byte_low
    bcc @decrement  ; no need to change the high byte
    lda vera_byte_mid
    adc #$0     ; add carry (so +1)
    sta vera_byte_mid
@decrement: ; next row
    dex
    bra @loop
@done:

; prepare the pointers to the back-end field data, so we know what to display
    lda ZP_PTR_FIELD
    sta ZP_PTR_1
    lda ZP_PTR_FIELD+1
    sta ZP_PTR_1+1

; start displaying the selected field
; (vera_byte_mid / vera_byte_low) is the address for the top-left position on-screen in the tile map
    ldx #0 ; row counter
@nextrow:
    ldy #0 ; column counter
    ; prepare vera pointers for this row
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    lda vera_byte_mid
    sta VERA_MID                        
    lda vera_byte_low
    sta VERA_LOW                       

@row:
    ; sweep the field, row by row, indexed by column y
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
    ; advance pointer to next row in the field
    lda ZP_PTR_1
    clc
    adc fieldwidth
    sta ZP_PTR_1
    bcc @checklastrow ; no carry, don't increment high byte on pointer
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    adc #0
    sta ZP_PTR_1+1
@checklastrow:
    ; last row?
    ; increment vera pointer to next row
    lda vera_byte_low
    clc
    adc #$80    ; add address delta to next row - 64 tiles * 2 = 128 / $80
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

titlescreen:
.incbin "tiles/titlescreen.bin"
messagescreen:
.incbin "tiles/messagescreen.bin"
tiledata:
black:
.incbin "tiles/black.bin"
Brick:
.incbin "tiles/brick.bin"
player:
.incbin "tiles/player.bin"
crate:
.incbin "tiles/crate.bin"
goal:
.incbin "tiles/goal.bin"
crateongoal:
.incbin "tiles/crateongoal.bin"
LOADSTART:
.incbin "levels.bin"

