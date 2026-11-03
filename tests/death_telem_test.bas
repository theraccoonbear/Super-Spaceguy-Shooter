' death_telem_test.bas -- regression tests for issue #169
'
' Drives the real PLAYER_TakeDamage (player.bas) and TELEM_SessionEnd
' (telemetry.bas) and checks that one death ends the session exactly once:
' two lethal hits in the same frame cost one ship and log one session end,
' and a repeated TELEM_SessionEnd call does nothing. The score post carries
' the run's difficulty level (#102).
'
' Session ends are counted through the real code's DBG_Print/HTTP_Post calls,
' so ioReadOnly stays set and no sss_telemetry.csv is written. A session with telemOn = 0 posts no score (#418).
'
' Build: ./tools/buildqb tests/death_telem_test.bas
' Run:   builds/death_telem_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

Const VERSION$ = "0.0.0-test"
Const BUILD_KIND$ = "dev"




Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Function UPG_ArmourDmg% (d As Integer) : UPG_ArmourDmg% = d : End Function
Dim Shared fxShakeTimer      As Integer
Dim Shared fxFlashTimer      As Integer
Function DBG_StateName$ (s As Integer) : DBG_StateName$ = "GS_TEST" : End Function
Dim Shared seqRunActive        As Integer   ' sequence.bas

Dim Shared dtEnds As Integer, dtScorePosts As Integer, dtPostBody As String
Dim Shared dtBatchN As Integer, dtBatch(1 To 20) As String

Sub DBG_Print (msg As String)
    If Left$(msg, 18) = "TELEM: SessionEnd " Then dtEnds = dtEnds + 1
End Sub
Sub HTTP_Post (u As String, k As String, b As String, t As String)
    If t = "score_post" Then dtScorePosts = dtScorePosts + 1 : dtPostBody = b
    If t = "telem_batch" And dtBatchN < 20 Then dtBatchN = dtBatchN + 1 : dtBatch(dtBatchN) = b
End Sub
Function JSON_Obj$ (s As String) : JSON_Obj$ = "{" + s + "}" : End Function
Function JSON_S$   (k As String, v As String) : JSON_S$ = k + ":" + v : End Function
Function JSON_N$   (k As String, v As String) : JSON_N$ = k + ":" + v : End Function
Sub SND_Hit   : End Sub
Sub SND_Death : End Sub
Sub SND_Shoot : End Sub
Dim Shared xpIdPlayer As Integer
Sub XP_Spawn (xsId As Integer, xsX As Single, xsY As Single, xsZ As Single, xsVX As Single, xsVY As Single, xsVZ As Single, xsScale As Single) : End Sub

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/telemetry.bas'
'$INCLUDE:'../src/gameplay/credits.bas'
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
    telemOn = -1 : ioReadOnly = -1
    dtEnds = 0 : dtScorePosts = 0 : dtPostBody = ""
    CR_ResetRun : credits = 0
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

Print "--- 3b. telemetry off (a dev flag, --no-telem or a declined prompt): no score post (#418) ---"
DT_NewGame 1
telemOn = 0
telemExitReason = "death"
TELEM_SessionEnd
TC_Assert dtScorePosts = 0, "3b.01  no score post while telemOn = 0"
telemOn = -1
Print ""

Print "--- 4. a new session can end again ---"
DT_NewGame 1
TELEM_SessionEnd
TC_Assert dtEnds = 1, "4.01  next session ends once"
Print ""

Print "--- 5. --god: lethal hits in one frame cost nothing ---"
DT_NewGame 1
godMode = -1
PLAYER_TakeDamage DMG_ASTEROID, SHAKE_COLLISION, FLASH_COLLISION
PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
godMode = 0
TC_Assert shipLives = 1, "5.01  no ship lost"
TC_Assert deathTimer = 0, "5.02  no death"
TC_Assert lives = 100,   "5.03  shields full"
TC_Assert dtEnds = 0,    "5.04  session still open"
Print ""

Print "--- 6. leftover credits become score once, before the score post (#268) ---"
DT_NewGame 1
credits = 300
PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
TC_Assert score = 800 And credits = 0,                 "6.01  500 score + 300 credits = 800, credits spent"
TC_Assert crBonusPts = 300 And crBonusCredits = 300,   "6.02  the game-over tally has 300 credits -> +300"
TC_Assert dtScorePosts = 1 And InStr(dtPostBody, "score:800") > 0, "6.03  the leaderboard post carries the bonus (score:800)"
CR_CashOut
TC_Assert score = 800,                                 "6.04  a later cash-out call adds nothing"
Print ""

Print "--- 7. a full bullet pool recycles the oldest shots instead of going silent (#268) ---"
Dim dtBI As Integer, dtBNew As Integer, dtBOld As Integer
For dtBI = 1 To MAX_BULLETS
    bullets(dtBI).active = -1 : bullets(dtBI).life = 100 + (dtBI Mod 100)
Next dtBI
bullets(40).life = 3 : bullets(77).life = 1 : bullets(200).life = 2
TC_Assert PLAYER_BulletSlot% = 77, "7.01  full pool: the slot with the least life left (77)"
bullets(150).active = 0
TC_Assert PLAYER_BulletSlot% = 150, "7.02  a free slot wins over recycling"
bullets(150).active = -1 : bullets(150).life = 250
gameState = GS_PLAYING : held(E3D_KEY_SPACE) = -1 : fireTimer = 0 : laserEnergy = 100
gunShots = 3 : gunSpread = 0.08 : telemShotsFired = 0
PLAYER_Fire
held(E3D_KEY_SPACE) = 0
For dtBI = 1 To MAX_BULLETS
    If bullets(dtBI).life > BULLET_RANGE / BULLET_SPEED - 0.01 Then dtBNew = dtBNew + 1
    If bullets(dtBI).active = 0 Then dtBOld = dtBOld + 1
Next dtBI
TC_Assert telemShotsFired = 3 And fireTimer > 0 And laserEnergy < 100, "7.03  a 3-shot volley fires with every slot taken"
TC_Assert dtBNew = 3 And dtBOld = 0, "7.04  it took 3 slots, all still active"
TC_Assert bullets(77).life > 300 And bullets(200).life > 300 And bullets(40).life > 300, "7.05  the three oldest (77, 200, 40) were the ones reused"
Print ""

Print "--- 8. the score post carries the run's difficulty level (#102) ---"
DT_NewGame 1
runDifficulty = "hard"
TELEM_SessionEnd
TC_Assert dtScorePosts = 1 And Right$(dtPostBody, 17) = ",difficulty:hard}", "8.01  difficulty:hard is the post's last field"
DT_NewGame 1
runDifficulty = ""
TELEM_SessionEnd
TC_Assert dtScorePosts = 1 And InStr(dtPostBody, "difficulty") = 0 And Right$(dtPostBody, 1) = "}", "8.02  no level: no difficulty field (the server stores the default)"
Print ""

Function DT_Count& (dtcHay As String, dtcNeedle As String)
    Dim dtcPos As Long, dtcN As Long
    dtcPos = InStr(dtcHay, dtcNeedle)
    Do While dtcPos > 0
        dtcN = dtcN + 1
        dtcPos = InStr(dtcPos + Len(dtcNeedle), dtcHay, dtcNeedle)
    Loop
    DT_Count& = dtcN
End Function

' The batch the session posted so far plus what's still queued, as one string.
Function DT_AllRows$
    Dim dtaI As Integer, dtaOut As String
    For dtaI = 1 To dtBatchN : dtaOut = dtaOut + dtBatch(dtaI) + ",": Next dtaI
    DT_AllRows$ = dtaOut + telemBatch
End Function

Sub DT_Telem
    dtBatchN = 0 : dtEnds = 0 : dtScorePosts = 0 : dtPostBody = ""
    telemOn = -1 : ioReadOnly = -1
    gameState = GS_PLAYING : lives = 100 : shipLives = 1 : score = 500 : credits = 0
    TELEM_SessionStart
End Sub

Print "--- 9. session_start lists the dev flags in use (#346) ---"
telemFlags = "god,fuel,script"
DT_Telem
TC_Assert InStr(telemBatch, "|flags=god,fuel,script") > 0, "9.01  flags= carries the list"
telemFlags = ""
DT_Telem
TC_Assert InStr(telemBatch, "|flags=|tv=2") > 0, "9.02  no flags: the field is empty"
TELEM_SessionEnd
Print ""

Print "--- 10. gameplay events say where they happened (#346) ---"
levelNum = 3 : stageKills = 7 : stageKillTarget = 20
DT_Telem
TELEM_EnemyKilled
TELEM_PowerupCollected "fuel", 10
TELEM_PowerupMissed "shield"
TELEM_EnemyEscaped
TELEM_FuelExhausted
TELEM_PlayerDamaged
TELEM_PlayerDeath
TELEM_BossReached
TELEM_BossPhase 2
TELEM_BossDefeated
Dim dtAt As String : dtAt = "chapter=3|stage_kills=7|stage_target=20"
TC_Assert DT_Count&(telemBatch, dtAt) = 10, "10.01  all ten gameplay events carry chapter and stage progress"
TELEM_UpgradeBought "armour", 2, 300
TC_Assert InStr(telemBatch, "credits_left=0|chapter=3") > 0, "10.02  upgrade_bought carries the chapter"
TELEM_SessionEnd
Print ""

Print "--- 11. session_end: quit state, chapter, progress and duration (#346) ---"
levelNum = 4 : stageKills = 2 : stageKillTarget = 15
DT_Telem
telemExitReason = "quit"
TELEM_SessionEnd
Dim dtAll As String : dtAll = DT_AllRows$
TC_Assert InStr(dtAll, "exit=quit") > 0 And InStr(dtAll, "|state=GS_TEST") > 0, "11.01  exit=quit names the state it happened in"
TC_Assert InStr(dtAll, "|secs=0|chapter=4|stage_kills=2|stage_target=15") > 0, "11.02  duration, chapter and progress on session_end"
DT_Telem
telemExitReason = "death"
TELEM_SessionEnd
TC_Assert InStr(DT_AllRows$, "|state=") = 0 And InStr(DT_AllRows$, "|secs=") > 0, "11.03  other exits: duration but no state"
Print ""

Print "--- 12. ev_time counts whole seconds from the session start (#346) ---"
TC_Assert TELEM_Elapsed&(3659, 0) = 60,      "12.01  60 frames to the second, rounded down"
TC_Assert TELEM_Elapsed&(9000, 5400) = 60,   "12.02  counted from the session's first frame"
TC_Assert TELEM_Elapsed&(7, 7) = 0,           "12.03  zero at the start"
gameFrame = 5000 : DT_Telem
TELEM_EnemyKilled
gameFrame = gameFrame + 90
TELEM_EnemyKilled
gameFrame = gameFrame + 3600
TELEM_SessionEnd
dtAll = DT_AllRows$
Dim dtP As Long, dtPrev As Long, dtV As Long, dtMono As Integer, dtRows As Long
dtMono = -1 : dtP = InStr(dtAll, "ev_time:")
If dtP > 0 Then
    dtV = Val(Mid$(dtAll, dtP + 8, 6))
    TC_Assert dtV = 0, "12.04  the first row (session_start) is at 0"
End If
Do While dtP > 0
    dtV = Val(Mid$(dtAll, dtP + 8, 6)) : dtRows = dtRows + 1
    If dtV < dtPrev Then dtMono = 0
    dtPrev = dtV
    dtP = InStr(dtP + 8, dtAll, "ev_time:")
Loop
TC_Assert dtMono And dtRows = 5 And dtPrev = 61 And InStr(dtAll, "|secs=61|") > 0, "12.05  never decreases and ends at the elapsed seconds (61), not the time of day"
Print ""

Print "--- 13. long sessions go out in chunks the Worker accepts (#346) ---"
DT_Telem
Dim dtK As Long
For dtK = 1 To 2500 : TELEM_EnemyKilled : Next dtK
TC_Assert dtBatchN >= 2, "13.01  full chunks were posted before the session ended"
TELEM_SessionEnd
Dim dtOk As Integer, dtTotal As Long, dtI As Integer
dtOk = -1
For dtI = 1 To dtBatchN
    dtRows = DT_Count&(dtBatch(dtI), "ev_time:")
    dtTotal = dtTotal + dtRows
    If dtRows > 1000 Or Len(dtBatch(dtI)) > 131072 Then dtOk = 0
Next dtI
TC_Assert dtOk, "13.02  no post over 1000 rows or the 128 KB body cap"
TC_Assert dtTotal = 2503 And telemBatch = "", "13.03  every row posted once: start + 2500 + credits_earned + end (" + LTrim$(Str$(dtTotal)) + ")"
TC_Assert Left$(dtBatch(1), 1) = "[" And Right$(dtBatch(dtBatchN), 1) = "]", "13.04  each post is a JSON array"
telemOn = 0 : ioReadOnly = 0
Print ""

' The data of the last row of this event in everything the session has queued.
Function DT_Data$ (dtdEvent As String)
    Dim dtdAll As String, dtdP As Long, dtdLast As Long, dtdE As Long
    dtdAll = DT_AllRows$
    dtdP = InStr(dtdAll, "event:" + dtdEvent + ",")
    Do While dtdP > 0
        dtdLast = dtdP
        dtdP = InStr(dtdP + 1, dtdAll, "event:" + dtdEvent + ",")
    Loop
    If dtdLast = 0 Then DT_Data$ = "(no row)" : Exit Function
    dtdP = InStr(dtdLast, dtdAll, "data:") + 5
    dtdE = InStr(dtdP, dtdAll, "}")
    DT_Data$ = Mid$(dtdAll, dtdP, dtdE - dtdP)
End Function

' "a=1|b=2" -> "a b"
Function DT_Keys$ (dtkData As String)
    Dim dtkP As Long, dtkQ As Long, dtkOut As String, dtkPart As String, dtkEq As Long
    dtkP = 1
    Do
        dtkQ = InStr(dtkP, dtkData, "|")
        If dtkQ = 0 Then dtkPart = Mid$(dtkData, dtkP) Else dtkPart = Mid$(dtkData, dtkP, dtkQ - dtkP)
        dtkEq = InStr(dtkPart, "=")
        If dtkEq > 0 Then dtkPart = Left$(dtkPart, dtkEq - 1)
        If Len(dtkOut) > 0 Then dtkOut = dtkOut + " "
        dtkOut = dtkOut + dtkPart
        If dtkQ = 0 Then Exit Do
        dtkP = dtkQ + 1
    Loop
    DT_Keys$ = dtkOut
End Function

' The key list the fixture expects for a shape ("event" or "event/variant"); "" when absent.
Function DT_Fixture$ (dtfName As String)
    Dim dtfPath As String, dtfF As Integer, dtfLine As String, dtfSp As Long
    dtfPath = _StartDir$ + "/tests/input/telemetry_rows.txt"
    dtfF = FreeFile
    Open dtfPath For Input As #dtfF
    Do While Not EOF(dtfF)
        Line Input #dtfF, dtfLine
        dtfSp = InStr(dtfLine, " ")
        If Left$(dtfLine, 1) <> "#" And dtfSp > 0 Then
            If Left$(dtfLine, dtfSp - 1) = dtfName Then DT_Fixture$ = Mid$(dtfLine, dtfSp + 1) : Exit Do
        End If
    Loop
    Close #dtfF
End Function

Sub DT_Shape (dtsName As String, dtsEvent As String)
    Dim dtsWant As String, dtsGot As String
    dtsWant = DT_Fixture$(dtsName)
    dtsGot = DT_Keys$(DT_Data$(dtsEvent))
    TC_Assert Len(dtsWant) > 0 And dtsGot = dtsWant, "payload shape " + dtsName
    If dtsGot <> dtsWant Then Print "      got:  " + dtsGot : Print "      want: " + dtsWant
End Sub

Print "--- 14. every event keeps the shape in tests/input/telemetry_rows.txt (#387) ---"
telemFlags = "" : levelNum = 2 : stageKills = 4 : stageKillTarget = 20
novaMax = 2 : novaCharges = 1 : rollCoolMax = 600 : rollCool = 0
DT_Telem
TELEM_EnemyKilled
DT_Shape "enemy_killed", "enemy_killed"
TELEM_NovaKill
DT_Shape "enemy_killed/nova", "enemy_killed"
TELEM_StageClear 2, 40.4, 61.2, 55
DT_Shape "stage_clear", "stage_clear"
TELEM_PlayerDeath
DT_Shape "player_death", "player_death"
telemExitReason = "death"
TELEM_SessionEnd
DT_Shape "session_start", "session_start"
DT_Shape "session_end/death", "session_end"
DT_Telem
telemExitReason = "quit"
TELEM_SessionEnd
DT_Shape "session_end/quit", "session_end"
TC_Assert InStr(DT_AllRows$, "|flags=|tv=2") > 0, "14.08  session_start carries the schema version tv=2"
Print ""

Print "--- 15. starved frames and episodes come from PLAYER_Fire (#387) ---"
DT_Telem
gameState = GS_PLAYING : fireTimer = 0 : laserEnergy = 0 : held(E3D_KEY_SPACE) = -1
Dim dtF As Integer
For dtF = 1 To 5 : PLAYER_Fire : Next dtF
TC_Assert InStr(TELEM_Leg$, "|fire_f=5|starve_f=5|starve_n=1|") > 0, "15.01  5 frames held with no energy: 5 starved, one episode"
held(E3D_KEY_SPACE) = 0 : PLAYER_Fire
held(E3D_KEY_SPACE) = -1
For dtF = 1 To 3 : PLAYER_Fire : Next dtF
TC_Assert InStr(TELEM_Leg$, "|fire_f=8|starve_f=8|starve_n=2|") > 0, "15.02  letting go and pressing again starts a second episode"
laserEnergy = 100 : fireTimer = 0
PLAYER_Fire
TC_Assert InStr(TELEM_Leg$, "|fire_f=9|starve_f=8|starve_n=2|") > 0, "15.03  a frame that fires is held but not starved"
TC_Assert fireTimer > 0, "15.04  the shot went out"
laserEnergy = 0
PLAYER_Fire
TC_Assert InStr(TELEM_Leg$, "|fire_f=10|starve_f=8|starve_n=2|") > 0, "15.05  held while the gun cools: not starved yet"
fireTimer = 0
PLAYER_Fire
TC_Assert InStr(TELEM_Leg$, "|starve_f=9|starve_n=3|") > 0, "15.06  cooled down and dry: starved again, a new episode"
held(E3D_KEY_SPACE) = 0 : gameState = GS_CINEMATIC : fireTimer = 0
PLAYER_Fire
TC_Assert InStr(TELEM_Leg$, "|fire_f=11|") > 0, "15.07  a release or a screen change counts no held frame"
gameState = GS_PLAYING
Print ""

Print "--- 16. dodges are hits avoided, not frames of a per-frame source (#387) ---"
DT_Telem
rollTimer = 10 : lives = 100 : deathTimer = 0
gameFrame = 200 : PLAYER_TakeDamage 5, 1, 1
gameFrame = 201 : PLAYER_TakeDamage 5, 1, 1
gameFrame = 202 : PLAYER_TakeDamage 5, 1, 1
TC_Assert InStr(TELEM_Leg$, "|dodge=1|") > 0 And lives = 100, "16.01  three frames in a row are one dodge, no damage"
gameFrame = 230 : PLAYER_TakeDamage 5, 1, 1
TC_Assert InStr(TELEM_Leg$, "|dodge=2|") > 0, "16.02  a later hit is another dodge"
rollTimer = 0 : gameFrame = 231 : PLAYER_TakeDamage 5, 1, 1
TC_Assert InStr(TELEM_Leg$, "|dodge=2|") > 0 And lives = 95, "16.03  a hit with no roll is damage, not a dodge"
Print ""

Print "--- 17. the leg summary, its counters and its reset (#387) ---"
DT_Telem
novaMax = 3 : rollCoolMax = 0
TELEM_NoteRoll 0
TELEM_NoteRoll 0
rollCoolMax = 600
TELEM_NoteRoll 0
TELEM_NoteRoll -1
TELEM_NoteNova -1
TELEM_NoteNova 0
TELEM_NoteNova 0
novaMax = 0
TELEM_NoteNova 0
novaMax = 3
TELEM_NoteRegen 4
TELEM_NoteRegen 3
TELEM_NoteArmour 5
TELEM_NoteArmour 0
telemShotsFired = telemShotsFired + 12 : telemShotsHit = telemShotsHit + 7
TELEM_NovaKill
TC_Assert InStr(TELEM_Leg$, "|roll_have=1|roll_n=1|roll_lock=2|roll_cool=1|") > 0, "17.01  roll: owned, rolled once, two presses locked, one on cooldown"
TC_Assert InStr(TELEM_Leg$, "|nova_max=3|nova_n=1|nova_dry=2|nova_kills=1|") > 0, "17.02  nova: fired once, two dry presses (a locked press isn't dry), one nova kill"
TC_Assert InStr(TELEM_Leg$, "|regen=7|armour_saved=5") > 0, "17.03  regen and armour totals"
TC_Assert InStr(TELEM_Leg$, "|lshots=12|lhits=7|") > 0, "17.04  leg shots and hits since the leg began"
TELEM_StageClear 1, 10, 30, 80
Dim dtSc As String : dtSc = DT_Data$("stage_clear")
TC_Assert InStr(dtSc, "|roll_n=1|roll_lock=2|") > 0 And InStr(dtSc, "|lshots=12|lhits=7|") > 0, "17.05  stage_clear carries the summary"
TC_Assert InStr(TELEM_Leg$, "|fire_f=0|starve_f=0|starve_n=0|lshots=0|lhits=0|roll_have=1|roll_n=0|roll_lock=0|roll_cool=0|dodge=0|nova_max=3|nova_n=0|nova_dry=0|nova_kills=0|regen=0|armour_saved=0") > 0, "17.06  the next leg starts at zero (ownership stays)"
TELEM_NoteNova -1
telemExitReason = "quit"
TELEM_SessionEnd
TC_Assert InStr(DT_Data$("session_end"), "|nova_n=1|") > 0 And InStr(DT_Data$("session_end"), "|roll_n=0|") > 0, "17.07  session_end carries the unfinished last leg only"
DT_Telem
TC_Assert InStr(TELEM_Leg$, "|nova_n=0|") > 0 And InStr(TELEM_Leg$, "|lshots=0|") > 0, "17.08  a new session starts a fresh leg"
Print ""

Print "--- 18. player_death: nova charges left and roll readiness (#387) ---"
DT_Telem
novaCharges = 2 : rollCoolMax = 0 : rollCool = 0
TELEM_PlayerDeath
TC_Assert Right$(DT_Data$("player_death"), 25) = "|nova_left=2|roll_ready=0", "18.01  no roll owned: not ready"
rollCoolMax = 600 : rollCool = 0 : novaCharges = 0
TELEM_PlayerDeath
TC_Assert Right$(DT_Data$("player_death"), 25) = "|nova_left=0|roll_ready=1", "18.02  roll owned and cooled down: ready"
rollCool = 40
TELEM_PlayerDeath
TC_Assert Right$(DT_Data$("player_death"), 12) = "roll_ready=0", "18.03  roll cooling: not ready"
Print ""

Print "--- 19. every payload stays well under the Worker's 1024-character data cap (#387) ---"
Const DT_BIG = 2147483647
telemFlags = "god,nerf,scene,credits,ships,shields,fuel,pup,seed,script"
telemPlayerID = "00000000-0000-4000-8000-000000000000"
runDifficulty = "normal"
settingNerf = 32767 : levelNum = 32767 : stageKills = DT_BIG : stageKillTarget = DT_BIG
score = DT_BIG : waveType = 32767
telemShotsFired = 0 : telemShotsHit = 0 : telemEscapes = DT_BIG
novaMax = 32767 : novaCharges = 32767 : rollCoolMax = 32767 : rollCool = 0
DT_Telem
telemKills = DT_BIG - 5
telemDeathCause = "enemy_col"
TELEM_EnemyKilled
TELEM_NovaKill
TELEM_PlayerDeath
Sub DT_MaxLeg
    telemShotsFired = DT_BIG : telemShotsHit = DT_BIG
    telemLegFireF = DT_BIG : telemLegStarveF = DT_BIG : telemLegStarveN = DT_BIG
    telemLegRollN = DT_BIG : telemLegRollLock = DT_BIG : telemLegRollCool = DT_BIG : telemLegDodge = DT_BIG
    telemLegNovaN = DT_BIG : telemLegNovaDry = DT_BIG : telemLegNovaKills = DT_BIG
    telemLegRegen = DT_BIG : telemLegArmour = DT_BIG
End Sub
DT_MaxLeg
TELEM_StageClear 32767, 3.4E+38, 3.4E+38, 3.4E+38
DT_MaxLeg
gameFrame = DT_BIG
telemExitReason = "quit"
TELEM_SessionEnd
Dim dtCapAll As String, dtCapP As Long, dtCapE As Long, dtCapLen As Long, dtCapMax As Long, dtCapRows As Long
dtCapAll = DT_AllRows$
dtCapP = InStr(dtCapAll, "data:")
Do While dtCapP > 0
    dtCapE = InStr(dtCapP, dtCapAll, "}")
    dtCapLen = dtCapE - (dtCapP + 5)
    If dtCapLen > dtCapMax Then dtCapMax = dtCapLen
    dtCapRows = dtCapRows + 1
    dtCapP = InStr(dtCapE, dtCapAll, "data:")
Loop
Print "      longest data= " + LTrim$(Str$(dtCapMax)) + " characters over " + LTrim$(Str$(dtCapRows)) + " rows"
TC_Assert dtCapRows >= 7 And dtCapMax < 600, "19.01  every row's data under 600 characters at maximum counters"
telemOn = 0 : ioReadOnly = 0
Print ""

Print "--- 20. credits_earned reports the unspent credits, not the zero after the cash-out (#387) ---"
DT_Telem
CR_ResetRun
credits = 300 : creditsEarned = 500 : creditsSpent = 200 : deathTimer = 0
PLAYER_TakeDamage DMG_COLLISION * 6, SHAKE_COLLISION, FLASH_COLLISION
TC_Assert credits = 0 And InStr(DT_Data$("credits_earned"), "|left=300") > 0, "20.01  death: left=300 although the cash-out zeroed credits"
DT_Shape "credits_earned", "credits_earned"
DT_Telem
CR_ResetRun
credits = 40 : telemExitReason = "quit"
TELEM_SessionEnd
TC_Assert InStr(DT_Data$("credits_earned"), "|left=40") > 0, "20.02  quit (no cash-out): left is what the player holds"
DT_Telem
CR_ResetRun
credits = 90
CR_CashOut
DT_Telem
credits = 5 : telemExitReason = "quit"
TELEM_SessionEnd
TC_Assert InStr(DT_Data$("credits_earned"), "|left=5") > 0, "20.03  a later session starts clean of an earlier cash-out"
Print ""

Print "--- 21. dock_visit: shape, fields and size at the maximum (#387) ---"
DT_Telem
levelNum = 3 : credits = 20
TELEM_DockVisit "launch", 100, 80, 0, 0, 3690, "laser:1", "cannon:1", "thrust", "refuel,repair,laser", "2,0,0,0,0,0,0,0,0,0,0"
DT_Shape "dock_visit", "dock_visit"
TC_Assert InStr(DT_Data$("dock_visit"), "chapter=3|credits_in=100|spent_upg=80|spent_fuel=0|spent_shield=0|credits_out=20|secs=61|exit=launch|bought=laser:1|denied=cannon:1|afford=thrust|seen=refuel,repair,laser|lv=2,0") = 1, "21.01  fields carry the figures given (seconds from frames)"
Dim dtDk As Integer, dtDkN As String, dtDkB As String, dtDkS As String, dtDkU As String, dtDkL As String
dtDkN = "refuel,repair,laser,cannon,rapid,shield,regen,armour,nova,thrust,roll,tractor,fuel"
dtDkU = "laser,cannon,rapid,shield,regen,armour,nova,thrust,roll,tractor,fuel"
dtDkS = dtDkN
For dtDk = 1 To Len(dtDkN)
    If Mid$(dtDkN, dtDk, 1) = "," Then dtDkB = dtDkB + ":99," Else dtDkB = dtDkB + Mid$(dtDkN, dtDk, 1)
Next dtDk
dtDkB = dtDkB + ":99"
For dtDk = 1 To 11
    If dtDk > 1 Then dtDkL = dtDkL + ","
    dtDkL = dtDkL + "5"
Next dtDk
levelNum = 32767 : credits = DT_BIG
TELEM_DockVisit "stranded", DT_BIG, DT_BIG, DT_BIG, DT_BIG, DT_BIG, dtDkB, dtDkB, dtDkU, dtDkS, dtDkL
Dim dtDkLen As Long : dtDkLen = Len(DT_Data$("dock_visit"))
Print "      longest dock_visit data= " + LTrim$(Str$(dtDkLen)) + " characters"
TC_Assert dtDkLen <= 600, "21.02  dock_visit with every list at its longest stays within 600 characters (real keys, counts capped at 99)"
telemOn = 0 : ioReadOnly = 0
Print ""

Print "=== " + LTrim$(Str$(tcPass + tcFail)) + " tests: " _
    + LTrim$(Str$(tcPass)) + " passed, " + LTrim$(Str$(tcFail)) + " failed ==="
If tcFail > 0 Then System 1 Else System 0
