' settingsio.bas -- persistent settings: sss_settings.ini in the launch folder

Sub SETTINGS_Save ()
    Dim sfH As Integer
    If ioReadOnly Then Exit Sub
    sfH = FreeFile
    Open _STARTDIR$ + "/sss_settings.ini" For Output As #sfH
    Print #sfH, "music="      + LTrim$(Str$(volMusic))
    Print #sfH, "sfx="        + LTrim$(Str$(volSfx))
    Print #sfH, "speech="     + LTrim$(Str$(volSpeech))
    Print #sfH, "narration="  + LTrim$(Str$(settingNarration))
    Print #sfH, "narration_speed=" + LTrim$(Str$(settingNarrSpeed))
    Print #sfH, "fullscreen=" + LTrim$(Str$(settingFullscreen))
    Print #sfH, "highscore="  + LTrim$(Str$(highScore))
    If Len(telemPlayerID) > 0 Then Print #sfH, "player_id=" + telemPlayerID
    If Len(leaderboardPlayerID) > 0 Then Print #sfH, "lb_player_id=" + leaderboardPlayerID
    If Len(telemPlayerName) > 0 Then Print #sfH, "player_name=" + telemPlayerName
    If telemConsent Then Print #sfH, "telem_consent=1"
    If camF.angleLocked Then
        Print #sfH, "cam_phi="   + LTrim$(Str$(camF.orbitPhi))
        Print #sfH, "cam_r="     + LTrim$(Str$(camF.orbitR))
        If debugMode Then DBG_Print "[settings] saved  cam_phi=" + LTrim$(Str$(camF.orbitPhi)) + "  cam_r=" + LTrim$(Str$(camF.orbitR))
    Else
        If debugMode Then DBG_Print "[settings] saved"
    End If
    E3D_BindsWrite sfH
    Close #sfH
End Sub

Sub SETTINGS_Load ()
    SETTINGS_LoadFile _STARTDIR$ + "/sss_settings.ini"
    If Len(telemPlayerID) < 32 Then
        telemPlayerID = TELEM_NewUUID$
        SETTINGS_Save
    End If
    If Len(leaderboardPlayerID) < 32 Then
        leaderboardPlayerID = TELEM_NewUUID$
        SETTINGS_Save
    End If
    E3D_PadReselect
End Sub

Sub SETTINGS_LoadFile (sfPath As String)
    Dim sfH As Integer, sfLine As String, sfKey As String, sfVal As Single, sfEq As Integer
    Dim sfRaw As String, sfBound As Integer
    camF.orbitTheta = _PI(1.0) : camF.orbitPhi = CAM_DEFAULT_PHI : camF.orbitR = CAM_DEFAULT_R : camF.angleLocked = 0
    If _FILEEXISTS(sfPath) Then
        sfH = FreeFile
        Open sfPath For Input As #sfH
        Do While Not EOF(sfH)
            Line Input #sfH, sfLine
            sfEq = InStr(sfLine, "=")
            If sfEq > 0 Then
                sfKey = Left$(sfLine, sfEq - 1)
                sfRaw = Mid$(sfLine, sfEq + 1)
                sfVal = Val(sfRaw)
                Select Case sfKey
                    Case "keys", "padbind"
                        sfBound = E3D_BindsLoadLine%(sfKey, sfRaw)
                    Case "player_id"
                        If Len(sfRaw) >= 32 Then telemPlayerID = sfRaw
                    Case "lb_player_id"
                        If Len(sfRaw) >= 32 Then leaderboardPlayerID = sfRaw
                    Case "player_name"
                        If Len(sfRaw) > 0 And Len(sfRaw) <= UN_MAX_LEN Then telemPlayerName = sfRaw
                    Case "telem_consent"
                        telemConsent = Int(sfVal + 0.5)
                    Case "cam_phi"
                        If sfVal < -1.5 Then sfVal = -1.5
                        If sfVal >  1.5 Then sfVal =  1.5
                        camF.orbitPhi    = sfVal
                        camF.orbitTheta  = _PI(1.0)
                        camF.angleLocked = -1
                    Case "cam_r"
                        If sfVal < 0.5 Then sfVal = 0.5
                        camF.orbitR = sfVal
                    Case "highscore"
                        If sfVal >= 0 Then highScore = CLng(sfVal)
                    Case "narration_speed"
                        settingNarrSpeed = Int(sfVal + 0.5)
                        If settingNarrSpeed < 1 Or settingNarrSpeed > 3 Then settingNarrSpeed = 2
                    Case Else
                        If sfVal < 0 Then sfVal = 0
                        If sfVal > 1 Then sfVal = 1
                        Select Case sfKey
                            Case "music"      : volMusic          = sfVal
                            Case "sfx"        : volSfx            = sfVal
                            Case "speech"     : volSpeech         = sfVal
                            Case "narration"  : settingNarration  = Int(sfVal + 0.5)
                            Case "fullscreen" : settingFullscreen = Int(sfVal + 0.5)
                        End Select
                End Select
            End If
        Loop
        Close #sfH
        If debugMode Then
            If camF.angleLocked Then
                DBG_Print "[settings] loaded  cam_phi=" + LTrim$(Str$(camF.orbitPhi)) + "  cam_r=" + LTrim$(Str$(camF.orbitR))
            Else
                DBG_Print "[settings] loaded"
            End If
        End If
    End If
End Sub
