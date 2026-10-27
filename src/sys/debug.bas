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
        Case Else           : DBG_StateName$ = "GS_?" + LTrim$(Str$(dbgSnState))
    End Select
End Function

' Milestone log for the full-playthrough test (tests/playthrough/run.sh). Off unless
' the SSS_MILESTONE_LOG env var names a file (relative = the launch folder). Then the
' file is emptied at startup and gets one line for each frame on which gameState or
' the sequence step changed, plus EXIT when --frames ends the run:
'   <frame> <state> <seqIdx> [<label> <TASK> <task args>]
'   <frame> EXIT
Sub DBG_MilestoneInit()
    Dim dbgMiF As Integer
    dbgMlogPath = Environ$("SSS_MILESTONE_LOG")
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

    If KEY_Down%(96) And Not dbgGraveWas Then dbgOverlay = 1 - dbgOverlay
    dbgGraveWas = KEY_Down%(96)

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
