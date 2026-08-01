' dbg_output_test.bas -- regression guard for Windows --debug logging (issue #200)
'
' Before the fix, DBG_Print/GTEXT_Log probed for /dev/tty at startup, which does
' not exist on Windows -- dbgTtyOK stayed 0 forever, silently swallowing every
' DBG_Print call (including HTTP/curl error reporting) regardless of --debug.
'
' Covers:
'   1. Windows: --debug (debugMode=-1) must enable dbgTtyOK via DBG_InitTty
'   2. Windows: without --debug (debugMode=0), dbgTtyOK stays disabled
'   3. Unix: DBG_InitTty's outcome depends only on the /dev/tty probe, not debugMode
'   4. DBG_Print / GTEXT_Log don't error in either gating state
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

'$INCLUDE:'../src/sys/debug.bas'
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
    Print "--- Unix: DBG_InitTty outcome depends only on the /dev/tty probe ---"

    debugMode = 0 : dbgTtyOK = 0
    DBG_InitTty
    Dim ttyA As Integer : ttyA = dbgTtyOK

    debugMode = -1 : dbgTtyOK = 0
    DBG_InitTty
    Dim ttyB As Integer : ttyB = dbgTtyOK

    ST_Assert ttyA = ttyB, "debugMode does not affect the /dev/tty probe outcome"
$END IF

' Disabled state must never error, on either platform.
dbgTtyOK = 0
DBG_Print "should be a silent no-op"
GTEXT_Log "should be a silent no-op"
ST_Assert -1, "DBG_Print/GTEXT_Log ran without error while disabled"

Print ""
Print "=== " + LTrim$(Str$(stPassed + stFailed)) + " tests: " + LTrim$(Str$(stPassed)) _
    + " passed, " + LTrim$(Str$(stFailed)) + " failed ==="
If stFailed > 0 Then System 1 Else System 0
