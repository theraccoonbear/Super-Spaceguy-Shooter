' leadin.bas -- studio / producer ANSI art lead-in screens (GS_LEADIN)
' Art is baked into the binary via $EMBED; no external files needed at runtime.
' Renders ANSI 256-colour escape sequences into a 640x480 surface, then
' scales to the 320x240 backBuffer.  Silent -- no music or speech.
'
' Game boots into GS_LEADIN; transitions to GS_TITLE when both cards complete.
' Does not replay (liDone session flag).  Any keypress skips the current card.

Dim Shared liCard  As Integer    ' 1=cogikel, 2=ctut, 0=done
Dim Shared liTimer As Integer
Dim Shared liSurf  As Long       ' 640x480 offscreen render surface

Const LI_HOLD = 200              ' frames to hold each card (~3s at 60fps)
Const LI_FADE = 35               ' fade-in / fade-out window in frames

' Map a 256-colour palette index to R, G, B components.
Sub LEADIN_ColorRGB(liN As Integer, liR As Integer, liG As Integer, liB As Integer)
    Dim liCI As Integer
    Dim liCo(0 To 5) As Integer
    Dim liCV As Integer
    liCo(0) = 0 : liCo(1) = 95 : liCo(2) = 135 : liCo(3) = 175 : liCo(4) = 215 : liCo(5) = 255
    Select Case liN
        Case 0  : liR = 0   : liG = 0   : liB = 0
        Case 1  : liR = 128 : liG = 0   : liB = 0
        Case 2  : liR = 0   : liG = 128 : liB = 0
        Case 3  : liR = 128 : liG = 128 : liB = 0
        Case 4  : liR = 0   : liG = 0   : liB = 128
        Case 5  : liR = 128 : liG = 0   : liB = 128
        Case 6  : liR = 0   : liG = 128 : liB = 128
        Case 7  : liR = 192 : liG = 192 : liB = 192
        Case 8  : liR = 128 : liG = 128 : liB = 128
        Case 9  : liR = 255 : liG = 0   : liB = 0
        Case 10 : liR = 0   : liG = 255 : liB = 0
        Case 11 : liR = 255 : liG = 255 : liB = 0
        Case 12 : liR = 0   : liG = 0   : liB = 255
        Case 13 : liR = 255 : liG = 0   : liB = 255
        Case 14 : liR = 0   : liG = 255 : liB = 255
        Case 15 : liR = 255 : liG = 255 : liB = 255
        Case 16 To 231
            liCI = liN - 16
            liB = liCo(liCI Mod 6) : liCI = liCI \ 6
            liG = liCo(liCI Mod 6) : liCI = liCI \ 6
            liR = liCo(liCI)
        Case Else
            liCV = 8 + 10 * (liN - 232)
            If liCV < 0 Then liCV = 0
            If liCV > 255 Then liCV = 255
            liR = liCV : liG = liCV : liB = liCV
    End Select
End Sub

' Parse an ANSI .ans string and render it into liSurf at 8x16 per character cell.
Sub LEADIN_RenderAns(liData As String)
    Dim liI    As Long
    Dim liCol  As Integer, liRow As Integer
    Dim liFg   As Integer, liBg As Integer
    Dim liCh   As Integer
    Dim liB1   As Integer, liB2 As Integer
    Dim liEsc  As String
    Dim liPStr As String
    Dim liPCnt As Integer
    Dim liPIdx As Integer
    Dim liPChr As Integer
    Dim liParam(0 To 15) As Integer
    Dim liPi   As Integer
    Dim liX1   As Integer, liY1 As Integer
    Dim liX2   As Integer, liY2 As Integer
    Dim liFgR  As Integer, liFgG As Integer, liFgB As Integer
    Dim liBgR  As Integer, liBgG As Integer, liBgB As Integer
    Dim liBlR  As Integer, liBlG As Integer, liBlB As Integer
    Dim liWt   As Integer
    Dim liRender As Integer

    liFg = 7 : liBg = 0
    liCol = 0 : liRow = 0

    _DONTBLEND liSurf
    _Dest liSurf
    LINE (0, 0)-(639, 479), _RGB(0, 0, 0), BF

    liI = 1
    Do While liI <= Len(liData)
        liCh = Asc(Mid$(liData, liI, 1))
        liRender = 0

        If liCh = 27 Then
            ' ESC [ params m
            liI = liI + 1
            If liI > Len(liData) Then Exit Do
            If Asc(Mid$(liData, liI, 1)) <> 91 Then liI = liI + 1 : GoTo liNext
            liI = liI + 1
            liEsc = ""
            Do While liI <= Len(liData)
                liCh = Asc(Mid$(liData, liI, 1))
                liI = liI + 1
                If liCh = 109 Then Exit Do  ' 'm'
                liEsc = liEsc + Chr$(liCh)
            Loop
            For liPi = 0 To 15 : liParam(liPi) = 0 : Next liPi
            liPCnt = 0 : liPStr = ""
            For liPIdx = 1 To Len(liEsc) + 1
                If liPIdx > Len(liEsc) Then
                    liPChr = 59
                Else
                    liPChr = Asc(Mid$(liEsc, liPIdx, 1))
                End If
                If liPChr = 59 Then
                    If liPCnt <= 15 Then liParam(liPCnt) = Val(liPStr)
                    liPCnt = liPCnt + 1 : liPStr = ""
                Else
                    liPStr = liPStr + Chr$(liPChr)
                End If
            Next liPIdx
            liPi = 0
            Do While liPi < liPCnt
                Select Case liParam(liPi)
                    Case 0 : liFg = 7 : liBg = 0
                    Case 38
                        If liPi + 2 < liPCnt And liParam(liPi + 1) = 5 Then
                            liFg = liParam(liPi + 2) : liPi = liPi + 2
                        End If
                    Case 48
                        If liPi + 2 < liPCnt And liParam(liPi + 1) = 5 Then
                            liBg = liParam(liPi + 2) : liPi = liPi + 2
                        End If
                End Select
                liPi = liPi + 1
            Loop

        ElseIf liCh = 10 Then
            liRow = liRow + 1 : liCol = 0
            liI = liI + 1

        ElseIf liCh = 13 Then
            liCol = 0
            liI = liI + 1

        ElseIf liCh = &HE2 Then
            ' possible 3-byte UTF-8 block character
            If liI + 2 <= Len(liData) Then
                liB1 = Asc(Mid$(liData, liI + 1, 1))
                liB2 = Asc(Mid$(liData, liI + 2, 1))
                If liB1 = &H96 Then
                    Select Case liB2
                        Case &H88 : liWt = 100  ' █ full block
                        Case &H93 : liWt = 75   ' ▓ dark shade
                        Case &H92 : liWt = 50   ' ▒ medium shade
                        Case &H91 : liWt = 25   ' ░ light shade
                        Case Else  : liWt = 0
                    End Select
                    liI = liI + 3 : liRender = 1
                Else
                    liWt = 0 : liI = liI + 1 : liRender = 1
                End If
            Else
                liI = liI + 1
            End If

        ElseIf liCh = 32 Then
            liWt = 0 : liI = liI + 1 : liRender = 1

        Else
            liWt = 100 : liI = liI + 1 : liRender = 1
        End If

        If liRender And liCol >= 0 And liCol < 80 And liRow >= 0 And liRow < 30 Then
            liX1 = liCol * 8 : liY1 = liRow * 16
            liX2 = liX1 + 7  : liY2 = liY1 + 15
            LEADIN_ColorRGB liBg, liBgR, liBgG, liBgB
            LINE (liX1, liY1)-(liX2, liY2), _RGB(liBgR, liBgG, liBgB), BF
            If liWt > 0 Then
                LEADIN_ColorRGB liFg, liFgR, liFgG, liFgB
                If liWt >= 100 Then
                    LINE (liX1, liY1)-(liX2, liY2), _RGB(liFgR, liFgG, liFgB), BF
                Else
                    liBlR = (liFgR * liWt + liBgR * (100 - liWt)) \ 100
                    liBlG = (liFgG * liWt + liBgG * (100 - liWt)) \ 100
                    liBlB = (liFgB * liWt + liBgB * (100 - liWt)) \ 100
                    LINE (liX1, liY1)-(liX2, liY2), _RGB(liBlR, liBlG, liBlB), BF
                End If
            End If
            liCol = liCol + 1
        ElseIf liRender Then
            liCol = liCol + 1
        End If

        liNext:
    Loop
    _Dest 0
End Sub

Sub LEADIN_ShowCard(liCardN As Integer)
    Dim liAns As String
    If liCardN = 1 Then
        liAns = _EMBEDDED$("COGIKEL")
    Else
        liAns = _EMBEDDED$("CTUT")
    End If
    LEADIN_RenderAns liAns
End Sub

Sub LEADIN_Init()
    liSurf = _NEWIMAGE(640, 480, 32)
    liCard = 1 : liTimer = 0
    LEADIN_ShowCard 1
End Sub

Sub LEADIN_Update()
    Dim liAlpha As Integer
    Dim liKey   As Long

    If liCard = 0 Then gameState = GS_TITLE : Exit Sub

    liTimer = liTimer + 1

    If liTimer < LI_FADE Then
        liAlpha = liTimer * 255 \ LI_FADE
    ElseIf liTimer > LI_HOLD - LI_FADE Then
        liAlpha = (LI_HOLD - liTimer) * 255 \ LI_FADE
        If liAlpha < 0 Then liAlpha = 0
    Else
        liAlpha = 255
    End If

    _Dest backBuffer
    _DONTBLEND backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 0), BF
    _PutImage (0, 0)-(scrW - 1, scrH - 1), liSurf, backBuffer
    If liAlpha < 255 Then
        _BLEND backBuffer
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, 255 - liAlpha), BF
    End If
    _BLEND backBuffer
    _Dest 0
    _PutImage , backBuffer, 0

    liKey = _KEYHIT
    If liTimer >= LI_HOLD Or liKey > 0 Then
        liCard = liCard + 1
        If liCard > 2 Then
            liCard = 0 : gameState = GS_TITLE
        Else
            liTimer = 0
            LEADIN_ShowCard liCard
        End If
    End If

    MUS_Fill 0
End Sub
