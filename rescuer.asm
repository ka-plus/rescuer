/*
 * MIT License
 *
 * Copyright (c) 2022-2023 Komoda & Amiga plus
 * Copyright (c) 2022-2023 Maciej Małecki
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
#import "build/charpad/metadata.asm"
/// VIC-2
.label SCREEN = $0400
.label COLOUR_RAM = $D800
// shapes
.label PLAYER_SHAPE_NEUTRAL = 0
.label PLAYER_SHAPE_LEFT = 1
.label PLAYER_SHAPE_RIGHT = 2
.label SURVIVOR_SHAPE = 3
.label SHAPES_COUNT = 4
.label PLAYER_SPRITE = 0
// physics & controls
.label ANIMATION_DELAY_MAX = 10
.label GRAVITY_ACCELERATION = 5
.label UP_ACCELERATION = 5
.label VERTICAL_ACCELERATION = 5
// game initials
.label LIVES = 5
.label START_LEVEL = 1
// player state
.label PLAYER_LEFT  = %00000100
.label PLAYER_RIGHT = %00000010
.label PLAYER_UP    = %00000001

*=$0801 "Basic Upstart"
BasicUpstart(start) // Basic start routine

*=$080d "Program" // Main program

start: { // outer game loop, handles title screen, launches the game
        jsr init
    outerMainLoop:
        jsr drawTitleScreen
    titleScreenLoop:
        jsr readJoy
        lda joyState
        and #%00010000 // check if fire is pressed to start the game
        bne !+
            jsr startGame
            jmp outerMainLoop // jump outside outer main loop to redraw title screen
        !:
        jmp titleScreenLoop
}

startGame: { // main game routine
        jsr initGame
    levelLoop:
        jsr initLevel
        jsr enableIRQ
    mainLoop:
        lda gameState
        and #%00000001 // check of die flag is on (live lost)
        bne liveLost
        lda $D015
        and #%00011110 // check if all survivors has been collected (their sprites are off) -> next level
        beq nextLevel
        jmp mainLoop
    liveLost:
        jsr disableIRQ
        dec livesCounter // decrement lives counter
        lda livesCounter
        beq gameOver // no lives left -> game over
        jmp levelLoop // restart level
    nextLevel:
        jsr disableIRQ
        inc levelCounter // increment level counter
        lda levelCounter
        cmp #MAX_LEVEL // max levels reached
        beq gameOver // game is finished
        jmp levelLoop
    gameOver:
        lda #0
        sta $D015 // hide all sprites
    rts
}

doOnEachFrame: { // code to be executed at regular interval, i.e. in raster interrupt (50/60 times per sec)
    jsr handleControls
    jsr updatePlayerPosition
    jsr animatePlayer
    jsr checkCollision
    dec $D019 // clear interrupt flag
    jmp $EA31 // perform standard Kernal IRQ routine
}

init: { // game initialization
    // * init interrupt (IRQ) *
    sei
    // disable CIA#1 interrupts
    lda #$7F
    sta $DC0D
    lda $DC0D
    // set new IRQ handler
    lda #<doOnEachFrame
    sta $0314
    lda #>doOnEachFrame
    sta $0315
    cli
    // * init IO *
    // set IO pins for joy 2 to input
    lda $DC02
    and #%11100000
    sta $DC02
    // * init VIC-2 *
    // init colours
    lda #backgroundColour0
    sta $D020
    sta $D021
    lda #backgroundColour1
    sta $D022
    lda #backgroundColour2
    sta $D023
    // init sprite colours
    lda #12
    sta $D025
    lda #11
    sta $D026
    // set charset mem bank to the last one (we'll use default screen location)
    lda $D018
    ora #%00001110
    sta $D018
    // set screen mode to multicolor
    lda $D016
    ora #%00010000
    sta $D016
    // set up shapes for sprites
    .for (var i = 0; i < 4; i++) {
        setShapeForSprite(SURVIVOR_SHAPE, i + 1)
    }
    rts
}

enableIRQ: { // starts to execute 'doOnEachFrame' logic
    lda #40
    sta $D012 // setup raster IRQ at line 40
    lda $D011
    and #%0111111
    sta $D011
    lda #%00000001
    sta $D01A
    rts
}

disableIRQ: { // stops executing 'doOnEachFrame' logic
    lda #%00000000
    sta $D01A
    rts
}

initGame: { // Initialization per individual game run.
    lda #START_LEVEL
    sta levelCounter
    lda #LIVES
    sta livesCounter
    // * init sprite *
    lda #15 // individual player sprite colour
    sta $D027
    lda $D01C
    ora #%00011111
    sta $D01C // set multicolor for all sprites
    lda #10 // common survivour sprite colour
    sta $D028
    sta $D029
    sta $D02A
    sta $D02B
    rts
}

initLevel: { // Initialization per each level.
    // set up player
    setWord(vAcceleration, 0)
    setWord(hAcceleration, 0)
    setWord(vSpeed, 0)
    setWord(hSpeed, 0)
    // set up state
    lda #0
    sta gameState
    sta playerState
    // set up level
    jsr drawDashboard
    ldy levelCounter
    dey
    lda spritesLo, y
    ldx spritesHi, y
    jsr initSpritesForLevel
    lda caveLo, y
    ldx caveHi, y
    jsr copyLevel
    // clear collision detection
    lda $D01F
    lda $D01E
    // set up delay
    lda #ANIMATION_DELAY_MAX
    sta animationDelay
    rts
}

initSpritesForLevel: { // Extra init for sprites per level. IN: A sprites lo, X sprites hi
    // init address of sprite definition structure (there is a one per level)
    sta spritesAddr
    stx spritesAddr + 1
    // player horizontal position
    ldx #0
    jsr loadSpriteByte
    sta hPosition + 1
    sta $D000,x
    lda #0
    sta hPosition
    // player vertical position
    inx
    jsr loadSpriteByte
    sta vPosition + 1
    sta $D000,x
    lda #0
    sta vPosition
    inx
!:  // for each survivors:
    // survivor horizontal position
    jsr loadSpriteByte
    beq endOfSprites
    sta $D000,x
    inx
    // survivor vertical position
    jsr loadSpriteByte
    sta $D000,x
    inx
    jmp !-
endOfSprites:
    // show all sprites
    lda $D015
    ora #%00011111
    sta $D015
    rts
loadSpriteByte:
    lda spritesAddr:$FFFF,x
    rts
}

// ==== IO handling ====
readJoy: {
    lda $DC00
    and #%00011111
    sta joyState // take a snapshot of the joystick state
    rts
}

// ==== Game physics ====
handleControls: {
    // animation delay makes stearing a little bit sluggish
    ldx animationDelay
    dex
    beq !+
    stx animationDelay
    rts
!:
    ldx #ANIMATION_DELAY_MAX
    stx animationDelay

    jsr readJoy

    lda joyState
    and #%00000100 // left
    bne !+
    jmp joyLeft
!:
    lda joyState
    and #%00001000 // right
    bne !+
    jmp joyRight
!:
    setWord(hAcceleration, 0) // stop accelerating in h-axis if joy is not in left/right position
    jmp checkUp
joyLeft:
    lda playerState
    and #PLAYER_RIGHT
    beq !+
        // rotate to neutral
        lda playerState
        and #(PLAYER_RIGHT ^ $FF)
        sta playerState
        setWord(hAcceleration, 0) // stop accelerating
        setWord(hSpeed, 0) // change direction, zero the speed
        jmp checkUp
!:
    lda playerState
    ora #PLAYER_LEFT
    sta playerState
    setWord(hAcceleration, VERTICAL_ACCELERATION) // joy left, accelerate
    jmp checkUp
joyRight:
    lda playerState
    and #PLAYER_LEFT
    beq !+
        // rotate to neutral
        lda playerState
        and #(PLAYER_LEFT ^ $FF)
        sta playerState
        setWord(hAcceleration, 0) // stop accelerating
        setWord(hSpeed, 0) // change direction, zero the speed
        jmp checkUp
!:
    lda playerState
    ora #PLAYER_RIGHT
    sta playerState
    setWord(hAcceleration, VERTICAL_ACCELERATION) // joy right, accelerate
checkUp:
    lda joyState
    and #%00000001 // up
    bne !+
    jmp joyUp
!:
    lda playerState
    and #PLAYER_UP
    beq !+
        lda playerState
        and #(PLAYER_UP ^ $FF)
        sta playerState
        setWord(vAcceleration, 0) // no up, stop up movement
        setWord(vSpeed, 0)
!:
    setWord(vAcceleration, GRAVITY_ACCELERATION) // let the gravity work
    rts
joyUp:
    lda playerState
    and #PLAYER_UP
    bne !+
        lda playerState
        ora #PLAYER_UP
        sta playerState
        setWord(vAcceleration, UP_ACCELERATION) // accelerate upwards
        setWord(vSpeed, 0)
!:
    rts
}

updatePlayerPosition: {
    // vertical
    lda playerState
    and #PLAYER_LEFT
    beq !+
        jsr adcHAcceleration
        sbcWord(hPosition, hSpeed, hPosition)
        jmp vertical
!:
    lda playerState
    and #PLAYER_RIGHT
    beq !+
        jsr adcHAcceleration
        adcWord(hSpeed, hPosition, hPosition)
!:
vertical:
    lda playerState
    and #PLAYER_UP
    beq !+
        jsr adcVAcceleration
        sbcWord(vPosition, vSpeed, vPosition)
        rts
!:
        jsr adcVAcceleration
        adcWord(vPosition, vSpeed, vPosition)
    rts
adcHAcceleration:
    adcWord(hAcceleration, hSpeed, hSpeed)
    rts
adcVAcceleration:
    adcWord(vAcceleration, vSpeed, vSpeed)
    rts
}

animatePlayer: {
    // move player
    lda hPosition + 1
    sta $D000
    lda vPosition + 1
    sta $D001
    // decide which shape of the player should be displayed
    lda playerState
    and #PLAYER_LEFT
    beq !+
        setShapeForSprite(PLAYER_SHAPE_LEFT, PLAYER_SPRITE)
        rts
!:
    lda playerState
    and #PLAYER_RIGHT
    beq !+
        setShapeForSprite(PLAYER_SHAPE_RIGHT, PLAYER_SPRITE)
        rts
!:
    setShapeForSprite(PLAYER_SHAPE_NEUTRAL, PLAYER_SPRITE)
    rts
}

checkCollision: {
    lda $D01F
    and #%00000001
    beq !+
        lda gameState
        ora #%00000001
        sta gameState
!:
    lda $D01E
    and #%00011110
    beq !+
        eor $D015
        and #%00011111
        ora #%00000001
        sta $D015
!:
    rts
}

// ==== sprites routines ====
.macro setShapeForSprite(shapeNum, spriteNum) {
    lda #(256 - SHAPES_COUNT + shapeNum)
    sta SCREEN + 1024 - 8 + spriteNum
}

// ==== screen drawing routines ====
/*
 * IN: A - source address lsb, X - source address hsb
 * DESTROYS: A,X,Y
 */
.macro copyScreenBlock(width, screenTarget, colorSource, colorTarget) {
    sta sourceAddress
    stx sourceAddress + 1
    setWord(destAddress, screenTarget)
    setWord(colorDestAddress, colorTarget)
    ldy #25
nextLine:
    ldx #width
    nextChar:
        dex
        tya
        pha
        lda sourceAddress:$FFFF,x
        tay
        sta destAddress:$FFFF,x
        lda colorSource,y
        sta colorDestAddress:$FFFF,x
        pla
        tay
        cpx #0
    bne nextChar
    adcWordValue(sourceAddress, width)
    adcWordValue(destAddress, 40)
    adcWordValue(colorDestAddress, 40)
    dey
    bne nextLine
    rts
}

copyFullScreen: copyScreenBlock(40, SCREEN, colours, COLOUR_RAM)
copyDashboard: copyScreenBlock(11, SCREEN + 29, colours, COLOUR_RAM + 29)
copyLevel: copyScreenBlock(29, SCREEN, colours, COLOUR_RAM)

drawTitleScreen: {
    lda #<titleScreen
    ldx #>titleScreen
    jsr copyFullScreen
    rts
}

drawDashboard: {
    lda #<dashboard
    ldx #>dashboard
    jsr copyDashboard
    clc
    lda levelCounter
    adc #48
    sta SCREEN + 40*9 + 34
    clc
    lda livesCounter
    adc #48
    sta SCREEN + 40*13 + 34
    rts
}

// ==== aux math routines ====
.macro setWord(address, value) {
    lda #<value
    sta address
    lda #>value
    sta address + 1
}
.macro adcWord(left, right, store) {
    clc
    lda left
    adc right
    sta store
    lda left + 1
    adc right + 1
    sta store + 1
}
.macro adcWordValue(address, value) {
    clc
    lda #<value
    adc address
    sta address
    lda #>value
    adc address + 1
    sta address + 1
}
.macro sbcWord(left, right, store) {
    sec
    lda left
    sbc right
    sta store
    lda left + 1
    sbc right + 1
    sta store + 1
}

// ==== variables ====
levelCounter:       .byte 0
livesCounter:       .byte 0
joyState:           .byte 0
vAcceleration:      .word 0
hAcceleration:      .word 0
vSpeed:             .word 0
hSpeed:             .word 0
vPosition:          .word 0
hPosition:          .word 0
animationDelay:     .byte 0
gameState:          .byte 0 // %0000000a a: player died
playerState:        .byte 0 // %00000abc a: left, b: right, c: up

// ==== data ====
.label MAX_LEVEL = 4
caveLo:         .byte <level1, <level2, <level3
caveHi:         .byte >level1, >level2, >level3
spritesLo:      .byte <sprites1, <sprites2, <sprites3
spritesHi:      .byte >sprites1, >sprites2, >sprites3

sprites1:       .byte 150, 100, 60, 85, 90, 221, 210, 221, 200, 141, 0
sprites2:       .byte 55, 70, 80, 221, 85, 140, 190, 221, 220, 133, 0
sprites3:       .byte 45, 70, 80, 93, 85, 149, 170, 221, 180, 149, 0

colours:        .import binary "build/charpad/colours.bin"
titleScreen:    .import binary "build/charpad/title.bin"
dashboard:      .import binary "build/charpad/dashboard.bin"
level1:         .import binary "build/charpad/level1.bin"
level2:         .import binary "build/charpad/level2.bin"
level3:         .import binary "build/charpad/level3.bin"
/*
 * To save time and coding efforts charset and sprites are moved straight to the target location within VIC-II address space
 * thus it is probably a good idea to pack the game with i.e. Exomizer after compiling.
 */
*=($4000 - $0800) "Charset"
.import binary "build/charpad/charset.bin"
*=($4000 - SHAPES_COUNT*64) "Sprites"
.import binary "build/spritepad/player.bin"
.import binary "build/spritepad/survivor.bin"
