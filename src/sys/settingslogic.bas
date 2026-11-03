' settingslogic.bas -- sss_settings.ini as text: SETTINGS_Parse reads it into the shared settings
' variables, SETTINGS_Serialize$ builds it from them. No file I/O and no screen; settingsio.bas
' wraps them with the file calls.

' -1 once the tutorial was finished or skipped (#240). A settings file with no tutorial_done line counts as
' done, so existing players are not sent to it; only a first run, with no file yet, starts at 0.
Dim Shared settingTutorialDone As Integer

' Every line of the file, LF-terminated.
Function SETTINGS_Serialize$ ()
    Dim ssNl As String, ssOut As String
    ssNl = Chr$(10)
    ssOut = "music="      + LTrim$(Str$(volMusic)) + ssNl
    ssOut = ssOut + "sfx="        + LTrim$(Str$(volSfx)) + ssNl
    ssOut = ssOut + "speech="     + LTrim$(Str$(volSpeech)) + ssNl
    ssOut = ssOut + "narration="  + LTrim$(Str$(settingNarration)) + ssNl
    ssOut = ssOut + "narration_speed=" + LTrim$(Str$(settingNarrSpeed)) + ssNl
    ssOut = ssOut + "fullscreen=" + LTrim$(Str$(settingFullscreen)) + ssNl
    ssOut = ssOut + "difficulty=" + DLV_Valid$(settingDifficulty) + ssNl
    ssOut = ssOut + "highscore="  + LTrim$(Str$(highScore)) + ssNl
    ssOut = ssOut + "tutorial_done=" + LTrim$(Str$(Abs(settingTutorialDone <> 0))) + ssNl
    If Len(telemPlayerID) > 0 Then ssOut = ssOut + "player_id=" + telemPlayerID + ssNl
    If Len(leaderboardPlayerID) > 0 Then ssOut = ssOut + "lb_player_id=" + leaderboardPlayerID + ssNl
    If Len(telemPlayerName) > 0 Then ssOut = ssOut + "player_name=" + telemPlayerName + ssNl
    If telemConsent Then ssOut = ssOut + "telem_consent=1" + ssNl
    If camF.angleLocked Then
        ssOut = ssOut + "cam_phi=" + LTrim$(Str$(camF.orbitPhi)) + ssNl
        ssOut = ssOut + "cam_r="   + LTrim$(Str$(camF.orbitR)) + ssNl
    End If
    SETTINGS_Serialize$ = ssOut + E3D_BindsLines$
End Function

' Reads a settings file's text (lines end in LF, CR or CRLF). The camera orbit starts at its
' default and a file counts as one the tutorial was already offered in (#240); keys it doesn't
' have leave the variable as it was. Bad values are clamped or ignored.
Sub SETTINGS_Parse (spText As String)
    Dim spPos As Long, spEnd As Long, spLen As Long, spCh As String
    Dim spLine As String, spKey As String, spRaw As String, spVal As Single, spEq As Integer, spBound As Integer
    camF.orbitTheta = _PI(1.0) : camF.orbitPhi = CAM_DEFAULT_PHI : camF.orbitR = CAM_DEFAULT_R : camF.angleLocked = 0
    settingTutorialDone = -1
    spLen = Len(spText)
    spPos = 1
    Do While spPos <= spLen
        spEnd = spPos
        Do While spEnd <= spLen
            spCh = Mid$(spText, spEnd, 1)
            If spCh = Chr$(10) Or spCh = Chr$(13) Then Exit Do
            spEnd = spEnd + 1
        Loop
        spLine = Mid$(spText, spPos, spEnd - spPos)
        spPos = spEnd + 1
        spEq = InStr(spLine, "=")
        If spEq > 0 Then
            spKey = Left$(spLine, spEq - 1)
            spRaw = Mid$(spLine, spEq + 1)
            spVal = Val(spRaw)
            Select Case spKey
                Case "keys", "padbind"
                    spBound = E3D_BindsLoadLine%(spKey, spRaw)
                Case "player_id"
                    If Len(spRaw) >= 32 Then telemPlayerID = spRaw
                Case "lb_player_id"
                    If Len(spRaw) >= 32 Then leaderboardPlayerID = spRaw
                Case "player_name"
                    If Len(spRaw) > 0 And Len(spRaw) <= UN_MAX_LEN Then telemPlayerName = spRaw
                Case "telem_consent"
                    telemConsent = Int(spVal + 0.5)
                Case "cam_phi"
                    If spVal < -1.5 Then spVal = -1.5
                    If spVal >  1.5 Then spVal =  1.5
                    camF.orbitPhi    = spVal
                    camF.orbitTheta  = _PI(1.0)
                    camF.angleLocked = -1
                Case "cam_r"
                    If spVal < 0.5 Then spVal = 0.5
                    camF.orbitR = spVal
                Case "highscore"
                    If spVal >= 0 Then highScore = CLng(spVal)
                Case "tutorial_done"
                    settingTutorialDone = (Int(spVal + 0.5) <> 0)
                Case "difficulty"
                    settingDifficulty = DLV_Valid$(spRaw)
                Case "narration_speed"
                    settingNarrSpeed = Int(spVal + 0.5)
                    If settingNarrSpeed < 1 Or settingNarrSpeed > 3 Then settingNarrSpeed = 2
                Case Else
                    If spVal < 0 Then spVal = 0
                    If spVal > 1 Then spVal = 1
                    Select Case spKey
                        Case "music"      : volMusic          = spVal
                        Case "sfx"        : volSfx            = spVal
                        Case "speech"     : volSpeech         = spVal
                        Case "narration"  : settingNarration  = Int(spVal + 0.5)
                        Case "fullscreen" : settingFullscreen = Int(spVal + 0.5)
                    End Select
            End Select
        End If
    Loop
End Sub
