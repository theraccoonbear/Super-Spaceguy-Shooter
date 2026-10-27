' death_telem_test.bas -- regression tests for issue #169
'
' Drives the real PLAYER_TakeDamage (player.bas) and TELEM_SessionEnd
' (telemetry.bas) and checks that one death ends the session exactly once:
' two lethal hits in the same frame cost one ship and log one session end,
' and a repeated TELEM_SessionEnd call does nothing.
'
' Session ends are counted through the real code's DBG_Print/HTTP_Post calls,
' so telemOn stays 0 and no sss_telemetry.csv is written.
'
' Build: ./tools/buildqb tests/death_telem_test.bas
' Run:   builds/death_telem_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

Const VERSION$ = "0.0.0-test"
Const GS_PLAYING   = 1
Const GS_CINEMATIC = 4
Const MAX_ENEMIES  = 35
Const MAX_BULLETS  = 30
Const MESH_BULLET  = 4
Const E3D_KEY_SPACE = 32
Const CAM_LAG_RATE  = 0.1
Const CAM_FWD_RATE  = 0.1

Type BossObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    hp As Integer
End Type

Type DtObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    vx As Single : vy As Single : vz As Single
    rx As Single : ry As Single : rz As Single
    life As Single
    scl As Single
End Type

Type CamFollow
    lagY As Single : lagZ As Single
    fwdY As Single : fwdZ As Single
End Type

Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Dim Shared boss              As BossObj
Dim Shared player            As DtObj
Dim Shared bullets(1 To MAX_BULLETS) As DtObj
Dim Shared enemies(1 To MAX_ENEMIES) As DtObj
Dim Shared camF              As CamFollow
Dim Shared held(0 To 32767)  As Integer
Dim Shared gameState         As Integer
Dim Shared fuelStranded      As Integer
Dim Shared cinPhase          As Single
Dim Shared playerVY          As Single
Dim Shared playerVZ          As Single
Dim Shared isManeuver        As Integer
Dim Shared fireTimer         As Single
Dim Shared laserEnergy       As Single
Dim Shared fuelLevel         As Single
Dim Shared lives             As Integer
Dim Shared shipLives         As Integer
Dim Shared deathTimer        As Integer
Dim Shared gameOver          As Integer
Dim Shared fxShakeTimer      As Integer
Dim Shared fxFlashTimer      As Integer
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
Dim Shared telemExitReason   As String
Dim Shared score             As Long
Dim Shared waveType          As Integer
Dim Shared leaderboardPlayerID As String
Dim Shared telemPlayerName     As String
Dim Shared settingNerf         As Integer

Dim Shared dtEnds As Integer, dtScorePosts As Integer

Sub DBG_Print (msg As String)
    If Left$(msg, 18) = "TELEM: SessionEnd " Then dtEnds = dtEnds + 1
End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String)
    If t = "score_post" Then dtScorePosts = dtScorePosts + 1
End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function
Sub SND_Hit   : End Sub
Sub SND_Death : End Sub
Sub SND_Shoot : End Sub
Sub FX_SpawnBurst (cx As Single, cy As Single, cz As Single, n As Integer, spd As Single, lifBase As Integer, lifVar As Integer, clr As Long) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/gameplay/player.bas'

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

Sub DT_NewGame (dtShips As Integer)
    gameState = GS_PLAYING : lives = 100 : shipLives = dtShips
    deathTimer = 0 : gameOver = 0 : score = 500
    dtEnds = 0 : dtScorePosts = 0
    TELEM_SessionStart
End Sub

DB_URL = "https://example.test/rest/v1" : DB_KEY = "key" : telemConsent = -1

Print "=== death_telem_test ==="
Print ""

Print "--- 1. two lethal hits in one frame on the last ship ---"
DT_NewGame 1
PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
TC_Assert shipLives = 0,     "1.01  one ship lost"
TC_Assert gameOver <> 0,     "1.02  game over set"
TC_Assert dtEnds = 1,        "1.03  one session end"
TC_Assert dtScorePosts = 1,  "1.04  one score post"
TC_Assert telemExitReason = "death", "1.05  exit reason is death"
Print ""

Print "--- 2. two lethal hits in one frame with ships to spare ---"
DT_NewGame 3
PLAYER_TakeDamage DMG_ASTEROID, SHAKE_COLLISION, FLASH_COLLISION
PLAYER_TakeDamage DMG_ASTEROID, SHAKE_COLLISION, FLASH_COLLISION
TC_Assert shipLives = 2, "2.01  one ship lost, not two"
TC_Assert gameOver = 0,  "2.02  no game over"
TC_Assert dtEnds = 0,    "2.03  session still open"
Print ""

Print "--- 3. TELEM_SessionEnd called twice ---"
DT_NewGame 1
telemExitReason = "quit"
TELEM_SessionEnd
Dim dt3First As Integer : dt3First = dtEnds
TELEM_SessionEnd
TC_Assert dt3First = 1,      "3.01  first call ends the session"
TC_Assert dtEnds = 1,        "3.02  second call is a no-op"
TC_Assert dtScorePosts = 1,  "3.03  score posted once"
TC_Assert telemSession = "", "3.04  session cleared"
Print ""

Print "--- 4. a new session can end again ---"
DT_NewGame 1
TELEM_SessionEnd
TC_Assert dtEnds = 1, "4.01  next session ends once"
Print ""

Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
