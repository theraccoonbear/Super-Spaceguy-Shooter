' consent.bas -- one-time telemetry disclosure screen (GS_CONSENT); input in consentlogic.bas
'
' OK                -- OK this session; will ask again next launch
' DON'T ASK AGAIN   -- OK, save telem_consent=1 to sss_settings.ini; never asks again
' NO THANKS         -- disables telemetry for this session
' Up / down pick a row and ENTER / pad A takes it; SPACE, S / pad X and ESC / pad B still
' take OK, DON'T ASK AGAIN and NO THANKS directly.

Sub GS_CONSENT_Update()
    Dim cnPX1 As Integer : cnPX1 = scrW \ 2 - 132
    Dim cnPX2 As Integer : cnPX2 = scrW \ 2 + 132
    Dim cnPY1 As Integer : cnPY1 = scrH \ 2 - 76
    Dim cnPY2 As Integer : cnPY2 = scrH \ 2 + 76
    Dim cnPick As Integer : cnPick = CONSENT_Input%

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    UI_DrawPanel cnPX1, cnPY1, cnPX2, cnPY2, "DATA NOTICE"

    ' body text (centered)
    Dim cnBY As Integer : cnBY = scrH \ 2 - 52
    FONT_PrintCenteredAlpha fontPalette(9), backBuffer, "THIS GAME SENDS ANONYMOUS",  cnBY,      scrW, 255
    FONT_PrintCenteredAlpha fontPalette(9), backBuffer, "GAMEPLAY DATA TO THE DEV.",  cnBY + 16, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "NO PERSONAL INFO COLLECTED.", cnBY + 32, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "A RANDOM ID LINKS SESSIONS.", cnBY + 48, scrW, 255

    LINE (cnPX1 + 8, scrH \ 2 + 16)-(cnPX2 - 8, scrH \ 2 + 16), _RGB(0, 55, 110)

    ' two-column layout: keys right-aligned to cnDX-16, descs left-aligned at cnDX
    ' all three key labels in fontPalette(15); right edges share X = cnDX - 2*FONT_CHAR_W
    Dim cnDX  As Integer : cnDX  = scrW \ 2          ' desc column left edge
    Dim cnAY(0 To 2) As Integer, cnI As Integer
    Dim cnKeyTxt(0 To 2) As String, cnDesc(0 To 2) As String, cnPal(0 To 2) As Integer, cnA(0 To 2) As Integer
    cnKeyTxt(0) = "SPACE/A" : cnDesc(0) = "OK"              : cnPal(0) = 9 : cnA(0) = 255
    cnKeyTxt(1) = "S/X"     : cnDesc(1) = "DON'T ASK AGAIN" : cnPal(1) = 9 : cnA(1) = 255
    cnKeyTxt(2) = "ESC/B"   : cnDesc(2) = "NO THANKS"       : cnPal(2) = 8 : cnA(2) = 200
    For cnI = 0 To 2
        cnAY(cnI) = scrH \ 2 + 22 + cnI * 16
        If cnI = consentSel Then
            UI_MenuHighlight cnPX1 + 6, cnAY(cnI) - 1, cnPX2 - 6, cnAY(cnI) + 14
            cnPal(cnI) = 15 : cnA(cnI) = 255
        End If
        FONT_PrintAlpha fontPalette(15), backBuffer, cnKeyTxt(cnI), cnDX - (Len(cnKeyTxt(cnI)) + 2) * FONT_CHAR_W, cnAY(cnI), cnA(cnI)
        FONT_PrintAlpha fontPalette(cnPal(cnI)), backBuffer, cnDesc(cnI), cnDX, cnAY(cnI), cnA(cnI)
    Next cnI

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Select Case cnPick
        Case CONSENT_OK
            telemConsent = -1
            If Len(telemPlayerName) = 0 Then gameState = GS_USERNAME Else LEADIN_Init : gameState = GS_LEADIN
        Case CONSENT_SAVE
            telemConsent = -1 : SETTINGS_Save
            If Len(telemPlayerName) = 0 Then gameState = GS_USERNAME Else LEADIN_Init : gameState = GS_LEADIN
        Case CONSENT_NO
            telemOn = 0 : LEADIN_Init : gameState = GS_LEADIN
    End Select

    MUS_Fill 0
End Sub
