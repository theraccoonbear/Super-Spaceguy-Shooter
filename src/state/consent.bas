' consent.bas -- one-time telemetry disclosure screen (GS_CONSENT)
'
' SPACE  -- OK this session; will ask again next launch
' S      -- OK, save telem_consent=1 to sss_settings.ini; never asks again
' ESC    -- No thanks; disables telemetry for this session

Sub GS_CONSENT_Update()
    Dim cnPX1 As Integer : cnPX1 = scrW \ 2 - 122
    Dim cnPX2 As Integer : cnPX2 = scrW \ 2 + 122
    Dim cnPY1 As Integer : cnPY1 = scrH \ 2 - 76
    Dim cnPY2 As Integer : cnPY2 = scrH \ 2 + 76

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
    Dim cnAY1 As Integer : cnAY1 = scrH \ 2 + 22
    Dim cnAY2 As Integer : cnAY2 = scrH \ 2 + 38
    Dim cnAY3 As Integer : cnAY3 = scrH \ 2 + 54

    ' SPACE  OK
    FONT_PrintAlpha fontPalette(15), backBuffer, "SPACE", cnDX - 7 * FONT_CHAR_W, cnAY1, 255
    FONT_PrintAlpha fontPalette(9),  backBuffer, "OK",    cnDX,                    cnAY1, 255

    ' S  DON'T ASK AGAIN
    FONT_PrintAlpha fontPalette(15), backBuffer, "S",               cnDX - 3 * FONT_CHAR_W, cnAY2, 255
    FONT_PrintAlpha fontPalette(9),  backBuffer, "DON'T ASK AGAIN", cnDX,                   cnAY2, 255

    ' ESC  NO THANKS
    FONT_PrintAlpha fontPalette(15), backBuffer, "ESC",       cnDX - 5 * FONT_CHAR_W, cnAY3, 200
    FONT_PrintAlpha fontPalette(8),  backBuffer, "NO THANKS", cnDX,                   cnAY3, 200

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
