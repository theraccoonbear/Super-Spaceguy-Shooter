' ui.bas — sci-fi panel renderer
'
' UI_DrawPanel x1, y1, x2, y2, title$
'   Draws a styled HUD panel into the current _DEST.
'   title$ may be "" for a plain panel with no header bar.

Sub UI_DrawPanel(uiX1 As Integer, uiY1 As Integer, uiX2 As Integer, uiY2 As Integer, uiTitle As String)
    Dim uiSy As Integer
    Const UI_CORNER = 7
    Const UI_TITLE_H = 12

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
