.include "x16.inc"

; constants
NEWLINE = $0D
UPPERCASE = $8E
CLEARSCREEN = 147
LEVELHEADER = 10
MAXUNDO = 10

; screen 16x16bit tile width/height
SCREENWIDTH = 40
SCREENHEIGHT = 30
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
quitmessage:      .byte "press q to quit",0
winstatement:     .byte "level complete!",0
help0:            .byte "(c)2021 venom",0
help1:            .byte "keyboard shortcuts:",0
help2:            .byte "cursor - moves player",0
help3:            .byte "     q - quit",0
help4:            .byte "     u - undo",0

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

    jsr resetvars
    jsr loadtiles       ; load tiles from normal memory to VRAM
    jsr layerconfig     ; configure layer 0/1 on screen
    jsr cleartiles

    jsr displaytitlescreen

    jsr selectlevel
    jsr cleartiles      ; cls tiles

    jsr initfield       ; load correct startup values for selected field
    jsr printfield2
;    jsr printfield

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
    bne @checkquit
    jsr handle_undocommand
    bra @done
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

handle_undocommand:
    jsr pull_undostack
    ; x now contains previous move
    ;   as #%000MUDRL - Multiple move / Up / Down / Right / Left
    ;
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


handle_undomove_old:
    ; input from pointers
    ; 3 - player
    ; 2 - backward destination of the player
    ; 1 - block 'behind' the player, that will be put in the player's position after the undo


    ; dummy undo up only
    jsr moveplayeronfield
    jsr moveplayerposition
    jsr cls
    jsr printfield2
    rts

    ; move the player 'back' first. Might return to a goal
    ldy #$0
    lda (ZP_PTR_1),y
    cmp #'.'
    beq @togoal
    ; player will go to normal space
    lda #'@'
    sta (ZP_PTR_1),y
    bra @next
@togoal:
    ; player will go to goal position
    lda #'+'
    sta (ZP_PTR_1),y
@next:
    ; move the crate back to the player's position. Player might have been standing on a goal
    lda (ZP_PTR_3),y
    cmp #'+'
    beq @togoal2
    ; crate will return as normal
    lda #'$'
    sta (ZP_PTR_1),y
    bra @next2
@togoal2:
    ; crate will return to goal position
    lda #'*'
    sta (ZP_PTR_1),y
@next2:
    ; return empty space, check what was there in the first place
    lda (ZP_PTR_2),y
    cmp #'*'
    beq @cratewasongoal
    ; leave behind 'normal' goal
    lda #'.'
    sta (ZP_PTR_2),y
    bra @next3
@cratewasongoal:
    ; leave behind empty space
    lda #' '
    sta (ZP_PTR_2),y
@next3:

    ; now return player pointer to new position
    lda ZP_PTR_1
    sta ZP_PTR_3
    lda ZP_PTR_1+1
    sta ZP_PTR_1+1

    ; output the playing field
    jsr printfield2
    jsr cls

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
    jsr displayhelp

    clc         ; PLOT to x,y
    ldy #0      ; column 
    ldx #45     ; row 
    jsr PLOT

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
    ldy #0  ; index to the offset from LOADSTART 
    ; add LOADSTART address to the offset in this field
    clc
    lda (ZP_PTR_1),y
    adc #<LOADSTART
    sta ZP_PTR_FIELD
    iny
    lda (ZP_PTR_1),y
    adc #>LOADSTART
    sta ZP_PTR_FIELD+1
    ; ZP_PTR_FIELD now contains the actual address in memory, not only the offset from the data

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

    clc
    lda (ZP_PTR_1),y
    adc #<LOADSTART
    sta ZP_PTR_3
    iny
    lda (ZP_PTR_1),y
    adc #>LOADSTART
    sta ZP_PTR_3+1
    ; ZP_PTR_3 now contains the actual address in memory of the player, not only the offset from the data
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

displaytitlescreen:

; Fill the Layer 0 with the titlescreen tileset
    stz VERA_CTRL                       ; Use Data Register 0
    lda #$10
    sta VERA_HIGH                       ; Set Increment to 1, High Byte to 0
    lda #$40
    sta VERA_MID                        ; Set Middle Byte to $40
    lda #$0
    sta VERA_LOW                        ; Set Low Byte to $00

    ; address to the tileset
    lda #<titlescreen
    sta ZP_PTR_1
    lda #>titlescreen
    sta ZP_PTR_1+1

;    ldy #0
;@loop:
;    lda (ZP_PTR_1),y
;    clc
;    adc #$1
;    sta VERA_DATA0
;    stz VERA_DATA0
;    iny
;    iny
;    cpy #128
;    bne @loop

    ldy #64
@outerloop:
    ldx #64
@innerloop:
    phy
    ldy #0
    lda (ZP_PTR_1),y                    ; load byte from tileset
    bne @else    
@brick:
    lda #$1     ; brick tile
    bra @next
@else:
    lda #$0     ; black tile
@next:
    sta VERA_DATA0
    stz VERA_DATA0
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

displayhelp:
    clc ; go to x,y
    ldy #45
    ldx #22

    jsr PLOT
    lda #<help0
    sta ZP_PTR_1
    lda #>help0
    sta ZP_PTR_1+1
    jsr print

    ldx #29
    jsr PLOT
    lda #<help1
    sta ZP_PTR_1
    lda #>help1
    sta ZP_PTR_1+1
    jsr print

    ldx #31
    jsr PLOT
    lda #<help2
    sta ZP_PTR_1
    lda #>help2
    sta ZP_PTR_1+1
    jsr print

    ldx #32
    jsr PLOT
    lda #<help3
    sta ZP_PTR_1
    lda #>help3
    sta ZP_PTR_1+1
    jsr print

    ldx #33
    jsr PLOT
    lda #<help4
    sta ZP_PTR_1
    lda #>help4
    sta ZP_PTR_1+1
    jsr print
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

    lda #0
    sta VERA_DATA0
    sta VERA_DATA0

    ldy #64
    lda #0
:   ldx #64
:   sta VERA_DATA0                      ; Write to VRAM with +1 Autoincrement
    sta VERA_DATA0                      ; Write Attribute
    dex
    bne :-
    dey
    bne :--

    rts

layerconfig:
; Configure Layer 0
    lda #%01010011                      ; 64 x 64 tiles, 8 bits per pixel
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

    ldy #64
    lda #0
:   ldx #64
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

titlescreen:
.incbin "tiles/titlescreen.bin"

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
