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
'
'   UI_MenuHighlight x1, y1, x2, y2      the selected menu row's box, the same in every menu
'
' Input prompts name only the device last used (INP_LastDevice%): a key's name, or a pad
' button's badge (A green, B red, X blue, Y yellow circles; START, BACK, bumpers and the like
' as pills; anything else, e.g. an unknown pad's numbered button, in grey).
'   t$ = UI_Tok$(key$, act)            a prompt inside prompt text: key$ on the keyboard ("" = act's
'                                      bound key), act's bound pad button on the pad (act 0 = none)
'   UI_Prompts txt$, x, y, pal, a      text with UI_Tok$ prompts, for the device last used
'   UI_PromptsCentered txt$, y, pal, a
'   UI_PromptsAt txt$, dev, x, y, pal, a, shadow   the same for a given device; shadow as UI_Text
'   w = UI_PromptsW%(txt$, dev)        its width in pixels
'   UI_PadBadge btn, x, y, a  /  w = UI_PadBadgeW%(btn)   one pad button (raw number) in a 16px row

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

Sub UI_MenuHighlight (umhX1 As Integer, umhY1 As Integer, umhX2 As Integer, umhY2 As Integer)
    Dim umhCC As Long
    Line (umhX1, umhY1)-(umhX2, umhY2), _RGBA(0, 40, 100, 180), BF
    Line (umhX1, umhY1)-(umhX2, umhY2), _RGB(0, 100, 180), B
    umhCC = _RGB(0, 210, 255)
    Line (umhX1, umhY1)-(umhX1 + 4, umhY1), umhCC : Line (umhX1, umhY1)-(umhX1, umhY1 + 4), umhCC
    Line (umhX2, umhY1)-(umhX2 - 4, umhY1), umhCC : Line (umhX2, umhY1)-(umhX2, umhY1 + 4), umhCC
    Line (umhX1, umhY2)-(umhX1 + 4, umhY2), umhCC : Line (umhX1, umhY2)-(umhX1, umhY2 - 4), umhCC
    Line (umhX2, umhY2)-(umhX2 - 4, umhY2), umhCC : Line (umhX2, umhY2)-(umhX2, umhY2 - 4), umhCC
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

Function UI_Tok$ (utkKey As String, utkAct As Integer)
    UI_Tok$ = "{" + utkKey + "|" + LTrim$(Str$(utkAct)) + "}"
End Function

' Badge shape and colours for raw pad button ubsBtn: ubsTxt$ is what goes inside, ubsPill is
' -1 for a pill (wider labels), ubsClr its fill, ubsDark -1 when the label is drawn in black.
Sub UI_BadgeStyle (ubsBtn As Integer, ubsTxt As String, ubsPill As Integer, ubsClr As Long, ubsDark As Integer, ubsA As Integer)
    ubsTxt = E3D_PadBtnName$(ubsBtn, ctrlLayout)
    If Left$(ubsTxt, 3) = "BTN" Then ubsTxt = Mid$(ubsTxt, 4)
    ubsPill = (Len(ubsTxt) > 1)
    ubsDark = 0
    Select Case ubsTxt
        Case "A" : ubsClr = _RGBA(40, 165, 50, ubsA)
        Case "B" : ubsClr = _RGBA(215, 40, 40, ubsA)
        Case "X" : ubsClr = _RGBA(30, 100, 225, ubsA)
        Case "Y" : ubsClr = _RGBA(245, 200, 30, ubsA) : ubsDark = -1
        Case Else : ubsClr = _RGBA(165, 168, 180, ubsA) : ubsDark = -1
    End Select
End Sub

Function UI_PadBadgeW% (upbwBtn As Integer)
    Dim upbwTxt As String, upbwPill As Integer, upbwClr As Long, upbwDark As Integer
    If upbwBtn <= 0 Then UI_PadBadgeW% = 3 * FONT_CHAR_W : Exit Function
    UI_BadgeStyle upbwBtn, upbwTxt, upbwPill, upbwClr, upbwDark, 255
    If upbwPill Then UI_PadBadgeW% = Len(upbwTxt) * FONT_CHAR_W + 6 Else UI_PadBadgeW% = 15
End Function

' The font's capitals fill rows 2-11 of its 16px cell, so the badge centres on row 7.
Sub UI_PadBadge (upbBtn As Integer, upbX As Integer, upbY As Integer, upbA As Integer)
    Dim upbTxt As String, upbPill As Integer, upbClr As Long, upbDark As Integer
    Dim upbW As Integer, upbD As Integer, upbH As Integer, upbSheet As Long
    If upbBtn <= 0 Then FONT_PrintAlpha fontPalette(8), backBuffer, "---", upbX, upbY, upbA : Exit Sub
    If uiShadowSheet = 0 Then
        FONT_BuildSheet uiShadowSheet, _RGB(0, 0, 0), _RGB(0, 0, 0)
        _Dest backBuffer
    End If
    UI_BadgeStyle upbBtn, upbTxt, upbPill, upbClr, upbDark, upbA
    If upbDark Then upbSheet = uiShadowSheet Else upbSheet = fontPalette(15)
    upbW = UI_PadBadgeW%(upbBtn)
    If upbPill Then
        Line (upbX + 2, upbY)-(upbX + upbW - 3, upbY + 14), upbClr, BF
        Line (upbX + 1, upbY + 1)-(upbX + 1, upbY + 13), upbClr
        Line (upbX + upbW - 2, upbY + 1)-(upbX + upbW - 2, upbY + 13), upbClr
        Line (upbX, upbY + 2)-(upbX, upbY + 12), upbClr
        Line (upbX + upbW - 1, upbY + 2)-(upbX + upbW - 1, upbY + 12), upbClr
        FONT_PrintAlpha upbSheet, backBuffer, upbTxt, upbX + 3, upbY, upbA
    Else
        For upbD = -7 To 7
            upbH = Int(Sqr(56 - upbD * upbD) + 0.5)
            If upbH > 7 Then upbH = 7
            Line (upbX + 7 - upbH, upbY + 7 + upbD)-(upbX + 7 + upbH, upbY + 7 + upbD), upbClr
        Next upbD
        FONT_PrintAlpha upbSheet, backBuffer, upbTxt, upbX + 4, upbY, upbA
    End If
End Sub

' Splits the next UI_Tok$ off upnTxt$ from upnPos: upnLit$ is the text before it; returns 0
' when there is no token left (upnLit$ is then the rest).
Function UI_PromptNext% (upnTxt As String, upnPos As Integer, upnLit As String, upnKey As String, upnAct As Integer)
    Dim upnO As Integer, upnC As Integer, upnBar As Integer, upnTok As String
    UI_PromptNext% = 0
    upnO = InStr(upnPos, upnTxt, "{")
    If upnO > 0 Then upnC = InStr(upnO, upnTxt, "}")
    If upnO = 0 Or upnC = 0 Then upnLit = Mid$(upnTxt, upnPos) : upnPos = Len(upnTxt) + 1 : Exit Function
    upnLit = Mid$(upnTxt, upnPos, upnO - upnPos)
    upnTok = Mid$(upnTxt, upnO + 1, upnC - upnO - 1)
    upnBar = InStr(upnTok, "|")
    upnKey = Left$(upnTok, upnBar - 1)
    upnAct = Val(Mid$(upnTok, upnBar + 1))
    If upnKey = "" And upnAct > 0 Then upnKey = E3D_KeyName$(keyBind(upnAct))
    upnPos = upnC + 1
    UI_PromptNext% = -1
End Function

Function UI_PromptsW% (upwTxt As String, upwDev As Integer)
    Dim upwPos As Integer, upwLit As String, upwKey As String, upwAct As Integer, upwW As Integer, upwMore As Integer
    upwPos = 1 : upwW = 0
    Do
        upwMore = UI_PromptNext%(upwTxt, upwPos, upwLit, upwKey, upwAct)
        upwW = upwW + Len(upwLit) * FONT_CHAR_W
        If upwMore = 0 Then Exit Do
        If upwDev = INP_DEV_PAD Then
            If upwAct > 0 Then upwW = upwW + UI_PadBadgeW%(padBind(upwAct))
        Else
            upwW = upwW + Len(upwKey) * FONT_CHAR_W
        End If
    Loop
    UI_PromptsW% = upwW
End Function

Sub UI_PromptsAt (upaTxt As String, upaDev As Integer, upaX As Integer, upaY As Integer, upaPal As Integer, upaA As Integer, upaShadow As Integer)
    Dim upaPos As Integer, upaLit As String, upaKey As String, upaAct As Integer, upaX2 As Integer, upaMore As Integer
    upaPos = 1 : upaX2 = upaX
    Do
        upaMore = UI_PromptNext%(upaTxt, upaPos, upaLit, upaKey, upaAct)
        If upaDev <> INP_DEV_PAD And upaMore Then upaLit = upaLit + upaKey
        If upaShadow Then UI_Text upaPal, upaLit, upaX2, upaY, upaA Else FONT_PrintAlpha fontPalette(upaPal), backBuffer, upaLit, upaX2, upaY, upaA
        upaX2 = upaX2 + Len(upaLit) * FONT_CHAR_W
        If upaMore = 0 Then Exit Do
        If upaDev = INP_DEV_PAD And upaAct > 0 Then
            UI_PadBadge padBind(upaAct), upaX2, upaY, upaA
            upaX2 = upaX2 + UI_PadBadgeW%(padBind(upaAct))
        End If
    Loop
End Sub

Sub UI_Prompts (uppTxt As String, uppX As Integer, uppY As Integer, uppPal As Integer, uppA As Integer)
    UI_PromptsAt uppTxt, INP_LastDevice%, uppX, uppY, uppPal, uppA, 0
End Sub

Sub UI_PromptsCentered (upcTxt As String, upcY As Integer, upcPal As Integer, upcA As Integer)
    UI_PromptsAt upcTxt, INP_LastDevice%, (scrW - UI_PromptsW%(upcTxt, INP_LastDevice%)) \ 2, upcY, upcPal, upcA, 0
End Sub
