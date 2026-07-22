' scene_jump_planet_test.bas -- verify --scene playingN arrives at planet N
'
' Regression: playing4 showed planet1 (Caldorinthia) instead of planet4 (Xeromith).
' This test simulates the exact sss.bas CLI flow: GAME_ResetState + levelNum=N-1 +
' SEQ_JumpToScene -> SEQ_Advance -> ARRIVE, then directly asserts planetCurrent = N.
'
' Build: from repo root:
'   ./tools/buildqb tests/scene_jump_planet_test.bas
' Run:   builds/scene_jump_planet_test   (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY
$EMBED:'assets/sequence.txt':'SEQTXT'

' ── game-state constants (must match dims.bas) ──────────────────────────────
Const GS_TITLE           = 0
Const GS_PLAYING         = 1
Const GS_PLANET          = 3
Const GS_INTRO           = 5
Const GS_CRAWL           = 6
Const LEVEL_COMBAT       = 0
Const LEVEL_ASTEROID     = 1
Const PLANET_COUNT       = 6
Const NERF_FACTOR        = 0.1
Const BOSS_WARN_FRAMES   = 120
Const DIFF_RAMP_DURATION = 600.0
Const DIFF_STAGE_COUNT   = 6.0
Const ASTFIELD_DURATION      = 120.0
Const ASTFIELD_FUEL_DRAIN_PT = 0.74
Const ASTFIELD_FUEL_FRAC     = 0.563
Const CAM_OFFSET_X = 6.5
Const CAM_OFFSET_Y = 2.0

' ── boss state stub ─────────────────────────────────────────────────────────
Type BossState
    warnTimer As Integer
End Type

' ── shared vars referenced by sequence.bas ──────────────────────────────────
Dim Shared gameState    As Integer
Dim Shared score        As Long
Dim Shared highScore    As Long
Dim Shared stageScore   As Long
Dim Shared levelNum     As Integer
Dim Shared levelType    As Integer
Dim Shared bltActive    As Integer
Dim Shared settingNerf  As Integer
Dim Shared diffTime     As Single
Dim Shared diffScale    As Single
Dim Shared astFieldStart As Single
Dim Shared astDestName  As String
Dim Shared fuelLevel    As Single
Dim Shared planetCurrent As Integer
Dim Shared planetNameIdx As Integer
Dim Shared planetTimer  As Integer
Dim Shared scrH         As Single
Dim Shared boss         As BossState
Dim Shared tt           As Single
Dim Shared planetNames(1 To PLANET_COUNT) As String
Dim introTimer As Integer

' ── stubs ────────────────────────────────────────────────────────────────────
Sub MUS_SetCue(c As String)         : End Sub
Sub StarfieldReset(x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub BELT_Init(w As Single, h As Single) : End Sub
Sub SPK_Say(s As String)            : End Sub
Function GTEXT_Get$(k As String)    : GTEXT_Get$ = "" : End Function
Sub DBG_Print(s As String)          : End Sub
Sub TELEM_SessionEnd()              : End Sub

' ── real sequencer ───────────────────────────────────────────────────────────
'$INCLUDE:'../src/sys/sequence.bas'

' ── test helpers ─────────────────────────────────────────────────────────────
Dim Shared stPassed As Integer, stFailed As Integer

Sub ST_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        stPassed = stPassed + 1
    Else
        Print "FAIL  " + testName
        stFailed = stFailed + 1
    End If
End Sub

' Simulate the exact sss.bas --scene playingN CLI flow, advancing until ARRIVE.
' Returns -1 on success (ARRIVE reached), 0 if jump failed or ARRIVE not found.
Function SimPlayingN%(spN As Integer)
    ' Mirror GAME_ResetState
    gameState    = GS_TITLE
    score        = 0 : highScore = 0 : stageScore = 0
    levelNum     = 0 : levelType = 0 : bltActive = 0
    settingNerf  = 0 : diffTime = 0 : diffScale = 0
    planetCurrent = PLANET_COUNT : planetNameIdx = PLANET_COUNT
    planetTimer  = 0 : boss.warnTimer = 0 : tt = 0
    SEQ_Load _EMBEDDED$("SEQTXT")

    ' Mirror sss.bas CLI for --scene playingN
    levelNum = spN - 1
    If levelNum < 0 Then levelNum = 0
    If SEQ_JumpToScene("playing" + LTrim$(Str$(spN))) < 0 Then SimPlayingN% = 0 : Exit Function

    ' Advance through PLAY entries until ARRIVE fires (sets GS_PLANET).
    ' 5 steps covers the longest path: combat -> boss -> ARRIVE.
    Dim spI As Integer
    For spI = 1 To 5
        SEQ_Advance
        If gameState = GS_PLANET Then SimPlayingN% = -1 : Exit Function
    Next spI
    SimPlayingN% = 0
End Function

' ─────────────────────────────────────────────────────────────────────────────
Print "=== scene_jump_planet_test ==="
Print ""

Dim scN As Integer
For scN = 1 To PLANET_COUNT
    Dim scLabel As String : scLabel = "--scene playing" + LTrim$(Str$(scN))
    Dim scOk As Integer : scOk = SimPlayingN%(scN)
    ST_Assert scOk <> 0, scLabel + " reached ARRIVE"
    ST_Assert planetCurrent = scN, scLabel + " planetCurrent=" + LTrim$(Str$(scN))
    ST_Assert planetNameIdx = scN, scLabel + " planetNameIdx=" + LTrim$(Str$(scN))
    Print ""
Next scN

' ─────────────────────────────────────────────────────────────────────────────
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
