' backdropdraw.bas -- drawing the matte-painting effects over a painted screen (#369)
'
' The timing and the effect tables are in backdrop.bas (headless); this file puts them on backBuffer
' and holds --backdrop-dev, the dev-build helper for placing effects:
'   BACKDROP_Draw name$, x1, y1, x2, y2   call right after the painting is drawn into the rectangle
'                                         x1,y1-x2,y2 of backBuffer, before any UI over it
'   --backdrop-dev                        shows the painting coordinates under the mouse and, on R,
'                                         re-reads assets/backdrops.txt from disk (parse problems are
'                                         shown on screen and the effects stay off until it is fixed)
' There is no additive blending, so a glow is a stack of translucent circles, as for the bolts.

Const BD_DEV_NOTE_FRAMES = 30   ' a successful reload is mentioned for this long
Const BD_DEV_FILE = "assets/backdrops.txt"

Dim Shared bdDevWas As Integer
Dim Shared bdDevMsg As String         ' last reload result, "" before the first
Dim Shared bdDevErr As Integer
Dim Shared bdDevAt As Long             ' main-loop frame of the last successful reload
Dim Shared bdDevX1 As Integer, bdDevY1 As Integer, bdDevX2 As Integer, bdDevY2 As Integer

' The file as shipped, parsed at startup. A problem here is caught by the test that parses the
' same file; at run time the effects just stay off.
Sub BACKDROP_Load ()
    Dim blOk As Integer
    blOk = BD_Parse%(_Embedded$("BACKDROPS"))
End Sub

' assets/backdrops.txt on disk: the launch folder (tools/dev run starts in the repository), else
' the repository relative to the executable's folder.
Function BACKDROP_DevPath$ ()
    Dim bdpA As String
    bdpA = _StartDir$ + "/" + BD_DEV_FILE
    If _FileExists(bdpA) Then BACKDROP_DevPath$ = bdpA : Exit Function
    bdpA = _Cwd$ + "/../" + BD_DEV_FILE
    If _FileExists(bdpA) Then BACKDROP_DevPath$ = bdpA : Exit Function
    BACKDROP_DevPath$ = ""
End Function

Sub BACKDROP_DevReload ()
    Dim bdrPath As String, bdrOk As Integer
    bdrPath = BACKDROP_DevPath$
    If bdrPath = "" Then
        bdDevMsg = "R: " + BD_DEV_FILE + " not found (launch from the repository folder)"
        bdDevErr = -1
        Exit Sub
    End If
    bdrOk = BD_Parse%(_ReadFile$(bdrPath))
    If bdrOk Then
        bdDevErr = 0
        bdDevMsg = "reloaded " + LTrim$(Str$(bdFxN))
        bdDevAt = gameFrame
    Else
        bdDevErr = -1
        bdDevMsg = bdErrors
    End If
    bdLastMain = -2
End Sub

' Pixel (bdsX, bdsY) of the 320x240 painting on the screen rectangle.
Function BACKDROP_ScreenX% (bsxP As Single)
    BACKDROP_ScreenX% = bdDevX1 + Int(bsxP * (bdDevX2 - bdDevX1 + 1) / BD_PAINT_W)
End Function

Function BACKDROP_ScreenY% (bsyP As Single)
    BACKDROP_ScreenY% = bdDevY1 + Int(bsyP * (bdDevY2 - bdDevY1 + 1) / BD_PAINT_H)
End Function

Sub BACKDROP_DrawBlink (bdbFx As Integer)
    Dim bdbLv As Single, bdbX As Integer, bdbY As Integer, bdbR As Integer
    Dim bdbC As Long, bdbRed As Long, bdbGrn As Long, bdbBlu As Long
    bdbLv = BD_BlinkLevel!(bdbFx, bdFrame)
    If bdbLv <= 0.01 Then Exit Sub
    bdbX = BACKDROP_ScreenX%(bdX(bdbFx)) : bdbY = BACKDROP_ScreenY%(bdY(bdbFx))
    bdbC = bdCol(bdbFx, 0)
    bdbRed = _Red32(bdbC) : bdbGrn = _Green32(bdbC) : bdbBlu = _Blue32(bdbC)
    For bdbR = bdSize(bdbFx) + bdGlow(bdbFx) To bdSize(bdbFx) + 1 Step -1
        Circle (bdbX, bdbY), bdbR, _RGBA(bdbRed, bdbGrn, bdbBlu, Int(34 * bdbLv))
    Next bdbR
    If bdSize(bdbFx) > 0 Then Line (bdbX - bdSize(bdbFx) + 1, bdbY - bdSize(bdbFx) + 1)-(bdbX + bdSize(bdbFx) - 1, bdbY + bdSize(bdbFx) - 1), _RGBA(bdbRed, bdbGrn, bdbBlu, Int(220 * bdbLv)), BF
    Line (bdbX, bdbY)-(bdbX, bdbY), _RGBA(255 - (255 - bdbRed) \ 3, 255 - (255 - bdbGrn) \ 3, 255 - (255 - bdbBlu) \ 3, Int(255 * bdbLv))
End Sub

Sub BACKDROP_DrawSparks ()
    Dim bdsS As Integer, bdsTX As Integer, bdsTY As Integer, bdsI As Integer, bdsX As Integer, bdsY As Integer, bdsA As Long, bdsC As Long
    For bdsI = 0 To BD_POOL - 1
        If bdPAlive(bdsI) Then
            bdsA = 255 - (255 * bdPAge(bdsI)) \ bdPLife(bdsI)
            bdsC = bdPCol(bdsI)
            bdsX = BACKDROP_ScreenX%(bdPX(bdsI)) : bdsY = BACKDROP_ScreenY%(bdPY(bdsI))
            bdsS = bdSize(bdPFx(bdsI))
            bdsTX = bdsX - Sgn(bdPVX(bdsI)) * bdsS : bdsTY = bdsY - Sgn(bdPVY(bdsI)) * bdsS
            Line (bdsTX, bdsTY)-(bdsTX + bdsS - 1, bdsTY + bdsS - 1), _RGBA(_Red32(bdsC), _Green32(bdsC), _Blue32(bdsC), bdsA \ 3), BF
            Line (bdsX, bdsY)-(bdsX + bdsS, bdsY + bdsS), _RGBA(_Red32(bdsC), _Green32(bdsC), _Blue32(bdsC), bdsA), BF
        End If
    Next bdsI
End Sub

Sub BACKDROP_DrawDev ()
    Dim bddI As Integer, bddMX As Integer, bddMY As Integer, bddNL As Integer, bddS As String, bddP As Integer
    Do While _MouseInput : Loop
    _MouseShow
    bddMX = _MouseX : bddMY = _MouseY
    If bddMX >= bdDevX1 And bddMX <= bdDevX2 And bddMY >= bdDevY1 And bddMY <= bdDevY2 Then
        bddS = LTrim$(Str$(Int((bddMX - bdDevX1) * BD_PAINT_W / (bdDevX2 - bdDevX1 + 1)))) + "," + LTrim$(Str$(Int((bddMY - bdDevY1) * BD_PAINT_H / (bdDevY2 - bdDevY1 + 1))))
        Line (bddMX - 3, bddMY)-(bddMX + 3, bddMY), _RGBA(255, 255, 0, 200)
        Line (bddMX, bddMY - 3)-(bddMX, bddMY + 3), _RGBA(255, 255, 0, 200)
    Else
        bddS = "off the painting"
    End If
    bddS = "at=" + bddS + "  R=reload"
    Line (0, 0)-(Len(bddS) * FONT_CHAR_W + 3, FONT_CHAR_H), _RGBA(0, 0, 0, 200), BF
    FONT_PrintAlpha fontPalette(14), backBuffer, bddS, 2, 0, 255
    If Len(bdDevMsg) > 0 Then
        If bdDevErr = 0 Then
            If gameFrame - bdDevAt < BD_DEV_NOTE_FRAMES Then UI_Text 10, bdDevMsg, Len(bddS) * FONT_CHAR_W + 8, 0, 255
        Else
            bddNL = 0 : bddP = 1
            Do While bddP <= Len(bdDevMsg)
                bddI = InStr(bddP, bdDevMsg, Chr$(10))
                If bddI = 0 Then bddI = Len(bdDevMsg) + 1
                If bddNL = 4 Then UI_Text 12, "(and more)", 2, FONT_CHAR_H * 5, 255 : Exit Do
                UI_Text 12, Left$(Mid$(bdDevMsg, bddP, bddI - bddP), 40), 2, FONT_CHAR_H * (1 + bddNL), 255
                bddNL = bddNL + 1 : bddP = bddI + 1
            Loop
        End If
    End If
End Sub

Sub BACKDROP_Draw (bdnName As String, bdnX1 As Integer, bdnY1 As Integer, bdnX2 As Integer, bdnY2 As Integer)
    Dim bdnI As Integer, bdnKeyNow As Integer
    bdDevX1 = bdnX1 : bdDevY1 = bdnY1 : bdDevX2 = bdnX2 : bdDevY2 = bdnY2
    If cliBackdropDev Then
        bdnKeyNow = KEY_Down%(82) Or KEY_Down%(114)
        If bdnKeyNow And bdDevWas = 0 Then BACKDROP_DevReload
        bdDevWas = bdnKeyNow
    End If
    BD_Advance gameFrame, bdnName
    _Dest backBuffer
    _Blend backBuffer
    If bdCur >= 0 Then
        For bdnI = bdSetFrom(bdCur) To bdSetFrom(bdCur) + bdSetN(bdCur) - 1
            If bdKind(bdnI) = BD_KIND_BLINK Then BACKDROP_DrawBlink bdnI
        Next bdnI
        BACKDROP_DrawSparks
    End If
    If cliBackdropDev Then BACKDROP_DrawDev
End Sub
