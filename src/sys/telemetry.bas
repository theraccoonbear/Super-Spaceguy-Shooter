' telemetry.bas — gameplay event logger
'
' Writes one CSV row per game event to sss_telemetry.csv in _STARTDIR$.
' telemOn (DIM SHARED in sss.bas) gates all writes; disabled by --no-telem flag.
'
' Format: time,session,event,data
' time    = seconds since midnight (INT(Timer))
' session = YYYYMMDDHHMMSS startup timestamp
' data    = pipe-separated key=value pairs
'
' Local variable prefix: tl*

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
End Sub

Sub TELEM_SessionStart()
    telemSession = Mid$(Date$, 7, 4) + Mid$(Date$, 1, 2) + Mid$(Date$, 4, 2) _
                  + Left$(Time$, 2) + Mid$(Time$, 4, 2) + Right$(Time$, 2)
    telemKills = 0 : telemBossReached = 0 : telemBossPhaseLog = 0 : telemDeathCause = ""
    telemShotsFired = 0 : telemShotsHit = 0 : telemEscapes = 0
    TELEM_Row "session_start", "version=" + VERSION$ + "|nerf=" + LTrim$(Str$(settingNerf))
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
    Dim tlMisses As Long : tlMisses = telemShotsFired - telemShotsHit
    Dim tlData As String
    tlData = "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
           + "|boss=" + LTrim$(Str$(telemBossReached)) _
           + "|shots=" + LTrim$(Str$(telemShotsFired)) + "|hits=" + LTrim$(Str$(telemShotsHit)) _
           + "|misses=" + LTrim$(Str$(tlMisses)) + "|escapes=" + LTrim$(Str$(telemEscapes))
    TELEM_Row "session_end", tlData
    If Len(TELEM_NET_URL) > 0 And Len(TELEM_NET_KEY) > 0 And Len(telemSession) > 0 Then
        Dim tlJson As String
        tlJson = JSON_Obj$(JSON_S$("session", telemSession) _
               + "," + JSON_N$("ev_time", LTrim$(Str$(Int(Timer)))) _
               + "," + JSON_S$("event", "session_end") _
               + "," + JSON_S$("data", tlData))
        HTTP_PostJSON TELEM_NET_URL, TELEM_NET_KEY, tlJson
    End If
    telemSession = ""
End Sub
