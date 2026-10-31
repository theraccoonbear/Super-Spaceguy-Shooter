' readonly_io_test.bas -- regression tests for issue #283
'
' With ioReadOnly set (the startup probe found the launch folder unwritable),
' the real SETTINGS_Save / SETTINGS_Load (settingsio.bas) and TELEM_Init /
' TELEM_Row (telemetry.bas) must not touch sss_settings.ini or
' sss_telemetry.csv, while the network telemetry batch still fills.
'
' The files live in _STARTDIR$ (the repo root under the test runner), where a
' developer may have real ones, so this test only ever runs the read-only path
' and checks that each file's existence and size are unchanged.
'
' Build: ./tools/buildqb tests/readonly_io_test.bas
' Run:   builds/readonly_io_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"
Const UN_MAX_LEN = 32
Const CAM_DEFAULT_PHI = 0.1545
Const CAM_DEFAULT_R   = 6.80

Type BossObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    hp As Integer
    phase As Integer
End Type

Type CamFollow
    angleLocked AS INTEGER
    orbitTheta  AS SINGLE
    orbitPhi    AS SINGLE
    orbitR      AS SINGLE
End Type

Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Dim Shared boss              As BossObj
Dim Shared camF              As CamFollow
Dim Shared ioReadOnly        As Integer
Dim Shared debugMode         As Integer
Dim Shared volMusic As Single, volSfx As Single, volSpeech As Single
Dim Shared settingNarration As Integer, settingNarrSpeed As Integer, settingFullscreen As Integer
Dim Shared highScore         As Long
Dim Shared telemOn           As Integer
Dim Shared telemSession      As String
Dim Shared telemPlayerID     As String
Dim Shared telemConsent      As Integer
Dim Shared telemKills        As Long
Dim Shared telemBossReached  As Integer
Dim Shared telemBossPhaseLog As Integer
Dim Shared telemDeathCause   As String
Dim Shared telemShotsFired   As Long
Dim Shared telemShotsHit     As Long
Dim Shared telemEscapes      As Long
Dim Shared telemBatch        As String
Dim Shared telemBatchRows    As Long
Dim Shared telemT0           As Long
Dim Shared gameFrame         As Long
Dim Shared telemFlags        As String
Dim Shared levelNum          As Integer
Dim Shared stageKills        As Long
Dim Shared stageKillTarget   As Long
Dim Shared gameState         As Integer
Function DBG_StateName$ (s As Integer) : DBG_StateName$ = "GS_TEST" : End Function
Dim Shared telemExitReason   As String
Dim Shared score             As Long
Dim Shared waveType          As Integer
Dim Shared leaderboardPlayerID As String
Dim Shared telemPlayerName     As String
Dim Shared settingNerf         As Integer
Dim Shared lives               As Integer
Dim Shared credits             As Long
Dim Shared creditsEarned       As Long
Dim Shared creditsSpent        As Long
Dim Shared fuelLevel           As Single
Dim Shared laserEnergy         As Single

Dim Shared roBindsWrites As Integer

Sub DBG_Print (msg As String) : End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Sub HTTP_Get  (u As String, k As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function
Sub E3D_BindsWrite (bwFH As Integer) : roBindsWrites = roBindsWrites + 1 : End Sub
Function E3D_BindsLoadLine% (blKey As String, blRaw As String) : E3D_BindsLoadLine% = 0 : End Function
Sub E3D_PadReselect : End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/sys/settingsio.bas'

' --- test harness ---
Dim Shared tcPass As Integer, tcFail As Integer

Sub TC_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        tcPass = tcPass + 1
    Else
        Print "FAIL  " + label
        tcFail = tcFail + 1
    End If
End Sub

' -1 = missing, else the file's size in bytes
Function RO_Size& (roName As String)
    Dim roFH As Integer
    If _FileExists(_StartDir$ + "/" + roName) = 0 Then RO_Size& = -1 : Exit Function
    roFH = FreeFile
    Open _StartDir$ + "/" + roName For Input As #roFH
    RO_Size& = LOF(roFH)
    Close #roFH
End Function

Print "=== readonly_io_test ==="
Print ""

Dim roSet0 As Long, roCsv0 As Long
roSet0 = RO_Size&("sss_settings.ini")
roCsv0 = RO_Size&("sss_telemetry.csv")

ioReadOnly = -1

Print "--- 1. settings ---"
SETTINGS_Save
TC_Assert roBindsWrites = 0, "1.01  SETTINGS_Save writes nothing when read-only"
telemPlayerID = "" : leaderboardPlayerID = ""
SETTINGS_Load
TC_Assert roBindsWrites = 0, "1.02  SETTINGS_Load's new-ID saves write nothing"
TC_Assert Len(telemPlayerID) >= 32, "1.03  player ID still generated for the session"
TC_Assert RO_Size&("sss_settings.ini") = roSet0, "1.04  sss_settings.ini unchanged"
Print ""

Print "--- 2. telemetry ---"
telemOn = -1
DB_URL = "https://example.invalid/rest/v1"
telemSession = "20260101000000"
TELEM_Init
TELEM_Row "enemy_killed", "score=100"
TELEM_Row "enemy_killed", "score=200"
TC_Assert RO_Size&("sss_telemetry.csv") = roCsv0, "2.01  sss_telemetry.csv not created or appended"
TC_Assert InStr(telemBatch, "score=200") > 0, "2.02  network telemetry batch still fills"
Print ""

Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
