' settings.bas -- volume config screen and persistent settings

Sub SETTINGS_Save ()
    Dim sfH As Integer
    sfH = FreeFile
    Open _STARTDIR$ + "/sss_settings.ini" For Output As #sfH
    Print #sfH, "music="  + LTrim$(Str$(volMusic))
    Print #sfH, "sfx="    + LTrim$(Str$(volSfx))
    Print #sfH, "speech=" + LTrim$(Str$(volSpeech))
    Close #sfH
End Sub

Sub SETTINGS_Load ()
    Dim sfH As Integer, sfLine As String, sfKey As String, sfVal As Single, sfEq As Integer
    If Not _FILEEXISTS(_STARTDIR$ + "/sss_settings.ini") Then Exit Sub
    sfH = FreeFile
    Open _STARTDIR$ + "/sss_settings.ini" For Input As #sfH
    Do While Not EOF(sfH)
        Line Input #sfH, sfLine
        sfEq = InStr(sfLine, "=")
        If sfEq > 0 Then
            sfKey = Left$(sfLine, sfEq - 1)
            sfVal = Val(Mid$(sfLine, sfEq + 1))
            If sfVal < 0 Then sfVal = 0
            If sfVal > 1 Then sfVal = 1
            Select Case sfKey
                Case "music"  : volMusic  = sfVal
                Case "sfx"    : volSfx    = sfVal
                Case "speech" : volSpeech = sfVal
            End Select
        End If
    Loop
    Close #sfH
End Sub

Sub OPTS_Update ()
    Dim oI As Integer, oY As Integer, oFill As Integer
    Dim oUp As Integer, oDn As Integer, oLf As Integer, oRt As Integer, oEsc As Integer
    Dim oVols(0 To 2) As Single
    Const OPT_BAR_X = 128 : Const OPT_BAR_W = 110

    oVols(0) = volMusic : oVols(1) = volSfx : oVols(2) = volSpeech

    ' ---- input ----
    oUp  = _KEYDOWN(18432)   ' up arrow
    oDn  = _KEYDOWN(20480)   ' down arrow
    oLf  = _KEYDOWN(19200)   ' left arrow
    oRt  = _KEYDOWN(19712)   ' right arrow
    oEsc = _KEYDOWN(27)

    ' navigate: edge-detect on up/down
    If oUp And Not optUpWas Then
        optSel = (optSel + 2) Mod 3
        optLfRpt = 0 : optRtRpt = 0
    End If
    If oDn And Not optDnWas Then
        optSel = (optSel + 1) Mod 3
        optLfRpt = 0 : optRtRpt = 0
    End If

    ' adjust: immediate press + hold repeat every 6 frames
    If oLf Then
        If Not optLfWas Or optLfRpt > 6 Then
            Select Case optSel
                Case 0 : volMusic  = volMusic  - 0.1 : If volMusic  < 0 Then volMusic  = 0
                Case 1 : volSfx    = volSfx    - 0.1 : If volSfx    < 0 Then volSfx    = 0
                Case 2 : volSpeech = volSpeech - 0.1 : If volSpeech < 0 Then volSpeech = 0
            End Select
            If optLfRpt > 6 Then optLfRpt = 1 Else optLfRpt = 0
        End If
        optLfRpt = optLfRpt + 1
    Else
        optLfRpt = 0
    End If

    If oRt Then
        If Not optRtWas Or optRtRpt > 6 Then
            Select Case optSel
                Case 0 : volMusic  = volMusic  + 0.1 : If volMusic  > 1 Then volMusic  = 1
                Case 1 : volSfx    = volSfx    + 0.1 : If volSfx    > 1 Then volSfx    = 1
                Case 2 : volSpeech = volSpeech + 0.1 : If volSpeech > 1 Then volSpeech = 1
            End Select
            If optRtRpt > 6 Then optRtRpt = 1 Else optRtRpt = 0
        End If
        optRtRpt = optRtRpt + 1
    Else
        optRtRpt = 0
    End If

    If oEsc And Not optEscWas Then
        SETTINGS_Save
        gameState = GS_TITLE
    End If

    optUpWas = oUp : optDnWas = oDn : optLfWas = oLf : optRtWas = oRt : optEscWas = oEsc

    ' refresh local vol copy after adjustments
    oVols(0) = volMusic : oVols(1) = volSfx : oVols(2) = volSpeech

    ' ---- render ----
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 8), BF

    FONT_PrintCentered fontPalette(14), backBuffer, "SETTINGS", 20, scrW

    Dim oLabels(0 To 2) As String
    oLabels(0) = "MUSIC"  : oLabels(1) = "SFX"  : oLabels(2) = "SPEECH"

    For oI = 0 To 2
        oY = 58 + oI * 44

        ' row highlight for selected
        If oI = optSel Then
            LINE (30, oY - 3)-(scrW - 31, oY + 13), _RGBA(40, 50, 110, 200), BF
            FONT_Print fontPalette(14), backBuffer, oLabels(oI), 38, oY
        Else
            FONT_Print fontPalette(9),  backBuffer, oLabels(oI), 38, oY
        End If

        ' bar trough
        LINE (OPT_BAR_X, oY)-(OPT_BAR_X + OPT_BAR_W, oY + 8), _RGB(18, 18, 45), BF
        ' bar fill
        oFill = Int(OPT_BAR_W * oVols(oI) + 0.5)
        If oFill > 0 Then
            LINE (OPT_BAR_X, oY)-(OPT_BAR_X + oFill, oY + 8), _RGB(45, 140, 255), BF
        End If
        ' tick marks at 25% intervals
        Dim oT As Integer
        For oT = 1 To 3
            LINE (OPT_BAR_X + (OPT_BAR_W * oT \ 4), oY)-(OPT_BAR_X + (OPT_BAR_W * oT \ 4), oY + 8), _RGBA(0, 0, 0, 90), , 0
        Next oT

        ' percentage label
        Dim oPct As String
        oPct = LTrim$(Str$(Int(oVols(oI) * 100 + 0.5))) + "%"
        FONT_Print fontPalette(9), backBuffer, oPct, OPT_BAR_X + OPT_BAR_W + 8, oY
    Next oI

    FONT_PrintCentered fontPalette(8), backBuffer, "< > adjust   up/dn select   ESC save", scrH - 18, scrW

    _DEST 0
    _PUTIMAGE , backBuffer, 0
End Sub
