' controls.bas — Controls reference screen (keyboard / gamepad pages)
'
' CONTROLS_Prep    remember where to return to; snapshot keys so the opening press isn't re-read
' CONTROLS_Update  render current page; left/right flips page, ESC returns

Const CTL_PAGES  = 4   ' keyboard, gamepad, then SHIP SYSTEMS over two pages (#268)
Const CTL_KEY_X  = 28
Const CTL_ACT_X  = 124
Const CTL_ROW_Y  = 46
Const CTL_ROW_H  = 14

Dim Shared ctlReturnState As Integer
Dim Shared ctlPage        As Integer
Dim Shared ctlEscWas      As Integer
Dim Shared ctlLfWas       As Integer
Dim Shared ctlRtWas       As Integer
Dim Shared ctlSavedImg    As Long     ' snapshot of the frame underneath, restored on return (the abort dialog draws over the last frame)

Sub CONTROLS_Prep (ctlpReturn As Integer)
    ctlReturnState = ctlpReturn
    ctlPage = 0
    ctlSavedImg = _CopyImage(backBuffer)
    ctlEscWas = (held(E3D_KEY_ESCAPE) <> 0) Or (held(E3D_KEY_PAD_B) <> 0) : ctlLfWas = held(E3D_KEY_LEFT) : ctlRtWas = held(E3D_KEY_RIGHT)
End Sub

Sub CONTROLS_Row (ctlrRow As Integer, ctlrKey As String, ctlrAct As String)
    Dim ctlrY As Integer
    ctlrY = CTL_ROW_Y + ctlrRow * CTL_ROW_H
    UI_PromptsAt ctlrKey, INP_DEV_PAD, CTL_KEY_X, ctlrY, 15, 255, 0
    FONT_PrintAlpha fontPalette(9),  backBuffer, ctlrAct, CTL_ACT_X, ctlrY, 255
End Sub

' SHIP SYSTEMS page csPart (0 or 1): six dock upgrades each, name and levels, then what it does.
Sub CONTROLS_Systems (csPart As Integer)
    Dim csI As Integer, csId As Integer, csY As Integer, csNm As String, csLv As String, csInfo As String
    FONT_PrintCenteredAlpha fontPalette(11), backBuffer, "SHIP SYSTEMS  " + LTrim$(Str$(csPart + 3)) + "/4", 30, scrW, 255
    For csI = 1 To 6
        csId = csPart * 6 + csI
        csY = 48 + (csI - 1) * 28
        If csId > UPG_COUNT Then
            ' the last slot: the dock's supply rows (#277)
            csNm = "FUEL / SHIELDS" : csLv = "PER DOCK" : csInfo = "BUY BY AMOUNT AT DOCKS"
        Else
            csNm = upgNames$(csId)
            If InStr(csNm, ",") > 0 Then csNm = Left$(csNm, InStr(csNm, ",") - 1) + " / " + Mid$(csNm, InStr(csNm, ",") + 1)
            csLv = LTrim$(Str$(upgMax(csId))) + " LV" : csInfo = UPG_Info$(csId)
        End If
        FONT_PrintAlpha fontPalette(15), backBuffer, csNm, CTL_KEY_X, csY, 255
        FONT_PrintAlpha fontPalette(8), backBuffer, csLv, scrW - 28 - Len(csLv) * FONT_CHAR_W, csY, 255
        UI_PromptsAt csInfo, INP_LastDevice%, CTL_KEY_X + 16, csY + 12, 9, 255, 0
    Next csI
End Sub

Sub CONTROLS_Update ()
    Dim ctlEsc As Integer, ctlLf As Integer, ctlRt As Integer, ctlSy As Integer

    ctlEsc = (held(E3D_KEY_ESCAPE) <> 0) Or (held(E3D_KEY_PAD_B) <> 0) : ctlLf = held(E3D_KEY_LEFT) : ctlRt = held(E3D_KEY_RIGHT)
    If ctlLf And ctlLfWas = 0 Then ctlPage = (ctlPage + CTL_PAGES - 1) Mod CTL_PAGES
    If ctlRt And ctlRtWas = 0 Then ctlPage = (ctlPage + 1) Mod CTL_PAGES
    ctlLfWas = ctlLf : ctlRtWas = ctlRt

    _Dest backBuffer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    For ctlSy = 0 To scrH - 1 Step 2
        Line (0, ctlSy)-(scrW - 1, ctlSy), _RGBA(0, 0, 18, 28)
    Next ctlSy

    UI_DrawPanel 16, 8, scrW - 17, scrH - 19, "CONTROLS"

    If ctlPage = 0 Then
        FONT_PrintCenteredAlpha fontPalette(11), backBuffer, "KEYBOARD  1/4", 30, scrW, 255
        CONTROLS_Row 0, "ARROWS/" + CONTROLS_Key$(E3D_ACT_UP) + CONTROLS_Key$(E3D_ACT_LEFT) + CONTROLS_Key$(E3D_ACT_DOWN) + CONTROLS_Key$(E3D_ACT_RIGHT), "MOVE SHIP"
        CONTROLS_Row 1, CONTROLS_Key$(E3D_ACT_FIRE),   "FIRE"
        CONTROLS_Row 2, CONTROLS_Key$(E3D_ACT_ROLL),   "EVASIVE ROLL (DOCK)"
        CONTROLS_Row 3, CONTROLS_Key$(E3D_ACT_NOVA),   "NOVA PULSE (DOCK)"
        CONTROLS_Row 4, "ESC",         "PAUSE / ABORT"
        CONTROLS_Row 5, CONTROLS_Key$(E3D_ACT_CAMERA), "CAMERA MODE ON/OFF"
        CONTROLS_Row 6, " UP/DOWN",    "TILT CAMERA"
        CONTROLS_Row 7, " R",          "RESET CAMERA"
        CONTROLS_Row 8, "P",           "START GAME (TITLE)"
        CONTROLS_Row 9, "F11",         "FULLSCREEN"
        CONTROLS_Row 10, "HOLD " + CONTROLS_Key$(E3D_ACT_FIRE), "FAST-FWD STORY"
        CONTROLS_Row 11, CONTROLS_Key$(E3D_ACT_FIRE) + "+ESC",  "SKIP STORY"
    ElseIf ctlPage = 1 Then
        FONT_PrintCenteredAlpha fontPalette(11), backBuffer, "GAMEPAD  2/4", 30, scrW, 255
        CONTROLS_Row 0, "LEFT STICK",  "MOVE / MENU SELECT"
        CONTROLS_Row 1, CONTROLS_Pad$(E3D_ACT_FIRE) + "/" + CONTROLS_Pad$(E3D_ACT_FIRE2), "FIRE"
        CONTROLS_Row 2, CONTROLS_Pad$(E3D_ACT_CONFIRM) + "/" + CONTROLS_Pad$(E3D_ACT_BACK), "MENU OK / BACK"
        CONTROLS_Row 3, CONTROLS_Pad$(E3D_ACT_ROLL),   "EVASIVE ROLL (DOCK)"
        CONTROLS_Row 4, CONTROLS_Pad$(E3D_ACT_NOVA),   "NOVA PULSE (DOCK)"
        CONTROLS_Row 5, CONTROLS_Pad$(E3D_ACT_PAUSE),  "PAUSE / ABORT"
        CONTROLS_Row 6, CONTROLS_Pad$(E3D_ACT_PAUSE),  "START GAME (TITLE)"
        CONTROLS_Row 7, CONTROLS_Pad$(E3D_ACT_CAMERA), "OPTIONS (TITLE)"
        CONTROLS_Row 8, CONTROLS_Pad$(E3D_ACT_CAMERA), "CAMERA MODE ON/OFF"
        CONTROLS_Row 9, " STICK U/D",  "TILT CAMERA"
        CONTROLS_Row 10, "HOLD " + CONTROLS_Pad$(E3D_ACT_FIRE), "FAST-FWD STORY"
        CONTROLS_Row 11, CONTROLS_Pad$(E3D_ACT_FIRE) + "+" + CONTROLS_Pad$(E3D_ACT_PAUSE), "SKIP STORY"
    Else
        CONTROLS_Systems ctlPage - 2
    End If

    UI_PromptsCentered "<- -> page   " + UI_Tok$("ESC", E3D_ACT_BACK) + " back", scrH - 14, 8, 255

    _Dest 0
    _PutImage , backBuffer, 0

    If ctlEsc And ctlEscWas = 0 Then
        gameState = ctlReturnState
        escWas = -1
        If ctlSavedImg < -1 Then _PutImage (0, 0), ctlSavedImg, backBuffer : _FreeImage ctlSavedImg : ctlSavedImg = 0
    End If
    ctlEscWas = ctlEsc
End Sub

' Bound key names, and pad button badges as UI_Tok$ prompts, for the reference pages
' (remapped in Settings > Controls, #266).
Function CONTROLS_Key$ (ckAct As Integer)
    CONTROLS_Key$ = E3D_KeyName$(keyBind(ckAct))
End Function

Function CONTROLS_Pad$ (cpAct As Integer)
    CONTROLS_Pad$ = UI_Tok$("", cpAct)
End Function
