' controls.bas — Controls reference screen (keyboard / gamepad pages)
'
' CONTROLS_Prep    remember where to return to; snapshot keys so the opening press isn't re-read
' CONTROLS_Update  render current page; left/right flips page, ESC returns

Const CTL_PAGES  = 2
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
    FONT_PrintAlpha fontPalette(15), backBuffer, ctlrKey, CTL_KEY_X, ctlrY, 255
    FONT_PrintAlpha fontPalette(9),  backBuffer, ctlrAct, CTL_ACT_X, ctlrY, 255
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
        FONT_PrintCenteredAlpha fontPalette(11), backBuffer, "KEYBOARD  1/2", 30, scrW, 255
        CONTROLS_Row 0, "ARROWS/WASD", "MOVE SHIP"
        CONTROLS_Row 1, "SPACE",       "FIRE"
        CONTROLS_Row 2, "E",           "EVASIVE ROLL (DOCK)"
        CONTROLS_Row 3, "Q",           "NOVA PULSE (DOCK)"
        CONTROLS_Row 4, "ESC",         "PAUSE / ABORT"
        CONTROLS_Row 5, "TAB",         "CAMERA MODE ON/OFF"
        CONTROLS_Row 6, " UP/DOWN",    "TILT CAMERA"
        CONTROLS_Row 7, " R",          "RESET CAMERA"
        CONTROLS_Row 8, "P",           "START GAME (TITLE)"
        CONTROLS_Row 9, "F11",         "FULLSCREEN"
        CONTROLS_Row 10, "HOLD SPACE", "FAST-FWD STORY"
        CONTROLS_Row 11, "SPACE+ESC",  "SKIP STORY"
    Else
        FONT_PrintCenteredAlpha fontPalette(11), backBuffer, "GAMEPAD  2/2", 30, scrW, 255
        CONTROLS_Row 0, "LEFT STICK",  "MOVE / MENU SELECT"
        CONTROLS_Row 1, "A",           "FIRE / MENU OK"
        CONTROLS_Row 2, "B",           "FIRE / MENU BACK"
        CONTROLS_Row 3, "X",           "EVASIVE ROLL (DOCK)"
        CONTROLS_Row 4, "Y",           "NOVA PULSE (DOCK)"
        CONTROLS_Row 5, "START",       "PAUSE / ABORT"
        CONTROLS_Row 6, "START",       "START GAME (TITLE)"
        CONTROLS_Row 7, "BACK",        "OPTIONS (TITLE)"
        CONTROLS_Row 8, "BACK",        "CAMERA MODE ON/OFF"
        CONTROLS_Row 9, " STICK U/D",  "TILT CAMERA"
        CONTROLS_Row 10, "HOLD A/B",    "FAST-FWD STORY"
        CONTROLS_Row 11, "A+START",     "SKIP STORY"
    End If

    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "<- -> page   ESC/B back", scrH - 14, scrW, 255

    _Dest 0
    _PutImage , backBuffer, 0

    If ctlEsc And ctlEscWas = 0 Then
        gameState = ctlReturnState
        escWas = -1
        If ctlSavedImg < -1 Then _PutImage (0, 0), ctlSavedImg, backBuffer : _FreeImage ctlSavedImg : ctlSavedImg = 0
    End If
    ctlEscWas = ctlEsc
End Sub
