Sub DBG_Print(dbgMsg As String)
    If dbgTtyOK = 0 Then Exit Sub
    Dim dbgF As Integer
    dbgF = FreeFile
    Open "/dev/tty" For Append As #dbgF
    Print #dbgF, dbgMsg
    Close #dbgF
End Sub

Sub DBG_Overlay()
    Dim dbgFrameMs As Single
    Dim dbgPolyClr As Long, dbgFpsClr As Long, dbgFps As Single
    Dim dbgBi  As Integer
    Dim dbgBwx As Single, dbgBwy As Single, dbgBwz As Single
    Dim dbgBhx As Single, dbgBhy As Single, dbgBhz As Single
    Dim dbgBtx As Single, dbgBty As Single, dbgBtz As Single
    Dim dbgBpx As Single, dbgBpy As Single, dbgBpw As Single
    Dim dbgBsx(0 To 7) As Single, dbgBsy(0 To 7) As Single, dbgBsw(0 To 7) As Single
    Dim dbgBci As Integer, dbgBa As Integer, dbgBb As Integer, dbgBdiff As Integer
    Dim dbgBclr As Long

    If _KeyDown(96) And Not dbgGraveWas Then dbgOverlay = 1 - dbgOverlay
    dbgGraveWas = _KeyDown(96)

    dbgFrameMs = (Timer - dbgT0) * 1000

    If Not dbgOverlay Then Exit Sub

    If E3D_scnCount > 350 Then
        dbgPolyClr = _RGB(255, 80, 60)
    ElseIf E3D_scnCount > 200 Then
        dbgPolyClr = _RGB(255, 210, 50)
    Else
        dbgPolyClr = _RGB(80, 210, 80)
    End If
    If dbgFrameMs > 0.0001 Then dbgFps = 1000 / dbgFrameMs Else dbgFps = 999
    If dbgFps < 30 Then
        dbgFpsClr = _RGB(255, 80, 60)
    ElseIf dbgFps < 50 Then
        dbgFpsClr = _RGB(255, 210, 50)
    Else
        dbgFpsClr = _RGB(80, 210, 80)
    End If

    _Dest 0
    Line (0, 0)-(105, 76), _RGBA(0, 0, 0, 190), BF
    Color dbgPolyClr
    _PrintString (2,  2), "POLY " + LTrim$(Str$(E3D_scnCount)) + "/450"
    Color dbgFpsClr
    _PrintString (2, 12), "FPS  " + LTrim$(Str$(CInt(dbgFps)))
    Color _RGB(140, 140, 160)
    _PrintString (2, 22), "ms   " + Left$(Str$(dbgFrameMs + 1000), 6)
    Color _RGB(120, 200, 255)
    _PrintString (2, 34), "RY   " + Left$(Str$(player.ry + 1000), 7)
    _PrintString (2, 44), "RZ   " + Left$(Str$(player.rz + 1000), 7)
    Color _RGB(180, 255, 180)
    _PrintString (2, 54), "VY   " + Left$(Str$(playerVY + 1000), 7)
    _PrintString (2, 64), "VZ   " + Left$(Str$(playerVZ + 1000), 7)

    If gameState = GS_PLAYING Then
        dbgBclr = _RGB(0, 255, 120)
        For dbgBi = 1 To MAX_ENEMIES
            If enemies(dbgBi).active Then
                dbgBwx = enemies(dbgBi).px
                dbgBwy = enemies(dbgBi).py
                dbgBwz = enemies(dbgBi).pz
                dbgBhx = boxLib(enemies(dbgBi).meshIdx).hx
                dbgBhy = boxLib(enemies(dbgBi).meshIdx).hy
                dbgBhz = boxLib(enemies(dbgBi).meshIdx).hz
                For dbgBci = 0 To 7
                    If (dbgBci And 4) Then dbgBtx = dbgBwx + dbgBhx Else dbgBtx = dbgBwx - dbgBhx
                    If (dbgBci And 2) Then dbgBty = dbgBwy + dbgBhy Else dbgBty = dbgBwy - dbgBhy
                    If (dbgBci And 1) Then dbgBtz = dbgBwz + dbgBhz Else dbgBtz = dbgBwz - dbgBhz
                    dbgBpx  = dbgBtx * vpMat.m(0,0) + dbgBty * vpMat.m(0,1) + dbgBtz * vpMat.m(0,2) + vpMat.m(0,3)
                    dbgBpy  = dbgBtx * vpMat.m(1,0) + dbgBty * vpMat.m(1,1) + dbgBtz * vpMat.m(1,2) + vpMat.m(1,3)
                    dbgBpw  = dbgBtx * vpMat.m(3,0) + dbgBty * vpMat.m(3,1) + dbgBtz * vpMat.m(3,2) + vpMat.m(3,3)
                    dbgBsw(dbgBci) = dbgBpw
                    If dbgBpw > 0 Then
                        dbgBsx(dbgBci) = (dbgBpx / dbgBpw + 1.0) * scrW * 0.5
                        dbgBsy(dbgBci) = (1.0 - dbgBpy / dbgBpw) * scrH * 0.5
                    End If
                Next dbgBci
                For dbgBa = 0 To 6
                    For dbgBb = dbgBa + 1 To 7
                        dbgBdiff = dbgBa Xor dbgBb
                        If dbgBdiff = 1 Or dbgBdiff = 2 Or dbgBdiff = 4 Then
                            If dbgBsw(dbgBa) > 0 Then
                                If dbgBsw(dbgBb) > 0 Then
                                    Line (dbgBsx(dbgBa), dbgBsy(dbgBa))-(dbgBsx(dbgBb), dbgBsy(dbgBb)), dbgBclr
                                End If
                            End If
                        End If
                    Next dbgBb
                Next dbgBa
            End If
        Next dbgBi
    End If
End Sub
