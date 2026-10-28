' dbg_output_test.bas -- regression guard for Windows --debug logging (issue #200)
'
' Before the fix, DBG_Print/GTEXT_Log probed for /dev/tty at startup, which does
' not exist on Windows -- dbgTtyOK stayed 0 forever, silently swallowing every
' DBG_Print call (including HTTP/curl error reporting) regardless of --debug.
'
' Covers:
'   1. Windows: --debug (debugMode=-1) must enable dbgTtyOK via DBG_InitTty
'   2. Windows: without --debug (debugMode=0), dbgTtyOK stays disabled
'   3. DBG_Print / GTEXT_Log don't error in either gating state
'
' DBG_InitTty only covers the Windows branch of the fix (see src/sys/debug.bas --
' QB64-PE rejects the ON ERROR GOTO / label pattern Unix's /dev/tty probe needs
' inside a SUB, so that probe stays inline in sss.bas and isn't unit-testable here).
'
' Build: ./tools/buildqb tests/dbg_output_test.bas
' Run:   builds/dbg_output_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

' -- game-state constants (must match dims.bas) --
Const GS_TITLE       = 0
Const GS_PLAYING     = 1
Const GS_GAMEOVER    = 2
Const GS_PLANET      = 3
Const GS_CINEMATIC   = 4
Const GS_INTRO       = 5
Const GS_CRAWL       = 6
Const GS_OPTIONS     = 7
Const GS_ABOUT       = 8
Const GS_LEADIN      = 9
Const GS_CONSENT     = 10
Const GS_USERNAME    = 11
Const GS_LEADERBOARD = 12
Const GS_CONTROLS    = 13
Const GS_CRAWLS      = 14
Const GS_DOCK        = 15
Const GS_REMAP       = 16
Const MAX_ENEMIES = 1
Const MESH_COUNT  = 1

' -- minimal stubs for DBG_Overlay's 3D/game-object dependencies (unused by this test) --
Type GameObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    ry As Single : rz As Single
End Type
Type E3D_AABB
    hx As Single : hy As Single : hz As Single
End Type
Type E3D_Matrix4
    m(0 To 3, 0 To 3) As Single
End Type

Dim Shared gameState As Integer, prevGameState As Integer
Dim Shared debugMode As Integer
Dim Shared dbgTtyOK  As Integer
Dim Shared dbgOverlay As Integer, dbgGraveWas As Integer
Dim Shared dbgT0 As Double
Dim Shared scrW As Single, scrH As Single
Dim Shared E3D_scnCount As Long
Dim Shared player As GameObj
Dim Shared playerVY As Single, playerVZ As Single
Dim Shared enemies(1 To MAX_ENEMIES) As GameObj
Dim Shared boxLib(1 To MESH_COUNT) As E3D_AABB
Dim Shared vpMat As E3D_Matrix4

' -- sequencer and frame counter, as sequence.bas / dims.bas declare them (milestone log) --
Const SEQ_MAX     = 64
Const SEQ_CRAWL   = 1
Const SEQ_EMPEROR = 2
Const SEQ_PLAY    = 3
Const SEQ_TITLE   = 4
Const SEQ_ARRIVE  = 5
Const SEQ_DOCK    = 6
Dim Shared seqKind(0 To SEQ_MAX - 1) As Integer
Dim Shared seqSval$(0 To SEQ_MAX - 1)
Dim Shared seqLabel$(0 To SEQ_MAX - 1)
Dim Shared seqCount As Integer, seqIdx As Integer
Dim Shared gameFrame As Long
Dim Shared dbgMlogPath As String
Dim Shared dbgMlogState As Integer, dbgMlogSeq As Integer

'$INCLUDE:'../src/sys/debug.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/sys/gametext.bas'

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

Print "=== dbg_output_test ==="
Print ""

$IF WIN THEN
    Print "--- Windows: DBG_InitTty gates on debugMode (no /dev/tty here) ---"

    debugMode = 0 : dbgTtyOK = 0
    DBG_InitTty
    ST_Assert dbgTtyOK = 0, "debugMode=0  -> dbgTtyOK stays disabled"

    debugMode = -1 : dbgTtyOK = 0
    DBG_InitTty
    ST_Assert dbgTtyOK <> 0, "debugMode=-1 (--debug) -> dbgTtyOK enabled"

    ' Exercises the real _Console/_Dest _Console path -- must not error.
    DBG_Print "dbg_output_test: DBG_Print smoke line"
    GTEXT_Log "dbg_output_test: GTEXT_Log smoke line"
    ' DBG_Print restores _Dest 0 (the graphics screen) after printing, which is
    ' correct in production (a real SCREEN is always open by then) but there is
    ' no screen in this $CONSOLE:ONLY test binary -- point back at the console
    ' so the rest of this test's own output stays visible.
    _Dest _Console
    ST_Assert -1, "DBG_Print/GTEXT_Log ran without error while enabled"
$ELSE
    Print "--- Unix: /dev/tty probe lives inline in sss.bas, not unit-testable here ---"
$END IF

' Disabled state must never error, on either platform.
dbgTtyOK = 0
DBG_Print "should be a silent no-op"
GTEXT_Log "should be a silent no-op"
ST_Assert -1, "DBG_Print/GTEXT_Log ran without error while disabled"

Print ""
Print "--- milestone log (SSS_MILESTONE_LOG, for tests/playthrough) ---"
Dim mlFile As String, mlFH As Integer, mlLine As String, mlN As Integer
Dim mlLines(1 To 10) As String
mlFile = _StartDir$ + "/dbg_milestone_test.log"
seqCount = 2
seqKind(0) = SEQ_CRAWL : seqLabel$(0) = "level1" : seqSval$(0) = "txt=stage1 mus=crawl"
seqKind(1) = SEQ_PLAY  : seqLabel$(1) = "level1" : seqSval$(1) = "type=combat mus=game trigger=10 "

Environ "SSS_MILESTONE_LOG="
DBG_MilestoneInit
gameState = GS_CRAWL : seqIdx = 0 : gameFrame = 1
DBG_MilestoneLog
ST_Assert dbgMlogPath = "", "unset: off"

Environ "SSS_MILESTONE_LOG=" + mlFile
DBG_MilestoneInit
ST_Assert dbgMlogPath = mlFile, "set: absolute path used as is"
gameState = GS_CONSENT : seqIdx = -1 : gameFrame = 0 : DBG_MilestoneLog
gameFrame = 1 : DBG_MilestoneLog
gameState = GS_CRAWL : seqIdx = 0 : gameFrame = 7 : DBG_MilestoneLog
gameFrame = 8 : DBG_MilestoneLog
seqIdx = 1 : gameState = GS_PLAYING : gameFrame = 40 : DBG_MilestoneLog
gameState = GS_PLANET : gameFrame = 90 : DBG_MilestoneLog
DBG_MilestoneWrite "120 EXIT"
mlFH = FreeFile
Open mlFile For Input As #mlFH
Do While Not EOF(mlFH)
    Line Input #mlFH, mlLine
    mlN = mlN + 1
    If mlN <= 10 Then mlLines(mlN) = mlLine
Loop
Close #mlFH
Kill mlFile
ST_Assert mlN = 5, "one line per change, plus EXIT (got" + Str$(mlN) + ")"
ST_Assert mlLines(1) = "0 GS_CONSENT -1", "before the sequence starts: frame, state, -1"
ST_Assert mlLines(2) = "7 GS_CRAWL 0 level1 CRAWL txt=stage1 mus=crawl", "sequence step: label, task, args"
ST_Assert mlLines(3) = "40 GS_PLAYING 1 level1 PLAY type=combat mus=game trigger=10", "trailing space trimmed"
ST_Assert mlLines(4) = "90 GS_PLANET 1 level1 PLAY type=combat mus=game trigger=10", "state change alone logs"
ST_Assert mlLines(5) = "120 EXIT", "EXIT line"
Environ "SSS_MILESTONE_LOG=dbg_milestone_rel.log"
DBG_MilestoneInit
ST_Assert dbgMlogPath = _StartDir$ + "/dbg_milestone_rel.log", "relative path: the launch folder"
ST_Assert _FileExists(dbgMlogPath), "file created at startup"
If _FileExists(dbgMlogPath) Then Kill dbgMlogPath
Environ "SSS_MILESTONE_LOG="

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) _
    + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0

' stub: debug.bas reads the overlay key through inputscript.bas, which this test doesn't include
Function KEY_Down% (dbgStubCode As Long)
    KEY_Down% = 0
End Function
