' backdrop.bas -- dynamic matte paintings: the effect list and its timing (#369)
'
' assets/backdrops.txt gives each painted screen a list of independent looping effects. There is
' no script and no runner: every line is its own loop, and what it looks like on a frame is worked
' out from that frame's number. every= and phase= are the only choreography. This file knows
' nothing about the game (no screen, no state): the caller hands BD_Advance the main loop's frame
' number, and src/2d/backdropdraw.bas draws what this leaves in the tables. Tests drive it with
' plain numbers.
'
' File format (; starts a comment; verbs are case-insensitive, keys are lower case):
'   backdrop:<name>          the painting the following lines belong to (title emperor dock)
'       CAMERA [fov=60] [horizon=120]      (at most once per backdrop; for LASER)
'       BLINK at=x,y color=rrggbb [size=1] [glow=3] [rise=0] [hold=0] [fall=0] [rest=0] [phase=0]
'             [morse=TEXT] [unit=6]
'       SPARK at=x,y color=rrggbb[,rrggbb...] [count=3] [every=60] [speed=0.6] [gravity=0.05]
'             [life=20] [dir=270] [spread=120] [phase=0] [jitter=0] [size=1]
'       SPRITE img=name at=x,y to=x,y [frames=300] [rest=0] [pingpong=0] [flip=0] [phase=0]
'              [scale=1[,1]] [bob=amp,period[,angle]]
'       LASER from=x,y,depth to=x,y,depth color=rrggbb [every=60] [speed=4] [length=12] [jitter=0] [phase=0]
' Positions are pixels on the 320x240 painting. Frames run at 60 per second.
'   BLINK  a light on a looping envelope: it fades up over `rise` frames, stays at full for `hold`,
'          fades down over `fall`, and is dark for `rest`; the loop is the sum of the four (at
'          least 1 frame). Fades are eased (half a cosine). rise=0 fall=0 is a hard blink. size is the
'          radius of the lit core in pixels.
'   SPARK  every `every` frames, `count` sparks leave the point at `speed` px/frame, spread over
'          `spread` degrees around `dir` (0 = right, 90 = down, 270 = up), pulled down by
'          `gravity`, and fade out over `life` frames. Each takes one of the colours.
'          morse=TEXT flashes TEXT in Morse code instead (letters, digits, _ for a space; unit= is the
'          dot in frames; dash 3, gaps 1 / 3 / 7), dark for `rest` before it repeats; rise and fall
'          soften each flash; hold is not allowed with it.
'   SPRITE an image from assets/backdrops/ goes at -> to over `frames`, then waits `rest` (hidden, or
'          parked at the end with pingpong=1, which drives it back; flip=1 mirrors the return leg).
'          scale=a[,b] is its size along the path (linear from at to to); bob=amp,period[,angle] a hop
'          of amp pixels (times the scale) every `period` frames while it moves, angle 0 right, 90 down, 270 up.
'   LASER  every `every` frames a bolt flies from -> to at `speed` world units a frame, `length` long,
'          through the backdrop's own CAMERA. x,y is where the bolt shows on the painting at that depth.
'   glow   pixels of soft glow around a BLINK core.
'   size   of a SPARK: 1 = a 2x2 head with a 1 pixel trail, each step adds a pixel to both.
'   jitter each SPARK burst comes up to this many frames late (below every), different each time,
'          from the frame/effect hash: bursts are every-jitter to every+jitter frames apart.
'   phase  shifts the loop: the effect behaves as if the screen had been open that many frames.
'
' Randomness is a hash of (frame, effect, spark): no RNG stream is read, so no other visual and no
' seeded gameplay shifts, and the same frames always draw the same picture.
'
' BD_Parse%(src)       1 when the file loaded clean, else 0 with bdErrors (one "line N: ..." each)
' BD_Validate$()       "" when sound, else one problem per line (parse problems first)
' BD_Find%(name)       the backdrop's number, -1 when it has none
' BD_Advance           call once per drawn frame; resets when a screen is entered
' BD_BlinkLevel!(fx,f) 0..1 brightness of a BLINK (or its Morse) at frame f
' BD_SpriteAt%(fx,f,x,y,flip)  where a SPRITE is on frame f (0 = hidden); BD_SpriteState% adds its size and hop offset
' BD_LaserHead%(fx,f,j,dist)   whether the j-th newest bolt of a LASER is in flight, and how far it has gone
' BD_World / BD_CamMatrix       the painting's fixed camera (CAMERA), so a LASER never reads the game's vpMat
' Shared state is bd*; every routine's locals carry their own two-letter prefix

Const BD_MAX_FX = 96          ' effects in the whole file
Const BD_MAX_SETS = 12        ' backdrops in the whole file
Const BD_MAX_COL = 4          ' colours on one effect
Const BD_POOL = 1024          ' sparks alive at once
Const BD_MAX_WORDS = 16
Const BD_KIND_BLINK = 1
Const BD_KIND_SPARK = 2
Const BD_KIND_SPRITE = 3
Const BD_KIND_LASER = 4
Const BD_SPRITE_NAMES = "tug baggage_cart"      ' images in assets/backdrops/, each embedded as BDIMG + the name in capitals without underscores
Const BD_CAM_FOV = 60                ' CAMERA defaults
Const BD_CAM_HORIZON = 120
Const BD_CAM_VPX = 160               ' the vanishing point's x: the middle of the painting
Const BD_MARGIN = 64                 ' a SPRITE may start and end this far off the painting
Const BD_MORSE_MAX = 24              ' characters of morse=
Const BD_LASER_BOLTS = 8             ' bolts of one LASER in flight at once
Const BD_PAINT_W = 320
Const BD_PAINT_H = 240

Dim Shared bdSetName(0 To BD_MAX_SETS - 1) As String
Dim Shared bdSetFrom(0 To BD_MAX_SETS - 1) As Integer    ' first effect
Dim Shared bdSetN(0 To BD_MAX_SETS - 1) As Integer       ' effects
Dim Shared bdSetLine(0 To BD_MAX_SETS - 1) As Integer
Dim Shared bdSetFov(0 To BD_MAX_SETS - 1) As Single
Dim Shared bdSetHor(0 To BD_MAX_SETS - 1) As Single
Dim Shared bdSetCam(0 To BD_MAX_SETS - 1) As Integer     ' a CAMERA line was given
Dim Shared bdSets As Integer

Dim Shared bdKind(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdX(0 To BD_MAX_FX - 1) As Single
Dim Shared bdY(0 To BD_MAX_FX - 1) As Single
Dim Shared bdCol(0 To BD_MAX_FX - 1, 0 To BD_MAX_COL - 1) As Long
Dim Shared bdColN(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdSize(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdGlow(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdJitter(0 To BD_MAX_FX - 1) As Long
Dim Shared bdRise(0 To BD_MAX_FX - 1) As Long
Dim Shared bdHold(0 To BD_MAX_FX - 1) As Long
Dim Shared bdFall(0 To BD_MAX_FX - 1) As Long
Dim Shared bdRest(0 To BD_MAX_FX - 1) As Long
Dim Shared bdPhase(0 To BD_MAX_FX - 1) As Long
Dim Shared bdCount(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdEvery(0 To BD_MAX_FX - 1) As Long
Dim Shared bdSpeed(0 To BD_MAX_FX - 1) As Single
Dim Shared bdGrav(0 To BD_MAX_FX - 1) As Single
Dim Shared bdLife(0 To BD_MAX_FX - 1) As Long
Dim Shared bdDir(0 To BD_MAX_FX - 1) As Single
Dim Shared bdSpread(0 To BD_MAX_FX - 1) As Single
Dim Shared bdFxLine(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdFxSet(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdX2(0 To BD_MAX_FX - 1) As Single       ' SPRITE to, LASER to
Dim Shared bdY2(0 To BD_MAX_FX - 1) As Single
Dim Shared bdD1(0 To BD_MAX_FX - 1) As Single       ' LASER depths
Dim Shared bdD2(0 To BD_MAX_FX - 1) As Single
Dim Shared bdFrames(0 To BD_MAX_FX - 1) As Long     ' SPRITE frames per leg
Dim Shared bdPing(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdFlip(0 To BD_MAX_FX - 1) As Integer
Dim Shared bdScaleA(0 To BD_MAX_FX - 1) As Single    ' SPRITE size at `at` and at `to`
Dim Shared bdScaleB(0 To BD_MAX_FX - 1) As Single
Dim Shared bdBobAmp(0 To BD_MAX_FX - 1) As Single    ' SPRITE hop: height in pixels, frames per hop, direction in degrees
Dim Shared bdBobPer(0 To BD_MAX_FX - 1) As Single
Dim Shared bdBobAng(0 To BD_MAX_FX - 1) As Single
Dim Shared bdImg(0 To BD_MAX_FX - 1) As Integer     ' SPRITE image, 1.. in BD_SPRITE_NAMES
Dim Shared bdLaserLen(0 To BD_MAX_FX - 1) As Single
Dim Shared bdMorse(0 To BD_MAX_FX - 1) As String    ' one character per unit, 1 lit and 0 dark; "" = not morse
Dim Shared bdUnit(0 To BD_MAX_FX - 1) As Long
Dim Shared bdFxN As Integer

Dim Shared bdErrors As String

' --- parse scratch: the key=value words of the line being read ---
Dim Shared bdKvKey(0 To BD_MAX_WORDS - 1) As String
Dim Shared bdKvVal(0 To BD_MAX_WORDS - 1) As String
Dim Shared bdKvN As Integer
Dim Shared bdPLine As Integer
Dim Shared bdPVerb As String
Dim Shared bdPBad As Integer          ' the line being read has a problem already

' --- run state: the backdrop on screen ---
Dim Shared bdCur As Integer           ' backdrop number, -1 = none
Dim Shared bdFrame As Long            ' frames since the screen was entered
Dim Shared bdLastMain As Long         ' main-loop frame of the last BD_Advance
Dim Shared bdPAlive(0 To BD_POOL - 1) As Integer
Dim Shared bdPX(0 To BD_POOL - 1) As Single
Dim Shared bdPY(0 To BD_POOL - 1) As Single
Dim Shared bdPVX(0 To BD_POOL - 1) As Single
Dim Shared bdPVY(0 To BD_POOL - 1) As Single
Dim Shared bdPAge(0 To BD_POOL - 1) As Long
Dim Shared bdPLife(0 To BD_POOL - 1) As Long
Dim Shared bdPCol(0 To BD_POOL - 1) As Long
Dim Shared bdPFx(0 To BD_POOL - 1) As Integer
Dim Shared bdPDropped As Long         ' sparks that found the pool full (never, in a file that validates)
Dim Shared bdPFirst As Integer        ' every slot below this one is in use: spawning starts its search here

Sub BD_Err (beLine As Integer, beMsg As String)
    bdErrors = bdErrors + "line " + LTrim$(Str$(beLine)) + ": " + beMsg + Chr$(10)
End Sub

' Reports a problem on the line being read, once per line.
Sub BD_LineErr (blMsg As String)
    If bdPBad Then Exit Sub
    bdPBad = -1
    BD_Err bdPLine, blMsg
End Sub

' A decimal number in bnText ("-1", "0.05", ".5"), no exponent. 1 and bnOut when it is one, else 0.
Function BD_ParseNum% (bnText As String, bnOut As Single)
    Dim bnI As Integer, bnC As String, bnDigits As Integer, bnDots As Integer
    BD_ParseNum% = 0
    If Len(bnText) = 0 Or Len(bnText) > 12 Then Exit Function
    For bnI = 1 To Len(bnText)
        bnC = Mid$(bnText, bnI, 1)
        If bnC >= "0" And bnC <= "9" Then
            bnDigits = bnDigits + 1
        ElseIf bnC = "." Then
            bnDots = bnDots + 1
            If bnDots > 1 Then Exit Function
        ElseIf bnC = "-" And bnI = 1 Then
        Else
            Exit Function
        End If
    Next bnI
    If bnDigits = 0 Then Exit Function
    bnOut = Val(bnText)
    BD_ParseNum% = -1
End Function

' A colour "rrggbb" (a leading # is allowed) as an opaque colour in bhOut. 1 when it is one, else 0.
Function BD_ParseHex% (bhText As String, bhOut As Long)
    Dim bhS As String, bhI As Integer, bhC As String
    bhS = bhText
    If Left$(bhS, 1) = "#" Then bhS = Mid$(bhS, 2)
    BD_ParseHex% = 0
    If Len(bhS) <> 6 Then Exit Function
    For bhI = 1 To 6
        bhC = LCase$(Mid$(bhS, bhI, 1))
        If Not ((bhC >= "0" And bhC <= "9") Or (bhC >= "a" And bhC <= "f")) Then Exit Function
    Next bhI
    bhOut = _RGB32(Val("&H" + Mid$(bhS, 1, 2)), Val("&H" + Mid$(bhS, 3, 2)), Val("&H" + Mid$(bhS, 5, 2)))
    BD_ParseHex% = -1
End Function

' Splits a line on spaces and tabs into bdW(0..), at most BD_MAX_WORDS; returns the count, or
' BD_MAX_WORDS + 1 when there are more.
Function BD_Words% (bwText As String, bwOut() As String)
    Dim bwN As Integer, bwRest As String, bwSp As Integer, bwI As Integer
    bwRest = bwText
    For bwI = 1 To Len(bwRest)
        If Mid$(bwRest, bwI, 1) = Chr$(9) Then Mid$(bwRest, bwI, 1) = " "
    Next bwI
    bwRest = LTrim$(RTrim$(bwRest))
    Do While Len(bwRest) > 0
        If bwN >= BD_MAX_WORDS Then BD_Words% = BD_MAX_WORDS + 1 : Exit Function
        bwSp = InStr(bwRest, " ")
        If bwSp = 0 Then
            bwOut(bwN) = bwRest : bwRest = ""
        Else
            bwOut(bwN) = Left$(bwRest, bwSp - 1) : bwRest = LTrim$(Mid$(bwRest, bwSp + 1))
        End If
        bwN = bwN + 1
    Loop
    BD_Words% = bwN
End Function

' The keys each verb takes, space-separated; "" for an unknown verb.
Function BD_KeysOf$ (bkVerb As String)
    Select Case bkVerb
        Case "BLINK" : BD_KeysOf$ = "at color size glow rise hold fall rest phase morse unit"
        Case "SPRITE" : BD_KeysOf$ = "img at to frames rest pingpong flip phase scale bob"
        Case "LASER" : BD_KeysOf$ = "from to color every jitter speed length phase"
        Case "CAMERA" : BD_KeysOf$ = "fov horizon"
        Case "SPARK" : BD_KeysOf$ = "at color count every jitter size speed gravity life dir spread phase"
        Case Else    : BD_KeysOf$ = ""
    End Select
End Function

Function BD_KvIdx% (bkKey As String)
    Dim bkI As Integer
    BD_KvIdx% = -1
    For bkI = 0 To bdKvN - 1
        If bdKvKey(bkI) = bkKey Then BD_KvIdx% = bkI : Exit Function
    Next bkI
End Function

' Reads the optional number `boKey` into boOut, default boDef, within boLo..boHi (whole when boInt).
' 0 and a reported problem when it is there and wrong.
Function BD_Opt% (boKey As String, boDef As Single, boLo As Single, boHi As Single, boInt As Integer, boOut As Single)
    Dim boI As Integer, boV As Single, boWhole As String
    BD_Opt% = -1
    boOut = boDef
    boI = BD_KvIdx%(boKey)
    If boI < 0 Then Exit Function
    If boInt Then boWhole = "a whole number " Else boWhole = "a number "
    If BD_ParseNum%(bdKvVal(boI), boV) = 0 Then
        BD_LineErr bdPVerb + " " + boKey + " must be " + boWhole + LTrim$(Str$(boLo)) + " to " + LTrim$(Str$(boHi)) + ", not '" + bdKvVal(boI) + "'"
        BD_Opt% = 0 : Exit Function
    End If
    If boInt And boV <> Int(boV) Then
        BD_LineErr bdPVerb + " " + boKey + " must be " + boWhole + LTrim$(Str$(boLo)) + " to " + LTrim$(Str$(boHi)) + ", not '" + bdKvVal(boI) + "'"
        BD_Opt% = 0 : Exit Function
    End If
    If boV < boLo Or boV > boHi Then
        BD_LineErr bdPVerb + " " + boKey + " must be " + boWhole + LTrim$(Str$(boLo)) + " to " + LTrim$(Str$(boHi)) + ", not '" + bdKvVal(boI) + "'"
        BD_Opt% = 0 : Exit Function
    End If
    boOut = boV
End Function

' key=x,y (bvN = 2) or key=x,y,depth (bvN = 3) into bvOut(0..): x,y within bvMargin pixels of the painting.
Function BD_ParseVec% (bvKey As String, bvN As Integer, bvMargin As Integer, bvOut() As Single)
    Dim bvI As Integer, bvV As String, bvP As Integer, bvK As Integer, bvShape As String, bvRest As String, bvCommas As Integer
    BD_ParseVec% = 0
    If bvN = 2 Then bvShape = "x,y" Else bvShape = "x,y,depth"
    bvI = BD_KvIdx%(bvKey)
    If bvI < 0 Then BD_LineErr bdPVerb + " needs " + bvKey + "=" + bvShape : Exit Function
    bvV = bdKvVal(bvI)
    For bvK = 1 To Len(bvV)
        If Mid$(bvV, bvK, 1) = "," Then bvCommas = bvCommas + 1
    Next bvK
    If bvCommas <> bvN - 1 Then BD_LineErr bdPVerb + " " + bvKey + " must be " + bvShape : Exit Function
    bvRest = bvV + ","
    For bvK = 0 To bvN - 1
        bvP = InStr(bvRest, ",")
        If BD_ParseNum%(Left$(bvRest, bvP - 1), bvOut(bvK)) = 0 Then BD_LineErr bdPVerb + " " + bvKey + " must be " + bvShape + " in pixels, not '" + bvV + "'" : Exit Function
        bvRest = Mid$(bvRest, bvP + 1)
    Next bvK
    If bvOut(0) < -bvMargin Or bvOut(0) > BD_PAINT_W + bvMargin Or bvOut(1) < -bvMargin Or bvOut(1) > BD_PAINT_H + bvMargin Then BD_LineErr bdPVerb + " " + bvKey + "=" + bvV + " is off the " + LTrim$(Str$(BD_PAINT_W)) + "x" + LTrim$(Str$(BD_PAINT_H)) + " painting" : Exit Function
    If bvN = 3 Then
        If bvOut(2) < -50 Or bvOut(2) > 500 Then BD_LineErr bdPVerb + " " + bvKey + " depth must be -50 to 500, not '" + bvV + "'" : Exit Function
    End If
    BD_ParseVec% = -1
End Function

' at=x,y inside the painting.
Function BD_ParseAt% (baFx As Integer)
    Dim baV(0 To 2) As Single, baOk As Integer
    baOk = BD_ParseVec%("at", 2, 0, baV())
    If baOk Then bdX(baFx) = baV(0) : bdY(baFx) = baV(1)
    BD_ParseAt% = baOk
End Function

' color=rrggbb[,rrggbb...]
Function BD_ParseColors% (bcFx As Integer, bcMax As Integer)
    Dim bcI As Integer, bcV As String, bcC As Integer, bcPart As String, bcN As Integer, bcCol As Long
    BD_ParseColors% = 0
    bcI = BD_KvIdx%("color")
    If bcI < 0 Then BD_LineErr bdPVerb + " needs color=rrggbb" : Exit Function
    bcV = bdKvVal(bcI) + ","
    Do While Len(bcV) > 0
        bcC = InStr(bcV, ",")
        bcPart = Left$(bcV, bcC - 1) : bcV = Mid$(bcV, bcC + 1)
        If BD_ParseHex%(bcPart, bcCol) = 0 Then BD_LineErr bdPVerb + " color must be rrggbb hex, not '" + bcPart + "'" : Exit Function
        If bcN >= bcMax Then BD_LineErr bdPVerb + " takes at most " + LTrim$(Str$(bcMax)) + " colour(s)" : Exit Function
        bdCol(bcFx, bcN) = bcCol : bcN = bcN + 1
    Loop
    bdColN(bcFx) = bcN
    BD_ParseColors% = -1
End Function

' Sparks alive at once from the SPARK lines of the backdrop being read, for the pool check.
Function BD_SparksAlive& (bsaSet As Integer)
    Dim bsaI As Integer, bsaTot As Long
    For bsaI = bdSetFrom(bsaSet) To bdSetFrom(bsaSet) + bdSetN(bsaSet) - 1
        If bdKind(bsaI) = BD_KIND_SPARK Then bsaTot = bsaTot + bdCount(bsaI) * ((bdLife(bsaI) - 1) \ (bdEvery(bsaI) - bdJitter(bsaI)) + 1)
    Next bsaI
    BD_SparksAlive& = bsaTot
End Function

' morse=TEXT [unit=6] on a BLINK: bdMorse gets one character per unit, 1 lit and 0 dark. Standard timing: dot 1,
' dash 3, a unit of dark between the symbols of a letter, 3 between letters, 7 between words.
Function BD_BuildMorse% (bmFx As Integer)
    Dim bmText As String, bmI As Integer, bmC As String, bmCode As String, bmK As Integer, bmOut As String, bmPend As String, bmP As Integer, bmV As Single
    Const bmCodes = ".- -... -.-. -.. . ..-. --. .... .. .--- -.- .-.. -- -. --- .--. --.- .-. ... - ..- ...- .-- -..- -.-- --.. ----- .---- ..--- ...-- ....- ..... -.... --... ---.. ----."
    BD_BuildMorse% = 0
    bmText = bdKvVal(BD_KvIdx%("morse"))
    If Len(bmText) > BD_MORSE_MAX Then BD_LineErr "BLINK morse is at most " + LTrim$(Str$(BD_MORSE_MAX)) + " characters" : Exit Function
    If Left$(bmText, 1) = "_" Or Right$(bmText, 1) = "_" Or InStr(bmText, "__") > 0 Then BD_LineErr "BLINK morse needs a single _ between words, none at either end" : Exit Function
    If bdHold(bmFx) > 0 Then BD_LineErr "BLINK hold cannot be used with morse= (the letters set the timing; use unit=, rest=, rise=, fall=)" : Exit Function
    For bmI = 1 To Len(bmText)
        bmC = Mid$(bmText, bmI, 1)
        If bmC = "_" Then
            bmPend = "0000000"
        Else
            If bmC >= "a" And bmC <= "z" Then
                bmP = Asc(bmC) - 96
            ElseIf bmC >= "0" And bmC <= "9" Then
                bmP = Asc(bmC) - 48 + 27
            Else
                BD_LineErr "BLINK morse may hold only letters, digits and _ (for a space), not '" + bmC + "'" : Exit Function
            End If
            bmCode = BD_Nth$(bmCodes, bmP)
            bmOut = bmOut + bmPend
            For bmK = 1 To Len(bmCode)
                If bmK > 1 Then bmOut = bmOut + "0"
                If Mid$(bmCode, bmK, 1) = "." Then bmOut = bmOut + "1" Else bmOut = bmOut + "111"
            Next bmK
            bmPend = "000"
        End If
    Next bmI
    If BD_Opt%("unit", 6, 1, 60, -1, bmV) = 0 Then Exit Function
    bdUnit(bmFx) = bmV
    bdMorse(bmFx) = bmOut
    BD_BuildMorse% = -1
End Function

' The bnN-th (from 1) space-separated word of bnText.
Function BD_Nth$ (bnText As String, bnN As Integer)
    Dim bnI As Integer, bnS As Integer, bnE As Integer
    bnS = 1
    For bnI = 2 To bnN
        bnS = InStr(bnS, bnText, " ") + 1
    Next bnI
    bnE = InStr(bnS, bnText, " ")
    If bnE = 0 Then bnE = Len(bnText) + 1
    BD_Nth$ = Mid$(bnText, bnS, bnE - bnS)
End Function

' The image's number in BD_SPRITE_NAMES (from 1), 0 when there is none of that name.
Function BD_SpriteIdx% (bsiName As String)
    Dim bsiK As Integer, bsiN As Integer
    BD_SpriteIdx% = 0
    If Len(bsiName) = 0 Then Exit Function
    bsiN = 1
    For bsiK = 1 To Len(BD_SPRITE_NAMES)
        If Mid$(BD_SPRITE_NAMES, bsiK, 1) = " " Then bsiN = bsiN + 1
    Next bsiK
    For bsiK = 1 To bsiN
        If BD_Nth$(BD_SPRITE_NAMES, bsiK) = bsiName Then BD_SpriteIdx% = bsiK : Exit Function
    Next bsiK
End Function

' key=n[,n[,n]] (bvMin to bvMax numbers) into bvOut(0..), their count in bvCount. A missing key is fine (count 0, 1 returned).
Function BD_ParseList% (blKey As String, blMin As Integer, blMax As Integer, blOut() As Single, blCount As Integer)
    Dim blI As Integer, blV As String, blRest As String, blP As Integer
    BD_ParseList% = -1
    blCount = 0
    blOut(0) = 1
    blI = BD_KvIdx%(blKey)
    If blI < 0 Then Exit Function
    BD_ParseList% = 0
    blV = bdKvVal(blI)
    blRest = blV + ","
    Do While Len(blRest) > 0
        blP = InStr(blRest, ",")
        If blCount >= blMax Then BD_LineErr bdPVerb + " " + blKey + " takes at most " + LTrim$(Str$(blMax)) + " numbers, not '" + blV + "'" : Exit Function
        If BD_ParseNum%(Left$(blRest, blP - 1), blOut(blCount)) = 0 Then BD_LineErr bdPVerb + " " + blKey + " must be numbers separated by commas, not '" + blV + "'" : Exit Function
        blCount = blCount + 1
        blRest = Mid$(blRest, blP + 1)
    Loop
    If blCount < blMin Then BD_LineErr bdPVerb + " " + blKey + " needs at least " + LTrim$(Str$(blMin)) + " numbers, not '" + blV + "'" : Exit Function
    BD_ParseList% = -1
End Function

Function BD_BuildSprite% (bsFx As Integer)
    Dim bsL(0 To 2) As Single, bsN As Integer
    Dim bsV As Single, bsP(0 To 2) As Single, bsName As String, bsI As Integer, bsK As Integer
    BD_BuildSprite% = 0
    bsK = BD_KvIdx%("img")
    If bsK < 0 Then BD_LineErr "SPRITE needs img=name (known: " + BD_SPRITE_NAMES + ")" : Exit Function
    bsName = bdKvVal(bsK)
    bsI = BD_SpriteIdx%(bsName)
    If bsI = 0 Then BD_LineErr "SPRITE img '" + bsName + "' is not a known image (known: " + BD_SPRITE_NAMES + ")" : Exit Function
    bdImg(bsFx) = bsI
    If BD_ParseVec%("at", 2, BD_MARGIN, bsP()) = 0 Then Exit Function
    bdX(bsFx) = bsP(0) : bdY(bsFx) = bsP(1)
    If BD_ParseVec%("to", 2, BD_MARGIN, bsP()) = 0 Then Exit Function
    bdX2(bsFx) = bsP(0) : bdY2(bsFx) = bsP(1)
    If BD_Opt%("frames", 300, 1, 3600, -1, bsV) = 0 Then Exit Function
    bdFrames(bsFx) = bsV
    If BD_Opt%("rest", 0, 0, 3600, -1, bsV) = 0 Then Exit Function
    bdRest(bsFx) = bsV
    If BD_Opt%("pingpong", 0, 0, 1, -1, bsV) = 0 Then Exit Function
    bdPing(bsFx) = bsV
    If BD_Opt%("flip", 0, 0, 1, -1, bsV) = 0 Then Exit Function
    bdFlip(bsFx) = bsV
    If bdFlip(bsFx) <> 0 And bdPing(bsFx) = 0 Then BD_LineErr "SPRITE flip=1 needs pingpong=1 (it mirrors the return leg, and there is none without it)" : Exit Function
    If BD_ParseList%("scale", 1, 2, bsL(), bsN) = 0 Then Exit Function
    bdScaleA(bsFx) = bsL(0)
    If bsN = 2 Then bdScaleB(bsFx) = bsL(1) Else bdScaleB(bsFx) = bsL(0)
    If BD_KvIdx%("scale") < 0 Then bdScaleA(bsFx) = 1 : bdScaleB(bsFx) = 1
    If BD_KvIdx%("scale") >= 0 Then
        For bsK = 0 To bsN - 1
            If bsL(bsK) < 0.1 Or bsL(bsK) > 4 Then BD_LineErr "SPRITE scale must be 0.1 to 4, not '" + bdKvVal(BD_KvIdx%("scale")) + "'" : Exit Function
        Next bsK
    End If
    bdBobAmp(bsFx) = 0 : bdBobPer(bsFx) = 1 : bdBobAng(bsFx) = 270
    If BD_ParseList%("bob", 2, 3, bsL(), bsN) = 0 Then Exit Function
    If BD_KvIdx%("bob") >= 0 Then
        If bsL(0) < 0 Or bsL(0) > 64 Then BD_LineErr "SPRITE bob amplitude must be 0 to 64 pixels, not '" + bdKvVal(BD_KvIdx%("bob")) + "'" : Exit Function
        If bsL(1) < 2 Or bsL(1) > 3600 Then BD_LineErr "SPRITE bob period must be 2 to 3600 frames, not '" + bdKvVal(BD_KvIdx%("bob")) + "'" : Exit Function
        If bsN = 3 Then
            If bsL(2) < 0 Or bsL(2) > 360 Then BD_LineErr "SPRITE bob angle must be 0 to 360 degrees, not '" + bdKvVal(BD_KvIdx%("bob")) + "'" : Exit Function
            bdBobAng(bsFx) = bsL(2)
        End If
        bdBobAmp(bsFx) = bsL(0) : bdBobPer(bsFx) = bsL(1)
    End If
    bdKind(bsFx) = BD_KIND_SPRITE
    BD_BuildSprite% = -1
End Function

Function BD_BuildLaser% (blFx As Integer)
    Dim blV As Single, blP(0 To 2) As Single
    BD_BuildLaser% = 0
    If BD_ParseVec%("from", 3, 0, blP()) = 0 Then Exit Function
    bdX(blFx) = blP(0) : bdY(blFx) = blP(1) : bdD1(blFx) = blP(2)
    If BD_ParseVec%("to", 3, 0, blP()) = 0 Then Exit Function
    bdX2(blFx) = blP(0) : bdY2(blFx) = blP(1) : bdD2(blFx) = blP(2)
    If bdX(blFx) = bdX2(blFx) And bdY(blFx) = bdY2(blFx) And bdD1(blFx) = bdD2(blFx) Then BD_LineErr "LASER from and to are the same point" : Exit Function
    If BD_ParseColors%(blFx, 1) = 0 Then Exit Function
    If BD_Opt%("every", 60, 1, 3600, -1, blV) = 0 Then Exit Function
    bdEvery(blFx) = blV
    If BD_Opt%("jitter", 0, 0, 3599, -1, blV) = 0 Then Exit Function
    bdJitter(blFx) = blV
    If bdJitter(blFx) >= bdEvery(blFx) Then BD_LineErr "LASER jitter must be less than every (" + LTrim$(Str$(bdEvery(blFx))) + ")" : Exit Function
    If BD_Opt%("speed", 4, 0.1, 50, 0, blV) = 0 Then Exit Function
    bdSpeed(blFx) = blV
    If BD_Opt%("length", 12, 0.5, 200, 0, blV) = 0 Then Exit Function
    bdLaserLen(blFx) = blV
    bdKind(blFx) = BD_KIND_LASER
    BD_BuildLaser% = -1
End Function

' CAMERA fov=<degrees across the painting> horizon=<y of the horizon, painting pixels>, once per backdrop.
Sub BD_BuildCamera ()
    Dim bcV As Single, bcSet As Integer
    bcSet = bdSets - 1
    If bdSetCam(bcSet) Then BD_LineErr "CAMERA is given twice in backdrop '" + bdSetName(bcSet) + "'" : Exit Sub
    If BD_Opt%("fov", BD_CAM_FOV, 10, 120, 0, bcV) = 0 Then Exit Sub
    bdSetFov(bcSet) = bcV
    If BD_Opt%("horizon", BD_CAM_HORIZON, 0, BD_PAINT_H, 0, bcV) = 0 Then Exit Sub
    bdSetHor(bcSet) = bcV
    bdSetCam(bcSet) = -1
End Sub

' One effect line (verb in bdPVerb, key=value words already in the bdKv tables) into the next slot.
Sub BD_BuildEffect ()
    Dim bfFx As Integer, bfV As Single, bfI As Integer, bfAlive As Long
    bfFx = bdFxN
    bdFxLine(bfFx) = bdPLine
    bdFxSet(bfFx) = bdSets - 1
    bdMorse(bfFx) = ""
    If bdPVerb <> "SPRITE" And bdPVerb <> "LASER" Then
        If BD_ParseAt%(bfFx) = 0 Then Exit Sub
    End If
    If bdPVerb = "SPRITE" Then
        If BD_BuildSprite%(bfFx) = 0 Then Exit Sub
    ElseIf bdPVerb = "LASER" Then
        If BD_BuildLaser%(bfFx) = 0 Then Exit Sub
    ElseIf bdPVerb = "BLINK" Then
        If BD_ParseColors%(bfFx, 1) = 0 Then Exit Sub
        bdKind(bfFx) = BD_KIND_BLINK
        If BD_Opt%("size", 1, 0, 8, -1, bfV) = 0 Then Exit Sub
        bdSize(bfFx) = bfV
        If BD_Opt%("glow", 3, 0, 12, -1, bfV) = 0 Then Exit Sub
        bdGlow(bfFx) = bfV
        If BD_Opt%("rise", 0, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdRise(bfFx) = bfV
        If BD_Opt%("hold", 0, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdHold(bfFx) = bfV
        If BD_Opt%("fall", 0, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdFall(bfFx) = bfV
        If BD_Opt%("rest", 0, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdRest(bfFx) = bfV
        If BD_KvIdx%("morse") >= 0 Then
            If BD_BuildMorse%(bfFx) = 0 Then Exit Sub
        ElseIf BD_KvIdx%("unit") >= 0 Then
            BD_LineErr "BLINK unit only goes with morse=" : Exit Sub
        ElseIf bdRise(bfFx) + bdHold(bfFx) + bdFall(bfFx) + bdRest(bfFx) < 1 Then
            BD_LineErr "BLINK needs a loop: rise + hold + fall + rest must add up to at least 1 frame (for example hold=30 rest=30)" : Exit Sub
        End If
    Else
        If BD_ParseColors%(bfFx, BD_MAX_COL) = 0 Then Exit Sub
        bdKind(bfFx) = BD_KIND_SPARK
        If BD_Opt%("count", 3, 1, 16, -1, bfV) = 0 Then Exit Sub
        bdCount(bfFx) = bfV
        If BD_Opt%("every", 60, 1, 3600, -1, bfV) = 0 Then Exit Sub
        bdEvery(bfFx) = bfV
        If BD_Opt%("jitter", 0, 0, 3599, -1, bfV) = 0 Then Exit Sub
        bdJitter(bfFx) = bfV
        If bdJitter(bfFx) >= bdEvery(bfFx) Then BD_LineErr "SPARK jitter must be less than every (" + LTrim$(Str$(bdEvery(bfFx))) + ")" : Exit Sub
        If BD_Opt%("size", 1, 1, 6, -1, bfV) = 0 Then Exit Sub
        bdSize(bfFx) = bfV
        If BD_Opt%("speed", 0.6, 0, 10, 0, bfV) = 0 Then Exit Sub
        bdSpeed(bfFx) = bfV
        If BD_Opt%("gravity", 0.05, -1, 1, 0, bfV) = 0 Then Exit Sub
        bdGrav(bfFx) = bfV
        If BD_Opt%("life", 20, 1, 600, -1, bfV) = 0 Then Exit Sub
        bdLife(bfFx) = bfV
        If BD_Opt%("dir", 270, 0, 360, 0, bfV) = 0 Then Exit Sub
        bdDir(bfFx) = bfV
        If BD_Opt%("spread", 120, 0, 360, 0, bfV) = 0 Then Exit Sub
        bdSpread(bfFx) = bfV
    End If
    If BD_Opt%("phase", 0, 0, 9999, -1, bfV) = 0 Then Exit Sub
    bdPhase(bfFx) = bfV
    bdFxN = bdFxN + 1
    bdSetN(bdSets - 1) = bdSetN(bdSets - 1) + 1
    If bdKind(bfFx) = BD_KIND_SPARK Then
        bfAlive = BD_SparksAlive&(bdSets - 1)
        If bfAlive > BD_POOL Then BD_LineErr "backdrop '" + bdSetName(bdSets - 1) + "' could have " + LTrim$(Str$(bfAlive)) + " sparks alive at once, the pool holds " + LTrim$(Str$(BD_POOL)) + " (lower count or life, or raise every)"
    End If
End Sub

' A "backdrop:<name>" header.
Sub BD_BeginSet (bbName As String)
    Dim bbI As Integer, bbC As String
    If Len(bbName) = 0 Or Len(bbName) > 16 Then BD_LineErr "backdrop needs a name of 1 to 16 letters, digits or _" : Exit Sub
    For bbI = 1 To Len(bbName)
        bbC = Mid$(bbName, bbI, 1)
        If Not ((bbC >= "a" And bbC <= "z") Or (bbC >= "0" And bbC <= "9") Or bbC = "_") Then BD_LineErr "backdrop name '" + bbName + "' may hold only lower-case letters, digits and _" : Exit Sub
    Next bbI
    If BD_Find%(bbName) >= 0 Then BD_LineErr "backdrop '" + bbName + "' is listed twice" : Exit Sub
    If bdSets >= BD_MAX_SETS Then BD_LineErr "more than BD_MAX_SETS (" + LTrim$(Str$(BD_MAX_SETS)) + ") backdrops" : Exit Sub
    bdSetName(bdSets) = bbName : bdSetFrom(bdSets) = bdFxN : bdSetN(bdSets) = 0 : bdSetLine(bdSets) = bdPLine
    bdSetFov(bdSets) = BD_CAM_FOV : bdSetHor(bdSets) = BD_CAM_HORIZON : bdSetCam(bdSets) = 0
    bdSets = bdSets + 1
End Sub

Function BD_Find% (bfName As String)
    Dim bfI As Integer
    BD_Find% = -1
    For bfI = 0 To bdSets - 1
        If bdSetName(bfI) = bfName Then BD_Find% = bfI : Exit Function
    Next bfI
End Function

' Parses file text into the tables. 1 = clean; 0 = problems listed in bdErrors, and then the
' tables are left empty, so a broken file draws nothing rather than half of something.
Function BD_Parse% (bpSrc As String)
    Dim bpI As Long, bpNL As Long, bpRaw As String, bpLine As String, bpSc As Integer
    Dim bpW(0 To BD_MAX_WORDS - 1) As String, bpN As Integer, bpVerb As String
    Dim bpK As Integer, bpEq As Integer, bpKey As String, bpKeys As String, bpHdr As Integer
    bdSets = 0 : bdFxN = 0 : bdErrors = "" : bdCur = -1
    bpI = 1 : bdPLine = 0 : bpHdr = 0
    Do While bpI <= Len(bpSrc)
        bpNL = InStr(bpI, bpSrc, Chr$(10))
        If bpNL = 0 Then bpNL = Len(bpSrc) + 1
        bpRaw = Mid$(bpSrc, bpI, bpNL - bpI)
        bpI = bpNL + 1
        bdPLine = bdPLine + 1 : bdPBad = 0
        If Right$(bpRaw, 1) = Chr$(13) Then bpRaw = Left$(bpRaw, Len(bpRaw) - 1)
        bpSc = InStr(bpRaw, ";")
        If bpSc > 0 Then bpRaw = Left$(bpRaw, bpSc - 1)
        bpLine = LTrim$(RTrim$(bpRaw))
        If Len(bpLine) = 0 Then GoTo bpNext
        bpN = BD_Words%(bpLine, bpW())
        If bpN > BD_MAX_WORDS Then BD_LineErr "more than " + LTrim$(Str$(BD_MAX_WORDS - 1)) + " options on one line" : GoTo bpNext
        If InStr(bpW(0), ":") > 0 Then
            If LCase$(Left$(bpW(0), 9)) <> "backdrop:" Then BD_LineErr "unknown header '" + bpW(0) + "' (backdrop:<name>)" : GoTo bpNext
            If bpN > 1 Then BD_LineErr "a backdrop header takes only its name" : GoTo bpNext
            BD_BeginSet Mid$(bpW(0), 10)
            bpHdr = (bdPBad = 0)
            GoTo bpNext
        End If
        bpVerb = UCase$(bpW(0))
        bpKeys = BD_KeysOf$(bpVerb)
        If Len(bpKeys) = 0 Then BD_LineErr "unknown effect '" + bpW(0) + "' (BLINK SPARK SPRITE LASER CAMERA)" : GoTo bpNext
        If bdSets = 0 Or bpHdr = 0 Then BD_LineErr bpVerb + " before any backdrop: header" : GoTo bpNext
        bdKvN = 0
        For bpK = 1 To bpN - 1
            bpEq = InStr(bpW(bpK), "=")
            If bpEq < 2 Or bpEq = Len(bpW(bpK)) Then BD_LineErr "expected key=value, got '" + bpW(bpK) + "'" : GoTo bpNext
            bpKey = LCase$(Left$(bpW(bpK), bpEq - 1))
            If InStr(" " + bpKeys + " ", " " + bpKey + " ") = 0 Then BD_LineErr "unknown " + bpVerb + " key '" + bpKey + "' (" + bpKeys + ")" : GoTo bpNext
            If BD_KvIdx%(bpKey) >= 0 Then BD_LineErr bpVerb + " key '" + bpKey + "' is given twice" : GoTo bpNext
            bdKvKey(bdKvN) = bpKey : bdKvVal(bdKvN) = LCase$(Mid$(bpW(bpK), bpEq + 1)) : bdKvN = bdKvN + 1
        Next bpK
        bdPVerb = bpVerb
        If bpVerb = "CAMERA" Then BD_BuildCamera : GoTo bpNext
        If bdFxN >= BD_MAX_FX Then
            If InStr(bdErrors, "more than BD_MAX_FX") = 0 Then BD_LineErr "more than BD_MAX_FX (" + LTrim$(Str$(BD_MAX_FX)) + ") effects"
            GoTo bpNext
        End If
        bdPVerb = bpVerb
        BD_BuildEffect
        bpNext:
    Loop
    If Len(bdErrors) > 0 Then bdSets = 0 : bdFxN = 0
    BD_Parse% = (Len(bdErrors) = 0)
End Function

' Static checks on a parsed file: "" when sound, else one problem per line. Parse problems come first.
'   - every backdrop names a painted screen (title, emperor or dock) and has at least one effect
Function BD_Validate$ ()
    Dim bvI As Integer, bvOut As String
    bvOut = bdErrors
    For bvI = 0 To bdSets - 1
        If InStr(" title emperor dock ", " " + bdSetName(bvI) + " ") = 0 Then bvOut = bvOut + "line " + LTrim$(Str$(bdSetLine(bvI))) + ": backdrop '" + bdSetName(bvI) + "' is not a painted screen (title emperor dock)" + Chr$(10)
        If bdSetN(bvI) = 0 Then bvOut = bvOut + "line " + LTrim$(Str$(bdSetLine(bvI))) + ": backdrop '" + bdSetName(bvI) + "' has no effects" + Chr$(10)
    Next bvI
    For bvI = 0 To bdFxN - 1
        If bdKind(bvI) = BD_KIND_LASER Then
            If BD_LaserTravel!(bvI) / bdEvery(bvI) >= BD_LASER_BOLTS Then bvOut = bvOut + "line " + LTrim$(Str$(bdFxLine(bvI))) + ": LASER takes " + LTrim$(Str$(Int(BD_LaserTravel!(bvI)))) + " frames to cross but fires every " + LTrim$(Str$(bdEvery(bvI))) + ", so more than " + LTrim$(Str$(BD_LASER_BOLTS - 1)) + " bolts would be in flight (raise every or speed)" + Chr$(10)
        End If
    Next bvI
    BD_Validate$ = bvOut
End Function

' --- timing ---

' A number 0 <= n < 1 from (frame, effect, salt) alone: a fixed mixing of the three, no state.
' Doubles hold every product below exactly (each factor is cut to 20 bits, and 2^53 is the limit).
Function BD_Hash! (bhFrame As Long, bhFx As Long, bhSalt As Long)
    Dim bhH As Double, bhHi As Double, bhLo As Double
    bhH = (bhFrame And 1048575) * 1103515245# + (bhFx And 1048575) * 12345# + (bhSalt And 1048575) * 2654435761#
    bhH = bhH - Int(bhH / 4294967296#) * 4294967296#
    bhH = bhH * 1664525# + 1013904223#
    bhH = bhH - Int(bhH / 4294967296#) * 4294967296#
    bhHi = Int(bhH / 65536) : bhLo = bhH - bhHi * 65536
    bhH = bhLo * 65536 + (CLng(bhHi) Xor CLng(bhLo))
    bhH = bhH * 69069# + 1
    bhH = bhH - Int(bhH / 4294967296#) * 4294967296#
    BD_Hash! = bhH / 4294967296#
End Function

' How lit a BLINK is on frame bbFrame: 0..1, from its envelope (rise, hold, fall, rest), eased with a half cosine.
Function BD_BlinkLevel! (bbFx As Integer, bbFrame As Long)
    Dim bbPer As Long, bbP As Long
    If Len(bdMorse(bbFx)) > 0 Then BD_BlinkLevel! = BD_MorseLevel!(bbFx, bbFrame) : Exit Function
    bbPer = bdRise(bbFx) + bdHold(bbFx) + bdFall(bbFx) + bdRest(bbFx)
    bbP = (bbFrame + bdPhase(bbFx)) Mod bbPer
    If bbP < bdRise(bbFx) Then BD_BlinkLevel! = 0.5 - 0.5 * Cos(3.14159265 * bbP / bdRise(bbFx)) : Exit Function
    bbP = bbP - bdRise(bbFx)
    If bbP < bdHold(bbFx) Then BD_BlinkLevel! = 1 : Exit Function
    bbP = bbP - bdHold(bbFx)
    If bbP < bdFall(bbFx) Then BD_BlinkLevel! = 0.5 + 0.5 * Cos(3.14159265 * bbP / bdFall(bbFx)) : Exit Function
    BD_BlinkLevel! = 0
End Function

' 0..1 brightness of a Morse BLINK: each flash is eased in over `rise` frames and out over `fall`, shortest of the two ramps wins.
Function BD_MorseLevel! (bmFx As Integer, bmFrame As Long)
    Dim bmU As Long, bmN As Long, bmP As Long, bmSlot As Long, bmS0 As Long, bmS1 As Long, bmT As Long, bmLen As Long, bmLv As Single, bmR As Single
    bmU = bdUnit(bmFx) : bmN = Len(bdMorse(bmFx))
    bmP = (bmFrame + bdPhase(bmFx)) Mod (bmN * bmU + bdRest(bmFx))
    BD_MorseLevel! = 0
    If bmP >= bmN * bmU Then Exit Function
    bmSlot = bmP \ bmU + 1
    If Mid$(bdMorse(bmFx), bmSlot, 1) = "0" Then Exit Function
    bmS0 = bmSlot : bmS1 = bmSlot
    Do While bmS0 > 1
        If Mid$(bdMorse(bmFx), bmS0 - 1, 1) = "0" Then Exit Do
        bmS0 = bmS0 - 1
    Loop
    Do While bmS1 < bmN
        If Mid$(bdMorse(bmFx), bmS1 + 1, 1) = "0" Then Exit Do
        bmS1 = bmS1 + 1
    Loop
    bmT = bmP - (bmS0 - 1) * bmU
    bmLen = (bmS1 - bmS0 + 1) * bmU
    bmLv = 1
    If bdRise(bmFx) > 0 And bmT < bdRise(bmFx) Then bmLv = 0.5 - 0.5 * Cos(3.14159265 * bmT / bdRise(bmFx))
    If bdFall(bmFx) > 0 And bmT >= bmLen - bdFall(bmFx) Then
        bmR = 0.5 + 0.5 * Cos(3.14159265 * (bmT - (bmLen - bdFall(bmFx))) / bdFall(bmFx))
        If bmR < bmLv Then bmLv = bmR
    End If
    BD_MorseLevel! = bmLv
End Function

' Where SPRITE bsFx is on frame bsFrame, in painting pixels. 0 when it is not on the painting (the rest
' after a one-way trip; with pingpong it waits at the ends instead). bsFlip = 1 on the return leg when flip=1.
Function BD_SpriteAt% (bsFx As Integer, bsFrame As Long, bsX As Single, bsY As Single, bsFlip As Integer)
    Dim bsSc As Single, bsDX As Single, bsDY As Single
    BD_SpriteAt% = BD_SpriteState%(bsFx, bsFrame, bsX, bsY, bsFlip, bsSc, bsDX, bsDY)
End Function

' BD_SpriteAt plus the sprite's size (scale=, linear along the path, so it follows the point on the return
' leg) and its hop offset in painting pixels (bob=, already multiplied by the size). The hop counts the frames
' of the current leg, so it stands still (offset 0) while the sprite waits at an end.
Function BD_SpriteState% (bsFx As Integer, bsFrame As Long, bsX As Single, bsY As Single, bsFlip As Integer, bsScale As Single, bsDX As Single, bsDY As Single)
    Dim bsP As Long, bsT As Single, bsF As Long, bsR As Long, bsLeg As Long, bsMoving As Integer, bsOff As Single, bsA As Single
    bsF = bdFrames(bsFx) : bsR = bdRest(bsFx)
    bsFlip = 0 : bsMoving = -1 : bsLeg = 0
    BD_SpriteState% = 0
    bsDX = 0 : bsDY = 0 : bsScale = 1
    If bdPing(bsFx) Then
        bsP = (bsFrame + bdPhase(bsFx)) Mod (2 * (bsF + bsR))
        If bsP < bsF Then
            bsT = bsP / bsF : bsLeg = bsP
        ElseIf bsP < bsF + bsR Then
            bsT = 1 : bsMoving = 0
        ElseIf bsP < 2 * bsF + bsR Then
            bsT = 1 - (bsP - bsF - bsR) / bsF
            bsLeg = bsP - bsF - bsR
            bsFlip = bdFlip(bsFx)
        Else
            bsT = 0 : bsMoving = 0
        End If
    Else
        bsP = (bsFrame + bdPhase(bsFx)) Mod (bsF + bsR)
        If bsP >= bsF Then Exit Function
        bsT = bsP / bsF : bsLeg = bsP
    End If
    bsX = bdX(bsFx) + (bdX2(bsFx) - bdX(bsFx)) * bsT
    bsY = bdY(bsFx) + (bdY2(bsFx) - bdY(bsFx)) * bsT
    bsScale = bdScaleA(bsFx) + (bdScaleB(bsFx) - bdScaleA(bsFx)) * bsT
    If bsMoving And bdBobAmp(bsFx) > 0 Then
        bsOff = bdBobAmp(bsFx) * Abs(Sin(3.14159265 * bsLeg / bdBobPer(bsFx))) * bsScale
        bsA = bdBobAng(bsFx) * 0.0174533
        bsDX = Cos(bsA) * bsOff : bsDY = Sin(bsA) * bsOff
    End If
    BD_SpriteState% = -1
End Function

' --- the painting's fixed camera ---
' A pinhole camera at depth -F looking along +depth, the vanishing point at (BD_CAM_VPX, horizon): F is the
' focal length in painting pixels, so fov is the angle the painting's 320 pixels span at depth 0. A LASER's
' x,y,depth names where a point shows on the painting AT that depth: BD_World finds the world point that
' projects there, so depth never moves x,y, it only sets the scale (F / (F + depth)) and the perspective.

Function BD_CamF! (bcSet As Integer)
    BD_CamF! = (BD_PAINT_W / 2) / Tan(bdSetFov(bcSet) * 0.5 * 3.14159265 / 180)
End Function

Sub BD_World (bwSet As Integer, bwX As Single, bwY As Single, bwD As Single, bwWX As Single, bwWY As Single, bwWZ As Single)
    Dim bwK As Single
    bwK = (BD_CamF!(bwSet) + bwD) / BD_CamF!(bwSet)
    bwWX = BD_CAM_VPX + (bwX - BD_CAM_VPX) * bwK
    bwWY = bdSetHor(bwSet) + (bwY - bdSetHor(bwSet)) * bwK
    bwWZ = bwD
End Sub

' Row-major clip matrix bcmM(0 To 3, 0 To 3) of the camera: with the usual divide by row 3, a world point lands
' on a BD_PAINT_W x BD_PAINT_H screen (the same layout as the game's vpMat, so the bolt renderer takes it).
Sub BD_CamMatrix (bcmSet As Integer, bcmM() As Single)
    Dim bcmF As Single, bcmI As Integer, bcmJ As Integer
    bcmF = BD_CamF!(bcmSet)
    For bcmI = 0 To 3
        For bcmJ = 0 To 3 : bcmM(bcmI, bcmJ) = 0 : Next bcmJ
    Next bcmI
    bcmM(0, 0) = bcmF / (BD_PAINT_W / 2) : bcmM(0, 3) = -BD_CAM_VPX * bcmF / (BD_PAINT_W / 2)
    bcmM(1, 1) = -bcmF / (BD_PAINT_H / 2) : bcmM(1, 2) = 1 - bdSetHor(bcmSet) / (BD_PAINT_H / 2) : bcmM(1, 3) = bcmF
    bcmM(2, 2) = 1
    bcmM(3, 2) = 1 : bcmM(3, 3) = bcmF
End Sub

' Length of a LASER's path in world units, and how many frames a bolt takes to cross it.
Function BD_LaserPath! (blpFx As Integer)
    Dim blpX1 As Single, blpY1 As Single, blpZ1 As Single, blpX2 As Single, blpY2 As Single, blpZ2 As Single
    BD_World bdFxSet(blpFx), bdX(blpFx), bdY(blpFx), bdD1(blpFx), blpX1, blpY1, blpZ1
    BD_World bdFxSet(blpFx), bdX2(blpFx), bdY2(blpFx), bdD2(blpFx), blpX2, blpY2, blpZ2
    BD_LaserPath! = Sqr((blpX2 - blpX1) ^ 2 + (blpY2 - blpY1) ^ 2 + (blpZ2 - blpZ1) ^ 2)
End Function

Function BD_LaserTravel! (bltFx As Integer)
    BD_LaserTravel! = BD_LaserPath!(bltFx) / bdSpeed(bltFx)
End Function

' Whether the bhJ-th newest bolt (0 = newest) of LASER bhFx is in flight on frame bhFrame; bhDist is how far
' along the path (world units) its head has gone. Bolt k leaves on frame k * every (+ a hashed delay up to jitter).
Function BD_LaserHead% (bhFx As Integer, bhFrame As Long, bhJ As Integer, bhDist As Single)
    Dim bhRel As Long, bhK As Long, bhAge As Long
    BD_LaserHead% = 0
    bhRel = bhFrame + bdPhase(bhFx)
    bhK = bhRel \ bdEvery(bhFx) - bhJ
    If bhK < 0 Then Exit Function
    bhAge = bhRel - (bhK * bdEvery(bhFx) + Int(BD_Hash!(bhK, bhFx, 2000) * (bdJitter(bhFx) + 1)))
    If bhAge < 0 Then Exit Function
    bhDist = bhAge * bdSpeed(bhFx)
    If bhDist > BD_LaserPath!(bhFx) Then Exit Function
    BD_LaserHead% = -1
End Function

Function BD_SparksLive% ()
    Dim bsI As Integer, bsN As Integer
    For bsI = 0 To BD_POOL - 1
        If bdPAlive(bsI) Then bsN = bsN + 1
    Next bsI
    BD_SparksLive% = bsN
End Function

Sub BD_Spawn (bsFx As Integer, bsFrame As Long)
    Dim bsP As Integer, bsSlot As Integer, bsAng As Single, bsSp As Single, bsK As Long
    For bsP = 0 To bdCount(bsFx) - 1
        bsSlot = bdPFirst
        Do While bsSlot < BD_POOL
            If bdPAlive(bsSlot) = 0 Then Exit Do
            bsSlot = bsSlot + 1
        Loop
        If bsSlot >= BD_POOL Then bdPDropped = bdPDropped + 1 : GoTo bsNext
        bsK = bsP * 4
        bsAng = (bdDir(bsFx) + (BD_Hash!(bsFrame, bsFx, bsK) - 0.5) * bdSpread(bsFx)) * 0.0174533
        bsSp = bdSpeed(bsFx) * (0.5 + 0.5 * BD_Hash!(bsFrame, bsFx, bsK + 1))
        bdPAlive(bsSlot) = -1
        bdPFirst = bsSlot + 1
        bdPX(bsSlot) = bdX(bsFx) : bdPY(bsSlot) = bdY(bsFx)
        bdPVX(bsSlot) = Cos(bsAng) * bsSp : bdPVY(bsSlot) = Sin(bsAng) * bsSp
        bdPAge(bsSlot) = 0 : bdPLife(bsSlot) = bdLife(bsFx)
        bdPCol(bsSlot) = bdCol(bsFx, Int(BD_Hash!(bsFrame, bsFx, bsK + 2) * bdColN(bsFx)))
        bdPFx(bsSlot) = bsFx
        bsNext:
    Next bsP
End Sub

' Frame bsFrame of the current backdrop: the sparks fly one frame on and the bursts due now start.
Sub BD_Tick (btFrame As Long)
    Dim btI As Integer, btFx As Integer, btRel As Long, btK As Long, btOff As Long
    For btI = 0 To BD_POOL - 1
        If bdPAlive(btI) Then
            bdPAge(btI) = bdPAge(btI) + 1
            If bdPAge(btI) >= bdPLife(btI) Then
                bdPAlive(btI) = 0
                If btI < bdPFirst Then bdPFirst = btI
            Else
                bdPX(btI) = bdPX(btI) + bdPVX(btI)
                bdPY(btI) = bdPY(btI) + bdPVY(btI)
                bdPVY(btI) = bdPVY(btI) + bdGrav(bdPFx(btI))
            End If
        End If
    Next btI
    If bdCur < 0 Then Exit Sub
    For btFx = bdSetFrom(bdCur) To bdSetFrom(bdCur) + bdSetN(bdCur) - 1
        If bdKind(btFx) = BD_KIND_SPARK Then
            btRel = btFrame - bdPhase(btFx)
            If btRel >= 0 Then
                btK = btRel \ bdEvery(btFx)
                btOff = Int(BD_Hash!(btK, btFx, 1000) * (bdJitter(btFx) + 1))
                If btRel = btK * bdEvery(btFx) + btOff Then BD_Spawn btFx, btFrame
            End If
        End If
    Next btFx
End Sub

' Starts a screen's loop over: frame 0, no sparks in flight.
Sub BD_Reset (brName As String)
    Dim brI As Integer
    For brI = 0 To BD_POOL - 1 : bdPAlive(brI) = 0 : Next brI
    bdPFirst = 0
    bdCur = BD_Find%(brName)
    bdFrame = 0
    BD_Tick 0
End Sub

' Call once per drawn frame of a painted screen with the main loop's frame number. The first call,
' a change of backdrop, or any gap in the frames (the screen was left and entered again) starts
' the loop at frame 0; a second call in the same main-loop frame changes nothing.
Sub BD_Advance (baMain As Long, baName As String)
    Dim baSame As Integer
    baSame = (bdCur >= 0)
    If baSame Then baSame = (bdSetName(bdCur) = baName)
    If baMain = bdLastMain And baSame Then Exit Sub
    If baSame And baMain = bdLastMain + 1 Then
        bdFrame = bdFrame + 1
        BD_Tick bdFrame
    Else
        BD_Reset baName
    End If
    bdLastMain = baMain
End Sub

' --- wrapping the parse problems for the dev screen ---

' Breaks bwtText (lines ended by Chr$(10)) into rows of at most bwtWidth characters, at spaces; a
' word longer than a row is cut. The first bwtMax rows go to bwtOut(0..); returns how many rows
' the whole text needs, which is more than bwtMax when some did not fit.
Function BD_WrapText% (bwtText As String, bwtWidth As Integer, bwtOut() As String, bwtMax As Integer)
    Dim bwtP As Long, bwtNL As Long, bwtRest As String, bwtN As Integer, bwtCut As Integer, bwtRow As String
    bwtP = 1
    Do While bwtP <= Len(bwtText)
        bwtNL = InStr(bwtP, bwtText, Chr$(10))
        If bwtNL = 0 Then bwtNL = Len(bwtText) + 1
        bwtRest = Mid$(bwtText, bwtP, bwtNL - bwtP)
        bwtP = bwtNL + 1
        Do
            If Len(bwtRest) <= bwtWidth Then
                bwtRow = bwtRest : bwtRest = ""
            Else
                bwtCut = bwtWidth
                Do While bwtCut > 0
                    If Mid$(bwtRest, bwtCut + 1, 1) = " " Then Exit Do
                    bwtCut = bwtCut - 1
                Loop
                If bwtCut = 0 Then bwtCut = bwtWidth
                bwtRow = RTrim$(Left$(bwtRest, bwtCut)) : bwtRest = LTrim$(Mid$(bwtRest, bwtCut + 1))
            End If
            If bwtN < bwtMax Then bwtOut(bwtN) = bwtRow
            bwtN = bwtN + 1
        Loop While Len(bwtRest) > 0
    Loop
    BD_WrapText% = bwtN
End Function
