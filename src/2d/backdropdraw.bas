' backdropdraw.bas -- drawing the matte-painting effects over a painted screen (#369)
'
' The timing and the effect tables are in backdrop.bas (headless); this file puts them on backBuffer
' and holds --backdrop-dev, the dev-build helper for placing effects:
'   BACKDROP_Draw name$, x1, y1, x2, y2   call right after the painting is drawn into the rectangle
'                                         x1,y1-x2,y2 of backBuffer, before any UI over it
'   --backdrop-dev                        shows the painting coordinates under the mouse, marks where each
'                                         SPRITE and LASER starts and ends (crosses, an index label, the path
'                                         faint) and, on R, re-reads assets/backdrops.txt from disk (parse
'                                         problems are shown on screen and the effects stay off until it is fixed)
' A LASER is drawn by COMBAT_DrawBoltM through the painting's own camera (BD_CamMatrix), never vpMat.
' There is no additive blending, so a glow is a stack of translucent circles, as for the bolts.

Const BD_DEV_NOTE_FRAMES = 30   ' a successful reload is mentioned for this long
Const BD_DEV_ROWS = 8          ' rows of parse problems shown (about three problems of two lines)
Const BD_DEV_FILE = "assets/backdrops.txt"

Dim Shared bdDevWas As Integer
Dim Shared bdImgHandle(1 To 8) As Long    ' SPRITE images, numbered as in BD_SPRITE_NAMES
Dim Shared bdCamArr(0 To 3, 0 To 3) As Single
Dim Shared bdCamMat As E3D_Matrix4        ' the camera of the backdrop on screen, folded onto its rectangle
Dim Shared bdDevMsg As String         ' last reload result, "" before the first
Dim Shared bdDevErr As Integer
Dim Shared bdDevAt As Long             ' main-loop frame of the last successful reload
Dim Shared bdDevX1 As Integer, bdDevY1 As Integer, bdDevX2 As Integer, bdDevY2 As Integer

' The file as shipped, parsed at startup. A problem here is caught by the test that parses the
' same file; at run time the effects just stay off.
Sub BACKDROP_Load ()
    Dim blOk As Integer
    blOk = BD_Parse%(_Embedded$("BACKDROPS"))
    BACKDROP_LoadArt
End Sub

' The SPRITE images, one line per name in BD_SPRITE_NAMES and in its order (assets/backdrops/<name>.png, embedded as BDIMG + the name in capitals without underscores).
Sub BACKDROP_LoadArt ()
    bdImgHandle(1) = UI_LoadArt&(_Embedded$("BDIMGTUG"))
    bdImgHandle(2) = UI_LoadArt&(_Embedded$("BDIMGBAGGAGECART"))
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

Sub BACKDROP_DrawSprite (bdpFx As Integer)
    Dim bdpX As Single, bdpY As Single, bdpFlip As Integer, bdpImg As Long, bdpSc As Single, bdpBX As Single, bdpBY As Single
    Dim bdpW As Integer, bdpH As Integer, bdpX1 As Integer, bdpY1 As Integer, bdpX2 As Integer, bdpY2 As Integer
    bdpImg = bdImgHandle(bdImg(bdpFx))
    If bdpImg >= -1 Then Exit Sub
    If BD_SpriteState%(bdpFx, bdFrame, bdpX, bdpY, bdpFlip, bdpSc, bdpBX, bdpBY) = 0 Then Exit Sub
    bdpW = Int(_Width(bdpImg) * bdpSc * (bdDevX2 - bdDevX1 + 1) / BD_PAINT_W + 0.5)
    bdpH = Int(_Height(bdpImg) * bdpSc * (bdDevY2 - bdDevY1 + 1) / BD_PAINT_H + 0.5)
    If bdpW < 1 Then bdpW = 1
    If bdpH < 1 Then bdpH = 1
    bdpX1 = BACKDROP_ScreenX%(bdpX + bdpBX) - bdpW \ 2 : bdpY1 = BACKDROP_ScreenY%(bdpY + bdpBY) - bdpH \ 2
    bdpX2 = bdpX1 + bdpW - 1 : bdpY2 = bdpY1 + bdpH - 1
    If bdpFlip Then _PutImage (bdpX2, bdpY1)-(bdpX1, bdpY2), bdpImg, backBuffer Else _PutImage (bdpX1, bdpY1)-(bdpX2, bdpY2), bdpImg, backBuffer
End Sub

' The camera of backdrop bdcSet as a game-style clip matrix that lands on the painting's rectangle of backBuffer.
Sub BACKDROP_BuildCam (bdcSet As Integer)
    Dim bdcA As Single, bdcB As Single, bdcC As Single, bdcE As Single, bdcJ As Integer
    BD_CamMatrix bdcSet, bdCamArr()
    bdcA = (bdDevX2 - bdDevX1 + 1) / scrW : bdcB = (2 * bdDevX1 + bdDevX2 - bdDevX1 + 1) / scrW - 1
    bdcC = (bdDevY2 - bdDevY1 + 1) / scrH : bdcE = 1 - (2 * bdDevY1 + bdDevY2 - bdDevY1 + 1) / scrH
    For bdcJ = 0 To 3
        bdCamMat.m(0, bdcJ) = bdcA * bdCamArr(0, bdcJ) + bdcB * bdCamArr(3, bdcJ)
        bdCamMat.m(1, bdcJ) = bdcC * bdCamArr(1, bdcJ) + bdcE * bdCamArr(3, bdcJ)
        bdCamMat.m(2, bdcJ) = bdCamArr(2, bdcJ)
        bdCamMat.m(3, bdcJ) = bdCamArr(3, bdcJ)
    Next bdcJ
End Sub

Sub BACKDROP_DrawLaser (bdlFx As Integer)
    Dim bdlJ As Integer, bdlDist As Single, bdlPath As Single, bdlSet As Integer
    Dim bdlX1 As Single, bdlY1 As Single, bdlZ1 As Single, bdlX2 As Single, bdlY2 As Single, bdlZ2 As Single
    Dim bdlDX As Single, bdlDY As Single, bdlDZ As Single, bdlHX As Single, bdlHY As Single, bdlHZ As Single
    Dim bdlLen As Double, bdlRad As Double, bdlMaxR As Integer, bdlF As Single
    Dim bdlLo As _Unsigned Long, bdlHi As _Unsigned Long, bdlBody As _Unsigned Long, bdlCore As _Unsigned Long
    Dim bdlC As Long, bdlRed As Long, bdlGrn As Long, bdlBlu As Long
    bdlSet = bdFxSet(bdlFx)
    BD_World bdlSet, bdX(bdlFx), bdY(bdlFx), bdD1(bdlFx), bdlX1, bdlY1, bdlZ1
    BD_World bdlSet, bdX2(bdlFx), bdY2(bdlFx), bdD2(bdlFx), bdlX2, bdlY2, bdlZ2
    bdlPath = BD_LaserPath!(bdlFx)
    bdlDX = (bdlX2 - bdlX1) / bdlPath : bdlDY = (bdlY2 - bdlY1) / bdlPath : bdlDZ = (bdlZ2 - bdlZ1) / bdlPath
    bdlC = bdCol(bdlFx, 0)
    bdlRed = _Red32(bdlC) : bdlGrn = _Green32(bdlC) : bdlBlu = _Blue32(bdlC)
    bdlLo = _RGBA32(bdlRed, bdlGrn, bdlBlu, 25) : bdlHi = _RGBA32(bdlRed, bdlGrn, bdlBlu, 80)
    bdlBody = _RGB32(bdlRed, bdlGrn, bdlBlu)
    bdlCore = _RGB32(255 - (255 - bdlRed) \ 3, 255 - (255 - bdlGrn) \ 3, 255 - (255 - bdlBlu) \ 3)
    bdlLen = bdLaserLen(bdlFx) : bdlRad = 2.5 : bdlMaxR = 4 : bdlF = 1
    For bdlJ = 0 To BD_LASER_BOLTS - 1
        If BD_LaserHead%(bdlFx, bdFrame, bdlJ, bdlDist) Then
            bdlHX = bdlX1 + bdlDX * bdlDist : bdlHY = bdlY1 + bdlDY * bdlDist : bdlHZ = bdlZ1 + bdlDZ * bdlDist
            COMBAT_DrawBoltM bdCamMat, scrW, scrH, bdlHX, bdlHY, bdlHZ, bdlDX, bdlDY, bdlDZ, bdlLen, bdlRad, bdlMaxR, bdlF, bdlLo, bdlHi, bdlBody, bdlCore
        End If
    Next bdlJ
End Sub

' A small cross with a label, for placing paths by eye.
Sub BACKDROP_DevCross (bdxX As Integer, bdxY As Integer, bdxLabel As String)
    Line (bdxX - 3, bdxY)-(bdxX + 3, bdxY), _RGBA(0, 255, 255, 230)
    Line (bdxX, bdxY - 3)-(bdxX, bdxY + 3), _RGBA(0, 255, 255, 230)
    UI_Text 14, bdxLabel, bdxX + 4, bdxY - FONT_CHAR_H \ 2, 230
End Sub

Sub BACKDROP_DrawDevMarks ()
    Dim bdmI As Integer, bdmS As Integer, bdmL As Integer, bdmX1 As Integer, bdmY1 As Integer, bdmX2 As Integer, bdmY2 As Integer, bdmTag As String, bdmLasers As Integer
    If bdCur < 0 Then Exit Sub
    For bdmI = bdSetFrom(bdCur) To bdSetFrom(bdCur) + bdSetN(bdCur) - 1
        If bdKind(bdmI) = BD_KIND_SPRITE Or bdKind(bdmI) = BD_KIND_LASER Then
            If bdKind(bdmI) = BD_KIND_SPRITE Then bdmTag = "S" + LTrim$(Str$(bdmS)) : bdmS = bdmS + 1 Else bdmTag = "L" + LTrim$(Str$(bdmL)) : bdmL = bdmL + 1 : bdmLasers = -1
            bdmX1 = BACKDROP_ScreenX%(bdX(bdmI)) : bdmY1 = BACKDROP_ScreenY%(bdY(bdmI))
            bdmX2 = BACKDROP_ScreenX%(bdX2(bdmI)) : bdmY2 = BACKDROP_ScreenY%(bdY2(bdmI))
            Line (bdmX1, bdmY1)-(bdmX2, bdmY2), _RGBA(0, 255, 255, 70)
            BACKDROP_DevCross bdmX1, bdmY1, bdmTag
            BACKDROP_DevCross bdmX2, bdmY2, bdmTag
        End If
    Next bdmI
    If bdmLasers Then
        bdmX1 = BACKDROP_ScreenX%(BD_CAM_VPX) : bdmY1 = BACKDROP_ScreenY%(bdSetHor(bdCur))
        Line (0, bdmY1)-(scrW - 1, bdmY1), _RGBA(255, 255, 0, 50)
        BACKDROP_DevCross bdmX1, bdmY1, "VP"
    End If
End Sub

Sub BACKDROP_DrawDev ()
    Dim bddN As Integer, bddMX As Integer, bddMY As Integer, bddNL As Integer, bddS As String
    Dim bddRows(0 To BD_DEV_ROWS - 1) As String
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
            bddN = BD_WrapText%(bdDevMsg, 40, bddRows(), BD_DEV_ROWS)
            If bddN > BD_DEV_ROWS Then bddRows(BD_DEV_ROWS - 1) = "(and more)" : bddN = BD_DEV_ROWS
            For bddNL = 0 To bddN - 1
                UI_Text 12, bddRows(bddNL), 2, FONT_CHAR_H * (1 + bddNL), 255
            Next bddNL
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
        BACKDROP_BuildCam bdCur
        For bdnI = bdSetFrom(bdCur) To bdSetFrom(bdCur) + bdSetN(bdCur) - 1
            If bdKind(bdnI) = BD_KIND_SPRITE Then BACKDROP_DrawSprite bdnI
        Next bdnI
        For bdnI = bdSetFrom(bdCur) To bdSetFrom(bdCur) + bdSetN(bdCur) - 1
            If bdKind(bdnI) = BD_KIND_BLINK Then BACKDROP_DrawBlink bdnI
        Next bdnI
        BACKDROP_DrawSparks
        For bdnI = bdSetFrom(bdCur) To bdSetFrom(bdCur) + bdSetN(bdCur) - 1
            If bdKind(bdnI) = BD_KIND_LASER Then BACKDROP_DrawLaser bdnI
        Next bdnI
    End If
    If cliBackdropDev Then BACKDROP_DrawDevMarks : BACKDROP_DrawDev
End Sub
