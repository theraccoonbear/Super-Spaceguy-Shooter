' telem_creds_test.bas -- unit tests for TELEM_LoadCredentials
'
' Verifies that the .env parser correctly reads DB_URL and DB_KEY,
' ignores unrecognised keys, and handles blank lines and comments.
' A failing test here means the CI build would ship with broken credentials.
'
' Build: ./tools/buildqb tests/telem_creds_test.bas
' Run:   builds/telem_creds_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

' --- minimal stubs so telemetry.bas compiles standalone ---
Dim Shared DB_URL As String
Dim Shared DB_KEY As String

Const VERSION$ = "0.0.0-test"

' BossObj TYPE required by TELEM_BossPhase
Type BossObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    vx As Single : vy As Single : vz As Single
    rx As Single : ry As Single : rz As Single
    drx As Single : dry As Single : drz As Single
    scl As Single
    life As Single
    hp        As Integer
    phase     As Integer
    fireTimer As Single
    moveTimer As Single
    targetY   As Single
    targetZ   As Single
    state     As Integer
    warnTimer As Integer
End Type

' Vars referenced by telemetry.bas but not under test
Dim Shared boss           As BossObj
Dim Shared telemOn         As Integer
Dim Shared telemSession    As String
Dim Shared telemPlayerID   As String
Dim Shared telemConsent    As Integer
Dim Shared telemKills      As Long
Dim Shared telemBossReached  As Integer
Dim Shared telemBossPhaseLog As Integer
Dim Shared telemDeathCause   As String
Dim Shared telemShotsFired   As Long
Dim Shared telemShotsHit     As Long
Dim Shared telemEscapes      As Long
Dim Shared telemBatch        As String
Dim Shared telemExitReason   As String
Dim Shared score             As Long
Dim Shared waveType          As Integer
Dim Shared leaderboardPlayerID As String
Dim Shared telemPlayerName     As String
Dim Shared settingNerf         As Integer
Dim Shared lives               As Integer
Dim Shared fuelLevel           As Single
Dim Shared laserEnergy         As Single

Sub DBG_Print (msg As String) : End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Sub HTTP_Get  (u As String, k As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function

'$INCLUDE:'../src/sys/telemetry.bas'

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

' --- helpers ---
Sub TC_Reset ()
    DB_URL = "" : DB_KEY = ""
End Sub

Print "=== telem_creds_test ==="
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 1. Normal two-key .env
' ────────────────────────────────────────────────────────────────────────────
Print "--- 1. normal .env ---"
TC_Reset
Dim tc1 As String
tc1 = "DB_URL=https://example.supabase.co/rest/v1" + Chr$(10) _
    + "DB_KEY=myapikey" + Chr$(10)
TELEM_LoadCredentials tc1
TC_Assert DB_URL = "https://example.supabase.co/rest/v1", "1.01  DB_URL parsed"
TC_Assert DB_KEY = "myapikey",                             "1.02  DB_KEY parsed"
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 2. Comments and blank lines are ignored
' ────────────────────────────────────────────────────────────────────────────
Print "--- 2. comments and blanks ---"
TC_Reset
Dim tc2 As String
tc2 = "# This is a comment" + Chr$(10) _
    + "" + Chr$(10) _
    + "DB_URL=https://a.b/v1" + Chr$(10) _
    + "# another comment" + Chr$(10) _
    + "DB_KEY=secret" + Chr$(10)
TELEM_LoadCredentials tc2
TC_Assert DB_URL = "https://a.b/v1", "2.01  DB_URL after comment"
TC_Assert DB_KEY = "secret",         "2.02  DB_KEY after blank line"
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 3. Old key names are NOT recognised (regression guard)
' ────────────────────────────────────────────────────────────────────────────
Print "--- 3. old key names rejected (regression) ---"
TC_Reset
Dim tc3 As String
tc3 = "TELEM_NET_URL=https://old.url/telem" + Chr$(10) _
    + "TELEM_NET_KEY=oldkey" + Chr$(10) _
    + "LB_BASE_URL=https://old.url" + Chr$(10) _
    + "LB_KEY=lbkey" + Chr$(10)
TELEM_LoadCredentials tc3
TC_Assert DB_URL = "", "3.01  TELEM_NET_URL not loaded into DB_URL"
TC_Assert DB_KEY = "", "3.02  TELEM_NET_KEY not loaded into DB_KEY"
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 4. Missing keys leave vars empty
' ────────────────────────────────────────────────────────────────────────────
Print "--- 4. missing keys ---"
TC_Reset
TELEM_LoadCredentials "DB_URL=https://only.url/v1" + Chr$(10)
TC_Assert DB_URL = "https://only.url/v1", "4.01  DB_URL set"
TC_Assert DB_KEY = "",                    "4.02  DB_KEY empty when absent"
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 5. Empty content leaves vars empty
' ────────────────────────────────────────────────────────────────────────────
Print "--- 5. empty content ---"
TC_Reset
TELEM_LoadCredentials ""
TC_Assert DB_URL = "", "5.01  DB_URL empty"
TC_Assert DB_KEY = "", "5.02  DB_KEY empty"
Print ""

' ────────────────────────────────────────────────────────────────────────────
' 6. Value containing '=' is preserved intact
' ────────────────────────────────────────────────────────────────────────────
Print "--- 6. value with embedded '=' ---"
TC_Reset
TELEM_LoadCredentials "DB_KEY=abc=def=ghi" + Chr$(10)
TC_Assert DB_KEY = "abc=def=ghi", "6.01  embedded '=' in value preserved"
Print ""

' ────────────────────────────────────────────────────────────────────────────
Print ""
Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
