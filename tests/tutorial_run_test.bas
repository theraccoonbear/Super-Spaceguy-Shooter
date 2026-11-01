' tutorial_run_test.bas -- the isolated tutorial run (#240)
'
' Drives the real sequencer (sequence.bas, the real assets/sequence.txt), telemetry.bas,
' credits.bas and player.bas with tutorialRun set, and checks the run leaves no record:
'   1. entry: the tutorial block is reached by label, not by NEXT, and is no ARRIVE/DOCK stage
'   2. telemetry: no CSV row, no batch row, no session start or end, whatever the session state
'   3. finishing: no session end, no cash-out, no high score, flag cleared at the title
'   4. quitting from the pause menu: same, and the flag is cleared
'   5. shields, fuel and stranding are protected; death is unreachable
'   6. --god behaves as before (godMode untouched, still refills, still records outside a tutorial)
'   7. a normal run after a tutorial records everything (session, cash-out, high score, death)
'   8. an abandoned tutorial flag is cleared by the next New Game's reset
'
' GAME_StartTutorial / GAME_ResetState (game.bas) pull in the whole game; TU_Start mirrors
' their two steps (clear the flag, jump to the label, set the flag, advance). The real entry
' is exercised by `sss --scene tutorial` (see the PR's by-hand section).
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/tutorial_run_test   (exit 0 = all pass)

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
Dim Shared tutorialRun         As Integer

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

Sub RE_Boot
    SEQ_Load _EMBEDDED$("SEQTXT")
    seqRunActive = 0 : crBonusDone = -1 : crTallyTimer = 0 : tutorialRun = 0
    telemSession = "" : telemExitReason = "" : telemCsvBuf = "" : telemBatch = "" : telemBatchRows = 0
    score = 0 : highScore = 0 : credits = 0 : godMode = 0
    reEnds = 0 : reLastExit = "" : reLastCue = "" : reSaves = 0
    gameState = GS_TITLE
    lives = 100 : fuelLevel = fuelMax : fuelStranded = 0 : shipLives = 1 : deathTimer = 0 : gameOver = 0
    laserEnergy = 100
    SEQ_RewindToTitle
End Sub

' GAME_NewGame's run start, from the title (game.bas)
Sub RE_NewGame
    tutorialRun = 0
    CR_ResetRun : credits = 0 : score = 0 : levelNum = 0
    lives = 100 : shipLives = 1 : deathTimer = 0 : gameOver = 0
    reEnds = 0 : reLastExit = ""
    TELEM_SessionStart
    SEQ_Advance
End Sub

' GAME_StartTutorial's run start, from the title (game.bas)
Function TU_Start%
    tutorialRun = 0
    CR_ResetRun : credits = 0 : score = 0 : levelNum = 0
    lives = 100 : shipLives = 1 : deathTimer = 0 : gameOver = 0
    reEnds = 0 : reLastExit = ""
    If SEQ_JumpToLabel%(SEQ_TUTORIAL_LABEL) < 0 Then TU_Start% = 0 : Exit Function
    tutorialRun = -1
    SEQ_Advance
    TU_Start% = -1
End Function

Function RE_AdvanceTo% (reStop As Integer, reMax As Integer)
    Dim ratN As Integer
    For ratN = 1 To reMax
        SEQ_Advance
        If gameState = reStop Then RE_AdvanceTo% = ratN : Exit Function
    Next ratN
    RE_AdvanceTo% = -1
End Function

Sub RE_Hit
    PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
    PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
End Sub

DB_URL = "https://example.test/rest/v1" : DB_KEY = "key" : telemConsent = -1
telemOn = -1 : telemCsvDir = "/nonexistent-csv-dir"

Print "=== tutorial_run_test ==="
Print ""

Dim reTitle As Integer, reN As Integer, reTb As Integer, reOk As Integer, reIdx As Integer

Print "--- 1. entry ---"
RE_Boot
reTitle = RE_FirstTitle%
reTb = SEQ_FindBlock%(SEQ_TUTORIAL_LABEL)
RE_Assert reTb >= 0 And seqBlkSecret(reTb) <> 0, "1.01  the tutorial block exists and is secret"
reN = seqBlkFirst(reTb)
RE_Assert seqKind(reN) = SEQ_PLAY And seqLabel$(reN) = "tutorial", "1.02  it starts with a PLAY"
RE_Assert SEQ_GetKV$(seqSval$(reN), "type") = "combat" And Val(SEQ_GetKV$(seqSval$(reN), "trigger")) = 3, "1.03  a short combat PLAY, trigger 3"
reOk = -1
For reIdx = reN To reN + seqBlkLen(reTb) - 1
    If seqKind(reIdx) = SEQ_ARRIVE Or seqKind(reIdx) = SEQ_DOCK Then reOk = 0
Next reIdx
RE_Assert reOk <> 0,                          "1.04  no ARRIVE or DOCK in the block (levelNum-indexed planet tables)"
reOk = 0
For reIdx = 0 To seqCount - 1
    If seqBlkNext$(seqTaskBlk(reIdx)) = SEQ_TUTORIAL_LABEL Then reOk = -1
Next reIdx
RE_Assert reOk = 0,                           "1.05  no block's NEXT reaches it"
seqLastError = "" : reIdx = SEQ_JumpToLabel%("nonesuch")
RE_Assert reIdx = -1 And Len(seqLastError) > 0, "1.06  an unknown label is refused with an error"
RE_Assert SEQ_JumpToScene("tutorial") = reN,  "1.07  --scene tutorial resolves to the block's first task"
RE_Boot
RE_Assert TU_Start% <> 0,                     "1.08  the run starts"
RE_Assert gameState = GS_PLAYING And tutorialRun <> 0, "1.09  playing, run flag set"
RE_Assert levelNum = 1 And stageKillTarget = 3 And levelType = LEVEL_COMBAT, "1.10  stage 1 style combat, kill target 3"
RE_Assert seqRunActive = 0,                   "1.11  no run in progress for the sequencer (PLAY does not set it)"
RE_Assert telemSession = "" And reEnds = 0,   "1.12  no session"
Print ""

Print "--- 2. telemetry ---"
RE_Boot
reOk = TU_Start%
telemSession = "stale"
TELEM_PlayerDamaged
TELEM_EnemyKilled
TELEM_StageClear 1, 10, 5, 90
TELEM_FuelExhausted
CR_StageClear
TELEM_SessionEnd
RE_Assert telemCsvBuf = "",                   "2.01  no CSV row written"
RE_Assert telemBatch = "" And telemBatchRows = 0, "2.02  no row queued for the POST"
RE_Assert reEnds = 0 And telemSession = "stale", "2.03  SessionEnd does nothing (no leaderboard post)"
TELEM_SessionStart
RE_Assert telemCsvBuf = "" And telemSession = "stale", "2.04  SessionStart starts no session and writes no row"
tutorialRun = 0
TELEM_PlayerDamaged
RE_Assert Len(telemCsvBuf) > 0,               "2.05  control: outside a tutorial the same call writes a row"
Print ""

Print "--- 3. finishing the tutorial ---"
RE_Boot
reTitle = RE_FirstTitle%
reOk = TU_Start%
credits = 300 : score = 1000
reN = RE_AdvanceTo%(GS_TITLE, 8)
RE_Assert reN > 0 And seqIdx = reTitle,       "3.01  the block ends on the first title"
RE_Assert reEnds = 0 And telemExitReason = "", "3.02  no session end, no exit=win"
RE_Assert score = 1000 And credits = 300 And crTallyTimer = 0, "3.03  no cash-out, no win tally"
RE_Assert highScore = 0 And reSaves = 0,      "3.04  no high score, nothing saved"
RE_Assert tutorialRun = 0 And seqRunActive = 0, "3.05  flag cleared"
RE_Assert telemCsvBuf = "",                   "3.06  no telemetry"
SEQ_QuitProcess
RE_Assert reEnds = 0,                         "3.07  closing the window afterwards ends nothing"
Print ""

Print "--- 4. quitting from the pause menu ---"
RE_Boot
reOk = TU_Start%
credits = 200 : score = 500
SEQ_QuitRun
RE_Assert reEnds = 0 And telemExitReason = "quit" And telemCsvBuf = "", "4.01  no session end, no rows"
RE_Assert credits = 200 And score = 500 And reSaves = 0 And highScore = 0, "4.02  no cash-out, no high score"
RE_Assert gameState = GS_TITLE And seqIdx = reTitle, "4.03  parked on the first title"
RE_Assert tutorialRun = 0,                    "4.04  flag cleared"
Print ""
RE_Boot
reOk = TU_Start%
SEQ_QuitProcess
RE_Assert reEnds = 0,                         "4.05  closing the window mid-tutorial ends no session"

Print "--- 5. cannot be failed ---"
RE_Boot
reOk = TU_Start%
lives = 1 : fuelLevel = 0 : fuelStranded = -1
PLAYER_TutorialGuard
RE_Assert lives = shieldMax And fuelLevel = fuelMax And fuelStranded = 0, "5.01  shields and fuel refilled, not stranded"
lives = 1 : laserEnergy = 10
PLAYER_TutorialGuard
RE_Assert laserEnergy = 10,                   "5.02  the laser is not part of the protection"
gameState = GS_PLAYING
RE_Hit
RE_Assert gameOver = 0 And shipLives = 1 And lives = shieldMax, "5.03  hits that would kill leave shields and ships alone"
RE_Assert reEnds = 0 And deathTimer = 0 And score = 0, "5.04  no death, no session end"
Print ""

Print "--- 6. --god ---"
RE_Boot
godMode = -1
reOk = TU_Start%
RE_Assert godMode = -1,                       "6.01  a tutorial leaves godMode alone"
SEQ_QuitRun
RE_Assert godMode = -1,                       "6.02  and so does leaving it"
godMode = -1 : lives = 50 : tutorialRun = 0
RE_NewGame : SEQ_Advance
lives = 1
RE_Hit
RE_Assert gameOver = 0 And lives = shieldMax, "6.03  --god still refills shields in a normal run"
RE_Assert reEnds = 0 And Len(telemCsvBuf) > 0, "6.04  and the run is still recorded"
Print ""

Print "--- 7. a normal run after a tutorial records everything ---"
telemCsvDir = ""   ' a death or win flushes the CSV buffer; there is nowhere to write it here
RE_Boot
reTitle = RE_FirstTitle%
reOk = TU_Start%
reN = RE_AdvanceTo%(GS_TITLE, 8)
RE_NewGame
RE_Assert tutorialRun = 0 And telemSession <> "", "7.01  New Game: flag clear, session started"
RE_Assert Len(telemBatch) > 0,                 "7.02  session_start row queued"
SEQ_Advance                                   ' chapter-1 PLAY
RE_Assert seqRunActive <> 0,                  "7.03  the first PLAY starts a run"
credits = 200 : score = 500
RE_Hit
RE_Assert gameOver <> 0 And reEnds = 1 And reLastExit = "death", "7.04  death: one session end, exit=death"
RE_Assert score = 700 And credits = 0,        "7.05  death cash-out"
gameState = GS_PLAYING : deathTimer = 0 : gameOver = 0
If score > highScore And tutorialRun = 0 Then highScore = score : SETTINGS_Save   ' playing.bas, at game over
RE_Assert highScore = 700 And reSaves = 1,    "7.06  the high score is saved"
RE_Boot
reOk = TU_Start%
reN = RE_AdvanceTo%(GS_TITLE, 8)
RE_NewGame
SEQ_Advance
credits = 300 : score = 1000
reN = RE_AdvanceTo%(GS_TITLE, 64)
RE_Assert reEnds = 1 And reLastExit = "win" And score = 1300 And highScore = 1300, "7.07  a full run after a tutorial still wins and scores"
Print ""

Print "--- 8. an abandoned tutorial flag ---"
RE_Boot
reOk = TU_Start%
RE_Assert tutorialRun <> 0,                   "8.01  flag set"
RE_NewGame
RE_Assert tutorialRun = 0 And telemSession <> "", "8.02  New Game clears it and records"
Print ""

Print "=== " + LTrim$(Str$(rePass + reFail)) + " tests: " _
    + LTrim$(Str$(rePass)) + " passed, " + LTrim$(Str$(reFail)) + " failed ==="
If reFail > 0 Then System 1 Else System 0
