' explosiondraw.bas -- drawing the explosion particles in 3D, and the dev tooling (#198)
'
' explosion.bas holds the particles (world space); this file puts them on backBuffer:
'   XPD_Draw      after E3D_SceneFlush and before the bolts and warnings. Every live particle goes
'                 through this frame's vpMat (so a burst follows the camera lag, the orbit and the
'                 cinematic camera), at a radius of size x focal / w pixels (w is the view depth).
'                 Layer maxpx caps it, a particle under max(minpx, 1) px becomes a 1 px dot that
'                 fades with the square of its radius, nearer than XP_NEAR it is not drawn and up
'                 to XP_NEAR_FULL it fades in. Occluding layers are tested against E3D_zBuf (set by
'                 the scene, the same NDC z); bursts are drawn far to near, a burst's layers in file order.
'   XPD_Boom      XP_Spawn plus the definition's SHAKE (fxShakeTimer = max(current, frames))
'   XPD_Frame     per frame in play: --explode spawns and, with --explosion-dev, the keys
'   XPD_DevDraw   the --explosion-dev readout and any parse problems
' There is no additive blend, so a glow is a stack of translucent fills, as for the bolts.

Const XPD_AHEAD = 12            ' world units ahead of the ship for X, V and --explode
Const XPD_GROUPS = 32           ' bursts sorted apart; more share the last one
Const XPD_SMALL = 6             ' up to this radius a disc is a stack of Circles, above it scanlines
Const XPD_GLOW_MAX = 48         ' pixels, the largest glow radius
Const XPD_GLOW_A = 38           ' alpha of one glow layer
Const XPD_DEV_FILE = "assets/explosions.txt"
Const XPD_DEV_ROWS = 8
Const XPD_NOTE_FRAMES = 60

Dim Shared xwSX(0 To XP_POOL - 1) As Single
Dim Shared xwSY(0 To XP_POOL - 1) As Single
Dim Shared xwW(0 To XP_POOL - 1) As Single
Dim Shared xwZ(0 To XP_POOL - 1) As Single
Dim Shared xwKey(0 To XP_POOL - 1) As Integer
Dim Shared xwOrder(0 To XP_POOL - 1) As Integer
Dim Shared xwBin(0 To XPD_GROUPS * 64) As Integer
Dim Shared xwGSer(0 To XPD_GROUPS - 1) As Long
Dim Shared xwGW(0 To XPD_GROUPS - 1) As Single
Dim Shared xwGRank(0 To XPD_GROUPS - 1) As Integer
Dim Shared xwFocal As Single

Dim Shared xwSel As Integer         ' --explosion-dev: the definition Z picked
Dim Shared xwOff As Integer         ' parse problems: effects stay off until the file is fixed
Dim Shared xwMsg As String          ' last reload result, or the parse problems
Dim Shared xwMsgAt As Long
Dim Shared xwWasZ As Integer, xwWasX As Integer, xwWasC As Integer, xwWasV As Integer
Dim Shared xwDone(0 To XP_MAX_EXPLODE - 1) As Integer

' Starts explosion xoId and applies its SHAKE to the screen.
Sub XPD_Boom (xoId As Integer, xoX As Single, xoY As Single, xoZ As Single, xoVX As Single, xoVY As Single, xoVZ As Single, xoSc As Single)
    Dim xoN As Integer
    If xoId < 0 Or xoId >= xdCnt Then Exit Sub
    XP_Spawn xoId, xoX, xoY, xoZ, xoVX, xoVY, xoVZ, xoSc
    xoN = XP_ShakeFrames%(xoId)
    If xoN > fxShakeTimer Then fxShakeTimer = xoN
End Sub

' 1 when an occluding particle at NDC depth xhZ is behind what the scene drew at pixel (xhX, xhY).
Function XPD_Hidden% (xhX As Integer, xhY As Integer, xhZ As Single)
    If xhX < 0 Or xhY < 0 Or xhX >= scrW Or xhY >= scrH Then Exit Function
    XPD_Hidden% = (E3D_zBuf(xhX, xhY) <= xhZ)
End Function

Function XPD_Alpha% (xaV As Single)
    If xaV < 0 Then xaV = 0
    If xaV > 255 Then xaV = 255
    XPD_Alpha% = Int(xaV)
End Function

' A filled disc by scanline. With xdOcc each row is split into the runs the depth buffer lets through.
Sub XPD_Disc (xdX As Single, xdY As Single, xdR As Single, xdCol As Long, xdA As Integer, xdZ As Single, xdOcc As Integer)
    Dim xdYY As Integer, xdY1 As Integer, xdY2 As Integer, xdDy As Single, xdH As Single
    Dim xdX1 As Integer, xdX2 As Integer, xdXX As Integer, xdRun As Integer, xdC As Long
    xdC = _RGBA(_Red32(xdCol), _Green32(xdCol), _Blue32(xdCol), xdA)
    xdY1 = Int(xdY - xdR) : If xdY1 < 0 Then xdY1 = 0
    xdY2 = Int(xdY + xdR) : If xdY2 > scrH - 1 Then xdY2 = scrH - 1
    For xdYY = xdY1 To xdY2
        xdDy = xdYY + 0.5 - xdY
        If Abs(xdDy) <= xdR Then
            xdH = Sqr(xdR * xdR - xdDy * xdDy)
            xdX1 = Int(xdX - xdH + 0.5) : If xdX1 < 0 Then xdX1 = 0
            xdX2 = Int(xdX + xdH - 0.5) : If xdX2 > scrW - 1 Then xdX2 = scrW - 1
            If xdX1 <= xdX2 Then
                If xdOcc = 0 Then
                    Line (xdX1, xdYY)-(xdX2, xdYY), xdC, BF
                Else
                    xdRun = -1
                    For xdXX = xdX1 To xdX2
                        If xdZ < E3D_zBuf(xdXX, xdYY) Then
                            If xdRun < 0 Then xdRun = xdXX
                        ElseIf xdRun >= 0 Then
                            Line (xdRun, xdYY)-(xdXX - 1, xdYY), xdC, BF
                            xdRun = -1
                        End If
                    Next xdXX
                    If xdRun >= 0 Then Line (xdRun, xdYY)-(xdX2, xdYY), xdC, BF
                End If
            End If
        End If
    Next xdYY
End Sub

' A small round blob as a stack of Circles from the rim in (alpha xsAEdge) to the centre (xsACen); the centre pixel decides occlusion.
Sub XPD_Blob (xsX As Single, xsY As Single, xsR As Single, xsCol As Long, xsACen As Single, xsAEdge As Single, xsZ As Single, xsOcc As Integer)
    Dim xsK As Integer, xsN As Integer, xsF As Single
    If xsOcc Then
        If XPD_Hidden%(Int(xsX), Int(xsY), xsZ) Then Exit Sub
    End If
    xsN = Int(xsR)
    For xsK = xsN To 1 Step -1
        xsF = (xsK - 1) / xsR
        Circle (xsX, xsY), xsK, _RGBA(_Red32(xsCol), _Green32(xsCol), _Blue32(xsCol), XPD_Alpha%(xsACen + (xsAEdge - xsACen) * xsF))
    Next xsK
    Line (Int(xsX), Int(xsY))-(Int(xsX), Int(xsY)), _RGBA(_Red32(xsCol), _Green32(xsCol), _Blue32(xsCol), XPD_Alpha%(xsACen))
End Sub

Sub XPD_Particle (xqS As Integer)
    Dim xqL As Integer, xqRaw As Single, xqR As Single, xqGlowR As Single, xqAF As Single, xqExt As Single
    Dim xqCol As Long, xqOcc As Integer, xqMin As Single, xqAx As Single, xqZn As Single
    xqL = xpLay(xqS)
    xqRaw = XP_PxRadius!(XP_Size!(xqS), xwFocal, xwW(xqS))
    xqR = XP_MaxPx!(xbMaxPx(xqL))
    If xqRaw < xqR Then xqR = xqRaw
    xqMin = xbMinPx(xqL)
    xqAF = XP_NearFade!(xwW(xqS)) * XP_LifeFade!(xpAge(xqS), xpLife(xqS)) * XP_DotFade!(xqR, xqMin)
    If xqAF <= 0.004 Then Exit Sub
    xqGlowR = xpGl(xqS) * xqR
    If xqGlowR > XPD_GLOW_MAX Then xqGlowR = XPD_GLOW_MAX
    xqExt = xqR : If xqGlowR > xqExt Then xqExt = xqGlowR
    If xqExt < 1 Then xqExt = 1
    If xwSX(xqS) + xqExt < 0 Or xwSX(xqS) - xqExt >= scrW Or xwSY(xqS) + xqExt < 0 Or xwSY(xqS) - xqExt >= scrH Then Exit Sub
    xqCol = XP_Color&(xqS)
    xqOcc = xbOcc(xqL)
    xqZn = xwZ(xqS)
    If xqGlowR >= 1 Then
        xqAx = XPD_GLOW_A * xqAF
        If xqGlowR <= XPD_SMALL Then
            XPD_Blob xwSX(xqS), xwSY(xqS), xqGlowR, xqCol, xqAx * 1.6, xqAx * 0.4, xqZn, xqOcc
        Else
            XPD_Disc xwSX(xqS), xwSY(xqS), xqGlowR, xqCol, XPD_Alpha%(xqAx), xqZn, xqOcc
            XPD_Disc xwSX(xqS), xwSY(xqS), xqGlowR * 0.66, xqCol, XPD_Alpha%(xqAx), xqZn, xqOcc
            XPD_Disc xwSX(xqS), xwSY(xqS), xqGlowR * 0.33, xqCol, XPD_Alpha%(xqAx), xqZn, xqOcc
        End If
    End If
    xqAx = 255 * xqAF
    If xqR < 1.5 Then
        XPD_Blob xwSX(xqS), xwSY(xqS), 1, xqCol, xqAx, xqAx, xqZn, xqOcc
    ElseIf xqR <= XPD_SMALL Then
        XPD_Blob xwSX(xqS), xwSY(xqS), xqR, xqCol, xqAx, xqAx, xqZn, xqOcc
    Else
        XPD_Disc xwSX(xqS), xwSY(xqS), xqR, xqCol, XPD_Alpha%(xqAx), xqZn, xqOcc
    End If
End Sub

Sub XPD_Draw ()
    Dim xrS As Integer, xrG As Integer, xrNG As Integer, xrX As Single, xrY As Single, xrZ As Single, xrW As Single
    Dim xrI As Integer, xrJ As Integer, xrN As Integer, xrK As Integer
    If xpLive = 0 Or xwOff Then Exit Sub
    _Dest backBuffer
    xwFocal = XP_Focal!(scrH, cam.fov)
    For xrS = 0 To XP_POOL - 1
        xwKey(xrS) = -1
        If xpAlive(xrS) Then
            xrW = xpX(xrS) * vpMat.m(3,0) + xpY(xrS) * vpMat.m(3,1) + xpZ(xrS) * vpMat.m(3,2) + vpMat.m(3,3)
            If xrW > XP_NEAR Then
                xrX = xpX(xrS) * vpMat.m(0,0) + xpY(xrS) * vpMat.m(0,1) + xpZ(xrS) * vpMat.m(0,2) + vpMat.m(0,3)
                xrY = xpX(xrS) * vpMat.m(1,0) + xpY(xrS) * vpMat.m(1,1) + xpZ(xrS) * vpMat.m(1,2) + vpMat.m(1,3)
                xrZ = xpX(xrS) * vpMat.m(2,0) + xpY(xrS) * vpMat.m(2,1) + xpZ(xrS) * vpMat.m(2,2) + vpMat.m(2,3)
                xwW(xrS) = xrW
                xwSX(xrS) = (xrX / xrW + 1.0) * scrW * 0.5
                xwSY(xrS) = (1.0 - xrY / xrW) * scrH * 0.5
                xwZ(xrS) = xrZ / xrW
                xrG = -1
                For xrI = 0 To xrNG - 1
                    If xwGSer(xrI) = xpSer(xrS) Then xrG = xrI : Exit For
                Next xrI
                If xrG < 0 Then
                    If xrNG < XPD_GROUPS Then
                        xrG = xrNG : xrNG = xrNG + 1
                        xwGSer(xrG) = xpSer(xrS)
                        xwGW(xrG) = xpOX(xrS) * vpMat.m(3,0) + xpOY(xrS) * vpMat.m(3,1) + xpOZ(xrS) * vpMat.m(3,2) + vpMat.m(3,3)
                    Else
                        xrG = XPD_GROUPS - 1
                    End If
                End If
                xwKey(xrS) = xrG
            End If
        End If
    Next xrS
    If xrNG = 0 Then Exit Sub
    ' far to near: rank 0 is the burst with the largest origin w
    For xrI = 0 To xrNG - 1
        xwGRank(xrI) = 0
        For xrJ = 0 To xrNG - 1
            If xwGW(xrJ) > xwGW(xrI) Or (xwGW(xrJ) = xwGW(xrI) And xrJ < xrI) Then xwGRank(xrI) = xwGRank(xrI) + 1
        Next xrJ
    Next xrI
    For xrI = 0 To XPD_GROUPS * 64 : xwBin(xrI) = 0 : Next xrI
    For xrS = 0 To XP_POOL - 1
        If xwKey(xrS) >= 0 Then
            xrK = xwGRank(xwKey(xrS)) * 64 + (xpLay(xrS) And 63)
            xwKey(xrS) = xrK
            xwBin(xrK + 1) = xwBin(xrK + 1) + 1
            xrN = xrN + 1
        End If
    Next xrS
    For xrI = 1 To XPD_GROUPS * 64 : xwBin(xrI) = xwBin(xrI) + xwBin(xrI - 1) : Next xrI
    For xrS = 0 To XP_POOL - 1
        If xwKey(xrS) >= 0 Then
            xwOrder(xwBin(xwKey(xrS))) = xrS
            xwBin(xwKey(xrS)) = xwBin(xwKey(xrS)) + 1
        End If
    Next xrS
    For xrI = 0 To xrN - 1
        XPD_Particle xwOrder(xrI)
    Next xrI
End Sub

' --- dev tooling and --explode ---

' assets/explosions.txt on disk: the launch folder (tools/dev run starts in the repository), else the repository relative to the executable's folder.
Function XPD_DevPath$ ()
    Dim xvA As String
    xvA = _StartDir$ + "/" + XPD_DEV_FILE
    If _FileExists(xvA) Then XPD_DevPath$ = xvA : Exit Function
    xvA = _Cwd$ + "/../" + XPD_DEV_FILE
    If _FileExists(xvA) Then XPD_DevPath$ = xvA : Exit Function
    XPD_DevPath$ = ""
End Function

Sub XPD_DevReload ()
    Dim xrPath As String, xrOk As Integer, xrBad As String
    xrPath = XPD_DevPath$
    If xrPath = "" Then
        xwMsg = "C: " + XPD_DEV_FILE + " not found (launch from the repository folder)"
        Exit Sub
    End If
    xrOk = XP_Parse%(_ReadFile$(xrPath))
    XP_Clear
    If xrOk Then
        xrBad = XP_Validate$
        If xrBad <> "" Then xrOk = 0 : xpErrors = xrBad
    End If
    If xrOk Then
        xwOff = 0
        xwMsg = "reloaded" + Str$(xdCnt)
        xwMsgAt = gameFrame
        If xwSel >= xdCnt Then xwSel = 0
    Else
        xwOff = -1
        xwMsg = xpErrors
    End If
End Sub

Sub XPD_Where (xaX As Single, xaY As Single, xaZ As Single)
    If boss.active Then
        xaX = boss.px : xaY = boss.py : xaZ = boss.pz
    Else
        xaX = player.px + XPD_AHEAD : xaY = player.py : xaZ = player.pz
    End If
End Sub

' Once per frame of play, after the pause check.
Sub XPD_Frame ()
    Dim xfI As Integer, xfX As Single, xfY As Single, xfZ As Single
    Dim xfKZ As Integer, xfKX As Integer, xfKC As Integer, xfKV As Integer
    If cliExplode <> "" And xwOff = 0 Then
        For xfI = 0 To xjCount - 1
            If xwDone(xfI) = 0 And gameFrame >= xjFrame(xfI) Then
                xwDone(xfI) = -1
                XPD_Boom XP_Find%(xjName(xfI)), player.px + XPD_AHEAD, player.py, player.pz, 0, 0, 0, 1
            End If
        Next xfI
    End If
    If cliExplosionDev = 0 Then Exit Sub
    xfKZ = KEY_Down%(90) Or KEY_Down%(122)
    xfKX = KEY_Down%(88) Or KEY_Down%(120)
    xfKC = KEY_Down%(67) Or KEY_Down%(99)
    xfKV = KEY_Down%(86) Or KEY_Down%(118)
    If xfKZ And xwWasZ = 0 And xdCnt > 0 Then xwSel = (xwSel + 1) Mod xdCnt
    If xfKX And xwWasX = 0 And xwOff = 0 Then
        XPD_Where xfX, xfY, xfZ
        XPD_Boom xwSel, xfX, xfY, xfZ, 0, 0, 0, 1
    End If
    If xfKC And xwWasC = 0 Then XPD_DevReload
    If xfKV And xwWasV = 0 And xwOff = 0 Then
        XPD_Where xfX, xfY, xfZ
        XPD_Boom xpIdBoss, xfX, xfY, xfZ, 0, 0, 0, 1
        For xfI = 0 To 7
            XPD_Boom xpIdEnemy, xfX - 3 + (xfI Mod 4) * 2, xfY + (xfI \ 4) * 3 - 1.5, xfZ + 3 - xfI, 0, 0, 0, 1
        Next xfI
    End If
    xwWasZ = xfKZ : xwWasX = xfKX : xwWasC = xfKC : xwWasV = xfKV
End Sub

Sub XPD_DevDraw ()
    Dim xvN As Integer, xvNL As Integer, xvS As String, xvRows(0 To XPD_DEV_ROWS - 1) As String
    If cliExplosionDev = 0 Then Exit Sub
    _Dest backBuffer
    If xdCnt > 0 Then xvS = xdName(xwSel) Else xvS = "-"
    xvS = "XP " + xvS + " live" + Str$(xpLive) + " drop" + Str$(xpDropped) + "  Z X C V"
    Line (0, scrH - FONT_CHAR_H - 1)-(Len(xvS) * FONT_CHAR_W + 3, scrH - 1), _RGBA(0, 0, 0, 200), BF
    FONT_PrintAlpha fontPalette(14), backBuffer, xvS, 2, scrH - FONT_CHAR_H - 1, 255
    If Len(xwMsg) > 0 Then
        If xwOff = 0 Then
            If gameFrame - xwMsgAt < XPD_NOTE_FRAMES Then UI_Text 10, xwMsg, Len(xvS) * FONT_CHAR_W + 8, scrH - FONT_CHAR_H - 1, 255
        Else
            xvN = BD_WrapText%(xwMsg, 40, xvRows(), XPD_DEV_ROWS)
            If xvN > XPD_DEV_ROWS Then xvRows(XPD_DEV_ROWS - 1) = "(and more)" : xvN = XPD_DEV_ROWS
            For xvNL = 0 To xvN - 1
                UI_Text 12, xvRows(xvNL), 2, scrH - FONT_CHAR_H * (2 + xvN - xvNL) - 2, 255
            Next xvNL
        End If
    End If
End Sub
