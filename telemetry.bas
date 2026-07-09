' telemetry.bas — gameplay event logger
'
' Writes one CSV row per game event to sss_telemetry.csv in _STARTDIR$.
' telemOn (DIM SHARED in sss.bas) gates all writes; on by default.
' Future: gated by --telem / --debug CLI flag (see issue #114).
'
' Format: time,session,event,data
' time    = seconds since midnight (INT(Timer))
' session = YYYYMMDDHHMMSS startup timestamp
' data    = pipe-separated key=value pairs
'
' Local variable prefix: tl*

Sub TELEM_Init()
    If telemOn = 0 Then Exit Sub
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
    Print #tlF, LTrim$(Str$(Int(Timer))) + "," + telemSession$ + "," + tlEvent + "," + tlData
    Close #tlF
End Sub

Sub TELEM_SessionStart()
    telemSession$ = Mid$(Date$, 7, 4) + Mid$(Date$, 1, 2) + Mid$(Date$, 4, 2) _
                  + Left$(Time$, 2) + Mid$(Time$, 4, 2) + Right$(Time$, 2)
    telemKills = 0 : telemBossReached = 0 : telemBossPhaseLog = 0 : telemDeathCause$ = ""
    TELEM_Row "session_start", "version=" + VERSION$ + "|nerf=" + LTrim$(Str$(settingNerf))
End Sub

Sub TELEM_EnemyKilled()
    telemKills = telemKills + 1
    TELEM_Row "enemy_killed", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) + "|wave=" + LTrim$(Str$(waveType))
End Sub

Sub TELEM_PlayerDamaged()
    TELEM_Row "player_damaged", "cause=" + telemDeathCause$ + "|score=" + LTrim$(Str$(score)) _
            + "|shield=" + LTrim$(Str$(lives)) + "|fuel=" + LTrim$(Str$(Int(fuelLevel))) _
            + "|laser=" + LTrim$(Str$(Int(laserEnergy)))
End Sub

Sub TELEM_PlayerDeath()
    TELEM_Row "player_death", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
            + "|wave=" + LTrim$(Str$(waveType)) + "|boss=" + LTrim$(Str$(telemBossReached)) _
            + "|cause=" + telemDeathCause$
End Sub

Sub TELEM_BossReached()
    telemBossReached = -1
    TELEM_Row "boss_reached", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills))
End Sub

Sub TELEM_BossPhase(tlPhase As Integer)
    TELEM_Row "boss_phase", "phase=" + LTrim$(Str$(tlPhase)) + "|score=" + LTrim$(Str$(score)) _
            + "|boss_hp=" + LTrim$(Str$(bossHP))
End Sub

Sub TELEM_BossDefeated()
    TELEM_Row "boss_defeated", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills))
End Sub

Sub TELEM_SessionEnd()
    TELEM_Row "session_end", "score=" + LTrim$(Str$(score)) + "|kills=" + LTrim$(Str$(telemKills)) _
            + "|boss=" + LTrim$(Str$(telemBossReached))
    telemSession$ = ""
End Sub
