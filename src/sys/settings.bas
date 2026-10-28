' settings.bas -- volume config screen and persistent settings

Sub SETTINGS_Save ()
    Dim sfH As Integer
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
    Dim sfH As Integer, sfLine As String, sfKey As String, sfVal As Single, sfEq As Integer
    Dim sfRaw As String, sfBound As Integer
    If _FILEEXISTS(_STARTDIR$ + "/sss_settings.ini") Then
        sfH = FreeFile
        Open _STARTDIR$ + "/sss_settings.ini" For Input As #sfH
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

Sub OPTS_Update ()
    Dim oI As Integer, oY As Integer, oFill As Integer
    Dim oUp As Integer, oDn As Integer, oLf As Integer, oRt As Integer, oEsc As Integer
    Dim oVols(0 To 4) As Single
    Const OPT_BAR_X = 128 : Const OPT_BAR_W = 110

    oVols(0) = volMusic : oVols(1) = volSfx : oVols(2) = volSpeech : oVols(3) = settingNarration * settingNarrSpeed / 3 : oVols(4) = settingFullscreen

    ' ---- input ----
    ' held() slots carry the keyboard arrows and the pad stick; ESC's slot also carries pad Start
    oUp  = (held(E3D_KEY_UP) <> 0)
    oDn  = (held(E3D_KEY_DOWN) <> 0)
    oLf  = (held(E3D_KEY_LEFT) <> 0)
    oRt  = (held(E3D_KEY_RIGHT) <> 0)
    oEsc = (held(E3D_KEY_ESCAPE) <> 0) Or (held(E3D_KEY_PAD_B) <> 0)

    ' navigate: edge-detect on up/down
    If oUp And Not optUpWas Then
        optSel = (optSel + 6) Mod 7
        optLfRpt = 0 : optRtRpt = 0
    End If
    If oDn And Not optDnWas Then
        optSel = (optSel + 1) Mod 7
        optLfRpt = 0 : optRtRpt = 0
    End If

    ' adjust: immediate press + hold repeat every 6 frames
    If oLf Then
        If Not optLfWas Or optLfRpt > 6 Then
            Select Case optSel
                Case 0 : volMusic         = volMusic  - 0.1 : If volMusic  < 0 Then volMusic  = 0
                Case 1 : volSfx           = volSfx    - 0.1 : If volSfx    < 0 Then volSfx    = 0
                Case 2 : volSpeech        = volSpeech - 0.1 : If volSpeech < 0 Then volSpeech = 0
                Case 3 ' FAST > NORMAL > SLOW > OFF
                    If settingNarration Then
                        If settingNarrSpeed > 1 Then settingNarrSpeed = settingNarrSpeed - 1 Else settingNarration = 0
                    End If
                Case 4 : settingFullscreen = 0 : _FULLSCREEN OFF
                Case 5 : ' callsign -- no left/right action
            End Select
            If optSel = 1 Then SND_Pup
            If optSel = 2 And Not optLfWas Then SPK_Say GTEXT_Get$("speech_poop")
            If optSel = 3 And Not optLfWas And settingNarration Then SPK_Say sSpkTitle : SPK_SetPreset settingNarrSpeed
            If optLfRpt > 6 Then optLfRpt = 1 Else optLfRpt = 0
        End If
        optLfRpt = optLfRpt + 1
    Else
        optLfRpt = 0
    End If

    If oRt Then
        If Not optRtWas Or optRtRpt > 6 Then
            Select Case optSel
                Case 0 : volMusic         = volMusic  + 0.1 : If volMusic  > 1 Then volMusic  = 1
                Case 1 : volSfx           = volSfx    + 0.1 : If volSfx    > 1 Then volSfx    = 1
                Case 2 : volSpeech        = volSpeech + 0.1 : If volSpeech > 1 Then volSpeech = 1
                Case 3 ' OFF > SLOW > NORMAL > FAST
                    If settingNarration = 0 Then
                        settingNarration = 1 : settingNarrSpeed = 1
                    ElseIf settingNarrSpeed < 3 Then
                        settingNarrSpeed = settingNarrSpeed + 1
                    End If
                Case 4 : settingFullscreen = 1 : _FULLSCREEN _SQUAREPIXELS
                Case 5 : ' callsign -- no left/right action
            End Select
            If optSel = 1 Then SND_Pup
            If optSel = 2 And Not optRtWas Then SPK_Say GTEXT_Get$("speech_poop")
            If optSel = 3 And Not optRtWas And settingNarration Then SPK_Say sSpkTitle : SPK_SetPreset settingNarrSpeed
            If optRtRpt > 6 Then optRtRpt = 1 Else optRtRpt = 0
        End If
        optRtRpt = optRtRpt + 1
    Else
        optRtRpt = 0
    End If

    If oEsc And Not optEscWas Then
        SETTINGS_Save
        TITLE_ReturnTo GS_TITLE
    End If

    ' a press, not a hold: the A that picked SETTINGS on the console is still down here
    Dim oEnter As Integer : oEnter = (KEY_Confirm% Or KEY_Pressed%(E3D_KEY_SPACE)) And KEY_Pressed%(E3D_KEY_PAD_B) = 0
    If oEnter And optSel = 5 Then
        SETTINGS_Save
        unSavedName    = telemPlayerName
        unFromSettings = -1
        Do While KEY_Hit& <> 0 : Loop  ' drain ENTER from the key-press buffer before username reads it
        GS_USERNAME_Init
        gameState      = GS_USERNAME
    End If
    If oEnter And optSel = 6 Then
        SETTINGS_Save
        RMP_Open GS_OPTIONS
    End If

    Dim oAbout As Integer : oAbout = KEY_Down%(65) Or KEY_Down%(97)
    If oAbout And Not optAboutWas Then
        ABOUT_Prep GS_OPTIONS : gameState = GS_ABOUT
    End If
    optAboutWas = oAbout

    optUpWas = oUp : optDnWas = oDn : optLfWas = oLf : optRtWas = oRt : optEscWas = oEsc

    ' refresh local vol copy after adjustments
    oVols(0) = volMusic : oVols(1) = volSfx : oVols(2) = volSpeech : oVols(3) = settingNarration * settingNarrSpeed / 3 : oVols(4) = settingFullscreen

    ' ---- render ----
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF

    ' bg scanlines
    Dim oSy As Integer
    For oSy = 0 To scrH - 1 Step 2
        LINE (0, oSy)-(scrW - 1, oSy), _RGBA(0, 0, 18, 28)
    Next oSy

    ' main content panel
    UI_DrawPanel 16, 8, scrW - 17, scrH - 19, "SETTINGS"

    Dim oLabels(0 To 6) As String
    oLabels(0) = "MUSIC" : oLabels(1) = "SFX" : oLabels(2) = "SPEECH" : oLabels(3) = "NARRATION" : oLabels(4) = "FULLSCREEN" : oLabels(5) = "CALLSIGN" : oLabels(6) = "CONTROLS"

    For oI = 0 To 6
        oY = 36 + oI * 24

        ' row highlight for selected — corner-bracket style
        If oI = optSel Then
            LINE (30, oY - 3)-(scrW - 31, oY + 17), _RGBA(0, 40, 100, 180), BF
            LINE (30, oY - 3)-(scrW - 31, oY + 17), _RGB(0, 100, 180), B
            ' corner accents on selection
            Dim oCC As Long : oCC = _RGB(0, 210, 255)
            LINE (30, oY - 3)-(34, oY - 3), oCC : LINE (30, oY - 3)-(30, oY + 1), oCC
            LINE (scrW - 31, oY - 3)-(scrW - 35, oY - 3), oCC : LINE (scrW - 31, oY - 3)-(scrW - 31, oY + 1), oCC
            LINE (30, oY + 17)-(34, oY + 17), oCC : LINE (30, oY + 17)-(30, oY + 13), oCC
            LINE (scrW - 31, oY + 17)-(scrW - 35, oY + 17), oCC : LINE (scrW - 31, oY + 17)-(scrW - 31, oY + 13), oCC
            FONT_PrintAlpha fontPalette(14), backBuffer, oLabels(oI), 38, oY, 255
        Else
            FONT_PrintAlpha fontPalette(9), backBuffer, oLabels(oI), 38, oY, 255
        End If

        If oI < 5 Then
            ' bar trough — centered in 16px label glyph (oY+4 to oY+12)
            LINE (OPT_BAR_X, oY + 4)-(OPT_BAR_X + OPT_BAR_W, oY + 12), _RGB(4, 8, 28), BF
            LINE (OPT_BAR_X, oY + 4)-(OPT_BAR_X + OPT_BAR_W, oY + 12), _RGB(0, 55, 110), B
            ' bar fill
            oFill = Int(OPT_BAR_W * oVols(oI) + 0.5)
            If oFill > 0 Then
                LINE (OPT_BAR_X + 1, oY + 5)-(OPT_BAR_X + oFill, oY + 11), _RGB(0, 130, 210), BF
                LINE (OPT_BAR_X + 1, oY + 5)-(OPT_BAR_X + oFill, oY + 7),  _RGBA(100, 200, 255, 80), BF
            End If
            ' tick marks at 25% intervals
            Dim oT As Integer
            For oT = 1 To 3
                LINE (OPT_BAR_X + (OPT_BAR_W * oT \ 4), oY + 5)-(OPT_BAR_X + (OPT_BAR_W * oT \ 4), oY + 11), _RGBA(0, 0, 0, 100), , 0
            Next oT

            ' percentage / state label
            Dim oPct As String
            If oI = 3 Then
                If settingNarration = 0 Then
                    oPct = "OFF"
                Else
                    Select Case settingNarrSpeed
                        Case 1 : oPct = "SLOW"
                        Case 3 : oPct = "FAST"
                        Case Else : oPct = "NORMAL"
                    End Select
                End If
            ElseIf oI = 4 Then
                If settingFullscreen Then oPct = "ON" Else oPct = "OFF"
            Else
                oPct = LTrim$(Str$(Int(oVols(oI) * 100 + 0.5))) + "%"
            End If
            FONT_PrintAlpha fontPalette(9), backBuffer, oPct, OPT_BAR_X + OPT_BAR_W + 8, oY, 255
        ElseIf oI = 6 Then
            If oI = optSel Then
                FONT_PrintAlpha fontPalette(15), backBuffer, "REMAP [ENTER]", OPT_BAR_X, oY, 255
            Else
                FONT_PrintAlpha fontPalette(9),  backBuffer, "KEYS + GAMEPAD", OPT_BAR_X, oY, 200
            End If
        Else
            ' callsign row: show current name (or prompt) instead of a slider
            Dim oCallName As String
            If Len(telemPlayerName) > 0 Then oCallName = telemPlayerName Else oCallName = "(NONE)"
            ' callsigns run to UN_MAX_LEN; keep the row inside the panel (21 cols from OPT_BAR_X)
            Dim oCallMax As Integer
            If oI = optSel Then oCallMax = 13 Else oCallMax = 21
            If Len(oCallName) > oCallMax Then oCallName = Left$(oCallName, oCallMax - 2) + ".."
            If oI = optSel Then
                FONT_PrintAlpha fontPalette(15), backBuffer, oCallName + " [ENTER]", OPT_BAR_X, oY, 255
            Else
                FONT_PrintAlpha fontPalette(9),  backBuffer, oCallName,             OPT_BAR_X, oY, 200
            End If
        End If
    Next oI

    If highScore > 0 Then
        FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "HI SCORE:  " + LTRIM$(STR$(highScore)), 202, scrW, 255
    End If
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "< > adjust  up/dn select  A about  ESC", scrH - 14, scrW, 255

    _DEST 0
    _PUTIMAGE , backBuffer, 0
End Sub
