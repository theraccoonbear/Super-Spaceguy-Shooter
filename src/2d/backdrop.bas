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
'       BLINK at=x,y color=rrggbb [size=1] [glow=3] [rise=0] [hold=30] [fall=0] [rest=30] [phase=0]
'       SPARK at=x,y color=rrggbb[,rrggbb...] [count=3] [every=60] [speed=0.6] [gravity=0.05]
'             [life=20] [dir=270] [spread=120] [phase=0] [jitter=0] [size=1]
' Positions are pixels on the 320x240 painting. Frames run at 60 per second.
'   BLINK  a light on a looping envelope: it fades up over `rise` frames, stays at full for `hold`,
'          fades down over `fall`, and is dark for `rest`; the loop is the sum of the four (at
'          least 1 frame). Fades are eased (half a cosine). rise=0 fall=0 is a hard blink. size is the
'          radius of the lit core in pixels.
'   SPARK  every `every` frames, `count` sparks leave the point at `speed` px/frame, spread over
'          `spread` degrees around `dir` (0 = right, 90 = down, 270 = up), pulled down by
'          `gravity`, and fade out over `life` frames. Each takes one of the colours.
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
' BD_BlinkLevel!(fx,f) 0..1 brightness of a BLINK at frame f
' Shared state is bd*; every routine's locals carry their own two-letter prefix

Const BD_MAX_FX = 96          ' effects in the whole file
Const BD_MAX_SETS = 12        ' backdrops in the whole file
Const BD_MAX_COL = 4          ' colours on one effect
Const BD_POOL = 64            ' sparks alive at once
Const BD_MAX_WORDS = 16
Const BD_KIND_BLINK = 1
Const BD_KIND_SPARK = 2
Const BD_PAINT_W = 320
Const BD_PAINT_H = 240

Dim Shared bdSetName(0 To BD_MAX_SETS - 1) As String
Dim Shared bdSetFrom(0 To BD_MAX_SETS - 1) As Integer    ' first effect
Dim Shared bdSetN(0 To BD_MAX_SETS - 1) As Integer       ' effects
Dim Shared bdSetLine(0 To BD_MAX_SETS - 1) As Integer
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
        Case "BLINK" : BD_KeysOf$ = "at color size glow rise hold fall rest phase"
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

' at=x,y inside the painting.
Function BD_ParseAt% (baFx As Integer)
    Dim baI As Integer, baC As Integer, baX As Single, baY As Single, baV As String
    BD_ParseAt% = 0
    baI = BD_KvIdx%("at")
    If baI < 0 Then BD_LineErr bdPVerb + " needs at=x,y" : Exit Function
    baV = bdKvVal(baI)
    baC = InStr(baV, ",")
    If baC = 0 Or InStr(baC + 1, baV, ",") > 0 Then BD_LineErr bdPVerb + " at must be x,y": Exit Function
    If BD_ParseNum%(Left$(baV, baC - 1), baX) = 0 Or BD_ParseNum%(Mid$(baV, baC + 1), baY) = 0 Then BD_LineErr bdPVerb + " at must be x,y in pixels, not '" + baV + "'" : Exit Function
    If baX < 0 Or baX > BD_PAINT_W Or baY < 0 Or baY > BD_PAINT_H Then BD_LineErr bdPVerb + " at=" + baV + " is off the " + LTrim$(Str$(BD_PAINT_W)) + "x" + LTrim$(Str$(BD_PAINT_H)) + " painting" : Exit Function
    bdX(baFx) = baX : bdY(baFx) = baY
    BD_ParseAt% = -1
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

' One effect line (verb in bdPVerb, key=value words already in the bdKv tables) into the next slot.
Sub BD_BuildEffect ()
    Dim bfFx As Integer, bfV As Single, bfI As Integer, bfAlive As Long
    bfFx = bdFxN
    bdFxLine(bfFx) = bdPLine
    If BD_ParseAt%(bfFx) = 0 Then Exit Sub
    If bdPVerb = "BLINK" Then
        If BD_ParseColors%(bfFx, 1) = 0 Then Exit Sub
        bdKind(bfFx) = BD_KIND_BLINK
        If BD_Opt%("size", 1, 0, 8, -1, bfV) = 0 Then Exit Sub
        bdSize(bfFx) = bfV
        If BD_Opt%("glow", 3, 0, 12, -1, bfV) = 0 Then Exit Sub
        bdGlow(bfFx) = bfV
        If BD_Opt%("rise", 0, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdRise(bfFx) = bfV
        If BD_Opt%("hold", 30, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdHold(bfFx) = bfV
        If BD_Opt%("fall", 0, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdFall(bfFx) = bfV
        If BD_Opt%("rest", 30, 0, 600, -1, bfV) = 0 Then Exit Sub
        bdRest(bfFx) = bfV
        If bdRise(bfFx) + bdHold(bfFx) + bdFall(bfFx) + bdRest(bfFx) < 1 Then BD_LineErr "BLINK rise + hold + fall + rest must be at least 1 frame" : Exit Sub
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
        If Len(bpKeys) = 0 Then BD_LineErr "unknown effect '" + bpW(0) + "' (BLINK SPARK)" : GoTo bpNext
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
    bbPer = bdRise(bbFx) + bdHold(bbFx) + bdFall(bbFx) + bdRest(bbFx)
    bbP = (bbFrame + bdPhase(bbFx)) Mod bbPer
    If bbP < bdRise(bbFx) Then BD_BlinkLevel! = 0.5 - 0.5 * Cos(3.14159265 * bbP / bdRise(bbFx)) : Exit Function
    bbP = bbP - bdRise(bbFx)
    If bbP < bdHold(bbFx) Then BD_BlinkLevel! = 1 : Exit Function
    bbP = bbP - bdHold(bbFx)
    If bbP < bdFall(bbFx) Then BD_BlinkLevel! = 0.5 + 0.5 * Cos(3.14159265 * bbP / bdFall(bbFx)) : Exit Function
    BD_BlinkLevel! = 0
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
        bsSlot = 0
        Do While bsSlot < BD_POOL
            If bdPAlive(bsSlot) = 0 Then Exit Do
            bsSlot = bsSlot + 1
        Loop
        If bsSlot >= BD_POOL Then bdPDropped = bdPDropped + 1 : GoTo bsNext
        bsK = bsP * 4
        bsAng = (bdDir(bsFx) + (BD_Hash!(bsFrame, bsFx, bsK) - 0.5) * bdSpread(bsFx)) * 0.0174533
        bsSp = bdSpeed(bsFx) * (0.5 + 0.5 * BD_Hash!(bsFrame, bsFx, bsK + 1))
        bdPAlive(bsSlot) = -1
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
