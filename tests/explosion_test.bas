' explosion_test.bas -- the headless explosion core (#198)
'
' Drives src/2d/explosion.bas with the real assets/explosions.txt and with small definitions:
'   1. the shipped file parses and validates clean, with boss and enemy resolved by name
'   2. parse failures name their line: unknown verb or key, bad numbers, ranges, colours, shapes,
'      missing colours, effects before a header, the count, glow and delay limits
'   3. ranges a..b are read for numeric keys; a line may use every key
'   4. determinism: the same spawn gives the same particles, a second spawn differs
'   5. no RNG stream is read (rngState is untouched)
'   6. the pool: overflow is reduced per spawn and counted, never past XP_POOL
'   7. delay timing and the pending queue
'   8. each frame is v *= drag, vy -= gravity, p += v; life ends a particle
'   9. inherit and scale
'  10. shapes: sphere speed, ring planarity (YZ), cone spread
'  11. colour: the list and the ramp
'  12. name lookup and required names
'  13. depth scale, pixel clamp, near fade and the dot and life fades
'  14. --explode parsing
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/explosion_test   (exit 0 = all pass)

$CONSOLE:ONLY
Option _Explicit
'$INCLUDE:'../src/sys/failfast.bi'

$EMBED:'assets/explosions.txt':'EXPLOSIONS'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/2d/backdrop.bas'
'$INCLUDE:'../src/2d/explosion.bas'

Dim Shared etPass As Integer, etFail As Integer

Sub ET_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        etPass = etPass + 1
    Else
        Print "FAIL  " + label
        etFail = etFail + 1
    End If
End Sub

Function ET_Near% (enA As Single, enB As Single, enEps As Single)
    ET_Near% = (Abs(enA - enB) <= enEps)
End Function

Function ET_Nl$ ()
    ET_Nl$ = Chr$(10)
End Function

' 1 when parsing src fails with a message holding etWant on line etLine.
Function ET_Fails% (efSrc As String, efLine As Integer, efWant As String)
    Dim efOk As Integer, efRes As Integer
    efOk = XP_Parse%(efSrc)
    efRes = (efOk = 0 And InStr(xpErrors, "line " + LTrim$(Str$(efLine)) + ": ") > 0 And InStr(LCase$(xpErrors), LCase$(efWant)) > 0)
    ET_Fails% = efRes
    If efRes = 0 Then Print "      got: " + xpErrors + " (ok=" + Str$(efOk) + ")"
End Function

' One explosion "t" holding the BURST body lines.
Function ET_Def$ (edBody As String)
    ET_Def$ = "explosion:t" + ET_Nl$ + edBody + ET_Nl$
End Function

Function ET_Burst$ (ebKeys As String)
    ET_Burst$ = ET_Def$("BURST " + ebKeys)
End Function

' Loads one burst line as explosion 0 and spawns it at the origin.
Sub ET_One (eoKeys As String, eoVX As Single, eoVY As Single, eoVZ As Single, eoScale As Single)
    Dim eoOk As Integer
    eoOk = XP_Parse%(ET_Burst$(eoKeys))
    If eoOk = 0 Then Print "      load: " + xpErrors
    XP_Spawn 0, 0, 0, 0, eoVX, eoVY, eoVZ, eoScale
End Sub

Sub ET_Steps (esN As Integer)
    Dim esI As Integer
    For esI = 1 To esN : XP_Update : Next esI
End Sub

Function ET_Hash$ ()
    Dim ehI As Integer, ehS As String
    For ehI = 0 To XP_POOL - 1
        If xpAlive(ehI) Then ehS = ehS + Str$(xpX(ehI)) + "," + Str$(xpY(ehI)) + "," + Str$(xpZ(ehI)) + "," + Str$(xpLife(ehI)) + "," + Str$(XP_Color&(ehI)) + ";"
    Next ehI
    ET_Hash$ = ehS
End Function

' Index of the first live particle.
Function ET_First% ()
    Dim efI As Integer
    ET_First% = -1
    For efI = 0 To XP_POOL - 1
        If xpAlive(efI) Then ET_First% = efI : Exit Function
    Next efI
End Function

Dim Shared etOkAll As Integer, etSrc As String, etS1 As String, etS2 As String, etRng(1 To RNG_COUNT) As _Unsigned Long
Dim Shared etI As Integer, etJ As Integer, etSlot As Integer, etBad As Integer, etV As Single, etN As Integer
Dim Shared etSumX As Single, etSumY As Single, etSumZ As Single, etLen As Single, etDot As Single
Dim Shared etDrop0 As Long

Print "=== explosion_test ==="

' --- 1. the shipped file ---
etOkAll = XP_Parse%(_Embedded$("EXPLOSIONS"))
ET_Assert etOkAll <> 0, "assets/explosions.txt parses"
ET_Assert XP_Validate$ = "", "assets/explosions.txt validates clean"
ET_Assert XP_Find%("boss") >= 0 And XP_Find%("enemy") >= 0, "boss and enemy are defined"
ET_Assert xpIdBoss = XP_Find%("boss") And xpIdEnemy = XP_Find%("enemy"), "ids are resolved at load"
ET_Assert XP_ShakeFrames%(xpIdBoss) > XP_ShakeFrames%(xpIdEnemy) And XP_ShakeFrames%(xpIdEnemy) > 0, "boss shakes longer than enemy"
ET_Assert xdN(xpIdBoss) >= 7, "boss has flash, fireball, embers, ring, smoke and two delayed bursts"
etN = 0
For etI = xdFrom(xpIdBoss) To xdFrom(xpIdBoss) + xdN(xpIdBoss) - 1
    If xbDelHi(etI) > 0 Then etN = etN + 1
Next etI
ET_Assert etN >= 3, "boss has delayed layers"
ET_Assert xdN(xpIdEnemy) < xdN(xpIdBoss), "enemy is the leaner definition"
XP_Spawn xpIdBoss, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% > 0 And XP_Live% <= XP_MAX_COUNT, "boss spawns within its particle limit"
XP_Clear

' --- 2. parse failures ---
ET_Assert ET_Fails%(ET_Def$("FLASH count=1"), 2, "unknown line"), "unknown verb"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff wibble=1"), 2, "unknown BURST key 'wibble'"), "unknown key"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff count=2 count=3"), 2, "given twice"), "repeated key"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff count=abc"), 2, "count must be a whole number"), "bad number"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff count=2.5"), 2, "count must be a whole number"), "fractional count"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff speed=5"), 2, "speed must be"), "speed above its limit"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff speed=0.3..0.1"), 2, "low..high"), "reversed range"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff speed=0.1..."), 2, "speed must be"), "malformed range"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff speed=0.1.."), 2, "speed must be"), "range with no end"
ET_Assert ET_Fails%(ET_Burst$("speed=0.1"), 2, "needs ramp"), "no colours"
ET_Assert ET_Fails%(ET_Burst$("ramp=ffffff,000000 color=ffffff"), 2, "not both"), "ramp and color together"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff,zzzzzz"), 2, "rrggbb"), "bad colour"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff,ffffff,ffffff,ffffff,ffffff,ffffff,ffffff"), 2, "at most 6"), "too many colours"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff shape=blob"), 2, "shape must be"), "unknown shape"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff dir=0,1,0"), 2, "belong to shape=cone"), "dir on a sphere"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff shape=cone dir=0,0,0"), 2, "must not be 0,0,0"), "cone with no direction"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff at=1,2"), 2, "x,y,z"), "at needs three numbers"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff at=99,0,0"), 2, "outside"), "at outside the limit"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff size=0.1,0.2,0.3"), 2, "size must be a[,b]"), "size with three parts"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff maxpx=2 minpx=4"), 2, "minpx must not exceed maxpx"), "minpx above maxpx"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff occlude=2"), 2, "occlude must be"), "occlude not 0 or 1"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff maxpx=1..4"), 2, "takes one number"), "range on a single-number key"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff count"), 2, "key=value"), "word that is not key=value"
ET_Assert ET_Fails%("BURST color=ffffff" + ET_Nl$, 1, "before any explosion"), "BURST before a header"
ET_Assert ET_Fails%("wave:x" + ET_Nl$, 1, "unknown header"), "unknown header"
ET_Assert ET_Fails%("explosion:Bad" + ET_Nl$, 1, "lower-case"), "name with capitals"
ET_Assert ET_Fails%(ET_Def$("BURST color=ffffff") + "explosion:t" + ET_Nl$, 3, "listed twice"), "explosion listed twice"
ET_Assert ET_Fails%(ET_Def$("SHAKE frames=4" + ET_Nl$ + "SHAKE frames=5"), 3, "two SHAKE"), "two SHAKE lines"
ET_Assert ET_Fails%(ET_Def$("SHAKE"), 2, "needs frames"), "SHAKE without frames"
ET_Assert ET_Fails%(ET_Def$("SHAKE frames=-1"), 2, "frames must be"), "negative SHAKE"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff count=301"), 2, "count must be"), "count above the limit"
ET_Assert ET_Fails%(ET_Def$("BURST color=ffffff count=200" + ET_Nl$ + "BURST color=ffffff count=101"), 3, "in all"), "total count over the limit"
ET_Assert ET_Fails%(ET_Burst$("color=ffffff count=200 glow=16"), 2, "budget"), "glow x count over the budget"
etSrc = ""
For etI = 1 To 9 : etSrc = etSrc + "BURST color=ffffff delay=5" + ET_Nl$ : Next etI
ET_Assert ET_Fails%(ET_Def$(etSrc), 10, "delayed layers"), "more delayed layers than allowed"
etSrc = ""
For etI = 1 To 13 : etSrc = etSrc + "BURST color=ffffff" + ET_Nl$ : Next etI
ET_Assert ET_Fails%(ET_Def$(etSrc), 14, "more than 12 BURST"), "more layers than one explosion holds"
etSrc = ""
For etI = 1 To 17 : etSrc = etSrc + "explosion:e" + LTrim$(Str$(etI)) + ET_Nl$ + "BURST color=ffffff" + ET_Nl$ : Next etI
ET_Assert ET_Fails%(etSrc, 33, "XP_MAX_DEF"), "more explosions than the table holds"
etOkAll = XP_Parse%(ET_Burst$("color=ffffff wibble=1"))
ET_Assert etOkAll = 0 And xdCnt = 0, "a file with an error leaves the tables empty"
ET_Assert XP_Validate$ <> "", "and does not validate"
etOkAll = XP_Parse%("explosion:t" + ET_Nl$)
ET_Assert etOkAll <> 0 And InStr(XP_Validate$, "line 1: explosion 't' has no BURST") > 0, "an explosion with no BURST is reported"
ET_Assert XP_Parse%("; nothing" + Chr$(13) + ET_Nl$ + ET_Burst$("color=FFFFFF ; trailing note")) <> 0, "comments, CRLF and upper-case values"

' --- 3. ranges and every key ---
ET_One "count=3..5 delay=2..4 speed=0.1..0.3 life=10..20 size=0.1..0.2,0.3 glow=1..2 drag=0.9..0.95 color=ff0000", 0, 0, 0, 1
ET_Assert xbCntLo(0) = 3 And xbCntHi(0) = 5 And xbDelLo(0) = 2 And xbDelHi(0) = 4, "count and delay ranges are stored"
ET_Assert ET_Near%(xbSpLo(0), 0.1, 0.0001) And ET_Near%(xbSpHi(0), 0.3, 0.0001), "speed range is stored"
ET_Assert xbLfLo(0) = 10 And xbLfHi(0) = 20, "life range is stored"
ET_Assert ET_Near%(xbSALo(0), 0.1, 0.0001) And ET_Near%(xbSAHi(0), 0.2, 0.0001) And ET_Near%(xbSBLo(0), 0.3, 0.0001), "size a is a range, b a number"
ET_Assert ET_Near%(xbDrLo(0), 0.9, 0.0001) And ET_Near%(xbDrHi(0), 0.95, 0.0001), "drag range is stored"
XP_Clear
ET_Assert XP_Parse%(ET_Burst$("count=2 delay=1 at=1,2,3 scatter=0.1 speed=0.1 shape=cone dir=0,1,0 spread=20 drag=0.9 gravity=0.01 inherit=0.5 life=9 size=0.1,0.2 glow=1 color=ff0000 maxpx=8 minpx=2 occlude=0")) <> 0, "a line may use every key"
ET_Assert xbMaxPx(0) = 8 And xbMinPx(0) = 2 And xbOcc(0) = 0, "pixel clamps and occlude are stored"
etOkAll = XP_Parse%(ET_Burst$("color=ffffff size=0.2"))
ET_Assert etOkAll <> 0 And ET_Near%(xbSAHi(0), xbSBHi(0), 0.0001), "one size is the size at death too"

' --- 4. determinism ---
etOkAll = XP_Parse%(_Embedded$("EXPLOSIONS"))
XP_Spawn xpIdBoss, 1, 2, 3, 0.1, 0, 0, 1
ET_Steps 25
etS1 = ET_Hash$
XP_Clear
XP_Spawn xpIdBoss, 1, 2, 3, 0.1, 0, 0, 1
ET_Steps 25
etS2 = ET_Hash$
ET_Assert Len(etS1) > 0 And etS1 = etS2, "the same spawn gives the same particles"
XP_Spawn xpIdBoss, 1, 2, 3, 0.1, 0, 0, 1
ET_Steps 3
etS2 = ET_Hash$
XP_Clear
XP_Spawn xpIdBoss, 1, 2, 3, 0.1, 0, 0, 1
XP_Update : XP_Update : XP_Update
etS1 = ET_Hash$
ET_Assert etS1 <> etS2, "a second spawn lands differently from the first"
XP_Clear
ET_One "count=40 speed=0.1..0.3 life=10..30 color=ff0000", 0, 0, 0, 1
etBad = 0
For etI = 1 To XP_POOL - 1
    If xpAlive(etI) And xpAlive(0) Then If ET_Near%(xpVX(etI), xpVX(0), 0.00001) And ET_Near%(xpVY(etI), xpVY(0), 0.00001) Then etBad = etBad + 1
Next etI
ET_Assert etBad = 0, "particles of one burst differ from each other"

' --- 5. no RNG stream ---
RNG_Seed 777
For etI = 1 To RNG_COUNT : etRng(etI) = rngState(etI) : Next etI
etOkAll = XP_Parse%(_Embedded$("EXPLOSIONS"))
XP_Spawn xpIdBoss, 0, 0, 0, 0, 0, 0, 1
XP_Spawn xpIdEnemy, 1, 1, 1, 0, 0, 0, 2
ET_Steps 80
etBad = 0
For etI = 1 To RNG_COUNT
    If rngState(etI) <> etRng(etI) Then etBad = etBad + 1
Next etI
ET_Assert etBad = 0, "rngState is untouched by parse, spawn and update"

' --- 6. the pool ---
XP_Clear
etOkAll = XP_Parse%(ET_Burst$("count=300 life=600 color=ffffff"))
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% = 600 And xpDropped = 0, "two full spawns fit"
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% = XP_POOL And xpDropped = 132, "the third is cut to the free slots and the cut is counted"
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% = XP_POOL And xpDropped = 432, "a full pool takes nothing and counts it all"
etI = 0
For etJ = 0 To XP_POOL - 1 : If xpAlive(etJ) Then etI = etI + 1
Next etJ
ET_Assert etI = XP_POOL, "the live flags agree with the count"
XP_Clear
etOkAll = XP_Parse%("explosion:fa" + ET_Nl$ + "BURST count=300 life=600 color=ffffff" + ET_Nl$ + "explosion:fb" + ET_Nl$ + "BURST count=18 life=600 color=ffffff" + ET_Nl$ + "explosion:two" + ET_Nl$ + "BURST count=200 life=600 color=ffffff" + ET_Nl$ + "BURST count=100 life=600 color=ffffff" + ET_Nl$)
ET_Assert etOkAll <> 0, "fill and two definitions load"
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
XP_Spawn 1, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% = 618, "618 particles in the pool"
XP_Spawn 2, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% = 618 + 100 + 50, "free 150 of 300 asked: each layer keeps half"
ET_Assert xpDropped = 150, "and the other half is counted"
XP_Clear
ET_Assert XP_Live% = 0 And xpDropped = 0 And xpPendN = 0, "XP_Clear empties the pool and the counters"

' --- 7. delay timing and the pending queue ---
etOkAll = XP_Parse%(ET_Def$("BURST count=2 life=100 color=ffffff" + ET_Nl$ + "BURST count=3 delay=3 life=100 color=ffffff"))
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1
ET_Assert XP_Live% = 2 And xpPendN = 1, "a delayed layer waits in the queue"
ET_Steps 2
ET_Assert XP_Live% = 2 And xpPendN = 1, "still waiting after 2 frames"
XP_Update
ET_Assert XP_Live% = 5 And xpPendN = 0, "starts on the 3rd frame"
etSrc = ""
For etI = 1 To 8 : etSrc = etSrc + "BURST count=1 delay=5 life=100 color=ffffff" + ET_Nl$ : Next etI
etOkAll = XP_Parse%(ET_Def$(etSrc))
For etI = 1 To 5 : XP_Spawn 0, 0, 0, 0, 0, 0, 0, 1 : Next etI
ET_Assert xpPendN = XP_MAX_PENDING And xpDropped = 8, "the queue holds 32 and counts the layers it could not take"
ET_Steps 5
ET_Assert XP_Live% = 32 And xpPendN = 0, "the queued layers all start"

' --- 8. drag, gravity and life ---
XP_Clear
ET_One "count=1 life=5 drag=0.5 gravity=0.01 inherit=1 color=ffffff", 0.4, 0.2, -0.1, 1
etSlot = ET_First%
ET_Assert ET_Near%(xpVX(etSlot), 0.4, 0.00001) And ET_Near%(xpX(etSlot), 0, 0.00001), "starts with the victim velocity at the spawn point"
XP_Update
ET_Assert ET_Near%(xpVX(etSlot), 0.2, 0.00001) And ET_Near%(xpVY(etSlot), 0.09, 0.00001) And ET_Near%(xpVZ(etSlot), -0.05, 0.00001), "step 1: v *= drag, vy -= gravity"
ET_Assert ET_Near%(xpX(etSlot), 0.2, 0.00001) And ET_Near%(xpY(etSlot), 0.09, 0.00001) And ET_Near%(xpZ(etSlot), -0.05, 0.00001), "step 1: p += v"
XP_Update
ET_Assert ET_Near%(xpVY(etSlot), 0.035, 0.00001) And ET_Near%(xpY(etSlot), 0.125, 0.00001) And ET_Near%(xpX(etSlot), 0.3, 0.00001), "step 2 follows from step 1"
ET_Steps 2
ET_Assert XP_Live% = 1, "alive 4 frames into a life of 5"
XP_Update
ET_Assert XP_Live% = 0, "gone when its life is up"

' --- 9. inherit and scale ---
XP_Clear
ET_One "count=1 speed=0 inherit=0.5 color=ffffff", 0.2, 0, 0, 1
ET_Assert ET_Near%(xpVX(ET_First%), 0.1, 0.00001), "inherit 0.5 takes half the victim's velocity"
XP_Clear
ET_One "count=1 speed=0 inherit=0 color=ffffff", 0.2, 0, 0, 1
ET_Assert ET_Near%(xpVX(ET_First%), 0, 0.00001), "inherit 0 takes none"
XP_Clear
ET_One "count=1 speed=0.1 at=1,0,0 size=0.2,0.4 life=10 color=ffffff", 0, 0, 0, 1
etSlot = ET_First%
etLen = Sqr(xpVX(etSlot) ^ 2 + xpVY(etSlot) ^ 2 + xpVZ(etSlot) ^ 2)
ET_Assert ET_Near%(etLen, 0.1, 0.0001) And ET_Near%(xpX(etSlot), 1, 0.00001) And ET_Near%(XP_Size!(etSlot), 0.2, 0.00001), "scale 1 reference"
XP_Clear
ET_One "count=1 speed=0.1 at=1,0,0 size=0.2,0.4 life=10 color=ffffff", 0, 0, 0, 2
etSlot = ET_First%
etLen = Sqr(xpVX(etSlot) ^ 2 + xpVY(etSlot) ^ 2 + xpVZ(etSlot) ^ 2)
ET_Assert ET_Near%(etLen, 0.2, 0.0001) And ET_Near%(xpX(etSlot), 2, 0.00001) And ET_Near%(XP_Size!(etSlot), 0.4, 0.00001), "scale 2 doubles speed, offset and size"
ET_Steps 5
ET_Assert ET_Near%(XP_Size!(etSlot), 0.6, 0.0001), "size runs from a to b over the life"
XP_Spawn -1, 0, 0, 0, 0, 0, 0, 1
XP_Spawn 5, 0, 0, 0, 0, 0, 0, 1
XP_Spawn 0, 0, 0, 0, 0, 0, 0, 0
ET_Assert XP_Live% = 1, "a bad id or a scale of 0 does nothing"

' --- 10. shapes ---
XP_Clear
ET_One "count=200 speed=0.2 shape=sphere life=100 color=ffffff", 0, 0, 0, 1
etBad = 0 : etSumX = 0 : etSumY = 0 : etSumZ = 0
For etI = 0 To XP_POOL - 1
    If xpAlive(etI) Then
        etLen = Sqr(xpVX(etI) ^ 2 + xpVY(etI) ^ 2 + xpVZ(etI) ^ 2)
        If Not ET_Near%(etLen, 0.2, 0.0001) Then etBad = etBad + 1
        etSumX = etSumX + xpVX(etI) : etSumY = etSumY + xpVY(etI) : etSumZ = etSumZ + xpVZ(etI)
    End If
Next etI
ET_Assert etBad = 0, "sphere particles leave at the layer's speed"
ET_Assert Abs(etSumX) < 4 And Abs(etSumY) < 4 And Abs(etSumZ) < 4, "and spread evenly (no net push)"
ET_Assert Abs(etSumX) > 0 Or Abs(etSumY) > 0, "but not all the same direction"
XP_Clear
ET_One "count=100 speed=0.1..0.3 shape=ring life=100 drag=0.9 color=ffffff", 0, 0, 0, 1
ET_Steps 10
etBad = 0
For etI = 0 To XP_POOL - 1
    If xpAlive(etI) Then
        If xpVX(etI) <> 0 Or xpX(etI) <> 0 Then etBad = etBad + 1
    End If
Next etI
ET_Assert XP_Live% = 100 And etBad = 0, "a ring stays in the YZ plane, perpendicular to the camera's +X forward axis"
XP_Clear
ET_One "count=100 speed=0.2 shape=ring life=100 inherit=1 color=ffffff", 0.3, 0, 0, 1
etSlot = ET_First%
ET_Assert ET_Near%(xpVX(etSlot), 0.3, 0.00001), "inherit alone moves a ring along X"
XP_Clear
ET_One "count=200 speed=0.2 shape=cone dir=1,0,0 spread=25 life=100 color=ffffff", 0, 0, 0, 1
etBad = 0
For etI = 0 To XP_POOL - 1
    If xpAlive(etI) Then
        etLen = Sqr(xpVX(etI) ^ 2 + xpVY(etI) ^ 2 + xpVZ(etI) ^ 2)
        etDot = xpVX(etI) / etLen
        If etDot < Cos(25 * 0.01745329) - 0.001 Then etBad = etBad + 1
        If Not ET_Near%(etLen, 0.2, 0.0001) Then etBad = etBad + 1
    End If
Next etI
ET_Assert XP_Live% = 200 And etBad = 0, "cone particles stay inside the spread about dir"
XP_Clear
ET_One "count=200 speed=0.2 shape=cone dir=0,3,4 spread=10 life=100 color=ffffff", 0, 0, 0, 1
etBad = 0
For etI = 0 To XP_POOL - 1
    If xpAlive(etI) Then
        etDot = (xpVY(etI) * 0.6 + xpVZ(etI) * 0.8) / 0.2
        If etDot < Cos(10 * 0.01745329) - 0.001 Then etBad = etBad + 1
    End If
Next etI
ET_Assert etBad = 0, "dir is normalised and a slanted cone holds"
XP_Clear
ET_One "count=100 scatter=0.5 life=100 color=ffffff", 0, 0, 0, 1
etBad = 0
For etI = 0 To XP_POOL - 1
    If xpAlive(etI) Then
        If Sqr(xpX(etI) ^ 2 + xpY(etI) ^ 2 + xpZ(etI) ^ 2) > 0.5001 Then etBad = etBad + 1
    End If
Next etI
ET_Assert etBad = 0, "scatter keeps start points inside its radius"

' --- 11. colour ---
XP_Clear
ET_One "count=60 color=ff0000,00ff00 life=100", 0, 0, 0, 1
etBad = 0 : etN = 0
For etI = 0 To XP_POOL - 1
    If xpAlive(etI) Then
        If XP_Color&(etI) = _RGB32(0, 255, 0) Then etN = etN + 1
        If XP_Color&(etI) <> _RGB32(255, 0, 0) And XP_Color&(etI) <> _RGB32(0, 255, 0) Then etBad = etBad + 1
    End If
Next etI
ET_Assert etBad = 0 And etN > 0 And etN < 60, "each particle takes one of the listed colours, both turn up"
XP_Clear
ET_One "count=1 life=10 ramp=ff0000,0000ff", 0, 0, 0, 1
etSlot = ET_First%
ET_Assert XP_Color&(etSlot) = _RGB32(255, 0, 0), "a ramp starts at its first colour"
ET_Steps 5
ET_Assert _Red32(XP_Color&(etSlot)) > 120 And _Red32(XP_Color&(etSlot)) < 135 And _Blue32(XP_Color&(etSlot)) > 120 And _Blue32(XP_Color&(etSlot)) < 135, "and is halfway at half its life"
ET_Steps 4
ET_Assert _Blue32(XP_Color&(etSlot)) > 220, "and nearly the last colour at the end"

' --- 12. names ---
etOkAll = XP_Parse%(ET_Burst$("color=ffffff"))
ET_Assert XP_Find%("t") = 0 And XP_Find%("nope") = -1, "lookup by name"
ET_Assert InStr(XP_Validate$, "explosion 'boss' is used by the game but not defined") > 0 And InStr(XP_Validate$, "explosion 'enemy' is used by the game") > 0, "validation names the missing required explosions"
ET_Assert xpIdBoss = -1 And xpIdEnemy = -1, "and their ids stay -1"


' --- 13. depth scale, clamp and near fade ---
Dim etF As Single, etStr As String
etF = XP_Focal!(240, 60)
ET_Assert ET_Near%(etF, 207.846, 0.01), "focal length is (height / 2) / tan(fov / 2)"
ET_Assert ET_Near%(XP_PxRadius!(1, etF, 10), etF / 10, 0.001) And ET_Near%(XP_PxRadius!(2, etF, 20), XP_PxRadius!(1, etF, 10), 0.001), "radius scales with size over view depth"
ET_Assert ET_Near%(XP_PxRadius!(0.5, etF, 5) / XP_PxRadius!(0.5, etF, 10), 2, 0.001), "twice as far is half the radius"
ET_Assert XP_MaxPx!(0) = 16 And XP_MaxPx!(9) = 9 And XP_MaxPx!(64) = 64, "maxpx: 0 is the default 16, a number stands"
ET_Assert XP_NearFade!(0.3) = 0 And XP_NearFade!(0.6) = 0 And XP_NearFade!(2) = 1 And XP_NearFade!(50) = 1, "nothing closer than 0.6, full from 2"
ET_Assert ET_Near%(XP_NearFade!(1.3), 0.5, 0.001), "the near fade is linear between 0.6 and 2"
ET_Assert XP_DotFade!(3, 1) = 1 And XP_DotFade!(1, 1) = 1 And ET_Near%(XP_DotFade!(0.5, 1), 0.25, 0.001), "under 1 px a speck fades with the square of its radius"
ET_Assert ET_Near%(XP_DotFade!(1, 2), 0.25, 0.001) And XP_DotFade!(2, 2) = 1 And XP_DotFade!(0, 1) = 0, "under minpx the same, from minpx"
ET_Assert XP_LifeFade!(0, 20) = 1 And XP_LifeFade!(15, 20) = 1 And ET_Near%(XP_LifeFade!(17.5, 20), 0.5, 0.001) And XP_LifeFade!(20, 20) = 0, "a particle fades over the last quarter of its life"

' --- 14. --explode ---
etOkAll = XP_ParseExplode%("boss@20")
ET_Assert etOkAll And xjCount = 1 And xjName(0) = "boss" And xjFrame(0) = 20, "--explode reads name@frame"
etOkAll = XP_ParseExplode%("boss@20,Enemy@0,x_1@400")
ET_Assert etOkAll And xjCount = 3 And xjName(1) = "enemy" And xjFrame(1) = 0 And xjFrame(2) = 400, "a list, case folded"
ET_Assert XP_ParseExplode%("") = 0 And InStr(xjErr, "needs") > 0, "empty is refused"
ET_Assert XP_ParseExplode%("boss") = 0 And InStr(xjErr, "name@frame") > 0, "a missing frame is refused"
ET_Assert XP_ParseExplode%("boss@") = 0 And XP_ParseExplode%("boss@-3") = 0 And XP_ParseExplode%("boss@1.5") = 0, "frames are whole numbers"
ET_Assert XP_ParseExplode%("@5") = 0 And XP_ParseExplode%("bo ss@5") = 0 And XP_ParseExplode%("bo-ss@5") = 0, "names are a-z 0-9 _"
ET_Assert XP_ParseExplode%("boss@1,,enemy@2") = 0, "an empty entry is refused"
etStr = ""
For etI = 1 To 17 : etStr = etStr + "a@" + LTrim$(Str$(etI)) + "," : Next etI
ET_Assert XP_ParseExplode%(Left$(etStr, Len(etStr) - 1)) = 0 And InStr(xjErr, "at most") > 0, "more than 16 entries are refused"
etOkAll = XP_Parse%(_Embedded$("EXPLOSIONS"))
etOkAll = XP_ParseExplode%("boss@3,enemy@4")
ET_Assert XP_ExplodeMissing$ = "", "the shipped names resolve"
etOkAll = XP_ParseExplode%("boss@3,nope@4")
ET_Assert XP_ExplodeMissing$ = "nope", "an unknown name is reported"
Print
Print "Passed:" + Str$(etPass) + "  Failed:" + Str$(etFail)
If etFail > 0 Then System 1
System 0
