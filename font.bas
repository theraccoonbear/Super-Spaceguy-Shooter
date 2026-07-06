' font.bas — pre-rendered gradient font sprite sheet
'
' ASCII 32-126 rendered into a 128x96 sprite sheet (16 chars x 6 rows, 8x16 per char).
' Gradient is baked top-to-bottom within each character cell at build time.
' Call FONT_BuildSheet once after Screen is created.
'
' Rendering uses _PUTIMAGE with _BLEND on the destination so each glyph's
' per-pixel alpha mask composites cleanly — no black box, holes in A/B/D/etc.
' show the background. _Dest is left set to dest on return.

Const FONT_CHAR_W = 8
Const FONT_CHAR_H = 16
Const FONT_COLS   = 16
Const FONT_ROWS   = 6     ' ceil(95 printable chars / 16 cols)

Sub FONT_BuildSheet(sheet As Long, topClr As Long, botClr As Long)
    Dim c As Integer, cx As Integer, cy As Integer
    Dim x As Integer, y As Integer, t As Single
    Dim r As Integer, g As Integer, b As Integer
    Dim tr As Integer, tg As Integer, tb As Integer
    Dim br As Integer, bg As Integer, bb As Integer

    sheet = _NewImage(FONT_CHAR_W * FONT_COLS, FONT_CHAR_H * FONT_ROWS, 32)
    _Dest sheet

    ' fill with opaque black so character pixels can be detected by brightness
    Line (0, 0)-(FONT_CHAR_W * FONT_COLS - 1, FONT_CHAR_H * FONT_ROWS - 1), _RGB(0, 0, 0), BF
    Color _RGB(255, 255, 255)
    For c = 32 To 126
        cx = ((c - 32) Mod FONT_COLS) * FONT_CHAR_W
        cy = ((c - 32) \ FONT_COLS) * FONT_CHAR_H
        _PrintString (cx, cy), Chr$(c)
    Next c

    ' extract gradient channel ranges
    tr = _Red32(topClr)  : tg = _Green32(topClr)  : tb = _Blue32(topClr)
    br = _Red32(botClr)  : bg = _Green32(botClr)  : bb = _Blue32(botClr)

    ' walk every pixel: white (glyph) -> gradient color + alpha=255
    '                   black (bg/holes) -> fully transparent
    ' _Source must equal _Dest here so Point reads from sheet, not game screen
    _Source sheet
    For y = 0 To FONT_CHAR_H * FONT_ROWS - 1
        t = (y Mod FONT_CHAR_H) / (FONT_CHAR_H - 1.0)
        r = Int(tr + (br - tr) * t)
        g = Int(tg + (bg - tg) * t)
        b = Int(tb + (bb - tb) * t)
        For x = 0 To FONT_CHAR_W * FONT_COLS - 1
            If _Red32(Point(x, y)) > 127 Then
                PSet (x, y), _RGBA(r, g, b, 255)
            Else
                PSet (x, y), _RGBA(0, 0, 0, 0)
            End If
        Next x
    Next y
    _Source 0
    _Dest 0
End Sub

Sub FONT_Print(sheet As Long, dest As Long, txt As String, x As Integer, y As Integer)
    Dim i As Integer, c As Integer, cx As Integer, cy As Integer, dx As Integer
    _BLEND dest
    For i = 1 To Len(txt)
        c = Asc(Mid$(txt, i, 1))
        If c >= 32 And c <= 126 Then
            cx = ((c - 32) Mod FONT_COLS) * FONT_CHAR_W
            cy = ((c - 32) \ FONT_COLS) * FONT_CHAR_H
            dx = x + (i - 1) * FONT_CHAR_W
            _PUTIMAGE (dx, y)-(dx + FONT_CHAR_W - 1, y + FONT_CHAR_H - 1), sheet, dest, (cx, cy)-(cx + FONT_CHAR_W - 1, cy + FONT_CHAR_H - 1)
        End If
    Next i
    _DONTBLEND dest
    _Dest dest
End Sub

Sub FONT_PrintCentered(sheet As Long, dest As Long, txt As String, y As Integer, scrW As Integer)
    FONT_Print sheet, dest, txt, (scrW - Len(txt) * FONT_CHAR_W) \ 2, y
End Sub

Sub FONT_BuildPalette(sheets() As Long)
    Dim fpI As Integer
    Dim fpTR(0 To 15) As Integer, fpTG(0 To 15) As Integer, fpTB(0 To 15) As Integer
    Dim fpBR(0 To 15) As Integer, fpBG(0 To 15) As Integer, fpBB(0 To 15) As Integer
    ' top: near-white tinted toward hue;  bottom: deep saturated color
    fpTR(0)=180 : fpTG(0)=180 : fpTB(0)=190 : fpBR(0)=0   : fpBG(0)=0   : fpBB(0)=0    ' 0  black
    fpTR(1)=210 : fpTG(1)=215 : fpTB(1)=255 : fpBR(1)=0   : fpBG(1)=10  : fpBB(1)=200  ' 1  dark blue
    fpTR(2)=210 : fpTG(2)=255 : fpTB(2)=210 : fpBR(2)=0   : fpBG(2)=160 : fpBB(2)=0    ' 2  dark green
    fpTR(3)=210 : fpTG(3)=255 : fpTB(3)=250 : fpBR(3)=0   : fpBG(3)=150 : fpBB(3)=200  ' 3  dark cyan
    fpTR(4)=255 : fpTG(4)=210 : fpTB(4)=205 : fpBR(4)=200 : fpBG(4)=0   : fpBB(4)=0    ' 4  dark red
    fpTR(5)=255 : fpTG(5)=205 : fpTB(5)=255 : fpBR(5)=180 : fpBG(5)=0   : fpBB(5)=210  ' 5  magenta
    fpTR(6)=255 : fpTG(6)=245 : fpTB(6)=210 : fpBR(6)=190 : fpBG(6)=80  : fpBB(6)=0    ' 6  brown/amber
    fpTR(7)=255 : fpTG(7)=255 : fpTB(7)=255 : fpBR(7)=100 : fpBG(7)=110 : fpBB(7)=180  ' 7  default: white → rich slate blue
    fpTR(8)=210 : fpTG(8)=210 : fpTB(8)=220 : fpBR(8)=20  : fpBG(8)=20  : fpBB(8)=30   ' 8  dark gray
    fpTR(9)=215 : fpTG(9)=230 : fpTB(9)=255 : fpBR(9)=0   : fpBG(9)=30  : fpBB(9)=240  ' 9  blue: pale sky → vivid royal
    fpTR(10)=215: fpTG(10)=255: fpTB(10)=215: fpBR(10)=0  : fpBG(10)=185: fpBB(10)=0   ' A  green
    fpTR(11)=210: fpTG(11)=255: fpTB(11)=255: fpBR(11)=0  : fpBG(11)=180: fpBB(11)=245 ' B  cyan
    fpTR(12)=255: fpTG(12)=215: fpTB(12)=210: fpBR(12)=240: fpBG(12)=0  : fpBB(12)=0   ' C  red
    fpTR(13)=255: fpTG(13)=210: fpTB(13)=255: fpBR(13)=235: fpBG(13)=0  : fpBB(13)=210 ' D  pink
    fpTR(14)=255: fpTG(14)=255: fpTB(14)=215: fpBR(14)=240: fpBG(14)=100: fpBB(14)=0   ' E  yellow: warm white → vivid amber
    fpTR(15)=255: fpTG(15)=255: fpTB(15)=255: fpBR(15)=190: fpBG(15)=190: fpBB(15)=215 ' F  white
    For fpI = 0 To 15
        FONT_BuildSheet sheets(fpI), _RGB(fpTR(fpI), fpTG(fpI), fpTB(fpI)), _RGB(fpBR(fpI), fpBG(fpI), fpBB(fpI))
    Next fpI
End Sub

' Print txt with inline ~X color codes (X = hex digit 0-F). Default color: sheets(7).
Sub FONT_PrintRich(sheets() As Long, dest As Long, txt As String, x As Integer, y As Integer)
    Dim frI As Integer, frC As Integer, frCX As Integer, frCY As Integer
    Dim frSheet As Long, frX As Integer, frHex As Integer, frSkip As Integer
    frSheet = sheets(7)
    frX = x
    _BLEND dest
    frI = 1
    Do While frI <= Len(txt)
        frC = Asc(Mid$(txt, frI, 1))
        frSkip = 0
        If frC = 126 And frI < Len(txt) Then   ' 126 = ~
            frHex = Asc(UCase$(Mid$(txt, frI + 1, 1)))
            If frHex >= 48 And frHex <= 57 Then
                frSheet = sheets(frHex - 48)    : frI = frI + 2 : frSkip = -1
            ElseIf frHex >= 65 And frHex <= 70 Then
                frSheet = sheets(frHex - 55)    : frI = frI + 2 : frSkip = -1
            End If
        End If
        If Not frSkip Then
            If frC >= 32 And frC <= 126 Then
                frCX = ((frC - 32) Mod FONT_COLS) * FONT_CHAR_W
                frCY = ((frC - 32) \ FONT_COLS) * FONT_CHAR_H
                _PUTIMAGE (frX, y)-(frX + FONT_CHAR_W - 1, y + FONT_CHAR_H - 1), frSheet, dest, (frCX, frCY)-(frCX + FONT_CHAR_W - 1, frCY + FONT_CHAR_H - 1)
                frX = frX + FONT_CHAR_W
            End If
            frI = frI + 1
        End If
    Loop
    _DONTBLEND dest
    _Dest dest
End Sub

Sub FONT_PrintCenteredRich(sheets() As Long, dest As Long, txt As String, y As Integer, scrW As Integer)
    Dim fcrI As Integer, fcrC As Integer, fcrHex As Integer, fcrLen As Integer, fcrSkip As Integer
    fcrLen = 0 : fcrI = 1
    Do While fcrI <= Len(txt)
        fcrC = Asc(Mid$(txt, fcrI, 1))
        fcrSkip = 0
        If fcrC = 126 And fcrI < Len(txt) Then
            fcrHex = Asc(UCase$(Mid$(txt, fcrI + 1, 1)))
            If (fcrHex >= 48 And fcrHex <= 57) Or (fcrHex >= 65 And fcrHex <= 70) Then
                fcrI = fcrI + 2 : fcrSkip = -1
            End If
        End If
        If Not fcrSkip Then fcrLen = fcrLen + 1 : fcrI = fcrI + 1
    Loop
    FONT_PrintRich sheets(), dest, txt, (scrW - fcrLen * FONT_CHAR_W) \ 2, y
End Sub

' Print txt at a specific opacity (alpha 0=invisible, 255=opaque).
' Renders to a temp image so per-pixel alpha scaling is safe, then composites
' onto dest with _BLEND. Allocates/frees a small image per call — suitable for
' effects (fade-in, dimmed hints) but not tight per-frame loops.
Sub FONT_PrintAlpha(sheet As Long, dest As Long, txt As String, x As Integer, y As Integer, alpha As Integer)
    Dim fai As Integer, fac As Integer, facx As Integer, facy As Integer
    Dim fapx As Integer, fapy As Integer, facol As Long, faa As Integer
    Dim tw As Integer, tmpImg As Long
    If alpha <= 0 Or Len(txt) = 0 Then Exit Sub
    tw = Len(txt) * FONT_CHAR_W
    tmpImg = _NewImage(tw, FONT_CHAR_H, 32)
    ' copy glyphs into tmpImg (no blend — preserves per-pixel alpha from sheet)
    For fai = 1 To Len(txt)
        fac = Asc(Mid$(txt, fai, 1))
        If fac >= 32 And fac <= 126 Then
            facx = ((fac - 32) Mod FONT_COLS) * FONT_CHAR_W
            facy = ((fac - 32) \ FONT_COLS) * FONT_CHAR_H
            _PUTIMAGE ((fai-1)*FONT_CHAR_W, 0)-((fai-1)*FONT_CHAR_W + FONT_CHAR_W - 1, FONT_CHAR_H - 1), sheet, tmpImg, (facx, facy)-(facx + FONT_CHAR_W - 1, facy + FONT_CHAR_H - 1)
        End If
    Next fai
    ' scale glyph alphas in-place; _Source=_Dest=tmpImg so Point reads correctly
    _Source tmpImg
    _Dest tmpImg
    For fapy = 0 To FONT_CHAR_H - 1
        For fapx = 0 To tw - 1
            facol = Point(fapx, fapy)
            If _Alpha32(facol) > 0 Then
                faa = (_Alpha32(facol) * alpha) \ 255
                PSet (fapx, fapy), _RGBA32(_Red32(facol), _Green32(facol), _Blue32(facol), faa)
            End If
        Next fapx
    Next fapy
    ' composite onto dest
    _BLEND dest
    _PUTIMAGE (x, y)-(x + tw - 1, y + FONT_CHAR_H - 1), tmpImg, dest
    _DONTBLEND dest
    _Dest dest
    _FreeImage tmpImg
End Sub

Sub FONT_PrintCenteredAlpha(sheet As Long, dest As Long, txt As String, y As Integer, scrW As Integer, alpha As Integer)
    FONT_PrintAlpha sheet, dest, txt, (scrW - Len(txt) * FONT_CHAR_W) \ 2, y, alpha
End Sub
