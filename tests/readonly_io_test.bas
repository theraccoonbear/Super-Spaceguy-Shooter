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

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"



Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Function DBG_StateName$ (s As Integer) : DBG_StateName$ = "GS_TEST" : End Function


Sub DBG_Print (msg As String) : End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Sub HTTP_Get  (u As String, k As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function

'$INCLUDE:'../src/gameplay/difficulty.bas'
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
TC_Assert RO_Size&("sss_settings.ini") = roSet0, "1.01  SETTINGS_Save writes nothing when read-only"
telemPlayerID = "" : leaderboardPlayerID = ""
SETTINGS_Load
TC_Assert RO_Size&("sss_settings.ini") = roSet0, "1.02  SETTINGS_Load's new-ID saves write nothing"
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
