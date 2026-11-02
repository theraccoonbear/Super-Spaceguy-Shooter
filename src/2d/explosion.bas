' explosion.bas -- data-defined 3D particle explosions: parse, validate, pool, simulate (#198)
'
' Headless: no drawing and no game state. assets/explosions.txt describes each explosion as layers
' of BURST lines (flash, fireball, embers, shock ring, smoke, delayed secondary bursts) plus a
' SHAKE; XP_Spawn starts one at a world position and XP_Update advances every particle one frame.
' Particles live in world space. Units are world units and frames; only maxpx and minpx are pixels.
' Drawing (projection, depth test, dev tooling) is a later change and reads the XP_ tables.
'
' File format (; starts a comment; verbs are case-insensitive, keys are lower case):
'   explosion:<name>
'       SHAKE frames=N
'       BURST [count=1] [delay=0] [at=0,0,0] [scatter=0] [speed=0] [shape=sphere] [dir=0,1,0]
'             [spread=30] [drag=1] [gravity=0] [inherit=0] [life=30] [size=0.1] [glow=0]
'             ramp=c1,c2,... | color=c1,c2,... [maxpx=0] [minpx=1] [occlude=1]
'   Numeric keys count, delay, scatter, speed, drag, gravity, inherit, life, size and glow take a
'   range a..b: each particle (count and delay: each spawn) picks a value from the hash.
'   count     particles in the layer         delay    frames after XP_Spawn the layer starts
'   at        offset from the spawn point     scatter  radius of the ball the start points fill
'   speed     world units per frame at launch shape   sphere (every direction), ring (the plane
'             perpendicular to the camera's forward axis: the camera looks along +X, so YZ) or
'             cone (about dir, half-angle spread degrees)
'   drag      velocity multiplier per frame   gravity  taken off vy per frame
'   inherit   share of the victim's velocity added to the launch velocity
'   life      frames                          size=a[,b] world radius, a at birth and b at death
'   glow      halo radius as a multiple of size
'   ramp      gradient over the particle's life; color  one colour per particle
'   maxpx minpx   pixel clamps on the drawn size (maxpx=0: no upper clamp)
'   occlude   1: ships in front hide the particle, 0: drawn over everything
' Each frame: v *= drag, vy -= gravity, p += v. Scale in XP_Spawn multiplies size, speed, at and
' scatter.
'
' Randomness is BD_Hash! keyed on the spawn serial, the layer and the particle: no RNG stream is
' read, so the game and a seeded run are unaffected, and a spawn always gives the same particles.
' Needs src/2d/backdrop.bas first (BD_ParseNum%, BD_ParseHex%, BD_Hash!).
'
' XP_Parse%(src)       1 when the file loaded clean, else 0 with xpErrors (one "line N: ..." each)
' XP_Validate$()       "" when sound, else one problem per line (parse problems first)
' XP_Find%(name)       the explosion's id, -1 when it has none
' XP_Spawn id,x,y,z,vx,vy,vz,scale   start an explosion; (vx,vy,vz) is the victim's velocity
' XP_Update            one frame
' XP_Clear             empty the pool and the pending queue
' Shared state is xd (definitions), xb (burst layers), xn (pending layers) and xp (particles);
' every routine's locals carry their own two-letter prefix

Const XP_POOL = 768
Const XP_MAX_DEF = 16
Const XP_MAX_BURST = 64
Const XP_MAX_PER_DEF = 12
Const XP_MAX_PENDING = 32
Const XP_MAX_DELAYED = 8
Const XP_MAX_COUNT = 300
Const XP_GLOW_BUDGET = 3000
Const XP_MAX_COLORS = 6
Const XP_MAX_WORDS = 40
Const XP_SHAPE_SPHERE = 0
Const XP_SHAPE_RING = 1
Const XP_SHAPE_CONE = 2
Const XP_REQUIRED = "boss enemy"

Dim Shared xdName(0 To XP_MAX_DEF - 1) As String
Dim Shared xdFrom(0 To XP_MAX_DEF - 1) As Integer
Dim Shared xdN(0 To XP_MAX_DEF - 1) As Integer
Dim Shared xdLine(0 To XP_MAX_DEF - 1) As Integer
Dim Shared xdShake(0 To XP_MAX_DEF - 1) As Integer
Dim Shared xdShakeSet(0 To XP_MAX_DEF - 1) As Integer
Dim Shared xdCnt As Integer

Dim Shared xbLine(0 To XP_MAX_BURST - 1) As Integer
Dim Shared xbCntLo(0 To XP_MAX_BURST - 1) As Long
Dim Shared xbCntHi(0 To XP_MAX_BURST - 1) As Long
Dim Shared xbDelLo(0 To XP_MAX_BURST - 1) As Long
Dim Shared xbDelHi(0 To XP_MAX_BURST - 1) As Long
Dim Shared xbAtX(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbAtY(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbAtZ(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbScLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbScHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbSpLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbSpHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbShape(0 To XP_MAX_BURST - 1) As Integer
Dim Shared xbDirX(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbDirY(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbDirZ(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbSpread(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbDrLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbDrHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbGrLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbGrHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbInLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbInHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbLfLo(0 To XP_MAX_BURST - 1) As Long
Dim Shared xbLfHi(0 To XP_MAX_BURST - 1) As Long
Dim Shared xbSALo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbSAHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbSBLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbSBHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbGlLo(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbGlHi(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbRampN(0 To XP_MAX_BURST - 1) As Integer
Dim Shared xbRamp(0 To XP_MAX_BURST - 1, 0 To XP_MAX_COLORS - 1) As Long
Dim Shared xbColN(0 To XP_MAX_BURST - 1) As Integer
Dim Shared xbCol(0 To XP_MAX_BURST - 1, 0 To XP_MAX_COLORS - 1) As Long
Dim Shared xbMaxPx(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbMinPx(0 To XP_MAX_BURST - 1) As Single
Dim Shared xbOcc(0 To XP_MAX_BURST - 1) As Integer
Dim Shared xpBurstN As Integer

Dim Shared xpErrors As String
Dim Shared xpIdBoss As Integer
Dim Shared xpIdEnemy As Integer

Dim Shared xpKvKey(0 To XP_MAX_WORDS - 1) As String
Dim Shared xpKvVal(0 To XP_MAX_WORDS - 1) As String
Dim Shared xpKvN As Integer
Dim Shared xpPLine As Integer
Dim Shared xpPVerb As String
Dim Shared xpPBad As Integer
Dim Shared xpTmpCol(0 To XP_MAX_COLORS - 1) As Long
Dim Shared xpTmpN As Integer

Dim Shared xpAlive(0 To XP_POOL - 1) As Integer
Dim Shared xpX(0 To XP_POOL - 1) As Single
Dim Shared xpY(0 To XP_POOL - 1) As Single
Dim Shared xpZ(0 To XP_POOL - 1) As Single
Dim Shared xpVX(0 To XP_POOL - 1) As Single
Dim Shared xpVY(0 To XP_POOL - 1) As Single
Dim Shared xpVZ(0 To XP_POOL - 1) As Single
Dim Shared xpAge(0 To XP_POOL - 1) As Long
Dim Shared xpLife(0 To XP_POOL - 1) As Long
Dim Shared xpLay(0 To XP_POOL - 1) As Integer
Dim Shared xpDrag(0 To XP_POOL - 1) As Single
Dim Shared xpGrav(0 To XP_POOL - 1) As Single
Dim Shared xpS0(0 To XP_POOL - 1) As Single
Dim Shared xpS1(0 To XP_POOL - 1) As Single
Dim Shared xpGl(0 To XP_POOL - 1) As Single
Dim Shared xpCol(0 To XP_POOL - 1) As Long
Dim Shared xpLive As Long
Dim Shared xpFirst As Integer         ' every slot below this one is in use
Dim Shared xpDropped As Long          ' particles the pool or the pending queue could not take
Dim Shared xpSerial As Long
Dim Shared xpDvX As Single, xpDvY As Single, xpDvZ As Single   ' XP_Direction's result

Dim Shared xnOn(0 To XP_MAX_PENDING - 1) As Integer
Dim Shared xnLay(0 To XP_MAX_PENDING - 1) As Integer
Dim Shared xnWait(0 To XP_MAX_PENDING - 1) As Long
Dim Shared xnCnt(0 To XP_MAX_PENDING - 1) As Long
Dim Shared xnSer(0 To XP_MAX_PENDING - 1) As Long
Dim Shared xnX(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xnY(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xnZ(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xnVX(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xnVY(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xnVZ(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xnSc(0 To XP_MAX_PENDING - 1) As Single
Dim Shared xpPendN As Integer

' --- parsing ---

Sub XP_Err (xeLine As Integer, xeMsg As String)
    xpErrors = xpErrors + "line " + LTrim$(Str$(xeLine)) + ": " + xeMsg + Chr$(10)
End Sub

' Reports a problem on the line being read, once per line.
Sub XP_LineErr (xlMsg As String)
    If xpPBad Then Exit Sub
    xpPBad = -1
    XP_Err xpPLine, xlMsg
End Sub

' Splits a line on spaces and tabs into xwOut(0..), at most XP_MAX_WORDS; returns the count, or
' XP_MAX_WORDS + 1 when there are more.
Function XP_Words% (xwText As String, xwOut() As String)
    Dim xwN As Integer, xwRest As String, xwSp As Integer, xwI As Integer
    xwRest = xwText
    For xwI = 1 To Len(xwRest)
        If Mid$(xwRest, xwI, 1) = Chr$(9) Then Mid$(xwRest, xwI, 1) = " "
    Next xwI
    xwRest = LTrim$(RTrim$(xwRest))
    Do While Len(xwRest) > 0
        If xwN >= XP_MAX_WORDS Then XP_Words% = XP_MAX_WORDS + 1 : Exit Function
        xwSp = InStr(xwRest, " ")
        If xwSp = 0 Then
            xwOut(xwN) = xwRest : xwRest = ""
        Else
            xwOut(xwN) = Left$(xwRest, xwSp - 1) : xwRest = LTrim$(Mid$(xwRest, xwSp + 1))
        End If
        xwN = xwN + 1
    Loop
    XP_Words% = xwN
End Function

Function XP_KvIdx% (xkKey As String)
    Dim xkI As Integer
    XP_KvIdx% = -1
    For xkI = 0 To xpKvN - 1
        If xpKvKey(xkI) = xkKey Then XP_KvIdx% = xkI : Exit Function
    Next xkI
End Function

' "n" or "a..b" as numbers. 1 and the ends when it is one, else 0.
Function XP_ParseRange% (xrText As String, xrLo As Single, xrHi As Single)
    Dim xrD As Integer
    XP_ParseRange% = 0
    If InStr(xrText, "...") > 0 Then Exit Function
    xrD = InStr(xrText, "..")
    If xrD = 0 Then
        If BD_ParseNum%(xrText, xrLo) = 0 Then Exit Function
        xrHi = xrLo
    Else
        If BD_ParseNum%(Left$(xrText, xrD - 1), xrLo) = 0 Then Exit Function
        If BD_ParseNum%(Mid$(xrText, xrD + 2), xrHi) = 0 Then Exit Function
    End If
    XP_ParseRange% = -1
End Function

' xvText as a number or range inside xvMin..xvMax (whole when xvInt). 0 and a reported problem when not.
Function XP_RangeVal% (xvLabel As String, xvText As String, xvMin As Single, xvMax As Single, xvInt As Integer, xvLo As Single, xvHi As Single)
    Dim xvWhat As String
    XP_RangeVal% = 0
    If xvInt Then xvWhat = "a whole number " Else xvWhat = "a number "
    xvWhat = xvWhat + LTrim$(Str$(xvMin)) + " to " + LTrim$(Str$(xvMax)) + " (or low..high)"
    If XP_ParseRange%(xvText, xvLo, xvHi) = 0 Then XP_LineErr xvLabel + " must be " + xvWhat + ", not '" + xvText + "'" : Exit Function
    If xvLo > xvHi Then XP_LineErr xvLabel + " range must run low..high, not '" + xvText + "'" : Exit Function
    If xvInt Then
        If xvLo <> Int(xvLo) Or xvHi <> Int(xvHi) Then XP_LineErr xvLabel + " must be " + xvWhat + ", not '" + xvText + "'" : Exit Function
    End If
    If xvLo < xvMin Or xvHi > xvMax Then XP_LineErr xvLabel + " must be " + xvWhat + ", not '" + xvText + "'" : Exit Function
    XP_RangeVal% = -1
End Function

' The optional number-or-range key xoKey into xoLo..xoHi, default xoDef. 0 and a reported problem when wrong.
Function XP_Opt% (xoKey As String, xoDef As Single, xoMin As Single, xoMax As Single, xoInt As Integer, xoLo As Single, xoHi As Single)
    Dim xoI As Integer
    xoLo = xoDef : xoHi = xoDef : XP_Opt% = -1
    xoI = XP_KvIdx%(xoKey)
    If xoI < 0 Then Exit Function
    XP_Opt% = XP_RangeVal%(xoKey, xpKvVal(xoI), xoMin, xoMax, xoInt, xoLo, xoHi)
End Function

' Like XP_Opt%, for a key that takes one number.
Function XP_OptOne% (xtKey As String, xtDef As Single, xtMin As Single, xtMax As Single, xtInt As Integer, xtOut As Single)
    Dim xtLo As Single, xtHi As Single
    XP_OptOne% = 0
    If XP_Opt%(xtKey, xtDef, xtMin, xtMax, xtInt, xtLo, xtHi) = 0 Then Exit Function
    If xtLo <> xtHi Then XP_LineErr xtKey + " takes one number, not a range" : Exit Function
    xtOut = xtLo
    XP_OptOne% = -1
End Function

' x,y,z with each part inside +-xaMax. 0 and a reported problem when wrong.
Function XP_Vec3% (xaKey As String, xaText As String, xaMax As Single, xaX As Single, xaY As Single, xaZ As Single)
    Dim xaC1 As Integer, xaC2 As Integer
    XP_Vec3% = 0
    xaC1 = InStr(xaText, ",")
    If xaC1 > 0 Then xaC2 = InStr(xaC1 + 1, xaText, ",")
    If xaC1 = 0 Or xaC2 = 0 Or InStr(xaC2 + 1, xaText, ",") > 0 Then XP_LineErr xaKey + " must be x,y,z, not '" + xaText + "'" : Exit Function
    If BD_ParseNum%(Left$(xaText, xaC1 - 1), xaX) = 0 Or BD_ParseNum%(Mid$(xaText, xaC1 + 1, xaC2 - xaC1 - 1), xaY) = 0 Or BD_ParseNum%(Mid$(xaText, xaC2 + 1), xaZ) = 0 Then XP_LineErr xaKey + " must be x,y,z in world units, not '" + xaText + "'" : Exit Function
    If Abs(xaX) > xaMax Or Abs(xaY) > xaMax Or Abs(xaZ) > xaMax Then XP_LineErr xaKey + "=" + xaText + " is outside +-" + LTrim$(Str$(xaMax)) : Exit Function
    XP_Vec3% = -1
End Function

' The comma-separated colours of key xcKey (1..xcMax) into xpTmpCol.
Function XP_ColorList% (xcKey As String, xcMax As Integer)
    Dim xcV As String, xcC As Integer, xcPart As String, xcCol As Long
    XP_ColorList% = 0
    xpTmpN = 0
    xcV = xpKvVal(XP_KvIdx%(xcKey)) + ","
    Do While Len(xcV) > 0
        xcC = InStr(xcV, ",")
        xcPart = Left$(xcV, xcC - 1) : xcV = Mid$(xcV, xcC + 1)
        If BD_ParseHex%(xcPart, xcCol) = 0 Then XP_LineErr xcKey + " must be rrggbb hex colours, not '" + xcPart + "'" : Exit Function
        If xpTmpN >= xcMax Then XP_LineErr xcKey + " takes at most " + LTrim$(Str$(xcMax)) + " colours" : Exit Function
        xpTmpCol(xpTmpN) = xcCol : xpTmpN = xpTmpN + 1
    Loop
    XP_ColorList% = -1
End Function

Function XP_Find% (xfName As String)
    Dim xfI As Integer
    XP_Find% = -1
    For xfI = 0 To xdCnt - 1
        If xdName(xfI) = xfName Then XP_Find% = xfI : Exit Function
    Next xfI
End Function

' One BURST line (key=value words already in the xpKv tables) into the next layer slot.
Sub XP_BuildBurst ()
    Dim xkL As Integer, xkLo As Single, xkHi As Single, xkI As Integer, xkS As Single, xkDef As Integer
    Dim xkTot As Long, xkGl As Single, xkDel As Integer, xkLen As Single, xkTxt As String
    xkL = xpBurstN : xkDef = xdCnt - 1
    xbLine(xkL) = xpPLine
    If xpBurstN >= XP_MAX_BURST Then XP_LineErr "more than XP_MAX_BURST (" + LTrim$(Str$(XP_MAX_BURST)) + ") BURST lines in the file" : Exit Sub
    If xdN(xkDef) >= XP_MAX_PER_DEF Then XP_LineErr "more than " + LTrim$(Str$(XP_MAX_PER_DEF)) + " BURST lines in explosion '" + xdName(xkDef) + "'" : Exit Sub
    If XP_Opt%("count", 1, 1, XP_MAX_COUNT, -1, xkLo, xkHi) = 0 Then Exit Sub
    xbCntLo(xkL) = xkLo : xbCntHi(xkL) = xkHi
    If XP_Opt%("delay", 0, 0, 600, -1, xkLo, xkHi) = 0 Then Exit Sub
    xbDelLo(xkL) = xkLo : xbDelHi(xkL) = xkHi
    xbAtX(xkL) = 0 : xbAtY(xkL) = 0 : xbAtZ(xkL) = 0
    xkI = XP_KvIdx%("at")
    If xkI >= 0 Then
        If XP_Vec3%("at", xpKvVal(xkI), 20, xbAtX(xkL), xbAtY(xkL), xbAtZ(xkL)) = 0 Then Exit Sub
    End If
    If XP_Opt%("scatter", 0, 0, 10, 0, xkLo, xkHi) = 0 Then Exit Sub
    xbScLo(xkL) = xkLo : xbScHi(xkL) = xkHi
    If XP_Opt%("speed", 0, 0, 2, 0, xkLo, xkHi) = 0 Then Exit Sub
    xbSpLo(xkL) = xkLo : xbSpHi(xkL) = xkHi
    xbShape(xkL) = XP_SHAPE_SPHERE
    xkI = XP_KvIdx%("shape")
    If xkI >= 0 Then
        Select Case xpKvVal(xkI)
            Case "sphere" : xbShape(xkL) = XP_SHAPE_SPHERE
            Case "ring" : xbShape(xkL) = XP_SHAPE_RING
            Case "cone" : xbShape(xkL) = XP_SHAPE_CONE
            Case Else : XP_LineErr "shape must be sphere, ring or cone, not '" + xpKvVal(xkI) + "'" : Exit Sub
        End Select
    End If
    xbDirX(xkL) = 0 : xbDirY(xkL) = 1 : xbDirZ(xkL) = 0 : xbSpread(xkL) = 30
    If xbShape(xkL) <> XP_SHAPE_CONE Then
        If XP_KvIdx%("dir") >= 0 Or XP_KvIdx%("spread") >= 0 Then XP_LineErr "dir and spread belong to shape=cone" : Exit Sub
    Else
        xkI = XP_KvIdx%("dir")
        If xkI >= 0 Then
            If XP_Vec3%("dir", xpKvVal(xkI), 100, xbDirX(xkL), xbDirY(xkL), xbDirZ(xkL)) = 0 Then Exit Sub
            xkLen = Sqr(xbDirX(xkL) * xbDirX(xkL) + xbDirY(xkL) * xbDirY(xkL) + xbDirZ(xkL) * xbDirZ(xkL))
            If xkLen < 0.000001 Then XP_LineErr "dir must not be 0,0,0" : Exit Sub
            xbDirX(xkL) = xbDirX(xkL) / xkLen : xbDirY(xkL) = xbDirY(xkL) / xkLen : xbDirZ(xkL) = xbDirZ(xkL) / xkLen
        End If
        If XP_OptOne%("spread", 30, 0, 180, 0, xkS) = 0 Then Exit Sub
        xbSpread(xkL) = xkS
    End If
    If XP_Opt%("drag", 1, 0, 1, 0, xkLo, xkHi) = 0 Then Exit Sub
    xbDrLo(xkL) = xkLo : xbDrHi(xkL) = xkHi
    If XP_Opt%("gravity", 0, -0.1, 0.1, 0, xkLo, xkHi) = 0 Then Exit Sub
    xbGrLo(xkL) = xkLo : xbGrHi(xkL) = xkHi
    If XP_Opt%("inherit", 0, 0, 2, 0, xkLo, xkHi) = 0 Then Exit Sub
    xbInLo(xkL) = xkLo : xbInHi(xkL) = xkHi
    If XP_Opt%("life", 30, 1, 600, -1, xkLo, xkHi) = 0 Then Exit Sub
    xbLfLo(xkL) = xkLo : xbLfHi(xkL) = xkHi
    xbSALo(xkL) = 0.1 : xbSAHi(xkL) = 0.1 : xbSBLo(xkL) = 0.1 : xbSBHi(xkL) = 0.1
    xkI = XP_KvIdx%("size")
    If xkI >= 0 Then
        xkTxt = xpKvVal(xkI)
        xkS = InStr(xkTxt, ",")
        If xkS > 0 Then
            If InStr(xkS + 1, xkTxt, ",") > 0 Then XP_LineErr "size must be a[,b], not '" + xkTxt + "'" : Exit Sub
            If XP_RangeVal%("size", Left$(xkTxt, xkS - 1), 0, 5, 0, xkLo, xkHi) = 0 Then Exit Sub
            xbSALo(xkL) = xkLo : xbSAHi(xkL) = xkHi
            If XP_RangeVal%("size", Mid$(xkTxt, xkS + 1), 0, 5, 0, xkLo, xkHi) = 0 Then Exit Sub
            xbSBLo(xkL) = xkLo : xbSBHi(xkL) = xkHi
        Else
            If XP_RangeVal%("size", xkTxt, 0, 5, 0, xkLo, xkHi) = 0 Then Exit Sub
            xbSALo(xkL) = xkLo : xbSAHi(xkL) = xkHi : xbSBLo(xkL) = xkLo : xbSBHi(xkL) = xkHi
        End If
    End If
    If XP_Opt%("glow", 0, 0, 16, 0, xkLo, xkHi) = 0 Then Exit Sub
    xbGlLo(xkL) = xkLo : xbGlHi(xkL) = xkHi
    xbRampN(xkL) = 0 : xbColN(xkL) = 0
    If XP_KvIdx%("ramp") >= 0 And XP_KvIdx%("color") >= 0 Then XP_LineErr "BURST takes ramp= or color=, not both" : Exit Sub
    If XP_KvIdx%("ramp") >= 0 Then
        If XP_ColorList%("ramp", XP_MAX_COLORS) = 0 Then Exit Sub
        xbRampN(xkL) = xpTmpN
        For xkI = 0 To xpTmpN - 1 : xbRamp(xkL, xkI) = xpTmpCol(xkI) : Next xkI
    ElseIf XP_KvIdx%("color") >= 0 Then
        If XP_ColorList%("color", XP_MAX_COLORS) = 0 Then Exit Sub
        xbColN(xkL) = xpTmpN
        For xkI = 0 To xpTmpN - 1 : xbCol(xkL, xkI) = xpTmpCol(xkI) : Next xkI
    Else
        XP_LineErr "BURST needs ramp=rrggbb,... or color=rrggbb,..." : Exit Sub
    End If
    If XP_OptOne%("maxpx", 0, 0, 64, 0, xkS) = 0 Then Exit Sub
    xbMaxPx(xkL) = xkS
    If XP_OptOne%("minpx", 1, 0, 16, 0, xkS) = 0 Then Exit Sub
    xbMinPx(xkL) = xkS
    If xbMaxPx(xkL) > 0 And xbMinPx(xkL) > xbMaxPx(xkL) Then XP_LineErr "minpx must not exceed maxpx" : Exit Sub
    If XP_OptOne%("occlude", 1, 0, 1, -1, xkS) = 0 Then Exit Sub
    xbOcc(xkL) = xkS
    xdN(xkDef) = xdN(xkDef) + 1
    xpBurstN = xpBurstN + 1
    For xkI = xdFrom(xkDef) To xdFrom(xkDef) + xdN(xkDef) - 1
        xkTot = xkTot + xbCntHi(xkI)
        xkGl = xkGl + xbGlHi(xkI) * xbCntHi(xkI)
        If xbDelHi(xkI) > 0 Then xkDel = xkDel + 1
    Next xkI
    If xkTot > XP_MAX_COUNT Then XP_LineErr "explosion '" + xdName(xkDef) + "' has " + LTrim$(Str$(xkTot)) + " particles in all, the limit is " + LTrim$(Str$(XP_MAX_COUNT)) : Exit Sub
    If xkGl > XP_GLOW_BUDGET Then XP_LineErr "explosion '" + xdName(xkDef) + "' has a glow x count of " + LTrim$(Str$(xkGl)) + ", the budget is " + LTrim$(Str$(XP_GLOW_BUDGET)) : Exit Sub
    If xkDel > XP_MAX_DELAYED Then XP_LineErr "explosion '" + xdName(xkDef) + "' has " + LTrim$(Str$(xkDel)) + " delayed layers, the limit is " + LTrim$(Str$(XP_MAX_DELAYED)) : Exit Sub
End Sub

' An "explosion:<name>" header.
Sub XP_BeginDef (xhName As String)
    Dim xhI As Integer, xhC As String
    If Len(xhName) = 0 Or Len(xhName) > 16 Then XP_LineErr "explosion needs a name of 1 to 16 letters, digits or _" : Exit Sub
    For xhI = 1 To Len(xhName)
        xhC = Mid$(xhName, xhI, 1)
        If Not ((xhC >= "a" And xhC <= "z") Or (xhC >= "0" And xhC <= "9") Or xhC = "_") Then XP_LineErr "explosion name '" + xhName + "' may hold only lower-case letters, digits and _" : Exit Sub
    Next xhI
    If XP_Find%(xhName) >= 0 Then XP_LineErr "explosion '" + xhName + "' is listed twice" : Exit Sub
    If xdCnt >= XP_MAX_DEF Then XP_LineErr "more than XP_MAX_DEF (" + LTrim$(Str$(XP_MAX_DEF)) + ") explosions" : Exit Sub
    xdName(xdCnt) = xhName : xdFrom(xdCnt) = xpBurstN : xdN(xdCnt) = 0 : xdLine(xdCnt) = xpPLine
    xdShake(xdCnt) = 0 : xdShakeSet(xdCnt) = 0
    xdCnt = xdCnt + 1
End Sub

' A SHAKE line.
Sub XP_BuildShake ()
    Dim xsLo As Single, xsDef As Integer
    xsDef = xdCnt - 1
    If XP_KvIdx%("frames") < 0 Then XP_LineErr "SHAKE needs frames=N" : Exit Sub
    If xdShakeSet(xsDef) Then XP_LineErr "explosion '" + xdName(xsDef) + "' has two SHAKE lines" : Exit Sub
    If XP_OptOne%("frames", 0, 0, 600, -1, xsLo) = 0 Then Exit Sub
    xdShake(xsDef) = xsLo : xdShakeSet(xsDef) = -1
End Sub

' Parses file text into the tables. 1 = clean; 0 = problems listed in xpErrors, and then the
' tables are left empty, so a broken file does nothing rather than half of something.
Function XP_Parse% (xlSrc As String)
    Dim xlI As Long, xlNL As Long, xlRaw As String, xlLine As String, xlSc As Integer
    Dim xlW(0 To XP_MAX_WORDS - 1) As String, xlN As Integer, xlVerb As String
    Dim xlK As Integer, xlEq As Integer, xlKey As String, xlKeys As String, xlHdr As Integer
    XP_Clear
    xdCnt = 0 : xpBurstN = 0 : xpErrors = "" : xpIdBoss = -1 : xpIdEnemy = -1
    xlI = 1 : xpPLine = 0 : xlHdr = 0
    Do While xlI <= Len(xlSrc)
        xlNL = InStr(xlI, xlSrc, Chr$(10))
        If xlNL = 0 Then xlNL = Len(xlSrc) + 1
        xlRaw = Mid$(xlSrc, xlI, xlNL - xlI)
        xlI = xlNL + 1
        xpPLine = xpPLine + 1 : xpPBad = 0
        If Right$(xlRaw, 1) = Chr$(13) Then xlRaw = Left$(xlRaw, Len(xlRaw) - 1)
        xlSc = InStr(xlRaw, ";")
        If xlSc > 0 Then xlRaw = Left$(xlRaw, xlSc - 1)
        xlLine = LTrim$(RTrim$(xlRaw))
        If Len(xlLine) = 0 Then GoTo xlNext
        xlN = XP_Words%(xlLine, xlW())
        If xlN > XP_MAX_WORDS Then XP_LineErr "more than " + LTrim$(Str$(XP_MAX_WORDS - 1)) + " words on one line" : GoTo xlNext
        If InStr(xlW(0), ":") > 0 Then
            If LCase$(Left$(xlW(0), 10)) <> "explosion:" Then XP_LineErr "unknown header '" + xlW(0) + "' (explosion:<name>)" : GoTo xlNext
            If xlN > 1 Then XP_LineErr "an explosion header takes only its name" : GoTo xlNext
            XP_BeginDef Mid$(xlW(0), 11)
            xlHdr = (xpPBad = 0)
            GoTo xlNext
        End If
        xlVerb = UCase$(xlW(0))
        Select Case xlVerb
            Case "BURST" : xlKeys = "count delay at scatter speed shape dir spread drag gravity inherit life size glow ramp color maxpx minpx occlude"
            Case "SHAKE" : xlKeys = "frames"
            Case Else : XP_LineErr "unknown line '" + xlW(0) + "' (BURST SHAKE)" : GoTo xlNext
        End Select
        If xdCnt = 0 Or xlHdr = 0 Then XP_LineErr xlVerb + " before any explosion: header" : GoTo xlNext
        xpKvN = 0
        For xlK = 1 To xlN - 1
            xlEq = InStr(xlW(xlK), "=")
            If xlEq < 2 Or xlEq = Len(xlW(xlK)) Then XP_LineErr "expected key=value, got '" + xlW(xlK) + "'" : GoTo xlNext
            xlKey = LCase$(Left$(xlW(xlK), xlEq - 1))
            If InStr(" " + xlKeys + " ", " " + xlKey + " ") = 0 Then XP_LineErr "unknown " + xlVerb + " key '" + xlKey + "' (" + xlKeys + ")" : GoTo xlNext
            If XP_KvIdx%(xlKey) >= 0 Then XP_LineErr xlVerb + " key '" + xlKey + "' is given twice" : GoTo xlNext
            xpKvKey(xpKvN) = xlKey : xpKvVal(xpKvN) = LCase$(Mid$(xlW(xlK), xlEq + 1)) : xpKvN = xpKvN + 1
        Next xlK
        xpPVerb = xlVerb
        If xlVerb = "BURST" Then XP_BuildBurst Else XP_BuildShake
        xlNext:
    Loop
    If Len(xpErrors) > 0 Then
        xdCnt = 0 : xpBurstN = 0
    Else
        xpIdBoss = XP_Find%("boss") : xpIdEnemy = XP_Find%("enemy")
    End If
    XP_Parse% = (Len(xpErrors) = 0)
End Function

' Static checks on a parsed file: "" when sound, else one problem per line. Parse problems come
' first. Every explosion has a BURST, and every name the game looks up (XP_REQUIRED) exists.
Function XP_Validate$ ()
    Dim xyI As Integer, xyOut As String, xyRest As String, xySp As Integer, xyName As String
    xyOut = xpErrors
    For xyI = 0 To xdCnt - 1
        If xdN(xyI) = 0 Then xyOut = xyOut + "line " + LTrim$(Str$(xdLine(xyI))) + ": explosion '" + xdName(xyI) + "' has no BURST" + Chr$(10)
    Next xyI
    If Len(xpErrors) = 0 Then
        xyRest = XP_REQUIRED
        Do While Len(xyRest) > 0
            xySp = InStr(xyRest, " ")
            If xySp = 0 Then xyName = xyRest : xyRest = "" Else xyName = Left$(xyRest, xySp - 1) : xyRest = Mid$(xyRest, xySp + 1)
            If XP_Find%(xyName) < 0 Then xyOut = xyOut + "explosion '" + xyName + "' is used by the game but not defined" + Chr$(10)
        Loop
    End If
    XP_Validate$ = xyOut
End Function

' Frames of screen shake an explosion asks for (0 when it has none or the id is wrong).
Function XP_ShakeFrames% (xzId As Integer)
    XP_ShakeFrames% = 0
    If xzId >= 0 And xzId < xdCnt Then XP_ShakeFrames% = xdShake(xzId)
End Function

' --- simulation ---

Function XP_Pick! (xzLo As Single, xzHi As Single, xzH As Single)
    XP_Pick! = xzLo + (xzHi - xzLo) * xzH
End Function

' A whole number from xzLo to xzHi (inclusive) chosen by xzH in [0, 1).
Function XP_PickInt& (xzLo As Single, xzHi As Single, xzH As Single)
    Dim xzV As Long
    xzV = Int(xzLo + xzH * (xzHi - xzLo + 1))
    If xzV > xzHi Then xzV = xzHi
    XP_PickInt& = xzV
End Function

' The launch direction of particle xiSalt of a layer, a unit vector, into xpDv*.
Sub XP_Direction (xiLay As Integer, xiSer As Long, xiSalt As Long)
    Dim xiU As Single, xiPhi As Single, xiZ As Single, xiR As Single
    Dim xiAx As Single, xiAy As Single, xiAz As Single, xiUx As Single, xiUy As Single, xiUz As Single
    Dim xiWx As Single, xiWy As Single, xiWz As Single, xiLen As Single, xiC As Single, xiS As Single
    xiPhi = 6.2831853 * BD_Hash!(xiSer, xiLay, xiSalt + 2)
    Select Case xbShape(xiLay)
        Case XP_SHAPE_SPHERE
            xiZ = 2 * BD_Hash!(xiSer, xiLay, xiSalt + 1) - 1
            xiR = Sqr(1 - xiZ * xiZ)
            xpDvX = xiR * Cos(xiPhi) : xpDvY = xiZ : xpDvZ = xiR * Sin(xiPhi)
        Case XP_SHAPE_RING
            xpDvX = 0 : xpDvY = Cos(xiPhi) : xpDvZ = Sin(xiPhi)
        Case Else
            xiU = BD_Hash!(xiSer, xiLay, xiSalt + 1)
            xiC = 1 - xiU * (1 - Cos(xbSpread(xiLay) * 0.01745329))
            xiS = 1 - xiC * xiC
            If xiS < 0 Then xiS = 0
            xiS = Sqr(xiS)
            If Abs(xbDirY(xiLay)) < 0.9 Then xiAx = 0 : xiAy = 1 : xiAz = 0 Else xiAx = 1 : xiAy = 0 : xiAz = 0
            xiUx = xbDirY(xiLay) * xiAz - xbDirZ(xiLay) * xiAy
            xiUy = xbDirZ(xiLay) * xiAx - xbDirX(xiLay) * xiAz
            xiUz = xbDirX(xiLay) * xiAy - xbDirY(xiLay) * xiAx
            xiLen = Sqr(xiUx * xiUx + xiUy * xiUy + xiUz * xiUz)
            xiUx = xiUx / xiLen : xiUy = xiUy / xiLen : xiUz = xiUz / xiLen
            xiWx = xbDirY(xiLay) * xiUz - xbDirZ(xiLay) * xiUy
            xiWy = xbDirZ(xiLay) * xiUx - xbDirX(xiLay) * xiUz
            xiWz = xbDirX(xiLay) * xiUy - xbDirY(xiLay) * xiUx
            xpDvX = xiC * xbDirX(xiLay) + xiS * (Cos(xiPhi) * xiUx + Sin(xiPhi) * xiWx)
            xpDvY = xiC * xbDirY(xiLay) + xiS * (Cos(xiPhi) * xiUy + Sin(xiPhi) * xiWy)
            xpDvZ = xiC * xbDirZ(xiLay) + xiS * (Cos(xiPhi) * xiUz + Sin(xiPhi) * xiWz)
    End Select
End Sub

' Puts xeCnt particles of layer xeLay into the pool; what does not fit is counted in xpDropped.
Sub XP_Emit (xeLay As Integer, xeSer As Long, xeCnt As Long, xeX As Single, xeY As Single, xeZ As Single, xeVX As Single, xeVY As Single, xeVZ As Single, xeSc As Single)
    Dim xeI As Long, xeSlot As Integer, xeB As Long, xeSp As Single, xeIn As Single, xeT As Single
    Dim xeR As Single, xeZz As Single, xeRr As Single, xeAng As Single
    For xeI = 0 To xeCnt - 1
        xeSlot = xpFirst
        Do While xeSlot < XP_POOL
            If xpAlive(xeSlot) = 0 Then Exit Do
            xeSlot = xeSlot + 1
        Loop
        If xeSlot >= XP_POOL Then xpDropped = xpDropped + (xeCnt - xeI) : Exit For
        xeB = xeI * 16
        XP_Direction xeLay, xeSer, xeB
        xeSp = XP_Pick!(xbSpLo(xeLay), xbSpHi(xeLay), BD_Hash!(xeSer, xeLay, xeB)) * xeSc
        xeIn = XP_Pick!(xbInLo(xeLay), xbInHi(xeLay), BD_Hash!(xeSer, xeLay, xeB + 12))
        xpVX(xeSlot) = xeVX * xeIn + xpDvX * xeSp
        xpVY(xeSlot) = xeVY * xeIn + xpDvY * xeSp
        xpVZ(xeSlot) = xeVZ * xeIn + xpDvZ * xeSp
        xpX(xeSlot) = xeX + xbAtX(xeLay) * xeSc
        xpY(xeSlot) = xeY + xbAtY(xeLay) * xeSc
        xpZ(xeSlot) = xeZ + xbAtZ(xeLay) * xeSc
        If xbScHi(xeLay) > 0 Then
            xeR = XP_Pick!(xbScLo(xeLay), xbScHi(xeLay), BD_Hash!(xeSer, xeLay, xeB + 13)) * xeSc
            xeR = xeR * BD_Hash!(xeSer, xeLay, xeB + 4) ^ 0.3333333
            xeZz = 2 * BD_Hash!(xeSer, xeLay, xeB + 5) - 1
            xeRr = Sqr(1 - xeZz * xeZz)
            xeAng = 6.2831853 * BD_Hash!(xeSer, xeLay, xeB + 6)
            xpX(xeSlot) = xpX(xeSlot) + xeR * xeRr * Cos(xeAng)
            xpY(xeSlot) = xpY(xeSlot) + xeR * xeZz
            xpZ(xeSlot) = xpZ(xeSlot) + xeR * xeRr * Sin(xeAng)
        End If
        xpAge(xeSlot) = 0
        xpLife(xeSlot) = XP_PickInt&(xbLfLo(xeLay), xbLfHi(xeLay), BD_Hash!(xeSer, xeLay, xeB + 3))
        xpDrag(xeSlot) = XP_Pick!(xbDrLo(xeLay), xbDrHi(xeLay), BD_Hash!(xeSer, xeLay, xeB + 8))
        xpGrav(xeSlot) = XP_Pick!(xbGrLo(xeLay), xbGrHi(xeLay), BD_Hash!(xeSer, xeLay, xeB + 9))
        xpGl(xeSlot) = XP_Pick!(xbGlLo(xeLay), xbGlHi(xeLay), BD_Hash!(xeSer, xeLay, xeB + 10))
        xeT = BD_Hash!(xeSer, xeLay, xeB + 11)
        xpS0(xeSlot) = XP_Pick!(xbSALo(xeLay), xbSAHi(xeLay), xeT) * xeSc
        xpS1(xeSlot) = XP_Pick!(xbSBLo(xeLay), xbSBHi(xeLay), xeT) * xeSc
        If xbColN(xeLay) > 0 Then
            xpCol(xeSlot) = xbCol(xeLay, Int(BD_Hash!(xeSer, xeLay, xeB + 7) * xbColN(xeLay)))
        End If
        xpLay(xeSlot) = xeLay
        xpAlive(xeSlot) = -1
        xpLive = xpLive + 1
        xpFirst = xeSlot + 1
    Next xeI
End Sub

' Starts explosion xsId at (xsX, xsY, xsZ) for a victim moving at (xsVX, xsVY, xsVZ). xsScale
' (above 0) multiplies size, speed, at and scatter. When the pool has fewer free slots than the
' whole explosion asks for, every layer is cut to the same share (count x free / asked), and the
' cut particles are counted in xpDropped. Layers with a delay wait in the pending queue.
Sub XP_Spawn (xsId As Integer, xsX As Single, xsY As Single, xsZ As Single, xsVX As Single, xsVY As Single, xsVZ As Single, xsScale As Single)
    Dim xsL As Integer, xsI As Integer, xsSer As Long, xsReq As Long, xsFree As Long, xsP As Integer, xsNew As Long
    Dim xsCnt(0 To XP_MAX_PER_DEF - 1) As Long, xsDel(0 To XP_MAX_PER_DEF - 1) As Long
    If xsId < 0 Or xsId >= xdCnt Then Exit Sub
    If xsScale <= 0 Then Exit Sub
    xpSerial = xpSerial + 1 : xsSer = xpSerial
    For xsI = 0 To xdN(xsId) - 1
        xsL = xdFrom(xsId) + xsI
        xsCnt(xsI) = XP_PickInt&(xbCntLo(xsL), xbCntHi(xsL), BD_Hash!(xsSer, xsL, 60001))
        xsDel(xsI) = XP_PickInt&(xbDelLo(xsL), xbDelHi(xsL), BD_Hash!(xsSer, xsL, 60002))
        xsReq = xsReq + xsCnt(xsI)
    Next xsI
    xsFree = XP_POOL - xpLive
    If xsFree < xsReq Then
        For xsI = 0 To xdN(xsId) - 1
            xsNew = (xsCnt(xsI) * xsFree) \ xsReq
            xpDropped = xpDropped + (xsCnt(xsI) - xsNew)
            xsCnt(xsI) = xsNew
        Next xsI
    End If
    For xsI = 0 To xdN(xsId) - 1
        xsL = xdFrom(xsId) + xsI
        If xsCnt(xsI) > 0 Then
            If xsDel(xsI) = 0 Then
                XP_Emit xsL, xsSer, xsCnt(xsI), xsX, xsY, xsZ, xsVX, xsVY, xsVZ, xsScale
            Else
                xsP = 0
                Do While xsP < XP_MAX_PENDING
                    If xnOn(xsP) = 0 Then Exit Do
                    xsP = xsP + 1
                Loop
                If xsP >= XP_MAX_PENDING Then
                    xpDropped = xpDropped + xsCnt(xsI)
                Else
                    xnOn(xsP) = -1 : xnLay(xsP) = xsL : xnWait(xsP) = xsDel(xsI) : xnCnt(xsP) = xsCnt(xsI) : xnSer(xsP) = xsSer
                    xnX(xsP) = xsX : xnY(xsP) = xsY : xnZ(xsP) = xsZ : xnVX(xsP) = xsVX : xnVY(xsP) = xsVY : xnVZ(xsP) = xsVZ : xnSc(xsP) = xsScale
                    xpPendN = xpPendN + 1
                End If
            End If
        End If
    Next xsI
End Sub

' One frame: every particle ages and moves (v *= drag, vy -= gravity, p += v), then the delayed
' layers whose wait has run out start. A particle of life L is alive for L - 1 updates.
Sub XP_Update ()
    Dim xuI As Integer
    For xuI = 0 To XP_POOL - 1
        If xpAlive(xuI) Then
            xpAge(xuI) = xpAge(xuI) + 1
            If xpAge(xuI) >= xpLife(xuI) Then
                xpAlive(xuI) = 0
                xpLive = xpLive - 1
                If xuI < xpFirst Then xpFirst = xuI
            Else
                xpVX(xuI) = xpVX(xuI) * xpDrag(xuI)
                xpVY(xuI) = xpVY(xuI) * xpDrag(xuI) - xpGrav(xuI)
                xpVZ(xuI) = xpVZ(xuI) * xpDrag(xuI)
                xpX(xuI) = xpX(xuI) + xpVX(xuI)
                xpY(xuI) = xpY(xuI) + xpVY(xuI)
                xpZ(xuI) = xpZ(xuI) + xpVZ(xuI)
            End If
        End If
    Next xuI
    For xuI = 0 To XP_MAX_PENDING - 1
        If xnOn(xuI) Then
            xnWait(xuI) = xnWait(xuI) - 1
            If xnWait(xuI) <= 0 Then
                xnOn(xuI) = 0
                xpPendN = xpPendN - 1
                XP_Emit xnLay(xuI), xnSer(xuI), xnCnt(xuI), xnX(xuI), xnY(xuI), xnZ(xuI), xnVX(xuI), xnVY(xuI), xnVZ(xuI), xnSc(xuI)
            End If
        End If
    Next xuI
End Sub

Sub XP_Clear ()
    Dim xcI As Integer
    For xcI = 0 To XP_POOL - 1 : xpAlive(xcI) = 0 : Next xcI
    For xcI = 0 To XP_MAX_PENDING - 1 : xnOn(xcI) = 0 : Next xcI
    xpLive = 0 : xpFirst = 0 : xpPendN = 0 : xpDropped = 0 : xpSerial = 0
End Sub

' Load the shipped file (the embedded copy); a problem leaves the tables empty, and the test that
' parses the same file catches it.
Sub XP_Load ()
    Dim xlOk As Integer
    xlOk = XP_Parse%(_Embedded$("EXPLOSIONS"))
End Sub

' --- what the drawing reads ---

Function XP_Live% ()
    XP_Live% = xpLive
End Function

' The particle's world radius now: size a at birth, size b at death, times the spawn scale.
Function XP_Size! (xzSlot As Integer)
    XP_Size! = xpS0(xzSlot) + (xpS1(xzSlot) - xpS0(xzSlot)) * xpAge(xzSlot) / xpLife(xzSlot)
End Function

Function XP_RampColor& (xgLay As Integer, xgT As Single)
    Dim xgN As Integer, xgPos As Single, xgI As Integer, xgF As Single, xgA As Long, xgB As Long
    xgN = xbRampN(xgLay)
    xgPos = xgT * (xgN - 1)
    xgI = Int(xgPos)
    If xgI >= xgN - 1 Then XP_RampColor& = xbRamp(xgLay, xgN - 1) : Exit Function
    xgF = xgPos - xgI
    xgA = xbRamp(xgLay, xgI) : xgB = xbRamp(xgLay, xgI + 1)
    XP_RampColor& = _RGB32(Int(_Red32(xgA) + (_Red32(xgB) - _Red32(xgA)) * xgF + 0.5), Int(_Green32(xgA) + (_Green32(xgB) - _Green32(xgA)) * xgF + 0.5), Int(_Blue32(xgA) + (_Blue32(xgB) - _Blue32(xgA)) * xgF + 0.5))
End Function

' The particle's colour now: its layer's ramp at its age, or the colour it drew at birth.
Function XP_Color& (xzSlot As Integer)
    If xbRampN(xpLay(xzSlot)) > 0 Then
        XP_Color& = XP_RampColor&(xpLay(xzSlot), xpAge(xzSlot) / xpLife(xzSlot))
    Else
        XP_Color& = xpCol(xzSlot)
    End If
End Function
