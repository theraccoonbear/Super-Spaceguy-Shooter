' run_end_test.bas -- regression tests for issue #331
'
' Reaching a TITLE task only ends a run that actually started. Drives the real
' sequencer (sequence.bas, the real assets/sequence.txt), TELEM_SessionEnd
' (telemetry.bas), the credit cash-out (credits.bas) and PLAYER_TakeDamage
' (player.bas), and counts session ends and their exit reasons:
'   1. boot, SPACE on the emperor card: no session end, no cash-out
'   2. the same with a session open and the cash-out armed: still nothing
'   3. SPACE on the emperor card lands where ESC does
'   4. a full run to the outro: one session end, exit=win, one cash-out
'   5. death: one session end, exit=death; reaching a TITLE after it adds none
'   6. quit from the pause menu: one session end, exit=quit, no cash-out
'   7. --scene title / crawl:death_final reach a TITLE without a run: nothing
'
' Session ends are counted through the real code's DBG_Print call, so telemOn
' stays 0 and no sss_telemetry.csv is written.
'
' Build: ./tools/buildqb tests/run_end_test.bas
' Run:   builds/run_end_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT
$EMBED:'assets/sequence.txt':'SEQTXT'

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"
Const GS_TITLE     = 0
Const GS_PLAYING   = 1
Const GS_PLANET    = 3
Const GS_CINEMATIC = 4
Const GS_INTRO     = 5
Const GS_CRAWL     = 6
Const LEVEL_COMBAT   = 0
Const LEVEL_ASTEROID = 1
Const LEVEL_BOSS     = 2
Const PLANET_COUNT   = 6
Const NERF_FACTOR    = 0.1
Const BOSS_WARN_FRAMES  = 120
Const DIFF_RAMP_DURATION = 600.0
Const DIFF_STAGE_COUNT   = 6.0
Const CAM_OFFSET_X = 6.5
Const CAM_OFFSET_Y = 2.0
Const MAX_ENEMIES  = 35
Const MAX_BULLETS  = 256
Const BULLET_SPEED = 0.35
Const BULLET_RANGE = 110
Const FIRE_TICK    = 0.025
Const MESH_BULLET  = 4
Const E3D_KEY_SPACE = 32
Const CAM_LAG_RATE  = 0.1
Const CAM_FWD_RATE  = 0.1

Type BossObj
    active  As Integer
    meshIdx As Integer
    px As Single : py As Single : pz As Single
    hp As Integer
    warnTimer As Integer
End Type

Type ReObj
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

' shared by player.bas / telemetry.bas / credits.bas
Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Dim Shared boss              As BossObj
Dim Shared player            As ReObj
Dim Shared bullets(1 To MAX_BULLETS) As ReObj
Dim Shared enemies(1 To MAX_ENEMIES) As ReObj
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
Dim Shared shieldMax         As Integer : shieldMax = 100
Dim Shared fuelMax           As Single  : fuelMax = 100
Dim Shared shipMaxVel        As Single  : shipMaxVel = 0.12
Dim Shared fireCool          As Single  : fireCool = 0.18
Dim Shared gunShots          As Integer : gunShots = 1
Dim Shared gunSpread         As Single
Dim Shared rollTimer         As Integer
Dim Shared rollDir           As Integer
Dim Shared rollFrames        As Integer : rollFrames = 20
Dim Shared rollSpeed         As Single
Dim Shared noHitFrames       As Long
Dim Shared credits           As Long
Dim Shared creditsEarned     As Long
Dim Shared creditsSpent      As Long
Function UPG_ArmourDmg% (d As Integer) : UPG_ArmourDmg% = d : End Function
Dim Shared shipLives         As Integer
Dim Shared deathTimer        As Integer
Dim Shared gameOver          As Integer
Dim Shared fxShakeTimer      As Integer
Dim Shared fxFlashTimer      As Integer
Dim Shared telemOn           As Integer
Dim Shared ioReadOnly        As Integer
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
Dim Shared telemCsvDir       As String
Dim Shared telemCsvBuf       As String
Dim Shared settingsDir       As String
Dim Shared telemBatchRows    As Long
Dim Shared telemT0           As Long
Dim Shared gameFrame         As Long
Dim Shared telemFlags        As String
Function DBG_StateName$ (s As Integer) : DBG_StateName$ = "GS_TEST" : End Function
Dim Shared telemExitReason   As String
Dim Shared score             As Long
Dim Shared waveType          As Integer
Dim Shared leaderboardPlayerID As String
Dim Shared telemPlayerName     As String
Dim Shared settingNerf         As Integer
Dim Shared godMode             As Integer

' shared by sequence.bas
Dim Shared highScore    As Long
Dim Shared stageKillTarget As Long
Dim Shared levelNum     As Integer
Dim Shared levelType    As Integer
Dim Shared bltActive    As Integer
Dim Shared diffTime     As Single
Dim Shared diffScale    As Single
Dim Shared spawnTimer   As Single
Dim Shared waveStageN   As Integer
Dim Shared bossCfgHp    As Integer
Dim Shared astFieldStart As Single
Dim Shared astDestName  As String
Dim Shared planetCurrent As Integer
Dim Shared planetNameIdx As Integer
Dim Shared planetTimer  As Integer
Dim Shared scrH         As Single
Dim Shared tt           As Single
Dim Shared planetNames(1 To PLANET_COUNT) As String
Dim Shared bossMusList$(0 To 7)
Dim Shared bossMusCnt        As Integer
Dim Shared bossSpeechList$(0 To 7)
Dim Shared bossSpeechCnt     As Integer
Dim Shared bossAttackList$(0 To 7)
Dim Shared bossAttackCnt     As Integer
Dim Shared bossSeekStr     As Single
Dim Shared introTimer As Integer
Dim Shared stageKills     As Long
Dim Shared scrW         As Single
Dim Shared planetR       As Single
Dim Shared planetBgR     As Single
Dim Shared planetBgAlpha As Single
Dim Shared astParsecs    As Integer

Dim Shared reEnds As Integer, reLastExit As String, reLastCue As String, reSaves As Integer

Sub DBG_Print (msg As String)
    If Left$(msg, 18) = "TELEM: SessionEnd " Then reEnds = reEnds + 1 : reLastExit = telemExitReason
End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String) : End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function
Sub SND_Hit   : End Sub
Sub SND_Death : End Sub
Sub SND_Shoot : End Sub
Sub FX_SpawnBurst (cx As Single, cy As Single, cz As Single, n As Integer, spd As Single, lifBase As Integer, lifVar As Integer, clr As Long) : End Sub
Sub MUS_SetCue (c As String) : reLastCue = c : End Sub
Sub StarfieldReset (x As Single, y As Single, z As Single) : End Sub
Sub CRAWL_Prep (k As String, h As Single) : End Sub
Sub SETTINGS_Save () : reSaves = reSaves + 1 : End Sub
Sub BELT_Init (w As Single, h As Single) : End Sub
Sub DOCK_Enter () : gameState = 15 : End Sub   ' GS_DOCK
Sub SPK_Say (s As String) : End Sub
Function GTEXT_Get$ (k As String) : GTEXT_Get$ = "" : End Function

Dim Shared tutorialRun As Integer   ' shared by sequence.bas / telemetry.bas / player.bas (dims.bas)
'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/sequence.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
'$INCLUDE:'../src/gameplay/player.bas'

Dim Shared rePass As Integer, reFail As Integer

Sub RE_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        rePass = rePass + 1
    Else
        Print "FAIL  " + label
        reFail = reFail + 1
    End If
End Sub

Function RE_FirstTitle%
    Dim rftI As Integer
    RE_FirstTitle% = -1
    For rftI = 0 To seqCount - 1
        If seqKind(rftI) = SEQ_TITLE Then RE_FirstTitle% = rftI : Exit Function
    Next rftI
End Function

' A fresh process: the sequence loaded and nothing played yet (crBonusDone starts at -1).
Sub RE_Boot
    SEQ_Load _EMBEDDED$("SEQTXT")
    seqRunActive = 0 : crBonusDone = -1 : crTallyTimer = 0
    telemSession = "" : telemExitReason = ""
    score = 0 : highScore = 0 : credits = 0
    reEnds = 0 : reLastExit = "" : reLastCue = "" : reSaves = 0
    gameState = GS_TITLE
End Sub

' GAME_NewGame's run start, from the title (game.bas)
Sub RE_NewGame
    CR_ResetRun : credits = 0 : score = 0
    lives = 100 : shipLives = 1 : deathTimer = 0 : gameOver = 0
    reEnds = 0 : reLastExit = ""
    TELEM_SessionStart
    SEQ_Advance
End Sub

' SEQ_Advance until gameState is reStop (at most reMax steps); the step count, or -1.
Function RE_AdvanceTo% (reStop As Integer, reMax As Integer)
    Dim ratN As Integer
    For ratN = 1 To reMax
        SEQ_Advance
        If gameState = reStop Then RE_AdvanceTo% = ratN : Exit Function
    Next ratN
    RE_AdvanceTo% = -1
End Function

DB_URL = "https://example.test/rest/v1" : DB_KEY = "key" : telemConsent = -1

Print "=== run_end_test ==="
Print ""

Dim reTitle As Integer, reN As Integer

Print "--- 1. boot, SPACE on the emperor card ---"
RE_Boot
reTitle = RE_FirstTitle%
SEQ_Advance                                   ' intro crawl
SEQ_Advance                                   ' emperor card
RE_Assert gameState = GS_INTRO,               "1.01  on the emperor card"
SEQ_Advance                                   ' SPACE (intro.bas)
RE_Assert gameState = GS_TITLE And seqIdx = reTitle, "1.02  SPACE lands on the first title"
RE_Assert reEnds = 0,                         "1.03  no session end"
RE_Assert telemExitReason = "",               "1.04  no exit reason set"
RE_Assert crTallyTimer = 0 And reSaves = 0,   "1.05  no cash-out tally, no high-score save"
RE_Assert seqRunActive = 0,                   "1.06  no run in progress"
Print ""

Print "--- 2. SPACE on the emperor card with a session open and the cash-out armed ---"
RE_Boot
CR_ResetRun : credits = 300 : score = 50
TELEM_SessionStart
SEQ_Advance : SEQ_Advance                     ' intro crawl, emperor card
SEQ_Advance                                   ' SPACE
RE_Assert reEnds = 0 And telemSession <> "",  "2.01  the session is not ended"
RE_Assert credits = 300 And score = 50 And crBonusDone = 0, "2.02  no cash-out: credits kept, score unchanged"
RE_Assert highScore = 0 And reSaves = 0,      "2.03  high score not touched"
RE_Assert telemExitReason = "",               "2.04  no exit=win"
Print ""

Print "--- 3. SPACE and ESC on the emperor card land on the same title ---"
Dim reSpIdx As Integer, reSpState As Integer, reSpCue As String
RE_Boot
SEQ_Advance : SEQ_Advance
SEQ_Advance
reSpIdx = seqIdx : reSpState = gameState : reSpCue = reLastCue
RE_Boot
SEQ_Advance : SEQ_Advance
SEQ_RewindToTitle : gameState = GS_TITLE : MUS_SetCue "title"   ' ESC (intro.bas)
RE_Assert reSpIdx = seqIdx,                   "3.01  same sequence position"
RE_Assert reSpState = gameState,              "3.02  same game state"
RE_Assert reSpCue = reLastCue,                "3.03  same music cue (" + reSpCue + ")"
RE_Assert reEnds = 0,                         "3.04  neither ends a session"
SEQ_Advance
RE_Assert gameState = GS_CRAWL And seqIdx = reTitle + 1, "3.05  New Game after SPACE goes to chapter 1"
Print ""

Print "--- 4. a full run to the outro ---"
RE_Boot
SEQ_Advance : SEQ_Advance : SEQ_Advance       ' boot, SPACE on the emperor card
RE_NewGame
RE_Assert gameState = GS_CRAWL And seqIdx = reTitle + 1, "4.01  New Game -> chapter-1 crawl"
RE_Assert seqRunActive = 0,                   "4.02  run not in progress until the first PLAY"
SEQ_Advance
RE_Assert gameState = GS_PLAYING And seqRunActive <> 0, "4.03  first PLAY: run in progress"
credits = 300 : score = 1000
reN = RE_AdvanceTo%(GS_TITLE, 64)
RE_Assert reN > 0 And seqIdx = reTitle,       "4.04  the outro ends on the first title"
RE_Assert reEnds = 1 And reLastExit = "win",  "4.05  exactly one session end, exit=win"
RE_Assert score = 1300 And credits = 0 And crBonusPts = 300, "4.06  one cash-out: 300 credits -> +300"
RE_Assert crTallyTimer = 300,                 "4.07  the win tally is shown"
RE_Assert highScore = 1300 And reSaves = 1,   "4.08  high score saved once"
RE_Assert seqRunActive = 0,                   "4.09  run over"
seqIdx = reTitle - 1 : SEQ_Advance            ' a later landing on a TITLE (e.g. --scene title)
RE_Assert reEnds = 1 And score = 1300 And reSaves = 1, "4.10  reaching a TITLE again adds nothing"
Print ""

Print "--- 5. death ---"
RE_Boot
SEQ_Advance : SEQ_Advance : SEQ_Advance
RE_NewGame
SEQ_Advance                                   ' chapter-1 PLAY
credits = 200 : score = 500
PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
RE_Assert gameOver <> 0,                      "5.01  game over"
RE_Assert reEnds = 1 And reLastExit = "death", "5.02  exactly one session end, exit=death"
RE_Assert score = 700 And credits = 0,        "5.03  one cash-out at the death"
RE_Assert seqRunActive = 0,                   "5.04  run over"
SEQ_RewindToTitle : gameState = GS_TITLE      ' game-over SPACE (gameover.bas)
seqIdx = reTitle - 1 : SEQ_Advance            ' the sequence then reaching a TITLE task
RE_Assert reEnds = 1 And reLastExit = "death", "5.05  no second session end, no exit=win"
RE_Assert score = 700 And crTallyTimer = 0,   "5.06  no second cash-out"
Print ""

Print "--- 6. quit from the pause menu ---"
RE_Boot
SEQ_Advance : SEQ_Advance : SEQ_Advance
RE_NewGame
SEQ_Advance                                   ' chapter-1 PLAY
credits = 200 : score = 500
SEQ_QuitRun
RE_Assert reEnds = 1 And reLastExit = "quit", "6.01  exactly one session end, exit=quit"
RE_Assert credits = 200 And score = 500,      "6.02  no cash-out on quit"
RE_Assert gameState = GS_TITLE And seqIdx = reTitle And reLastCue = "title", "6.03  parked on the first title"
RE_Assert seqRunActive = 0,                   "6.04  run over"
RE_NewGame
RE_Assert gameState = GS_CRAWL And seqIdx = reTitle + 1, "6.05  the next New Game starts chapter 1"
Print ""

Print "--- 7. scene jumps that reach a TITLE without a run ---"
RE_Boot
CR_ResetRun : credits = 100
reN = SEQ_JumpToScene("title") : SEQ_Advance
RE_Assert gameState = GS_TITLE And reEnds = 0 And credits = 100, "7.01  --scene title: no session end, no cash-out"
RE_Boot
CR_ResetRun : credits = 100
reN = SEQ_JumpToScene("crawl:death_final") : SEQ_Advance   ' the crawl ends -> SEQ_Advance
RE_Assert gameState = GS_TITLE And reEnds = 0 And credits = 100, "7.02  --scene crawl:death_final: no session end, no cash-out"
RE_Boot
CR_ResetRun : credits = 100
reN = SEQ_JumpToScene("playing6") : SEQ_Advance
RE_Assert seqRunActive <> 0,                  "7.03  --scene playing6: the PLAY starts a run"
reN = RE_AdvanceTo%(GS_TITLE, 16)
RE_Assert reN > 0 And credits = 0 And crBonusPts = 100, "7.04  its win cashes out once"
Print ""

Print "--- 8. closing the window or QUIT on the title (#346) ---"
RE_Boot
SEQ_QuitProcess
RE_Assert reEnds = 0 And telemExitReason = "",  "8.01  no run (title, boot): no session end"
RE_Boot
SEQ_Advance : SEQ_Advance : SEQ_Advance
RE_NewGame
SEQ_Advance                                   ' chapter-1 PLAY
credits = 200 : score = 500
SEQ_QuitProcess
RE_Assert reEnds = 1 And reLastExit = "quit", "8.02  a run in progress ends once as exit=quit"
RE_Assert credits = 200 And score = 500,      "8.03  no cash-out"
RE_Assert seqRunActive = 0,                   "8.04  run over"
SEQ_QuitProcess
RE_Assert reEnds = 1,                         "8.05  closing again ends nothing more"
RE_Boot
SEQ_Advance : SEQ_Advance : SEQ_Advance
RE_NewGame
SEQ_Advance
SEQ_QuitRun
SEQ_QuitProcess
RE_Assert reEnds = 1,                         "8.06  pause-menu quit then close: still one session end"
RE_Boot
SEQ_Advance : SEQ_Advance : SEQ_Advance
RE_NewGame
SEQ_Advance
PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
SEQ_QuitProcess
RE_Assert reEnds = 1 And reLastExit = "death", "8.07  a run that already died: close adds nothing"
Print ""

Print "=== " + LTrim$(Str$(rePass + reFail)) + " tests: " _
    + LTrim$(Str$(rePass)) + " passed, " + LTrim$(Str$(reFail)) + " failed ==="
If reFail > 0 Then System 1 Else System 0
