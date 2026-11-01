' settingsio.bas -- persistent settings: sss_settings.ini in the per-user settings dir (#284)
'
' settingsDir is where the file lives; sss.bas picks it at startup (the per-user dir, else the
' launch folder, else "" = read-only session, #283). SETTINGS_DirFor$ is the per-OS rule.

Const SETTINGS_FILE = "sss_settings.ini"

' -1 once the tutorial was finished or skipped (#240). A settings file with no tutorial_done line counts as
' done, so existing players are not sent to it; only a first run, with no file yet, starts at 0.
Dim Shared settingTutorialDone As Integer

' The per-user settings dir for an OS (the _OS$ string), or "" when its base can't be told.
' sdXdg / sdAppData / sdHome are the XDG_CONFIG_HOME, APPDATA and HOME environment values.
Function SETTINGS_DirFor$ (sdOs As String, sdXdg As String, sdAppData As String, sdHome As String)
    SETTINGS_DirFor$ = ""
    If InStr(sdOs, "WIN") > 0 Then
        If Len(sdAppData) > 0 Then SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdAppData) + "\sss"
    ElseIf InStr(sdOs, "MAC") > 0 Then
        If Len(sdHome) > 0 Then SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdHome) + "/Library/Application Support/sss"
    Else
        If Left$(sdXdg, 1) = "/" Then
            SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdXdg) + "/sss"
        ElseIf Len(sdHome) > 0 Then
            SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdHome) + "/.config/sss"
        End If
    End If
End Function

Function SETTINGS_TrimSlash$ (tsPath As String)
    Dim tsOut As String : tsOut = tsPath
    Do While Len(tsOut) > 1 And (Right$(tsOut, 1) = "/" Or Right$(tsOut, 1) = "\")
        tsOut = Left$(tsOut, Len(tsOut) - 1)
    Loop
    SETTINGS_TrimSlash$ = tsOut
End Function

' The folder holding parPath, or "" when it has no parent left.
Function SETTINGS_Parent$ (parPath As String)
    Dim parI As Integer, parCh As String
    SETTINGS_Parent$ = ""
    For parI = Len(parPath) - 1 To 1 Step -1
        parCh = Mid$(parPath, parI, 1)
        If parCh = "/" Or parCh = "\" Then SETTINGS_Parent$ = Left$(parPath, parI - 1) : Exit Function
    Next parI
End Function

' First run in a new settings dir: copy an existing launch-folder file over, leaving the original.
' Returns -1 when it copied, 0 when there was nothing to do.
Function SETTINGS_Migrate% (smSrc As String, smDst As String)
    Dim smB As Integer, smData As String
    SETTINGS_Migrate% = 0
    If _FileExists(smDst) Or _FileExists(smSrc) = 0 Then Exit Function
    smData = _ReadFile$(smSrc)
    smB = FreeFile
    Open smDst For Binary As #smB
    Put #smB, , smData
    Close #smB
    SETTINGS_Migrate% = -1
End Function

Sub SETTINGS_Save ()
    If Len(settingsDir) = 0 Then Exit Sub
    SETTINGS_SaveFile settingsDir + "/" + SETTINGS_FILE
End Sub

Sub SETTINGS_SaveFile (sfsPath As String)
    Dim sfH As Integer
    If ioReadOnly Then Exit Sub
    sfH = FreeFile
    Open sfsPath For Output As #sfH
    Print #sfH, "music="      + LTrim$(Str$(volMusic))
    Print #sfH, "sfx="        + LTrim$(Str$(volSfx))
    Print #sfH, "speech="     + LTrim$(Str$(volSpeech))
    Print #sfH, "narration="  + LTrim$(Str$(settingNarration))
    Print #sfH, "narration_speed=" + LTrim$(Str$(settingNarrSpeed))
    Print #sfH, "fullscreen=" + LTrim$(Str$(settingFullscreen))
    Print #sfH, "difficulty=" + DLV_Valid$(settingDifficulty)
    Print #sfH, "highscore="  + LTrim$(Str$(highScore))
    Print #sfH, "tutorial_done=" + LTrim$(Str$(Abs(settingTutorialDone <> 0)))
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
    If Len(settingsDir) > 0 Then SETTINGS_LoadFile settingsDir + "/" + SETTINGS_FILE Else SETTINGS_LoadFile ""
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
    If Len(sfPath) > 0 And _FILEEXISTS(sfPath) Then settingTutorialDone = -1 Else settingTutorialDone = 0
    If Len(sfPath) > 0 And _FILEEXISTS(sfPath) Then
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
                    Case "tutorial_done"
                        settingTutorialDone = (Int(sfVal + 0.5) <> 0)
                    Case "difficulty"
                        settingDifficulty = DLV_Valid$(sfRaw)
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
