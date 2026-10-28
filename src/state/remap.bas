' remap.bas -- draws the Controls remap page and the pad setup wizard (GS_REMAP, #266).
' Input and state: remaplogic.bas. Opened from Settings > Controls, the pause dialog
' (K / nova button), and by the title for an unknown pad's first-run setup.
' Local variable prefix: rmd*

Const RMD_ROWS_SHOWN = 8
Const RMD_ROW_Y = 48
Const RMD_ROW_H = 17
Const RMD_KEY_X = 150
Const RMD_PAD_X = 222

Dim Shared rmdTop As Integer
Dim Shared rmdSavedImg As Long   ' the frame underneath (the pause dialog's game view), restored on leaving

Sub RMP_Update
    Dim rmdEv As Integer
    If rmpSnapDue Then
        rmpSnapDue = 0
        If rmdSavedImg < -1 Then _FreeImage rmdSavedImg
        rmdSavedImg = _CopyImage(backBuffer)
    End If
    rmdEv = RMP_Input%
    Select Case rmdEv
        Case RMP_EV_MOVE : SND_UiMove
        Case RMP_EV_OK : SND_Pup
        Case RMP_EV_DENY : SND_UiDeny
    End Select
    If rmpSaveDue Then rmpSaveDue = 0 : SETTINGS_Save
    If rmpLeft Then
        rmpLeft = 0
        If rmdSavedImg < -1 Then _PutImage (0, 0), rmdSavedImg, backBuffer : _FreeImage rmdSavedImg : rmdSavedImg = 0
        Exit Sub
    End If
    RMP_DrawPage
    If rmpMode = RMP_MODE_WIZ Then RMP_DrawWizard
    _Dest 0
    _PutImage , backBuffer, 0
End Sub

Sub RMP_DrawPage
    Dim rmdI As Integer, rmdRow As Integer, rmdY As Integer, rmdAct As Integer, rmdSy As Integer
    Dim rmdKey As String, rmdPad As String, rmdKPal As Integer, rmdPPal As Integer, rmdLPal As Integer
    Dim rmdName As String

    If rmpSel < rmdTop Then rmdTop = rmpSel
    If rmpSel >= rmdTop + RMD_ROWS_SHOWN Then rmdTop = rmpSel - RMD_ROWS_SHOWN + 1

    _Dest backBuffer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    For rmdSy = 0 To scrH - 1 Step 2
        Line (0, rmdSy)-(scrW - 1, rmdSy), _RGBA(0, 0, 18, 28)
    Next rmdSy
    UI_DrawPanel 16, 8, scrW - 17, scrH - 19, "CONTROLS"

    FONT_PrintAlpha fontPalette(8), backBuffer, "ACTION", 30, 30, 255
    If rmpCol = 0 Then rmdKPal = 11 Else rmdKPal = 8
    If rmpCol = 1 Then rmdPPal = 11 Else rmdPPal = 8
    FONT_PrintAlpha fontPalette(rmdKPal), backBuffer, "KEY", RMD_KEY_X, 30, 255
    FONT_PrintAlpha fontPalette(rmdPPal), backBuffer, "PAD", RMD_PAD_X, 30, 255

    For rmdI = 0 To RMD_ROWS_SHOWN - 1
        rmdRow = rmdTop + rmdI
        If rmdRow >= RMP_ROWS Then Exit For
        rmdY = RMD_ROW_Y + rmdI * RMD_ROW_H
        If rmdRow = rmpSel Then
            UI_MenuHighlight 26, rmdY - 1, scrW - 27, rmdY + 15
            rmdLPal = 14
        Else
            rmdLPal = 9
        End If
        If rmdRow = RMP_ROW_SETUP Then
            FONT_PrintAlpha fontPalette(rmdLPal), backBuffer, "RUN PAD SETUP", 30, rmdY, 255
        ElseIf rmdRow = RMP_ROW_RESET Then
            FONT_PrintAlpha fontPalette(rmdLPal), backBuffer, "RESET TO DEFAULTS", 30, rmdY, 255
        Else
            rmdAct = RMP_RowAct%(rmdRow)
            FONT_PrintAlpha fontPalette(rmdLPal), backBuffer, E3D_ActName$(rmdAct), 30, rmdY, 255
            rmdKey = E3D_KeyName$(keyBind(rmdAct))
            rmdKPal = 9 : rmdPPal = 9
            If E3D_KeyFixed%(rmdAct) Then rmdKPal = 8
            If rmdAct > E3D_ACT_PAD_COUNT Then rmdPad = "STICK" : rmdPPal = 8 Else rmdPad = ""
            If rmdRow = rmpSel Then
                If rmpCol = 0 Then rmdKPal = 15 Else rmdPPal = 15
            End If
            FONT_PrintAlpha fontPalette(rmdKPal), backBuffer, rmdKey, RMD_KEY_X, rmdY, 255
            If rmdPad = "" Then UI_PadBadge padBind(rmdAct), RMD_PAD_X, rmdY, 255 Else FONT_PrintAlpha fontPalette(rmdPPal), backBuffer, rmdPad, RMD_PAD_X, rmdY, 255
        End If
    Next rmdI
    If rmdTop > 0 Then FONT_PrintAlpha fontPalette(8), backBuffer, "^", scrW - 34, RMD_ROW_Y - 2, 255
    If rmdTop + RMD_ROWS_SHOWN < RMP_ROWS Then FONT_PrintAlpha fontPalette(8), backBuffer, "v", scrW - 34, RMD_ROW_Y + (RMD_ROWS_SHOWN - 1) * RMD_ROW_H, 255

    If rmpMsgT > 0 Then
        If rmpMsgBad Then rmdLPal = 12 Else rmdLPal = 10
        FONT_PrintCenteredAlpha fontPalette(rmdLPal), backBuffer, rmpMsg$, 190, scrW, 255
    Else
        If ctrlDev > 0 Then rmdName = "PAD: " + UCase$(ctrlName$) Else rmdName = "NO GAMEPAD CONNECTED"
        If Len(rmdName) > 34 Then rmdName = Left$(rmdName, 32) + ".."
        FONT_PrintCenteredAlpha fontPalette(8), backBuffer, rmdName, 190, scrW, 255
    End If
    UI_PromptsCentered UI_Tok$("ENTER", E3D_ACT_CONFIRM) + " REBIND  < > KEY/PAD  " + UI_Tok$("ESC", E3D_ACT_BACK), scrH - 14, 8, 255
End Sub

Sub RMP_DrawWizard
    Dim rmwCur As String, rmwLine As String, rmwN As Integer, rmwOf As Integer, rmwSecs As Integer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 5, 210), BF
    UI_Panel 28, 56, scrW - 29, 198
    If rmpWizKind = E3D_BIND_PAD Then
        UI_TextCentered 11, "GAMEPAD SETUP", 62, 255
        rmwLine = UCase$(ctrlName$)
        If Len(rmwLine) > 30 Then rmwLine = Left$(rmwLine, 28) + ".."
        UI_TextCentered 8, rmwLine, 80, 255
        UI_TextCentered 9, "PRESS YOUR", 100, 255
        UI_TextCentered 15, E3D_ActName$(rmpWizAct) + " BUTTON", 118, 255
    Else
        UI_TextCentered 11, "KEYBOARD", 62, 255
        UI_TextCentered 9, "PRESS A KEY FOR", 100, 255
        UI_TextCentered 15, E3D_ActName$(rmpWizAct), 118, 255
    End If
    rmwCur = RMP_BindName$(rmpWizKind, rmpWizWork(rmpWizAct))
    rmwN = rmpWizAct - rmpWizFirst + 1 : rmwOf = rmpWizLast - rmpWizFirst + 1
    rmwLine = "NOW " + rmwCur
    If rmwOf > 1 Then rmwLine = rmwLine + "   " + LTrim$(Str$(rmwN)) + "/" + LTrim$(Str$(rmwOf))
    UI_TextCentered 8, rmwLine, 136, 255
    If rmpMsgT > 0 Then
        UI_TextCentered 12, rmpMsg$, 154, 255
    Else
        rmwSecs = (RMP_TIMEOUT - rmpWizTimer + 59) \ 60
        UI_TextCentered 8, "SKIPPING IN" + Str$(rmwSecs), 154, 255
    End If
    UI_TextCentered 8, "STICK/ARROWS SKIP  ESC CANCEL", 176, 255
End Sub
