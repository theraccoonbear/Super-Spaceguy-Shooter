' telemetry.bas -- gameplay event logger
'
' Local CSV: one row per event in sss_telemetry.csv (_STARTDIR$).
' Network:   batches all rows and POSTs a JSON array at session end.
'            Requires TELEM_NET_URL and TELEM_NET_KEY (loaded from assets/.env).
'
' Format: time,session,event,data
' time    = seconds since midnight (INT(Timer))
' session = YYYYMMDDHHMMSS startup timestamp
' data    = pipe-separated key=value pairs
'
' Local variable prefix: tl*

Function TELEM_NewUUID$
    Dim tlUStr As String
    Dim tlUByte As Integer
    Dim tlUI As Integer
    For tlUI = 1 To 16
        tlUByte = Int(Rnd * 256)
        If tlUI = 7 Then tlUByte = (tlUByte And &H0F) Or &H40
        If tlUI = 9 Then tlUByte = (tlUByte And &H3F) Or &H80
        tlUStr = tlUStr + Right$("0" + Hex$(tlUByte), 2)
        Select Case tlUI
            Case 4, 6, 8, 10 : tlUStr = tlUStr + "-"
        End Select
    Next tlUI
    TELEM_NewUUID$ = LCase$(tlUStr)
End Function

' Parse TELEM_NET_URL and TELEM_NET_KEY from embedded .env content.
Sub TELEM_LoadCredentials(tlcContent As String)
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
                    Case "TELEM_NET_URL" : TELEM_NET_URL = Mid$(tlcLine, tlcEq + 1)
                    Case "TELEM_NET_KEY" : TELEM_NET_KEY = Mid$(tlcLine, tlcEq + 1)
                End Select
            End If
        End If
        If tlcNl = 0 Then Exit Do
        tlcPos = tlcNl + 1
    Loop
End Sub

Sub TELEM_Init()
    If telemOn = 0 Then Exit Sub
    telemPlayerID = TELEM_NewUUID$
    If Len(TELEM_NET_URL) > 0 Then
        DBG_Print "TELEM: HTTP telemetry enabled"
    Else
        DBG_Print "TELEM: HTTP telemetry local only (no network URL configured)"
    End If
    Dim tlF As Integer : tlF = FreeFile
    If Not _FileExists(_StartDir$ + "/sss_telemetry.csv") Then
        Open _StartDir$ + "/sss_telemetry.csv" For Output As #tlF
        Print #tlF, "time,session,event,data"
        Close #tlF
    End If
End Sub

Sub TELEM_Row(tlEvent As String, tlData As String)
    If telemOn = 0 Then Exit Sub
    Dim tlF As Integer : tlF = FreeFile
    Open _StartDir$ + "/sss_telemetry.csv" For Append As #tlF
    Print #tlF, LTrim$(Str$(Int(Timer))) + "," + telemSession + "," + tlEvent + "," + tlData
    Close #tlF
    If Len(TELEM_NET_URL) > 0 And Len(telemSession) > 0 Then
        Dim tlQ As String : tlQ = Chr$(34)
        Dim tlRowJson As String
        tlRowJson = "{" + tlQ + "session"   + tlQ + ":" + tlQ + telemSession          + tlQ _
                  + "," + tlQ + "ev_time"   + tlQ + ":" + LTrim$(Str$(Int(Timer))) _
                  + "," + tlQ + "event"     + tlQ + ":" + tlQ + tlEvent               + tlQ _
                  + "," + tlQ + "player_id" + tlQ + ":" + tlQ + telemPlayerID         + tlQ _
                  + "," + tlQ + "data"      + tlQ + ":" + tlQ + tlData                + tlQ + "}"
        If Len(telemBatch) > 0 Then telemBatch = telemBatch + ","
        telemBatch = telemBatch + tlRowJson
    End If
End Sub

Sub TELEM_SessionStart()
    telemSession = Mid$(Date$, 7, 4) + Mid$(Date$, 1, 2) + Mid$(Date$, 4, 2) _
                  + Left$(Time$, 2) + Mid$(Time$, 4, 2) + Right$(Time$, 2)
    telemKills = 0 : telemBossReached = 0 : telemBossPhaseLog = 0 : telemDeathCause = ""
    telemShotsFired = 0 : telemShotsHit = 0 : telemEscapes = 0 : telemBatch = ""
    telemExitReason = ""
    TELEM_Row "session_start", "player_id=" + telemPlayerID + "|version=" + VERSION$ + "|nerf=" + LTrim$(Str$(settingNerf))
End Sub

Sub TELEM_EnemyKilled()
    telemKills = telemKills + 1
    TELEM_Row "enemy_killed", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) + "|wave=" + LTrim$(Str$(waveType))
End Sub

Sub TELEM_PowerupCollected()
    TELEM_Row "powerup_collected", "score=" + LTrim$(Str$(score)) + "|shield=" + LTrim$(Str$(lives)) _
            + "|wave=" + LTrim$(Str$(waveType))
End Sub

Sub TELEM_EnemyEscaped()
    telemEscapes = telemEscapes + 1
    TELEM_Row "enemy_escaped", "score=" + LTrim$(Str$(score)) + "|wave=" + LTrim$(Str$(waveType)) _
            + "|escapes=" + LTrim$(Str$(telemEscapes))
End Sub

Sub TELEM_FuelExhausted()
    TELEM_Row "fuel_exhausted", "score=" + LTrim$(Str$(score)) + "|shield=" + LTrim$(Str$(lives)) _
            + "|wave=" + LTrim$(Str$(waveType))
End Sub

Sub TELEM_PlayerDamaged()
    TELEM_Row "player_damaged", "cause=" + telemDeathCause + "|score=" + LTrim$(Str$(score)) _
            + "|shield=" + LTrim$(Str$(lives)) + "|fuel=" + LTrim$(Str$(Int(fuelLevel))) _
            + "|laser=" + LTrim$(Str$(Int(laserEnergy)))
End Sub

Sub TELEM_PlayerDeath()
    TELEM_Row "player_death", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
            + "|wave=" + LTrim$(Str$(waveType)) + "|boss=" + LTrim$(Str$(telemBossReached)) _
            + "|cause=" + telemDeathCause
End Sub

Sub TELEM_BossReached()
    telemBossReached = -1
    TELEM_Row "boss_reached", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills))
End Sub

Sub TELEM_BossPhase(tlPhase As Integer)
    TELEM_Row "boss_phase", "phase=" + LTrim$(Str$(tlPhase)) + "|score=" + LTrim$(Str$(score)) _
            + "|boss_hp=" + LTrim$(Str$(boss.hp))
End Sub

Sub TELEM_BossDefeated()
    TELEM_Row "boss_defeated", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills))
End Sub

Sub TELEM_SessionEnd()
    If Len(telemSession) = 0 Then Exit Sub
    Dim tlMisses As Long : tlMisses = telemShotsFired - telemShotsHit
    Dim tlData As String
    tlData = "exit=" + telemExitReason _
           + "|score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
           + "|wave=" + LTrim$(Str$(waveType)) _
           + "|boss=" + LTrim$(Str$(telemBossReached)) _
           + "|shots=" + LTrim$(Str$(telemShotsFired)) + "|hits=" + LTrim$(Str$(telemShotsHit)) _
           + "|misses=" + LTrim$(Str$(tlMisses)) + "|escapes=" + LTrim$(Str$(telemEscapes))
    TELEM_Row "session_end", tlData
    If Len(TELEM_NET_URL) > 0 And Len(TELEM_NET_KEY) > 0 And Len(telemBatch) > 0 Then
        HTTP_Post TELEM_NET_URL, TELEM_NET_KEY, "[" + telemBatch + "]", "telem_batch"
        DBG_Print "TELEM: batch enqueued (" + LTrim$(Str$(Len(telemBatch))) + " bytes)"
    End If
    telemSession = "" : telemBatch = ""
End Sub
