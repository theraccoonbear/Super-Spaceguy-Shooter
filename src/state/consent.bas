' consent.bas -- one-time telemetry disclosure screen (GS_CONSENT)
'
' Shown before the studio leadin when telemOn is set and telemConsent = 0.
' Uses _KEYHIT (not held/keydown) so the keypress is consumed and cannot
' bleed into LEADIN_Update and skip a studio card.
'
' SPACE  -- OK this session; will ask again next launch
' S      -- OK, save telem_consent=1 to sss_settings.ini; never asks again
' ESC    -- No thanks; disables telemetry for this session

Sub GS_CONSENT_Update()
    Dim cnThrobBright As Integer
    tt = tt + 0.025
    cnThrobBright = Int(170 + 85 * Sin(tt * 5))

    Dim cnPX1 As Integer : cnPX1 = scrW \ 2 - 110
    Dim cnPX2 As Integer : cnPX2 = scrW \ 2 + 110
    Dim cnPY1 As Integer : cnPY1 = scrH \ 2 - 80
    Dim cnPY2 As Integer : cnPY2 = scrH \ 2 + 80

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    UI_DrawPanel cnPX1, cnPY1, cnPX2, cnPY2, "DATA NOTICE"

    ' body text
    Dim cnBY As Integer : cnBY = scrH \ 2 - 56
    FONT_PrintCenteredAlpha fontPalette(9), backBuffer, "THIS GAME SENDS ANONYMOUS",  cnBY,      scrW, 255
    FONT_PrintCenteredAlpha fontPalette(9), backBuffer, "GAMEPLAY DATA TO THE DEV.",  cnBY + 16, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "NO PERSONAL INFO COLLECTED.", cnBY + 32, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "A RANDOM ID LINKS SESSIONS.", cnBY + 48, scrW, 255

    ' separator
    LINE (cnPX1 + 8, scrH \ 2 + 12)-(cnPX2 - 8, scrH \ 2 + 12), _RGB(0, 55, 110)

    ' action lines: print full string dim, then overprint key in bright
    Dim cnA1 As String  : cnA1 = "SPACE  OK"
    Dim cnA1Y As Integer : cnA1Y = scrH \ 2 + 18
    Dim cnA1X As Integer : cnA1X = (scrW - Len(cnA1) * FONT_CHAR_W) \ 2
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, cnA1,    cnA1Y, scrW, cnThrobBright
    FONT_PrintAlpha         fontPalette(15), backBuffer, "SPACE", cnA1X, cnA1Y, cnThrobBright

    Dim cnA2 As String  : cnA2 = "S  OK, DON'T ASK AGAIN"
    Dim cnA2Y As Integer : cnA2Y = scrH \ 2 + 34
    Dim cnA2X As Integer : cnA2X = (scrW - Len(cnA2) * FONT_CHAR_W) \ 2
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, cnA2, cnA2Y, scrW, 255
    FONT_PrintAlpha         fontPalette(14), backBuffer, "S",   cnA2X, cnA2Y, 255

    Dim cnA3 As String  : cnA3 = "ESC  NO THANKS"
    Dim cnA3Y As Integer : cnA3Y = scrH \ 2 + 50
    Dim cnA3X As Integer : cnA3X = (scrW - Len(cnA3) * FONT_CHAR_W) \ 2
    FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, cnA3,  cnA3Y, scrW, 255
    FONT_PrintAlpha         fontPalette(15), backBuffer, "ESC", cnA3X, cnA3Y, 200

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Dim cnKey As Long : cnKey = _KEYHIT
    Select Case cnKey
        Case 32          ' SPACE -- OK this session
            LEADIN_Init : gameState = GS_LEADIN
        Case 83, 115     ' S -- OK, save preference
            telemConsent = -1 : SETTINGS_Save : LEADIN_Init : gameState = GS_LEADIN
        Case 27          ' ESC -- No thanks, disable telemetry this session
            telemOn = 0 : LEADIN_Init : gameState = GS_LEADIN
    End Select

    MUS_Fill 0
End Sub
