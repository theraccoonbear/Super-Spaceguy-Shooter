' consent.bas -- one-time telemetry disclosure screen (GS_CONSENT)
'
' Shown before the studio leadin when telemOn is set and telemConsent = 0.
' SPACE dismisses for this session only; S saves preference to sss_settings.ini.
' Either key transitions to GS_LEADIN.

Dim Shared consentSpaceWas As Integer
Dim Shared consentSWas     As Integer

Sub GS_CONSENT_Update()
    Dim cnThrobBright As Integer
    tt = tt + 0.025
    cnThrobBright = Int(170 + 85 * Sin(tt * 5))

    Dim cnPX1 As Integer : cnPX1 = scrW \ 2 - 110
    Dim cnPX2 As Integer : cnPX2 = scrW \ 2 + 110
    Dim cnPY1 As Integer : cnPY1 = scrH \ 2 - 62
    Dim cnPY2 As Integer : cnPY2 = scrH \ 2 + 62

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    UI_DrawPanel cnPX1, cnPY1, cnPX2, cnPY2, "DATA NOTICE"

    Dim cnY As Integer : cnY = scrH \ 2 - 36
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "THIS GAME SENDS ANONYMOUS",  cnY,      scrW, 255
    FONT_PrintCenteredAlpha fontPalette(9),  backBuffer, "GAMEPLAY DATA TO THE DEV.",  cnY + 16, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "NO PERSONAL INFO COLLECTED.", cnY + 32, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8),  backBuffer, "A RANDOM ID LINKS SESSIONS.", cnY + 48, scrW, 255

    LINE (cnPX1 + 8, scrH \ 2 + 20)-(cnPX2 - 8, scrH \ 2 + 20), _RGB(0, 55, 110)

    FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "SPACE  OK",                  scrH \ 2 + 28, scrW, cnThrobBright
    FONT_PrintCenteredAlpha fontPalette(14), backBuffer, "S  OK, DON'T ASK AGAIN",     scrH \ 2 + 44, scrW, 255

    _DEST 0
    _PUTIMAGE , backBuffer, 0

    Dim cnSpace As Integer : cnSpace = held(E3D_KEY_SPACE)
    Dim cnS As Integer     : cnS = _KEYDOWN(83) Or _KEYDOWN(115)

    If cnSpace And consentSpaceWas = 0 Then
        LEADIN_Init
        gameState = GS_LEADIN
    End If
    If cnS And consentSWas = 0 Then
        telemConsent = -1
        SETTINGS_Save
        LEADIN_Init
        gameState = GS_LEADIN
    End If

    consentSpaceWas = cnSpace
    consentSWas     = cnS

    MUS_Fill 0
End Sub
