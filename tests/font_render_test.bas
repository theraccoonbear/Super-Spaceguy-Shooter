' font_render_test.bas -- bitmap font compositing (src/2d/font.bas), the bugs behind #71
'
' Renders with the real FONT_* subs onto off-screen canvases and checks pixels:
'   glyph transparency   holes and gaps in A B D O show the background, not black boxes
'   blend preservation   a transparent-background _PutImage after font calls still composites
'                        (catches _DONTBLEND left set on the destination)
'   partial opacity      alpha 128 text is the expected blend of glyph and background
'   rich colour codes    ~4 and ~2 pick palette entries 4 and 2
' Whole scenes are covered by the golden-screenshot suite (tests/render/run.sh).
'
' Build: ./tools/buildqb tests/font_render_test.bas
' Run:   ./tests/font_render_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

Dim Shared fontPalette(0 To 15) As Long

'$INCLUDE:'../src/2d/font.bas'

Dim Shared frtPassed As Integer, frtFailed As Integer

Sub FRT_Assert (frtCond As Integer, frtName As String)
    _Dest _Console
    If frtCond Then
        Print "PASS  " + frtName
        frtPassed = frtPassed + 1
    Else
        Print "FAIL  " + frtName
        frtFailed = frtFailed + 1
    End If
End Sub

Function FRT_Canvas& (frtW As Integer, frtH As Integer, frtBg As _Unsigned Long)
    Dim frtImg As Long
    frtImg = _NewImage(frtW, frtH, 32)
    _Dest frtImg
    Line (0, 0)-(frtW - 1, frtH - 1), frtBg, BF
    FRT_Canvas& = frtImg
End Function

Function FRT_Px~& (frtImg As Long, frtX As Integer, frtY As Integer)
    _Source frtImg
    FRT_Px~& = Point(frtX, frtY)
End Function

Function FRT_Near% (frtA As Long, frtB As Long, frtTol As Long)
    FRT_Near% = (Abs(frtA - frtB) <= frtTol)
End Function

' Pixels of character frtCh$ drawn at (frtDX, 0) on frtDest that don't match what the sheet
' says should be there: background where the glyph is transparent, the glyph colour blended
' at frtAlpha where it is opaque (channel tolerance frtTol). A glyph with (almost) no ink in
' the sheet counts as an error too, so a blank sheet can't pass.
Function FRT_CellErrors% (frtDest As Long, frtDX As Integer, frtSheet As Long, frtCh As String, frtBg As _Unsigned Long, frtAlpha As Integer, frtTol As Long)
    Dim frtCX As Integer, frtCY As Integer, frtPX As Integer, frtPY As Integer
    Dim frtS As _Unsigned Long, frtD As _Unsigned Long, frtErr As Integer, frtA As Long, frtInk As Integer
    frtCX = ((Asc(frtCh) - 32) Mod FONT_COLS) * FONT_CHAR_W
    frtCY = ((Asc(frtCh) - 32) \ FONT_COLS) * FONT_CHAR_H
    frtInk = 0
    For frtPY = 0 To FONT_CHAR_H - 1
        For frtPX = 0 To FONT_CHAR_W - 1
            frtS = FRT_Px~&(frtSheet, frtCX + frtPX, frtCY + frtPY)
            frtD = FRT_Px~&(frtDest, frtDX + frtPX, frtPY)
            If _Alpha32(frtS) = 0 Then
                If frtD <> frtBg Then frtErr = frtErr + 1
            Else
                frtInk = frtInk + 1
                frtA = (_Alpha32(frtS) * frtAlpha) \ 255
                If FRT_Near%((_Red32(frtS) * frtA + _Red32(frtBg) * (255 - frtA)) \ 255, _Red32(frtD), frtTol) = 0 Then frtErr = frtErr + 1
                If FRT_Near%((_Green32(frtS) * frtA + _Green32(frtBg) * (255 - frtA)) \ 255, _Green32(frtD), frtTol) = 0 Then frtErr = frtErr + 1
                If FRT_Near%((_Blue32(frtS) * frtA + _Blue32(frtBg) * (255 - frtA)) \ 255, _Blue32(frtD), frtTol) = 0 Then frtErr = frtErr + 1
            End If
        Next frtPX
    Next frtPY
    If frtInk <= 10 Then frtErr = frtErr + 1
    FRT_CellErrors% = frtErr
End Function

Print "=== font_render_test ==="

Dim frtBG As _Unsigned Long : frtBG = _RGB32(20, 60, 200)
Dim frtCan As Long, frtI As Integer, frtGlyphs As String

' the palette's _RGB colours are evaluated against _Dest: make it 32-bit, as the game's screen is
frtCan = FRT_Canvas&(64, 16, frtBG)
FONT_BuildPalette fontPalette()

' --- glyph transparency: holes show the background ---
frtGlyphs = "ABDO"
FONT_PrintAlpha fontPalette(7), frtCan, frtGlyphs, 0, 0, 255
For frtI = 1 To 4
    FRT_Assert FRT_CellErrors%(frtCan, (frtI - 1) * FONT_CHAR_W, fontPalette(7), Mid$(frtGlyphs, frtI, 1), frtBG, 255, 0) = 0, _
        "glyph '" + Mid$(frtGlyphs, frtI, 1) + "': holes show the background, ink is the glyph colour"
Next frtI
FRT_Assert FRT_Px~&(frtCan, 40, 8) = frtBG, "nothing drawn past the end of the string"

' --- blend state: a transparent-background image composites after font calls ---
Dim frtSpr As Long
frtSpr = _NewImage(8, 8, 32)
_DontBlend frtSpr
_Dest frtSpr
Line (0, 0)-(7, 7), _RGBA32(0, 0, 0, 0), BF
PSet (4, 4), _RGB32(255, 0, 0)
_Blend frtSpr  ' _PutImage composites only when both source and destination blend
FONT_PrintRichAlpha fontPalette(), frtCan, "~4X", 32, 0, 255
FRT_Assert _Blend(frtCan) <> 0, "FONT_PrintAlpha / FONT_PrintRichAlpha leave blending on for the destination"
_PutImage (48, 4), frtSpr, frtCan
FRT_Assert FRT_Px~&(frtCan, 48, 4) = frtBG, "transparent sprite pixels after font calls show the background (no _DONTBLEND poisoning)"
FRT_Assert FRT_Px~&(frtCan, 52, 8) = _RGB32(255, 0, 0), "opaque sprite pixel still lands"

' --- partial opacity: alpha 128 blends glyph and background ---
Dim frtCan2 As Long
frtCan2 = FRT_Canvas&(16, 16, frtBG)
FONT_PrintAlpha fontPalette(15), frtCan2, "O", 0, 0, 128
FRT_Assert FRT_CellErrors%(frtCan2, 0, fontPalette(15), "O", frtBG, 128, 2) = 0, "alpha 128 glyph pixels are the glyph/background blend"
FRT_Assert _Alpha32(FRT_Px~&(frtCan2, 0, 0)) = 255, "destination stays opaque under semi-transparent text"

' --- rich colour codes pick palette entries ---
Dim frtCan3 As Long
frtCan3 = FRT_Canvas&(32, 16, frtBG)
FONT_PrintRichAlpha fontPalette(), frtCan3, "~4R~2G", 0, 0, 255
FRT_Assert FRT_CellErrors%(frtCan3, 0, fontPalette(4), "R", frtBG, 255, 0) = 0, "~4 draws with palette 4 (red)"
FRT_Assert FRT_CellErrors%(frtCan3, FONT_CHAR_W, fontPalette(2), "G", frtBG, 255, 0) = 0, "~2 draws with palette 2 (green)"
FRT_Assert FRT_CellErrors%(frtCan3, FONT_CHAR_W, fontPalette(4), "G", frtBG, 255, 0) > 0, "palettes 4 and 2 really differ (the check above can fail)"
FRT_Assert FRT_Px~&(frtCan3, 2 * FONT_CHAR_W + 2, 8) = frtBG, "colour codes take no space"

_Dest _Console
Print ""
Print "=== font_render_test:" + Str$(frtPassed + frtFailed) + " checks," + Str$(frtPassed) + " passed," + Str$(frtFailed) + " failed ==="
If frtFailed > 0 Then System 1 Else System 0
