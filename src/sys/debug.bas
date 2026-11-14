' Windows: there is no /dev/tty and no reliable way to detect a controlling console,
' so use --debug as the signal instead -- only show the $CONSOLE window (and log)
' when the user explicitly asked for it, so double-click launches stay silent.
' DBG_Print and GTEXT_Log check dbgTtyOK.
'
' Unix's /dev/tty probe stays inline in sss.bas rather than living here: QB64-PE
' rejects the ON ERROR GOTO / label pattern it needs ("Common label within a
' SUB/FUNCTION") when placed inside a SUB.
Sub DBG_InitTty()
    $IF WIN THEN
        IF debugMode THEN
            _Console On
            dbgTtyOK = -1
        END IF
    $END IF
End Sub

Sub DBG_LogStateChange()
    If debugMode = 0 Then Exit Sub
    If gameState = prevGameState Then Exit Sub
    DBG_Print "[state] " + DBG_StateName$(gameState)
End Sub

Function DBG_StateName$(dbgSnState As Integer)
    Select Case dbgSnState
        Case GS_TITLE    : DBG_StateName$ = "GS_TITLE"
        Case GS_PLAYING  : DBG_StateName$ = "GS_PLAYING"
        Case GS_GAMEOVER : DBG_StateName$ = "GS_GAMEOVER"
        Case GS_PLANET   : DBG_StateName$ = "GS_PLANET"
        Case GS_CINEMATIC: DBG_StateName$ = "GS_CINEMATIC"
        Case GS_INTRO    : DBG_StateName$ = "GS_INTRO"
        Case GS_CRAWL    : DBG_StateName$ = "GS_CRAWL"
        Case GS_OPTIONS  : DBG_StateName$ = "GS_OPTIONS"
        Case GS_ABOUT    : DBG_StateName$ = "GS_ABOUT"
        Case GS_LEADIN   : DBG_StateName$ = "GS_LEADIN"
        Case GS_CONSENT     : DBG_StateName$ = "GS_CONSENT"
        Case GS_USERNAME    : DBG_StateName$ = "GS_USERNAME"
        Case GS_LEADERBOARD : DBG_StateName$ = "GS_LEADERBOARD"
        Case GS_CONTROLS    : DBG_StateName$ = "GS_CONTROLS"
        Case GS_CRAWLS      : DBG_StateName$ = "GS_CRAWLS"
        Case GS_DOCK        : DBG_StateName$ = "GS_DOCK"
        Case GS_REMAP       : DBG_StateName$ = "GS_REMAP"
        Case Else           : DBG_StateName$ = "GS_?" + LTrim$(Str$(dbgSnState))
    End Select
End Function

' Milestone log for the full-playthrough test (tests/playthrough/run.sh). Off unless
' the SSS_MILESTONE_LOG env var names a file (relative = the launch folder). Then the
' file is emptied at startup and gets one line for each frame on which gameState or
' the sequence step changed, plus EXIT when --frames ends the run:
'   <frame> <state> <seqIdx> [<label> <TASK> <task args>]
'   <frame> NARR <label> <paragraph>   a crawl paragraph starts speaking (DBG_MilestoneNarr)
'   <frame> EXIT
Sub DBG_MilestoneInit()
    Dim dbgMiF As Integer
    $IF RELEASEBUILD = 1 THEN
        dbgMlogPath = ""
    $ELSE
        dbgMlogPath = Environ$("SSS_MILESTONE_LOG")
    $END IF
    If dbgMlogPath = "" Then Exit Sub
    If Left$(dbgMlogPath, 1) <> "/" And Mid$(dbgMlogPath, 2, 1) <> ":" Then dbgMlogPath = _StartDir$ + "/" + dbgMlogPath
    dbgMlogState = -1 : dbgMlogSeq = -2
    dbgMiF = FreeFile
    Open dbgMlogPath For Output As #dbgMiF
    Close #dbgMiF
End Sub

' Call once per frame; writes a line only when gameState or seqIdx changed.
Sub DBG_MilestoneLog()
    Dim dbgMlLine As String
    If dbgMlogPath = "" Then Exit Sub
    If gameState = dbgMlogState And seqIdx = dbgMlogSeq Then Exit Sub
    dbgMlogState = gameState : dbgMlogSeq = seqIdx
    dbgMlLine = LTrim$(Str$(gameFrame)) + " " + DBG_StateName$(gameState) + " " + LTrim$(Str$(seqIdx))
    If seqIdx >= 0 And seqIdx < seqCount Then
        dbgMlLine = dbgMlLine + " " + seqLabel$(seqIdx)
        Select Case seqKind(seqIdx)
            Case SEQ_CRAWL   : dbgMlLine = dbgMlLine + " CRAWL"
            Case SEQ_EMPEROR : dbgMlLine = dbgMlLine + " CARD"
            Case SEQ_PLAY    : dbgMlLine = dbgMlLine + " PLAY"
            Case SEQ_TITLE   : dbgMlLine = dbgMlLine + " TITLE"
            Case SEQ_ARRIVE  : dbgMlLine = dbgMlLine + " ARRIVE"
            Case SEQ_DOCK    : dbgMlLine = dbgMlLine + " DOCK"
            Case Else        : dbgMlLine = dbgMlLine + " ?"
        End Select
        dbgMlLine = RTrim$(dbgMlLine + " " + seqSval$(seqIdx))
    End If
    DBG_MilestoneWrite dbgMlLine
End Sub

' Call once per crawl frame, after CRAWL_Step%: a NARR line for each paragraph the crawl
' started since the last call (fast-forward can start more than one in a frame).
Sub DBG_MilestoneNarr()
    Dim dbgMnLab As String
    If dbgMlogPath = "" Then Exit Sub
    dbgMnLab = "-"
    If seqIdx >= 0 And seqIdx < seqCount Then dbgMnLab = seqLabel$(seqIdx)
    Do While dbgMlogNarr < crawlSaidCount
        DBG_MilestoneWrite LTrim$(Str$(gameFrame)) + " NARR " + dbgMnLab + " " + LTrim$(Str$(dbgMlogNarr))
        dbgMlogNarr = dbgMlogNarr + 1
    Loop
End Sub

Sub DBG_MilestoneWrite(dbgMwLine As String)
    Dim dbgMwF As Integer
    If dbgMlogPath = "" Then Exit Sub
    dbgMwF = FreeFile
    Open dbgMlogPath For Append As #dbgMwF
    Print #dbgMwF, dbgMwLine
    Close #dbgMwF
End Sub

Sub DBG_Print(dbgMsg As String)
    If dbgTtyOK = 0 Then Exit Sub
    $IF WIN THEN
        _Dest _Console
        Print dbgMsg
        _Dest 0
    $ELSE
        Dim dbgF As Integer
        dbgF = FreeFile
        Open "/dev/tty" For Append As #dbgF
        Print #dbgF, dbgMsg
        Close #dbgF
    $END IF
End Sub

Const DBG_TRAJ_FRAMES = 200   ' frames of motion drawn for a rock that is not moving toward the despawn line

' Wireframe of the AABB centred on (dbCx, dbCy, dbCz), projected through vpMat; an edge is drawn only when both ends are in front of the camera.
Sub DBG_DrawBox(dbCx As Single, dbCy As Single, dbCz As Single, dbBox As E3D_AABB, dbClr As Long)
    Dim dbTx As Single, dbTy As Single, dbTz As Single
    Dim dbPx As Single, dbPy As Single, dbPw As Single
    Dim dbSx(0 To 7) As Single, dbSy(0 To 7) As Single, dbSw(0 To 7) As Single
    Dim dbCi As Integer, dbA As Integer, dbB As Integer, dbDiff As Integer
    For dbCi = 0 To 7
        If (dbCi And 4) Then dbTx = dbCx + dbBox.hx Else dbTx = dbCx - dbBox.hx
        If (dbCi And 2) Then dbTy = dbCy + dbBox.hy Else dbTy = dbCy - dbBox.hy
        If (dbCi And 1) Then dbTz = dbCz + dbBox.hz Else dbTz = dbCz - dbBox.hz
        dbPx = dbTx * vpMat.m(0,0) + dbTy * vpMat.m(0,1) + dbTz * vpMat.m(0,2) + vpMat.m(0,3)
        dbPy = dbTx * vpMat.m(1,0) + dbTy * vpMat.m(1,1) + dbTz * vpMat.m(1,2) + vpMat.m(1,3)
        dbPw = dbTx * vpMat.m(3,0) + dbTy * vpMat.m(3,1) + dbTz * vpMat.m(3,2) + vpMat.m(3,3)
        dbSw(dbCi) = dbPw
        If dbPw > 0 Then
            dbSx(dbCi) = (dbPx / dbPw + 1.0) * scrW * 0.5
            dbSy(dbCi) = (1.0 - dbPy / dbPw) * scrH * 0.5
        End If
    Next dbCi
    For dbA = 0 To 6
        For dbB = dbA + 1 To 7
            dbDiff = dbA Xor dbB
            If dbDiff = 1 Or dbDiff = 2 Or dbDiff = 4 Then
                If dbSw(dbA) > 0 Then
                    If dbSw(dbB) > 0 Then
                        Line (dbSx(dbA), dbSy(dbA))-(dbSx(dbB), dbSy(dbB)), dbClr
                    End If
                End If
            End If
        Next dbB
    Next dbA
End Sub

' Straight line from an asteroid along its velocity to the despawn line (px = player.px - 20); a rock not moving toward it gets DBG_TRAJ_FRAMES of motion.
Sub DBG_DrawTrajectory(dtI As Integer)
    Dim dtEx As Single, dtEy As Single, dtEz As Single, dtN As Single
    Dim dtSx0 As Single, dtSy0 As Single, dtSx1 As Single, dtSy1 As Single
    Dim dtOk0 As Integer, dtOk1 As Integer
    dtN = DBG_TRAJ_FRAMES
    If asteroids(dtI).vx < 0 Then
        dtN = (player.px - 20 - asteroids(dtI).px) / asteroids(dtI).vx
        If dtN < 0 Then dtN = 0
    End If
    dtEx = asteroids(dtI).px + asteroids(dtI).vx * dtN
    dtEy = asteroids(dtI).py + asteroids(dtI).vy * dtN
    dtEz = asteroids(dtI).pz + asteroids(dtI).vz * dtN
    COMBAT_Project asteroids(dtI).px, asteroids(dtI).py, asteroids(dtI).pz, dtSx0, dtSy0, dtOk0
    COMBAT_Project dtEx, dtEy, dtEz, dtSx1, dtSy1, dtOk1
    If dtOk0 Then
        If dtOk1 Then Line (dtSx0, dtSy0)-(dtSx1, dtSy1), _RGB(200, 200, 200)
    End If
End Sub

Sub DBG_Overlay()
    Dim dbgFrameMs As Single
    Dim dbgPolyClr As Long, dbgFpsClr As Long, dbgFps As Single
    Dim dbgBi  As Integer

    If KEY_Down%(96) And Not dbgGraveWas Then dbgOverlay = 1 - dbgOverlay
    dbgGraveWas = KEY_Down%(96)
    If KEY_Down%(17152) And Not dbgF9Was Then dbgTraj = 1 - dbgTraj
    dbgF9Was = KEY_Down%(17152)

    If gameState = GS_PLAYING And dbgTraj <> 0 Then
        _Dest 0
        For dbgBi = 1 To MAX_ASTEROIDS
            If asteroids(dbgBi).active Then DBG_DrawTrajectory dbgBi
        Next dbgBi
    End If

    dbgFrameMs = (Timer - dbgT0) * 1000

    If dbgOverlay = 0 Then Exit Sub

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
        For dbgBi = 1 To MAX_ENEMIES
            If enemies(dbgBi).active Then DBG_DrawBox enemies(dbgBi).px, enemies(dbgBi).py, enemies(dbgBi).pz, boxLib(enemies(dbgBi).meshIdx), _RGB(0, 255, 120)
        Next dbgBi
        For dbgBi = 1 To MAX_ASTEROIDS
            If asteroids(dbgBi).active Then DBG_DrawBox asteroids(dbgBi).px, asteroids(dbgBi).py, asteroids(dbgBi).pz, boxLib(MESH_ASTEROID), _RGB(255, 140, 0)
        Next dbgBi
        DBG_DrawBox player.px, player.py, player.pz, boxLib(MESH_PLAYER), _RGB(0, 220, 255)
    End If
End Sub
