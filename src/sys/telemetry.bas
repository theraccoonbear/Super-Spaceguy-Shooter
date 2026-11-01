' telemetry.bas — gameplay event logger
'
' Buffers one CSV row per game event (telemCsvBuf) and writes sss_telemetry.csv in telemCsvDir once, at session end (#284).
' telemOn (DIM SHARED in sss.bas) gates all writes; disabled by --no-telem flag.
'
' Format: time,session,event,data
' time    = seconds since midnight (INT(Timer))
' session = YYYYMMDDHHMMSS startup timestamp
' data    = pipe-separated key=value pairs
'
' Local variable prefix: tl*

Const TELEM_MAX_ROWS = 1000   ' the Worker rejects a batch over 1000 rows
Const TELEM_MAX_BYTES = 100000 ' under the 128 KB POST body cap in curl_qb64.h

Function TELEM_NewUUID$
    Dim uuidStr As String
    Dim uuidByte As Integer
    Dim uuidI As Integer
    For uuidI = 1 To 16
        uuidByte = Int(RNG!(RNG_UNIQUE) * 256)
        If uuidI = 7 Then uuidByte = (uuidByte And &H0F) Or &H40  ' version 4
        If uuidI = 9 Then uuidByte = (uuidByte And &H3F) Or &H80  ' variant 10xx
        uuidStr = uuidStr + Right$("0" + Hex$(uuidByte), 2)
        Select Case uuidI
            Case 4, 6, 8, 10 : uuidStr = uuidStr + "-"
        End Select
    Next uuidI
    TELEM_NewUUID$ = LCase$(uuidStr)
End Function


Sub TELEM_LoadCredentials (tlcContent As String)
    Dim tlcPos As Long : tlcPos = 1
    Dim tlcNl As Long
    Dim tlcLine As String
    Dim tlcEq As Integer
    Do
        tlcNl = InStr(tlcPos, tlcContent, Chr$(10))
        If tlcNl = 0 Then tlcLine = Mid$(tlcContent, tlcPos) _
                       Else tlcLine = Mid$(tlcContent, tlcPos, tlcNl - tlcPos)
        tlcLine = RTrim$(LTrim$(tlcLine))
        If Right$(tlcLine, 1) = Chr$(13) Then tlcLine = Left$(tlcLine, Len(tlcLine) - 1)
        If Left$(tlcLine, 1) <> "#" And Len(tlcLine) > 0 Then
            tlcEq = InStr(tlcLine, "=")
            If tlcEq > 0 Then
                Select Case Left$(tlcLine, tlcEq - 1)
                    Case "DB_URL" : DB_URL = Mid$(tlcLine, tlcEq + 1)
                    Case "DB_KEY" : DB_KEY = Mid$(tlcLine, tlcEq + 1)
                End Select
            End If
        End If
        If tlcNl = 0 Then Exit Do
        tlcPos = tlcNl + 1
    Loop
End Sub

Sub TELEM_Init()
    If telemOn = 0 Then Exit Sub
    If Len(DB_URL) > 0 Then
        DBG_Print "TELEM: HTTP telemetry enabled"
    Else
        DBG_Print "TELEM: HTTP telemetry local only (no DB_URL configured)"
    End If
End Sub

' Write the buffered CSV rows (header first when the file is new) in one open/close. Called once
' per session at its end, and on a --frames exit, so a kill never touches the disk.
Sub TELEM_FlushCsv
    Dim tlF As Integer, tlNew As Integer, tlPath As String
    If Len(telemCsvBuf) = 0 Then Exit Sub
    If Len(telemCsvDir) = 0 Then telemCsvBuf = "" : Exit Sub
    tlPath = telemCsvDir + "/sss_telemetry.csv"
    tlNew = (_FileExists(tlPath) = 0)
    tlF = FreeFile
    Open tlPath For Append As #tlF
    If tlNew Then Print #tlF, "time,session,event,data"
    Print #tlF, telemCsvBuf;
    Close #tlF
    telemCsvBuf = ""
End Sub

Sub TELEM_Row(tlEvent As String, tlData As String)
    ' a tutorial run has no session, and a row with a blank session would still reach the CSV
    If tutorialRun Then Exit Sub
    If telemOn = 0 Then Exit Sub
    If Len(telemCsvDir) > 0 Then
        telemCsvBuf = telemCsvBuf + LTrim$(Str$(Int(Timer))) + "," + telemSession + "," + tlEvent + "," + tlData + Chr$(10)
    End If
    ' accumulate for bulk HTTP POST; sent in chunks the Worker accepts
    If Len(DB_URL) > 0 And Len(telemSession) > 0 Then
        Dim tlRowJson As String
        tlRowJson = JSON_Obj$(JSON_S$("session", telemSession) _
                 + "," + JSON_N$("ev_time", LTrim$(Str$(TELEM_Elapsed&(gameFrame, telemT0)))) _
                 + "," + JSON_S$("event", tlEvent) _
                 + "," + JSON_S$("player_id", telemPlayerID) _
                 + "," + JSON_S$("data", tlData))
        If Len(telemBatch) > 0 Then telemBatch = telemBatch + ","
        telemBatch = telemBatch + tlRowJson
        telemBatchRows = telemBatchRows + 1
        If telemBatchRows >= TELEM_MAX_ROWS Or Len(telemBatch) >= TELEM_MAX_BYTES Then TELEM_FlushBatch
    End If
End Sub

' Whole seconds from the session's first frame (tleF0) to tleNow, 60 frames to the second. Counted
' in frames, not wall time, so a scripted run reports the same figures at any speed.
Function TELEM_Elapsed& (tleNow As Long, tleF0 As Long)
    TELEM_Elapsed& = (tleNow - tleF0) \ 60
End Function

' The chapter and how far into its stage: kills made of the kills the stage needs.
Function TELEM_At$
    TELEM_At$ = "chapter=" + LTrim$(Str$(levelNum)) + "|stage_kills=" + LTrim$(Str$(stageKills)) _
              + "|stage_target=" + LTrim$(Str$(stageKillTarget))
End Function

' Queue the rows gathered so far as one POST; the Worker takes at most 1000 rows per batch and
' the HTTP layer 128 KB per body. Never blocks.
Sub TELEM_FlushBatch
    If Len(telemBatch) = 0 Then Exit Sub
    If Len(DB_URL) = 0 Or Len(DB_KEY) = 0 Then Exit Sub
    DBG_Print "TELEM: POST batch " + LTrim$(Str$(telemBatchRows)) + " rows " + LTrim$(Str$(Len(telemBatch) + 2)) + " bytes"
    HTTP_Post DB_URL + "/sss_telemetry", DB_KEY, "[" + telemBatch + "]", "telem_batch"
    telemBatch = "" : telemBatchRows = 0
End Sub

Sub TELEM_SessionStart()
    If tutorialRun Then Exit Sub
    telemSession = Mid$(Date$, 7, 4) + Mid$(Date$, 1, 2) + Mid$(Date$, 4, 2) _
                  + Left$(Time$, 2) + Mid$(Time$, 4, 2) + Right$(Time$, 2)
    telemKills = 0 : telemBossReached = 0 : telemBossPhaseLog = 0 : telemDeathCause = ""
    telemShotsFired = 0 : telemShotsHit = 0 : telemEscapes = 0 : telemBatch = ""
    telemExitReason = "" : telemBatchRows = 0 : telemT0 = gameFrame
    TELEM_Row "session_start", "player_id=" + telemPlayerID + "|version=" + VERSION$ + "|build=" + BUILD_KIND$ + "|nerf=" + LTrim$(Str$(settingNerf)) + "|difficulty=" + runDifficulty + "|flags=" + telemFlags
End Sub

Sub TELEM_EnemyKilled()
    telemKills = telemKills + 1
    TELEM_Row "enemy_killed", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) + "|wave=" + LTrim$(Str$(waveType)) + "|" + TELEM_At$
End Sub

Sub TELEM_PowerupCollected(tlpKind As String, tlpAmt As Single)
    TELEM_Row "powerup_collected", "kind=" + tlpKind + "|amount=" + LTrim$(Str$(Int(tlpAmt + 0.5))) _
            + "|score=" + LTrim$(Str$(score)) + "|shield=" + LTrim$(Str$(lives)) _
            + "|fuel=" + LTrim$(Str$(Int(fuelLevel))) + "|wave=" + LTrim$(Str$(waveType)) + "|" + TELEM_At$
End Sub

Sub TELEM_PowerupMissed(tlpmKind As String)
    TELEM_Row "powerup_missed", "kind=" + tlpmKind + "|wave=" + LTrim$(Str$(waveType)) + "|" + TELEM_At$
End Sub

Sub TELEM_EnemyEscaped()
    telemEscapes = telemEscapes + 1
    TELEM_Row "enemy_escaped", "score=" + LTrim$(Str$(score)) + "|wave=" + LTrim$(Str$(waveType)) _
            + "|escapes=" + LTrim$(Str$(telemEscapes)) + "|" + TELEM_At$
End Sub

Sub TELEM_FuelExhausted()
    TELEM_Row "fuel_exhausted", "score=" + LTrim$(Str$(score)) + "|shield=" + LTrim$(Str$(lives)) _
            + "|wave=" + LTrim$(Str$(waveType)) + "|" + TELEM_At$
End Sub

Sub TELEM_PlayerDamaged()
    TELEM_Row "player_damaged", "cause=" + telemDeathCause + "|score=" + LTrim$(Str$(score)) _
            + "|shield=" + LTrim$(Str$(lives)) + "|fuel=" + LTrim$(Str$(Int(fuelLevel))) _
            + "|laser=" + LTrim$(Str$(Int(laserEnergy))) + "|" + TELEM_At$
End Sub

Sub TELEM_PlayerDeath()
    TELEM_Row "player_death", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
            + "|wave=" + LTrim$(Str$(waveType)) + "|boss=" + LTrim$(Str$(telemBossReached)) _
            + "|cause=" + telemDeathCause + "|" + TELEM_At$
End Sub

Sub TELEM_BossReached()
    telemBossReached = -1
    TELEM_Row "boss_reached", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) + "|" + TELEM_At$
End Sub

Sub TELEM_BossPhase(tlPhase As Integer)
    TELEM_Row "boss_phase", "phase=" + LTrim$(Str$(tlPhase)) + "|score=" + LTrim$(Str$(score)) _
            + "|boss_hp=" + LTrim$(Str$(boss.hp)) + "|" + TELEM_At$
End Sub

Sub TELEM_BossDefeated()
    TELEM_Row "boss_defeated", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) + "|" + TELEM_At$
End Sub

' A dock purchase (#268): which upgrade, the level it reached, what it cost, what's left.
Sub TELEM_UpgradeBought(tlubItem As String, tlubLevel As Integer, tlubPrice As Long)
    TELEM_Row "upgrade_bought", "item=" + tlubItem + "|level=" + LTrim$(Str$(tlubLevel)) _
            + "|price=" + LTrim$(Str$(tlubPrice)) + "|credits_left=" + LTrim$(Str$(credits)) + "|chapter=" + LTrim$(Str$(levelNum))
End Sub

' Fuel bought at the dock by the amount (#277): units, total price, price per unit, the
' blockade surcharge multiplier and the chapter it applied to.
Sub TELEM_FuelBought(tlfbAmt As Integer, tlfbPrice As Long, tlfbUnit As Single, tlfbMult As Single, tlfbCh As Integer)
    TELEM_Row "fuel_bought", "amount=" + LTrim$(Str$(tlfbAmt)) + "|price=" + LTrim$(Str$(tlfbPrice)) _
            + "|unit=" + LTrim$(Str$(tlfbUnit)) + "|mult=" + LTrim$(Str$(tlfbMult)) _
            + "|chapter=" + LTrim$(Str$(tlfbCh)) + "|credits_left=" + LTrim$(Str$(credits))
End Sub

Sub TELEM_ShieldBought(tlsbAmt As Integer, tlsbPrice As Long, tlsbCh As Integer)
    TELEM_Row "shield_bought", "amount=" + LTrim$(Str$(tlsbAmt)) + "|price=" + LTrim$(Str$(tlsbPrice)) _
            + "|chapter=" + LTrim$(Str$(tlsbCh)) + "|credits_left=" + LTrim$(Str$(credits))
End Sub

' The run ended at a dock without the fuel or the credits for the next jump (#277). Logged
' before the cash-out, so credits is what was left unspent.
Sub TELEM_RunStranded(tlrsCh As Integer, tlrsFuel As Single, tlrsNeed As Single, tlrsCredits As Long, tlrsUnit As Single)
    TELEM_Row "run_stranded", "chapter=" + LTrim$(Str$(tlrsCh)) + "|fuel=" + LTrim$(Str$(Int(tlrsFuel))) _
            + "|need=" + LTrim$(Str$(tlrsNeed)) + "|credits=" + LTrim$(Str$(tlrsCredits)) _
            + "|fuel_price=" + LTrim$(Str$(tlrsUnit))
End Sub

' A leg flown (#277): from leaving the last dock (or the start) to the planet arrival, the
' fuel burned and the seconds spent in play, so #274 can fit economy.ini's leg fuel need.
Sub TELEM_StageClear(tlscCh As Integer, tlscFuelUsed As Single, tlscSecs As Single, tlscFuelLeft As Single)
    TELEM_Row "stage_clear", "chapter=" + LTrim$(Str$(tlscCh)) + "|fuel_used=" + LTrim$(Str$(Int(tlscFuelUsed + 0.5))) _
            + "|seconds=" + LTrim$(Str$(Int(tlscSecs + 0.5))) + "|fuel_left=" + LTrim$(Str$(Int(tlscFuelLeft))) _
            + "|credits=" + LTrim$(Str$(credits))
End Sub

' End of a run (#268): leftover credits cashed in for score, logged once per run.
Sub TELEM_CreditBonus(tlcbCredits As Long, tlcbRate As Double, tlcbPts As Long)
    TELEM_Row "credit_bonus", "credits=" + LTrim$(Str$(tlcbCredits)) + "|rate=" + LTrim$(Str$(tlcbRate)) _
            + "|points=" + LTrim$(Str$(tlcbPts)) + "|score=" + LTrim$(Str$(score))
End Sub

Sub TELEM_SessionEnd()
    If tutorialRun Then Exit Sub
    If Len(telemSession) = 0 Then Exit Sub  ' idempotent: already ended or never started
    TELEM_Row "credits_earned", "earned=" + LTrim$(Str$(creditsEarned)) + "|spent=" + LTrim$(Str$(creditsSpent)) _
            + "|left=" + LTrim$(Str$(credits))
    Dim tlMisses As Long : tlMisses = telemShotsFired - telemShotsHit
    Dim tlData As String
    tlData = "exit=" + telemExitReason _
           + "|score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
           + "|wave=" + LTrim$(Str$(waveType)) _
           + "|boss=" + LTrim$(Str$(telemBossReached)) _
           + "|shots=" + LTrim$(Str$(telemShotsFired)) + "|hits=" + LTrim$(Str$(telemShotsHit)) _
           + "|misses=" + LTrim$(Str$(tlMisses)) + "|escapes=" + LTrim$(Str$(telemEscapes)) _
           + "|secs=" + LTrim$(Str$(TELEM_Elapsed&(gameFrame, telemT0))) + "|" + TELEM_At$
    If telemExitReason = "quit" Then tlData = tlData + "|state=" + DBG_StateName$(gameState)
    TELEM_Row "session_end", tlData  ' also appends to telemBatch
    DBG_Print "TELEM: SessionEnd rows=" + LTrim$(Str$(Len(telemBatch))) + " bytes"
    TELEM_FlushBatch
    TELEM_FlushCsv
    If Len(DB_URL) = 0 Or Len(DB_KEY) = 0 Then
        DBG_Print "LBRD: score POST skipped -- DB_URL/DB_KEY not set in .env"
    ElseIf telemConsent = 0 Then
        DBG_Print "LBRD: score POST skipped -- no consent"
    ElseIf score = 0 Then
        DBG_Print "LBRD: score POST skipped -- score=0"
    Else
        Dim tlScoreJson As String, tlDiffJson As String
        ' no level (difficulty.ini never loaded) leaves it out: the server stores those as normal
        If Len(runDifficulty) > 0 Then tlDiffJson = "," + JSON_S$("difficulty", runDifficulty) Else tlDiffJson = ""
        tlScoreJson = JSON_Obj$(JSON_S$("player_id",   leaderboardPlayerID) + "," _
                              + JSON_S$("player_name", telemPlayerName) + "," _
                              + JSON_N$("score",       LTrim$(Str$(score))) + "," _
                              + JSON_N$("wave",        LTrim$(Str$(waveType))) + "," _
                              + JSON_S$("session",     telemSession) _
                              + tlDiffJson)
        DBG_Print "LBRD: POST score=" + LTrim$(Str$(score)) + " player=" + telemPlayerName
        HTTP_Post DB_URL + "/scores", DB_KEY, tlScoreJson, "score_post"
    End If
    telemSession = "" : telemBatch = ""
End Sub
