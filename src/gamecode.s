; constants
NEWLINE             = $0D
LEVELHEADER         = 12
MAXUNDO             = 10
WIDTH_IN_TILES      = 20        ; screen width/height in 16x16 tiles
HEIGHT_IN_TILES     = 15
SCREENWIDTH         = 40        ; actual screenwidth
SCREENHEIGHT        = 30        ; actual screenheight
VIDSTART            = $F800     ; top-left memory address in Cerberus 2080
FIRSTCHAR           = 128       ; first custom character to be part of a tileset
KEY_UP              = $0B
KEY_DOWN            = $0A
KEY_LEFT            = $08
KEY_RIGHT           = $15
KEY_ENTER           = $0D
TILE_PLAYER         = 0         
TILE_CRATE          = 1
TILE_GOAL           = 2
TILE_CRATE_ON_GOAL  = 3
TILE_WALL           = 4
TILE_IGNORE         = 5

    .zeropage
xpos:           .res 1
ypos:           .res 1
conptr:         .res 2
strptr:         .res 2  ; used for con_print routine. Load zero-terminated string to strptr/strptr+1 and call routine
ZP_PTR_1:       .res 2
ZP_PTR_2:       .res 2
ZP_PTR_3:       .res 2  ; position of player
ZP_PTR_FIELD:   .res 2
ZP_PTR_UNDO:    .res 2  ; used to point to the 'undo stack'
temp:           .res 2  ; used for temp 8/16 bit storage, or just local temp variables
temp2:          .res 2
video:          .res 2
tempwidth:      .res 1
tempheight:     .res 1
tileindex:      .res 1  ; used during calculation of presention tile quarter 0-3
fieldindex:     .res 1  ; used for column-indexing the fieldpointer

.setcpu "65C02"
    .code
    jmp init

    .data
; strings 
selectmessage:    .byte "ENTER to select level: ",0
clear:            .byte "                           ",0
resetmessage:     .byte "really RESET level? y/n",0
quitaskmessage:   .byte "really QUIT? y/n",0
congratmessage:   .byte "Level complete - press ENTER",0
quitmessage:      .byte "press q to quit",0
title:            .byte "Sokoban for cerberus 2080",0
copyright:        .byte "(c)2022 Venom",0
help1:            .byte "game controls:",0
help2:            .byte "cursor:move player",0
help3:            .byte "     q:quit",0
help4:            .byte "     u:undo move",0
help5:            .byte "     r:reset level",0
; variables that the program uses during execution
currentlevel:     .byte 0 ; will need to be filled somewhere in the future in the GUI, or asked from the user
no_levels:        .byte 0 ; will be read by initfield
no_goals:         .byte 0 ; will be read by initfield, depending on the currentlevel
no_goalsreached:  .byte 0 ; static now, reset for each game
fieldwidth:       .byte 0 ; will be read by initfield, depending on the currentlevel
fieldheight:      .byte 0 ; will be read by initfield, depending on the currentlevel
undostack:        .byte 0,0,0,0,0,0,0,0,0,0
undoindex:        .byte 0
undocounter:      .byte 0

    .code
init:
    ; Init stack
    ldx #$ff  ; start stack at $1ff
    txs       ; init stack pointer (X => SP)
    lda #1
    sta currentlevel    ; game starts at level 1
start:
    jsr con_init
    jsr con_cls
    jsr resetvars
    jsr loadtiledata
    jsr displaytitlescreen
    jsr selectlevel
    jsr con_cls
    jsr printgraphics

keyloop:
    jsr con_getinput
    sta temp
    ldy #0
@keymatch:
    lda ingame_keyinput,y
    cmp temp
    beq @keyfound
    cmp #0
    beq @keyfound
    iny
    bra @keymatch 
@keyfound:
    tya
    asl ; *2 for word index
    tax
    jmp (ingame_keyjump,x)
    ; will never get here

handle_ingamekeyup:
    jsr handleup
    jmp checkdone
handle_ingamekeydown:
    jsr handledown
    jmp checkdone
handle_ingamekeyleft:
    jsr handleleft
    jmp checkdone
handle_ingamekeyright:
    jsr handleright
    jmp checkdone
handle_ingamekeyundo:
    jsr handle_undocommand
    jmp checkdone
handle_ingamekeyreset:
    jsr askreset
    bcs @resetgame
    jsr con_cls
    jsr printgraphics
    jmp checkdone
@resetgame:
    jsr resetvars
    jsr initfield
    jsr con_cls
    jsr printgraphics
    jmp keyloop
handle_ingamekeyquit:
    jsr askquit
    bcs @exit
    jsr con_cls
    jsr printgraphics
    jmp checkdone
@exit:
    jmp start
checkdone:
    ; check if we have reached all goals
    lda no_goals
    cmp no_goalsreached
    bne @donenextkey
    jsr congratulations
    ; check if this was the last level
    lda no_levels
    cmp currentlevel
    bne @nextlevel
    lda #1              ; max level reached, reset to 1
    sta currentlevel
    bra @prepnextgame
@nextlevel:
    inc currentlevel ; next level
@prepnextgame:
    jmp start
@donenextkey:
    jmp keyloop

exit:
    ; does not seem to work with standard bios, with defaults to starting at vector 0 for Z80
    ; stub routine for now, not called in code
    lda #$7F    ; BIOS request to reset
    sta $202    ; INBOX_FLAG
@loop:
    jmp @loop

printcenteredmesssage:
    ; prints a centered yes/no style of message, single line
    ; given as strptr
    ; first calculate message length
    ; length can be maximum of #SCREENWIDTH-2, will not be checked, code is too static for this
    phx
    phy

    ldy #0
@loop:
    lda (strptr),y
    iny
    cmp #0
    bne @loop   ; at the end of the loop, y contains number of characters in string
    sty temp
    lda #SCREENWIDTH
    sec
    sbc temp
    lsr         ; divide by two
    sta temp2
    dec temp2   ; start one early for space
    ; temp == length of string
    ; temp2 == start of string on screen
    ; prep line1
    ldx temp2
    ldy #13
    jsr con_gotoxy
    inc temp
    inc temp
    ; line 1: all spaces 
    ldy #0
    lda #' '
@line1:
    jsr con_printchar
    iny
    cpy temp
    bne @line1
    ; prep line2
    ldx temp2
    ldy #14
    jsr con_gotoxy
    lda #' '
    jsr con_printchar
    jsr con_print   ; print out actual string
    lda #' '
    jsr con_printchar   ; end with space
    ; prep line3
    ldx temp2
    ldy #15
    jsr con_gotoxy
    ldy #0
    lda #' '
@line3:
    jsr con_printchar
    iny
    cpy temp
    bne @line3
    ply
    plx
    rts

yesnomessage:
    ; wait for y/n
    jsr printcenteredmesssage
    clc
@keyloop:
    jsr con_getinput
@checkyes:
    cmp #'y'
    bne @checkno
    sec
    bra @done
    rts
@checkno:
    cmp #'n'
    bne @keyloop
    clc
@done:
    rts

waitforentermessage:
    ; wait for ENTER
    jsr printcenteredmesssage
    clc
@keyloop:
    jsr con_getinput
@checkenter:
    cmp #KEY_ENTER
    bne @checkenter
@done:
    rts

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

congratulations:
    lda #<congratmessage
    sta strptr
    lda #>congratmessage
    sta strptr+1
    jsr waitforentermessage
    rts

askquit:
    ; ask if the user would like to quit, and return carry on 'y'
    lda #<quitaskmessage
    sta strptr
    lda #>quitaskmessage
    sta strptr+1
    jsr yesnomessage
    rts

askreset:
    ; ask if the user would like to reset, and return carry on 'y'
    lda #<resetmessage
    sta strptr
    lda #>resetmessage
    sta strptr+1
    jsr yesnomessage
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
    jsr printgraphics
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
    jsr printgraphics
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
    jsr printgraphics
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
    jsr printgraphics
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
    jsr printgraphics
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
    
printdecimal:
    ; prints decimal from A register
    phx
    phy
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
    jsr con_printchar
@tens:
    pla
    cmp #$30 ; is it a '0' petscii?
    beq @ones
    jsr con_printchar
@ones:
    pla
    jsr con_printchar

    ply
    plx
    rts

selectlevel:
    ; initial level needs to have been set.

    jsr initfield   ; select field for chosen level
    jsr printpreview

    ldx #11
    ldy #13
    jsr con_gotoxy
    lda #<clear
    sta strptr
    lda #>clear
    sta strptr+1
    jsr con_print

    ldx #11
    ldy #13
    jsr con_gotoxy
    lda #<selectmessage
    sta strptr
    lda #>selectmessage
    sta strptr+1
    jsr con_print

    ; print level number
    lda currentlevel
    jsr printdecimal

selectlevel_charloop:
    jsr con_getinput
    sta temp

    ldy #0
@keymatch:
    lda select_keyinput,y
    cmp temp
    beq @keyfound
    cmp #0
    beq @keyfound
    iny
    bra @keymatch 
@keyfound:
    tya
    asl ; *2 for word index
    tax
    jmp (select_keyjump,x)
    ; will never get here

handle_selectup:
    lda currentlevel
    cmp no_levels
    beq selectlevel_charloop   ; maximum value reached
    inc currentlevel
    bra selectlevel
handle_selectdown:
    lda currentlevel
    cmp #1
    beq selectlevel_charloop   ; lowest value == 1
    dec currentlevel
    bra selectlevel
handle_selectenter:
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

displaytitlescreen:
    ldx #7
    ldy #5
    jsr con_gotoxy
    lda #<title
    sta strptr
    lda #>title
    sta strptr+1
    jsr con_print

    ldx #19
    ldy #7
    jsr con_gotoxy
    lda #<copyright
    sta strptr
    lda #>copyright
    sta strptr+1
    jsr con_print

    ldx #3
    ldy #19
    jsr con_gotoxy
    lda #<help1
    sta strptr
    lda #>help1
    sta strptr+1
    jsr con_print

    ldx #0
    ldy #21
    jsr con_gotoxy
    lda #<help2
    sta strptr
    lda #>help2
    sta strptr+1
    jsr con_print

    ldx #0
    ldy #22
    jsr con_gotoxy
    lda #<help3
    sta strptr
    lda #>help3
    sta strptr+1
    jsr con_print

    ldx #0
    ldy #23
    jsr con_gotoxy
    lda #<help4
    sta strptr
    lda #>help4
    sta strptr+1
    jsr con_print

    ldx #0
    ldy #24
    jsr con_gotoxy
    lda #<help5
    sta strptr
    lda #>help5
    sta strptr+1
    jsr con_print

    rts

loadtiledata:
    ; loads tile data into character memory, starting from FIRSTCHAR
    lda #00
    sta temp
    lda #$f4        ; $F400 = F000 + (128 * 8) - start of FIRSTCHAR definition
    sta temp+1     ; temp is the destination into video character memory

    lda #<tiledata
    sta temp2
    lda #>tiledata
    sta temp2+1    ; temp2 is the source of the data
    
    ldx #0
    ldy #0
@loop:
    lda (temp2),y
    sta (temp),y
    inx
    ; +1 to both pointers
    clc
    lda temp
    adc #1
    sta temp
    lda temp+1
    adc #0
    sta temp+1

    clc
    lda temp2
    adc #1
    sta temp2
    lda temp2+1
    adc #0
    sta temp2+1

    cpx #(6 * 16 * 2)   ; 6 tiles times 16 x 16 bit, or 6 * 16 * 2 byte
    bne @loop
    rts

printgraphics:
; Calculate start address
; first calculate TX and TY (Tile (X,Y) position)
; resulting address = $F800 + (TY*80) + (TX *2)
; Center field within WIDTH_IN_TILES first
; shift to the right (WIDTH_IN_TILES - fieldwidth) /2 positions
    lda #WIDTH_IN_TILES
    sec
    sbc fieldwidth
    lsr ; /2
    asl ; TX * 2, round down by shifting left first
    ; A now contains Tile X position (TX)
    sta temp
; Center field vertically within HEIGHT_IN_TILES next
; Shift down (HEIGHT_IN_TILES - fieldheight) / 2 positions   
    lda #HEIGHT_IN_TILES
    sec
    sbc fieldheight
    lsr ; /2
    sta temp2
    ; A now contains Tile Y position (TY)
; Now calculate video start position
; FAC1 =
    lda #SCREENWIDTH*2
    sta video      ; FAC1 == video(low), FAC2 = temp2. FAC1 gets clobbered to final low byte of result
    ; multiply ypos * SCREENWIDTH, store in conptr
@mul8:
    lda #$00
    ldx #$08
    clc
@m0:
    bcc @m1
    clc
    adc temp2     ; FAC2
@m1:
    ror
    ror video   ; FAC1
    dex
    bpl @m0
    sta video+1
    ; result now in video / video+1
    ; Add both video start address (F800) and xpos to conptr.
    clc
    lda video
    adc temp    ; add TX*2
    sta video
    lda video+1
    adc #$F8
    sta video+1

; prepare the pointers to the back-end field data, so we know what to display
    lda ZP_PTR_FIELD
    sta ZP_PTR_1
    lda ZP_PTR_FIELD+1
    sta ZP_PTR_1+1

    stz fieldindex
; start displaying the selected field
; temp2 will a loop counter for the actual display rows
    lda #0
    sta temp2

; we need the *2 of both field variables, to print the actual graphics on screen, which is twice as large in both dimensions
    lda fieldwidth
    asl
    sta tempwidth
    lda fieldheight
    asl
    sta tempheight

    ldx #0 ; 0 == top row of 16x16 tile, 10 == bottom row of 16x16 tile
@nextrow:
    ldy #0 ; column counter
@col:
    ; sweep the field, row by row, indexed by column y
    ; inputs are: y (column and also (y >> 1) == high/low byte in tile)
    ;             x top/bottom row in tile  
    ; returns quarter tile as video code index in A
    jsr get_tilequarter
    sta (video),y
    iny
    cpy tempwidth
    bne @col
@checkrow:
    inc temp2       ; increment display row counter
    lda temp2
    cmp tempheight
    beq @done
    inx
    ; next row, add 40 to video
    lda video
    clc
    adc #SCREENWIDTH
    sta video
    bcc @nextrow
    lda video+1
    adc #0
    sta video+1
    bra @nextrow
@done:
    rts

get_tilequarter:
    ; inputs:
    ; x,y,Z_PTR_1
    phy
    ; Inputs need mapping to temp as follows
    ; X lowbit(Y) - temp index
    ; 0        0 - #0
    ; 0        1 - #1
    ; 1        0 - #2
    ; 1        1 - #3
    tya
    and #%00000001 ; leave only bit 0
    sta tileindex  ; temp will be index 0-3, this is the low bit
    txa
    and #%00000001 ; leave only bit 0
    beq @indexdone
    lda tileindex
    clc
    adc #%00000010 ; add high bit
    sta tileindex  ; now contains index into Tile ID from 0-3

@indexdone:
    ldy fieldindex      ; load from current index into the fieldpointer
    lda (ZP_PTR_1),y    ; obtain content in field position
    sta temp

    ldy #0
@loop:
    lda translatefrom,y
    cmp temp    ; field content matching lookup table? 
    beq @found
    cmp #0
    beq @found  ; terminate at end-of-table
    iny
    bra @loop
@found:
    lda translateto,y

    ; A contains tile ID now (Tile 0 - Tile 5)
    asl
    asl             ; Tile ID * 4
    clc
    adc tileindex   
    adc #FIRSTCHAR  ; A is answer to the caller
    ; now decide if we need to advance the fieldpointer
    pha ; save result to the caller
    ; is this the last time we used this tile on this particular row? (we display twice)
    ; need to advance the tile after the last bit of y becomes 1
    lda tileindex
    and #%00000001
    beq @done   ; screen-column in Y is even, so we're in the middle of the current tile. Nothing to advance.
    ; advance pointer to next item
    ; depends on ROW0/ROW1, which is represented by bit 0 in x register currently
    ; first check if we are at the end of the field
    inc fieldindex
    lda fieldindex
    cmp fieldwidth
    bne @done   ; not at the end yet

    ; Here we are at the end of the row
    ; first reset fieldindex
    stz fieldindex
    ; then check bit 0 in x - ROW1 / ROW0
    txa
    and #%00000001 ; leave only bit 0
    beq @done
@ROW1advance:
    ; add fieldwidth to the fieldpointer
    lda ZP_PTR_1
    clc
    adc fieldwidth
    sta ZP_PTR_1
    bcc @done
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    adc #0
    sta ZP_PTR_1+1
@done:
    pla
    ply
    rts

printfield:
    ; console routines only
    ; depends only on
    ; - field label for start of field

    jsr con_cls

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
    jsr con_printchar
    iny
    cpy fieldwidth
    bne @row
    bra @endline
@normalcolor:
    cmp #0  ; zero ending?
    beq @skip
    jsr con_printchar
@skip:
    iny
    cpy fieldwidth
    bne @row
@endline:
    lda #NEWLINE
    jsr con_printchar
    
    ; advance pointer to next row
    lda ZP_PTR_1
    clc
    adc fieldwidth
    sta ZP_PTR_1
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    adc #0
    sta ZP_PTR_1+1
@checklastrow:
    ; last row?
    inx
    cpx fieldheight
    bne @nextrow

    ; print quit message at the end of the field
    lda #NEWLINE
    jsr con_printchar

    lda #<quitmessage
    sta strptr
    lda #>quitmessage
    sta strptr+1
    jsr con_print

    rts

printpreview:
    ; console routines only
    ; depends only on
    ; - field label for start of field
    ; prints on bottom-left part of the screen
    ; calling routine needs to clear the screen
    ; con_init needs to be performed previously

    ; clear area first
    ldy #(SCREENHEIGHT/2)
    lda #' '
@clsloop:
    ldx #(SCREENWIDTH/2)
    jsr con_gotoxy
@rowloop:
    jsr con_printchar
    inx
    cpx #SCREENWIDTH
    bne @rowloop
    iny
    cpy #SCREENHEIGHT
    bne @clsloop

    ; point ZP_PTR_1 to the field
    lda ZP_PTR_FIELD
    sta ZP_PTR_1
    lda ZP_PTR_FIELD+1
    sta ZP_PTR_1+1

    ; find start y position in the middle of lower part of the screen
    lda #(SCREENHEIGHT/2)   ; the maximum space we have vertically
    sec
    sbc fieldheight
    lsr ; divide by two
    clc
    adc #(SCREENHEIGHT/2)   ; at starting point
    tay ; y position

    ; find start x position
    lda #(SCREENWIDTH/2)
    sec
    sbc fieldwidth
    lsr ; divide by two
    clc
    adc #(SCREENWIDTH/2)
    sta temp2
    tax ; x position
    ; position in the middle of the screen for top-left mini-field
    jsr con_gotoxy

    ldx #0 ; row counter
@nextrow:
    ldy #0 ; column counter
@row:
    lda (ZP_PTR_1),y        ; load character from field
    phy     ; save volumn counter
    sta temp                ; save for comparison, limited 6502

    ; find character in map
    ldy #0
@loop:
    lda translatefrom,y
    cmp temp    ; field content matching lookup table? 
    beq @found
    cmp #0
    beq @found  ; terminate at end-of-table
    iny
    bra @loop
@found:
    lda translatepreview,y
    ply     ; retrieve column counter again

    jsr con_printchar

    iny
    cpy fieldwidth
    bne @row

    phx
    lda #$0d
    jsr con_printchar
    ldx temp2
    jsr con_gotox
    plx

    ; advance pointer to next row
    lda ZP_PTR_1
    clc
    adc fieldwidth
    sta ZP_PTR_1
    lda ZP_PTR_1+1 ; carry to high byte if carry set ;-)
    adc #0
    sta ZP_PTR_1+1
@checklastrow:
    ; last row?
    inx
    cpx fieldheight
    bne @nextrow
    rts

con_init:
    ; initializes the console variables
    ; reset to X,Y = 0,0
    pha
    phx
    phy
    stz xpos
    stz ypos
    lda #<VIDSTART
    sta conptr
    lda #>VIDSTART
    sta conptr+1
    ply
    plx
    pla
    rts

con_cls:
    ; Fill the entire screen with empty tile (space)
    ; and reset console to 0,0
    pha
    phx
    phy
    jsr con_init

    ldx #$0
@outer:
    lda #' '            ; space character
    ldy #$0
@inner:
    sta (conptr),y
    iny
    cpy #SCREENWIDTH
    bne @inner          ; next column
    clc
    lda conptr
    adc #SCREENWIDTH             ; next row
    sta conptr
    bcc @next
    lda conptr+1
    adc #$0             ; add the carry (1) to the high byte
    sta conptr+1
@next:
    inx
    cpx #SCREENHEIGHT
    bne @outer
    
    jsr con_init
    ply
    plx
    pla
    rts

con_gotox:
    pha
    phx
    phy
    ldy ypos
    jsr con_gotoxy
    ply
    plx
    pla
    rts

con_gotoxy:
    ; input .x == x position
    ; input .y == y position
    pha
    phx
    phy
    cpx #SCREENWIDTH
    bcs @done           ; >= to WIDTH, set carry and exit
    cpy #SCREENHEIGHT
    bcs @done           ; >= to HEIGHT, set carry and exit
    stx xpos
    sty ypos

    lda #SCREENWIDTH
    sta conptr      ; FAC1 == conptr(low), FAC2 = ypos. FAC1 gets clobbered to final low byte of result
    ; multiply ypos * SCREENWIDTH, store in conptr
@mul8:
    lda #$00
    ldx #$08
    clc
@m0:
    bcc @m1
    clc
    adc ypos
@m1:
    ror
    ror conptr
    dex
    bpl @m0
    sta conptr+1
    ; result now in conptr / conptr+1
    ; Add both video start address (F800) and xpos to conptr.
    ; As xpos <40, we can use the low byte immediately
    clc
    lda conptr
    adc xpos
    sta conptr
    lda conptr+1
    adc #$F8
    sta conptr+1
@done:
    ply
    plx
    pla
    rts

con_getinput:
    lda $0200  ; mail flag
    cmp #$01    ; character received?
    bne con_getinput   ; blocked wait for character
    stz $0200  ; acknowledge receive
    lda $0201  ; receive the character from the mailbox slot
    rts

con_print:
    ; prints zero-terminated string pointed to by strptr in zeropage
    pha
    phx
    phy

    ldy #0
@loop:
    lda (strptr),y
    beq @done
    jsr con_printchar 
    iny
    bra @loop
@done:
    ply
    plx
    pla
    rts

con_printchar:
    ; prints character from A to the current X,Y coordinate in zeropage
    ; X,Y is always a previously checked valid coordinate
    pha
    phx
    phy

    cmp #$d ; CR
    beq @CRLF
    cmp #$a ; LF
    beq @CRLF

    ; print normally
    ldy #0
    sta (conptr),y
    ; update position and check validity
    ; wrap around at end of screen to 0,0
    ; X = X + 1
    lda xpos
    cmp #SCREENWIDTH-1
    beq @CRLF
    clc
    adc #1
    sta xpos
    bra @nextptr
@CRLF:
    lda #SCREENWIDTH
    sec
    sbc xpos            ; move down SCREENWIDTH - xpos characters
    clc
    adc conptr          ; add to low byte of pointer
    sta conptr
    lda conptr+1
    adc #0
    sta conptr+1        ; add to high byte of pointer

    ; now reset x and check y next
    stz xpos
    lda ypos
    cmp #SCREENHEIGHT-1
    bne @nextrow
    ; return to 0,0
    jsr con_init
    bra @done
@nextrow:
    inc ypos
    bra @done
@nextptr:
    lda conptr
    clc
    adc #1
    sta conptr
    bcc @done
    lda conptr+1
    adc #0
    sta conptr+1
@done:
    ply
    plx
    pla
    rts

; tile data
; each tile consists of 16x16, 4x8x8 laid out sequentially
; this will need to be loaded dynamically into character memory at program start
    .data
tiledata:
player:
    .byte $1,$3,$4,$A,$8,$5,$4,$3,$80,$C0,$20,$50,$10,$A0,$20,$C0,$6,$F,$E,$1B,$3,$2,$6,$E,$60,$F0,$70,$D8,$C0,$40,$60,$70
crate:
    .byte $0,$77,$48,$44,$22,$51,$48,$44,$0,$EE,$12,$22,$44,$8A,$12,$22,$44,$48,$51,$22,$44,$48,$77,$0,$22,$12,$8A,$44,$22,$12,$EE,$0
goal:
    .byte $0,$0,$4,$2,$1,$20,$10,$9,$0,$0,$20,$40,$80,$4,$8,$90,$9,$10,$20,$1,$2,$4,$0,$0,$90,$8,$4,$80,$40,$20,$0,$0
crateongoal:
    .byte $0,$77,$68,$54,$2A,$55,$4A,$45,$0,$EE,$16,$2A,$54,$AA,$52,$A2,$45,$4A,$55,$2A,$54,$68,$77,$0,$A2,$52,$AA,$54,$2A,$16,$EE,$0
brick:
    .byte $F7,$F7,$F7,$0,$7F,$7F,$7F,$0,$F7,$F7,$F7,$0,$7F,$7F,$7F,$0,$F7,$F7,$F7,$0,$7F,$7F,$7F,$0,$F7,$F7,$F7,$0,$7F,$7F,$7F,$0
black:
    .byte $0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0,$0
ingame_keyinput:
    .byte KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,'u','U','r','R','q','Q',0
ingame_keyjump:
    .word handle_ingamekeyup
    .word handle_ingamekeydown
    .word handle_ingamekeyleft
    .word handle_ingamekeyright
    .word handle_ingamekeyundo
    .word handle_ingamekeyundo
    .word handle_ingamekeyreset
    .word handle_ingamekeyreset
    .word handle_ingamekeyquit
    .word handle_ingamekeyquit
    .word keyloop               ; the default option 
select_keyinput:
    .byte KEY_DOWN,KEY_LEFT,KEY_UP,KEY_RIGHT,KEY_ENTER,'q',0
select_keyjump:
    .word handle_selectdown
    .word handle_selectdown
    .word handle_selectup
    .word handle_selectup
    .word handle_selectenter
    .word exit
    .word selectlevel_charloop  ; the default option
translatefrom:
    .byte '@','+','$','.','*','#',' ',0
translateto:
    .byte TILE_PLAYER,TILE_PLAYER,TILE_CRATE,TILE_GOAL,TILE_CRATE_ON_GOAL,TILE_WALL,TILE_IGNORE,TILE_IGNORE
translatepreview:
    .byte 0,0,'#','X','*',8,' ',' '
LOADSTART:
.incbin "levels.bin"
RAMBANK:    ; Start of variable DATA, used for copying new field into
