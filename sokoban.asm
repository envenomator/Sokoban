.include "x16.inc"

temp = $30  ; used for temp 8/16 bit storage $30/$31
field = $100c; load for fields
loadstart = $1000;

.org $080D
.segment "STARTUP"
.segment "INIT"
.segment "ONCE"
.segment "CODE"

   jmp start

message: .byte "press a key",0
errormessage: .byte "error loading file",0
quitmessage: .byte "press q to quit",0
filename: .byte "levels.bin"
filename_end:

winstatement: .byte "goal reached!",0

; variables that the program uses during execution
no_goals:       .byte 2
no_goalsreached:.byte 0
fieldwidth:     .byte 0
fieldheight:    .byte 0

NEWLINE = $0D
UPPERCASE = $8E
CLEARSCREEN = 147

; usage of zeropage pointers:
; ZP_PTR_1 - temporary pointer
; ZP_PTR_2 - temporary pointer
; ZP_PTR_3 - position of player
; ZP_PTR_4 - use as height/width

loadfield:
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
    bcs @error
    rts

@error:
    sec
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
    jsr printfield

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

initfield:
    ;skeleton code for now
    
    ; reset goals
    lda #0
    sta no_goalsreached

    ; advance player to the field
    lda #$16
    sta ZP_PTR_3
    lda #$10
    sta ZP_PTR_3+1

    ; load fieldwidth from load area
    lda $1004
    sta fieldwidth

    ; load fieldheight from load area
    lda $1006
    sta fieldheight

    ; load goals from load area
    lda $1008
    sta no_goals
    rts

printfield:
    ; no clearscreen, just print the field to screen on current position
    ; depends only on
    ; - field label for start of field

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
