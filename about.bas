' about.bas — About / credits scroll screen
'
' ABOUT_Prep    load [BLOCK:about] from gametext.txt, inject title header
' ABOUT_Update  render panel + auto-scroll + manual up/dn + ESC back

Const ABOUT_MAX_LINES = 64
Const ABOUT_CHARS     = 34     ' same wrap width as crawl
Const ABOUT_LINE_H    = 22     ' same as crawl
Const ABOUT_SPEED     = 0.12   ' pixels/frame — slower than crawl (0.25)

Dim Shared aboutLines$(0 To ABOUT_MAX_LINES - 1)
Dim Shared aboutLineCount As Integer
Dim Shared aboutScroll    As Single
Dim Shared aboutUpWas     As Integer
Dim Shared aboutDnWas     As Integer
Dim Shared aboutEscWas    As Integer

Sub ABOUT_Prep()
    Dim abBlock As String, abPos As Long, abNxt As Long, abLn As String
    Dim abRem As String, abCut As Integer, abVCut As Integer
    Dim abCI As Integer, abCJ As Integer, abCA As Integer, abLast As String
    Dim abHi As Integer, abHMax As Integer

    aboutLineCount = 0

    abBlock = GTEXT_Get$("about")
    abPos = 1
    Do While abPos <= Len(abBlock)
        abNxt = InStr(abPos, abBlock, Chr$(10))
        If abNxt = 0 Then abNxt = Len(abBlock) + 1
        abLn = Mid$(abBlock, abPos, abNxt - abPos)
        abPos = abNxt + 1
        If Right$(abLn, 1) = Chr$(13) Then abLn = Left$(abLn, Len(abLn) - 1)
        abLn = LTrim$(RTrim$(abLn))
        If Len(abLn) = 0 Then
            If aboutLineCount < ABOUT_MAX_LINES Then
                aboutLines$(aboutLineCount) = "" : aboutLineCount = aboutLineCount + 1
            End If
        Else
            abRem = abLn
            Do While Len(abRem) > 0 And aboutLineCount < ABOUT_MAX_LINES
                If CRAWL_VisLen%(abRem) <= ABOUT_CHARS Then
                    aboutLines$(aboutLineCount) = abRem
                    aboutLineCount = aboutLineCount + 1
                    abRem = ""
                Else
                    abVCut = CRAWL_VisCut%(abRem, ABOUT_CHARS)
                    abCut = abVCut
                    Do While abCut > 0 And Mid$(abRem, abCut, 1) <> " "
                        abCut = abCut - 1
                    Loop
                    If abCut = 0 Then abCut = abVCut
                    aboutLines$(aboutLineCount) = Left$(abRem, abCut)
                    aboutLineCount = aboutLineCount + 1
                    abRem = LTrim$(Mid$(abRem, abCut + 1))
                End If
            Loop
        End If
    Loop

    ' carry color codes across line boundaries
    abLast = "~7"
    For abCI = 0 To aboutLineCount - 1
        If Len(aboutLines$(abCI)) > 0 Then
            abCA = 0
            If Len(aboutLines$(abCI)) >= 2 And Left$(aboutLines$(abCI), 1) = "~" Then
                abCA = Asc(UCase$(Mid$(aboutLines$(abCI), 2, 1)))
                If Not ((abCA >= 48 And abCA <= 57) Or (abCA >= 65 And abCA <= 70)) Then abCA = 0
            End If
            If abCA = 0 Then aboutLines$(abCI) = abLast + aboutLines$(abCI)
            For abCJ = 1 To Len(aboutLines$(abCI)) - 1
                If Mid$(aboutLines$(abCI), abCJ, 1) = "~" Then
                    abCA = Asc(UCase$(Mid$(aboutLines$(abCI), abCJ + 1, 1)))
                    If (abCA >= 48 And abCA <= 57) Or (abCA >= 65 And abCA <= 70) Then
                        abLast = Mid$(aboutLines$(abCI), abCJ, 2)
                    End If
                End If
            Next abCJ
        End If
    Next abCI

    ' inject game title + version at top (shift existing lines down by 3)
    abHMax = ABOUT_MAX_LINES - 1 - 3
    If aboutLineCount - 1 < abHMax Then abHMax = aboutLineCount - 1
    For abHi = abHMax To 0 Step -1
        aboutLines$(abHi + 3) = aboutLines$(abHi)
    Next abHi
    aboutLines$(0) = "~ESUPER SPACEGUY SHOOTER"
    aboutLines$(1) = "~8" + VERSION$
    aboutLines$(2) = ""
    If aboutLineCount + 3 > ABOUT_MAX_LINES Then
        aboutLineCount = ABOUT_MAX_LINES
    Else
        aboutLineCount = aboutLineCount + 3
    End If

    aboutScroll = scrH - 22    ' first line appears at bottom of content area
    aboutUpWas = 0 : aboutDnWas = 0 : aboutEscWas = 0
End Sub

Sub ABOUT_Update()
    Dim abI As Integer, abY As Integer
    Dim abUp As Integer, abDn As Integer, abEsc As Integer, abSy As Integer

    abUp  = _KEYDOWN(18432)   ' up arrow
    abDn  = _KEYDOWN(20480)   ' down arrow
    abEsc = _KEYDOWN(27)

    ' manual scroll (4 px/frame while held)
    If abUp Then aboutScroll = aboutScroll + 4
    If abDn Then aboutScroll = aboutScroll - 4

    ' auto-scroll upward
    aboutScroll = aboutScroll - ABOUT_SPEED

    ' clamp: top of content is scrH-22, bottom is past last line
    If aboutScroll > scrH - 22 Then aboutScroll = scrH - 22
    Dim abFloor As Single : abFloor = -(aboutLineCount * ABOUT_LINE_H) + 24
    If aboutScroll < abFloor Then aboutScroll = abFloor

    If abEsc And Not aboutEscWas Then gameState = GS_TITLE

    aboutUpWas = abUp : aboutDnWas = abDn : aboutEscWas = abEsc

    ' ---- render ----
    _Dest backBuffer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    For abSy = 0 To scrH - 1 Step 2
        Line (0, abSy)-(scrW - 1, abSy), _RGBA(0, 0, 18, 28)
    Next abSy

    UI_DrawPanel 16, 8, scrW - 17, scrH - 19, "ABOUT"

    ' draw scrolling lines clipped to panel content area (y 22 .. scrH-20)
    For abI = 0 To aboutLineCount - 1
        abY = Int(aboutScroll + abI * ABOUT_LINE_H)
        If abY > 20 And abY < scrH - 20 Then
            If Len(aboutLines$(abI)) > 0 Then
                FONT_PrintCenteredRich fontPalette(), backBuffer, aboutLines$(abI), abY, scrW
            End If
        End If
    Next abI

    ' top fade — masks text emerging from under the title bar
    Line (17, 21)-(scrW - 18, 38), _RGBA(2, 4, 18, 220), BF
    Line (17, 38)-(scrW - 18, 50), _RGBA(2, 4, 18, 100), BF

    ' bottom fade — masks text near the footer
    Line (17, scrH - 36)-(scrW - 18, scrH - 28), _RGBA(2, 4, 18, 100), BF
    Line (17, scrH - 28)-(scrW - 18, scrH - 20), _RGBA(2, 4, 18, 220), BF

    FONT_PrintCentered fontPalette(8), backBuffer, "up/dn scroll   ESC back", scrH - 14, scrW

    _Dest 0
    _PutImage , backBuffer, 0
End Sub
