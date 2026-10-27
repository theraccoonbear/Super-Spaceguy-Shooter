' ui.bas — sci-fi panel renderer
'
' UI_DrawPanel x1, y1, x2, y2, title$
'   Draws a styled HUD panel into the current _DEST.
'   title$ may be "" for a plain panel with no header bar.
'
' Panels drawn over art (the dock, the win tally) use the see-through style instead, so
' every one of them looks the same (#268):
'   UI_Panel x1, y1, x2, y2              see-through fill (UI_SEE_ALPHA), the panel borders and corners
'   UI_PanelFade x1, y1, x2, y2, a       the same, faded as a whole to opacity a (0-255)
'   UI_Text pal, txt$, x, y, a           text with the 1px drop shadow that keeps it legible there
'   UI_TextCentered pal, txt$, y, a

Const UI_SEE_ALPHA = 100   ' see-through panel fill opacity (0-255): low so the art shows

Dim Shared uiShadowSheet As Long   ' all-black font sheet for the text shadow, built on first use

Sub UI_Panel (upX1 As Integer, upY1 As Integer, upX2 As Integer, upY2 As Integer)
    UI_PanelFade upX1, upY1, upX2, upY2, 255
End Sub

Sub UI_PanelFade (upfX1 As Integer, upfY1 As Integer, upfX2 As Integer, upfY2 As Integer, upfA As Integer)
    Dim upfCC As Long
    Line (upfX1, upfY1)-(upfX2, upfY2), _RGBA(2, 4, 18, UI_SEE_ALPHA * upfA \ 255), BF
    Line (upfX1, upfY1)-(upfX2, upfY2), _RGBA(0, 55, 110, upfA), B
    Line (upfX1 + 1, upfY1 + 1)-(upfX2 - 1, upfY2 - 1), _RGBA(0, 130, 210, upfA), B
    upfCC = _RGBA(0, 210, 255, upfA)
    Line (upfX1, upfY1)-(upfX1 + 7, upfY1), upfCC : Line (upfX1, upfY1)-(upfX1, upfY1 + 7), upfCC
    Line (upfX2, upfY1)-(upfX2 - 7, upfY1), upfCC : Line (upfX2, upfY1)-(upfX2, upfY1 + 7), upfCC
    Line (upfX1, upfY2)-(upfX1 + 7, upfY2), upfCC : Line (upfX1, upfY2)-(upfX1, upfY2 - 7), upfCC
    Line (upfX2, upfY2)-(upfX2 - 7, upfY2), upfCC : Line (upfX2, upfY2)-(upfX2, upfY2 - 7), upfCC
End Sub

Sub UI_Text (utPal As Integer, utTxt As String, utX As Integer, utY As Integer, utA As Integer)
    If uiShadowSheet = 0 Then
        FONT_BuildSheet uiShadowSheet, _RGB(0, 0, 0), _RGB(0, 0, 0)
        _Dest backBuffer
    End If
    FONT_PrintAlpha uiShadowSheet, backBuffer, utTxt, utX + 1, utY + 1, utA
    FONT_PrintAlpha fontPalette(utPal), backBuffer, utTxt, utX, utY, utA
End Sub

Sub UI_TextCentered (utcPal As Integer, utcTxt As String, utcY As Integer, utcA As Integer)
    UI_Text utcPal, utcTxt, (scrW - Len(utcTxt) * FONT_CHAR_W) \ 2, utcY, utcA
End Sub


Sub UI_DrawPanel(uiX1 As Integer, uiY1 As Integer, uiX2 As Integer, uiY2 As Integer, uiTitle As String)
    Dim uiSy As Integer
    Const UI_CORNER = 7
    Const UI_TITLE_H = 20

    ' dark fill
    LINE (uiX1, uiY1)-(uiX2, uiY2), _RGBA(2, 4, 18, 242), BF

    ' subtle scanline texture
    For uiSy = uiY1 + 1 To uiY2 - 1 Step 2
        LINE (uiX1 + 1, uiSy)-(uiX2 - 1, uiSy), _RGBA(0, 0, 22, 32)
    Next uiSy

    ' outer border (dim) + inner border (bright)
    LINE (uiX1,     uiY1    )-(uiX2,     uiY2    ), _RGB(0,  55, 110), B
    LINE (uiX1 + 1, uiY1 + 1)-(uiX2 - 1, uiY2 - 1), _RGB(0, 130, 210), B

    ' corner bracket accents — bright cyan L-shapes
    Dim uiCC As Long : uiCC = _RGB(0, 210, 255)
    LINE (uiX1, uiY1)-(uiX1 + UI_CORNER, uiY1), uiCC       ' top-left H
    LINE (uiX1, uiY1)-(uiX1, uiY1 + UI_CORNER), uiCC       ' top-left V
    LINE (uiX2, uiY1)-(uiX2 - UI_CORNER, uiY1), uiCC       ' top-right H
    LINE (uiX2, uiY1)-(uiX2, uiY1 + UI_CORNER), uiCC       ' top-right V
    LINE (uiX1, uiY2)-(uiX1 + UI_CORNER, uiY2), uiCC       ' bot-left H
    LINE (uiX1, uiY2)-(uiX1, uiY2 - UI_CORNER), uiCC       ' bot-left V
    LINE (uiX2, uiY2)-(uiX2 - UI_CORNER, uiY2), uiCC       ' bot-right H
    LINE (uiX2, uiY2)-(uiX2, uiY2 - UI_CORNER), uiCC       ' bot-right V

    ' title bar
    If Len(uiTitle) > 0 Then
        LINE (uiX1 + 2, uiY1 + 2)-(uiX2 - 2, uiY1 + UI_TITLE_H), _RGB(0, 28, 68), BF
        LINE (uiX1 + 2, uiY1 + UI_TITLE_H)-(uiX2 - 2, uiY1 + UI_TITLE_H), _RGB(0, 100, 180)
        FONT_PrintCenteredAlpha fontPalette(11), backBuffer, uiTitle, uiY1 + 3, scrW, 255
    End If
End Sub
