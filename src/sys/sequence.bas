' sequence.bas -- linear game-flow sequencer
'
' sequence.txt block format:
'   label:id              section header (id appended -> --scene name "labelid")
'     TASK key=val ...    task line (must be indented)
'
' Task types: CRAWL EMPEROR TITLE PLAY ARRIVE DOCK
'   CRAWL  txt=<gtext-key>  mus=<cue>
'   EMPEROR mus=<cue>
'   TITLE  mus=<cue>
'   PLAY   type=combat|boss|asteroid  mus=<cue>  [trigger=<n>]
'     trigger: enemy kills that end the combat phase (nerf: * NERF_FACTOR, at least 1)
'   ARRIVE mus=<cue>
'   DOCK   [mus=<cue>]   upgrade dock (src/state/dock.bas); none after the last stage
'
' Writes a line to the CLI output stream. On Windows the QB64-PE console has no
' Win32 CON: device to OPEN, so output must go through _DEST _CONSOLE + PRINT
' instead of a file handle; the caller is expected to have already done
' _CONSOLE ON / _DEST _CONSOLE on Windows before calling this.
Sub CLI_Emit(ceFH As Integer, ceMsg As String)
    If InStr(_OS$, "WIN") Then
        Print ceMsg
    Else
        Print #ceFH, ceMsg
    End If
End Sub

' All callers:
'   sss.bas  startup           : SEQ_Load _EMBEDDED$("SEQTXT")
'   game.bas GAME_NewGame      : SEQ_Load _EMBEDDED$("SEQTXT") : SEQ_Advance
'   sss.bas  GS_INTRO SPACE    : SEQ_Advance
'   sss.bas  GS_CRAWL ends     : SEQ_Advance
'   boss.bas  score threshold  : SEQ_Advance  (-> boss or arrive)
'   boss.bas  boss defeated    : SEQ_Advance  (-> arrive)
'   wave.bas  asteroid done    : SEQ_Advance  (-> arrive)
'   stage.bas cinematic done   : SEQ_Advance  (-> next crawl or title)

Const SEQ_MAX     = 64
Const SEQ_CRAWL   = 1
Const SEQ_EMPEROR = 2
Const SEQ_PLAY    = 3
Const SEQ_TITLE   = 4
Const SEQ_ARRIVE  = 5
Const SEQ_DOCK    = 6

Dim Shared seqKind(0 To SEQ_MAX - 1)   As Integer
Dim Shared seqSval$(0 To SEQ_MAX - 1)
Dim Shared seqLabel$(0 To SEQ_MAX - 1)
Dim Shared seqCount     As Integer
Dim Shared seqIdx       As Integer
Dim Shared seqLastError As String

' Named crawls: every CRAWL task in sequence.txt, plus crawls the code starts
' directly. SEQ_ListCrawls builds the list; --scene crawl:<key>, the --help scene
' list and the --crawls browser all read it, so it is the one complete list.
Const SEQ_CRAWL_DEATH = "death_final"   ' started by playing.bas on game over
Const SEQ_CRAWL_STRANDED = "stranded_final"   ' started by dock.bas when the run ends stranded (#277)

Dim Shared seqCrawlCount As Integer
Dim Shared seqCrawlKey$(0 To SEQ_MAX - 1)
Dim Shared seqCrawlUse$(0 To SEQ_MAX - 1)   ' sequence label, or what triggers it in code
Dim Shared seqCrawlAt(0 To SEQ_MAX - 1) As Integer   ' sequence index; -1 = started by code
Dim Shared seqJumpCrawl$   ' set by SEQ_JumpToScene when --scene names a code-started crawl

' Every --scene type (#334). CLI_Parse accepts exactly these (plus crawl:<key>) and
' SEQ_SceneList$ can only list these, so --help and the parser cannot drift apart.
' consent and username are started by sss.bas itself, not by the sequence.
Const SEQ_SCENE_TYPES = " crawl playing boss dock title emperor consent username "

' The scene type of a --scene name: trailing digits stripped, lowercased; "crawl:" for crawl:<key>.
Function SEQ_SceneType$(sstSpec As String)
    Dim sstI As Integer
    If LCase$(Left$(sstSpec, 6)) = "crawl:" Then SEQ_SceneType$ = "crawl:" : Exit Function
    sstI = Len(sstSpec)
    Do While sstI > 0
        If Mid$(sstSpec, sstI, 1) >= "0" And Mid$(sstSpec, sstI, 1) <= "9" Then sstI = sstI - 1 Else Exit Do
    Loop
    SEQ_SceneType$ = LCase$(Left$(sstSpec, sstI))
End Function

Function SEQ_SceneTypeOk%(sstoType As String)
    If sstoType = "crawl:" Then SEQ_SceneTypeOk% = -1 : Exit Function
    SEQ_SceneTypeOk% = (sstoType <> "" And InStr(SEQ_SCENE_TYPES, " " + sstoType + " ") > 0)
End Function

Sub SEQ_AddCrawl(seqacKey As String, seqacUse As String, seqacAt As Integer)
    Dim seqacI As Integer
    If Len(seqacKey) = 0 Or seqCrawlCount >= SEQ_MAX Then Exit Sub
    For seqacI = 0 To seqCrawlCount - 1
        If seqCrawlKey$(seqacI) = seqacKey Then Exit Sub
    Next seqacI
    seqCrawlKey$(seqCrawlCount) = seqacKey
    seqCrawlUse$(seqCrawlCount) = seqacUse
    seqCrawlAt(seqCrawlCount) = seqacAt
    seqCrawlCount = seqCrawlCount + 1
End Sub

' Sequence crawls in play order, then code-started ones. Call after SEQ_Load.
Sub SEQ_ListCrawls()
    Dim seqlcI As Integer
    seqCrawlCount = 0
    For seqlcI = 0 To seqCount - 1
        If seqKind(seqlcI) = SEQ_CRAWL Then SEQ_AddCrawl SEQ_GetKV$(seqSval$(seqlcI), "txt"), seqLabel$(seqlcI), seqlcI
    Next seqlcI
    SEQ_AddCrawl SEQ_CRAWL_DEATH, "game over", -1
    SEQ_AddCrawl SEQ_CRAWL_STRANDED, "stranded at a dock", -1
End Sub

' The leg after the current task (the dock): its PLAY tasks up to the next ARRIVE, as the
' combat kill triggers summed, the boss fights' secs= summed (#90), the boss fights with no
' secs= (economy.ini fuel_boss_secs each) and asteroid fields (SUP_LegNeed!'s fuel need).
' All zero when no leg follows.
Sub SEQ_NextLeg(seqnKills As Long, seqnBossSecs As Single, seqnBoss As Integer, seqnAst As Integer)
    Dim seqnI As Integer, seqnType As String, seqnSecs As String
    seqnKills = 0 : seqnBossSecs = 0 : seqnBoss = 0 : seqnAst = 0
    For seqnI = seqIdx + 1 To seqCount - 1
        If seqKind(seqnI) = SEQ_ARRIVE Or seqKind(seqnI) = SEQ_TITLE Then Exit For
        If seqKind(seqnI) = SEQ_PLAY Then
            seqnType = LCase$(SEQ_GetKV$(seqSval$(seqnI), "type"))
            Select Case seqnType
                Case "combat" : seqnKills = seqnKills + Val(SEQ_GetKV$(seqSval$(seqnI), "trigger"))
                Case "boss"
                    seqnSecs = SEQ_GetKV$(seqSval$(seqnI), "secs")
                    If Len(seqnSecs) > 0 Then seqnBossSecs = seqnBossSecs + Val(seqnSecs) Else seqnBoss = seqnBoss + 1
                Case "asteroid" : seqnAst = seqnAst + 1
            End Select
        End If
    Next seqnI
End Sub

' A combat stage ends on enemy kills, not score (#312): power-ups and bonuses only add points.
' stageKills counts ships shot down or caught in a Nova; asteroids and the boss's spores don't count.
Function SEQ_StageCleared%
    SEQ_StageCleared% = (stageKills >= stageKillTarget)
End Function

' 0..1 share of the combat stage's kill target reached (the approaching planet's size).
Function SEQ_StageProgress!
    Dim seqpP As Single
    If stageKillTarget <= 0 Then SEQ_StageProgress! = 1.0 : Exit Function
    seqpP = stageKills / CSng(stageKillTarget)
    If seqpP < 0.0 Then seqpP = 0.0
    If seqpP > 1.0 Then seqpP = 1.0
    SEQ_StageProgress! = seqpP
End Function

Sub SEQ_Add(seqaKind As Integer, seqaSval As String, seqaLabel As String)
    If seqCount >= SEQ_MAX Then Exit Sub
    seqKind(seqCount)   = seqaKind
    seqSval$(seqCount)  = seqaSval
    seqLabel$(seqCount) = seqaLabel
    seqCount = seqCount + 1
End Sub

' Splits "a,b,c" into sscOut$(0..) (at most 8 entries); empty entries are kept, so
' ",x,y" gives "", "x", "y".
Sub SEQ_SplitCSV(sscSrc As String, sscOut() As String, sscCnt As Integer)
    Dim sscStart As Integer, sscComma As Integer
    sscCnt = 0 : sscStart = 1
    Do While sscStart <= Len(sscSrc) And sscCnt < 8
        sscComma = InStr(sscStart, sscSrc, ",")
        If sscComma = 0 Then sscComma = Len(sscSrc) + 1
        sscOut(sscCnt) = Mid$(sscSrc, sscStart, sscComma - sscStart)
        sscCnt = sscCnt + 1
        sscStart = sscComma + 1
    Loop
End Sub

' Extract value for key from a "key=val key2=val2 ..." string.
Function SEQ_GetKV$(seqgSval As String, seqgKey As String)
    Dim seqgSearch As String, seqgI As Integer, seqgStart As Integer, seqgEnd As Integer
    seqgSearch = LCase$(seqgKey) + "="
    seqgI = InStr(LCase$(seqgSval), seqgSearch)
    If seqgI = 0 Then SEQ_GetKV$ = "" : Exit Function
    seqgStart = seqgI + Len(seqgSearch)
    seqgEnd   = InStr(seqgStart, seqgSval, " ")
    If seqgEnd = 0 Then seqgEnd = Len(seqgSval) + 1
    SEQ_GetKV$ = Mid$(seqgSval, seqgStart, seqgEnd - seqgStart)
End Function

' Parse the embedded sequence.txt block format and populate the sequence table.
Sub SEQ_Load(seqlData As String)
    Dim seqlI As Integer, seqlNL As Integer
    Dim seqlRaw As String, seqlLine As String
    Dim seqlKindStr As String, seqlSval As String, seqlSp As Integer
    Dim seqlLabel As String, seqlColon As Integer
    seqCount = 0 : seqIdx = -1
    seqlLabel = ""
    seqlI = 1
    Do While seqlI <= Len(seqlData)
        seqlNL = InStr(seqlI, seqlData, Chr$(10))
        If seqlNL = 0 Then seqlNL = Len(seqlData) + 1
        seqlRaw  = Mid$(seqlData, seqlI, seqlNL - seqlI)
        seqlI    = seqlNL + 1
        If Right$(seqlRaw, 1) = Chr$(13) Then seqlRaw = Left$(seqlRaw, Len(seqlRaw) - 1)
        seqlLine = LTrim$(RTrim$(seqlRaw))
        If Len(seqlLine) = 0 Or Left$(seqlLine, 1) = ";" Then GoTo seqlNext
        If Left$(seqlRaw, 1) = " " Or Left$(seqlRaw, 1) = Chr$(9) Then
            ' indented task line under current label
            seqlSp = InStr(seqlLine, " ")
            If seqlSp > 0 Then
                seqlKindStr = UCase$(Left$(seqlLine, seqlSp - 1))
                seqlSval    = Mid$(seqlLine, seqlSp + 1)
            Else
                seqlKindStr = UCase$(seqlLine)
                seqlSval    = ""
            End If
            Select Case seqlKindStr
                Case "CRAWL"            : SEQ_Add SEQ_CRAWL,   seqlSval, seqlLabel
                Case "CARD", "EMPEROR"  : SEQ_Add SEQ_EMPEROR,  seqlSval, seqlLabel
                Case "TITLE"            : SEQ_Add SEQ_TITLE,    seqlSval, seqlLabel
                Case "PLAY"             : SEQ_Add SEQ_PLAY,     seqlSval, seqlLabel
                Case "ARRIVE"           : SEQ_Add SEQ_ARRIVE,   seqlSval, seqlLabel
                Case "DOCK"             : SEQ_Add SEQ_DOCK,     seqlSval, seqlLabel
            End Select
        Else
            ' label header: "name:id" or "name:"
            seqlColon = InStr(seqlLine, ":")
            If seqlColon > 0 Then
                seqlLabel = Left$(seqlLine, seqlColon - 1) + Mid$(seqlLine, seqlColon + 1)
            Else
                seqlLabel = seqlLine
            End If
        End If
        seqlNext:
    Loop
End Sub

' Rewind seqIdx to the first SEQ_TITLE waypoint.
Sub SEQ_RewindToTitle()
    Dim seqrI As Integer
    For seqrI = 0 To seqCount - 1
        If seqKind(seqrI) = SEQ_TITLE Then seqIdx = seqrI : Exit Sub
    Next seqrI
End Sub

' Jump to a named scene. Spec format: crawlN, playingN, bossN, title, emperor.
'   crawl0   -> CRAWL task in label "crawl0"  (intro crawl)
'   crawlN   -> CRAWL task in label "levelN"  (N >= 1)
'   playingN -> first PLAY type=combat in label "levelN"
'   bossN    -> first PLAY type=boss   in label "levelN"
'   title    -> first SEQ_TITLE entry
'   emperor  -> first SEQ_EMPEROR entry
' Returns target sequence index, or -1 on error (seqLastError set).
Function SEQ_JumpToScene%(seqjSpec As String)
    Dim seqjI As Integer, seqjLast As Integer
    Dim seqjType As String, seqjNum As Integer, seqjHasNum As Integer
    Dim seqjTargetLabel As String, seqjTaskKind As Integer
    Dim seqjPlaySub As String, seqjLabelFound As Integer
    Dim seqjCKey As String, seqjAt As Integer

    ' crawl:<key> -- any named crawl. A sequence crawl resumes the sequence from there;
    ' a code-started one (seqJumpCrawl$) plays and then continues to the title.
    seqJumpCrawl$ = ""
    If LCase$(Left$(seqjSpec, 6)) = "crawl:" Then
        seqjCKey = LCase$(Mid$(seqjSpec, 7))
        SEQ_ListCrawls
        For seqjI = 0 To seqCrawlCount - 1
            If LCase$(seqCrawlKey$(seqjI)) = seqjCKey Then
                If seqCrawlAt(seqjI) >= 0 Then
                    seqIdx = seqCrawlAt(seqjI) - 1
                    SEQ_JumpToScene% = seqCrawlAt(seqjI)
                Else
                    seqjAt = -1
                    For seqjLast = 0 To seqCount - 1
                        If seqKind(seqjLast) = SEQ_TITLE Then seqjAt = seqjLast : Exit For
                    Next seqjLast
                    If seqjAt >= 0 Then
                        seqIdx = seqjAt - 1
                        seqJumpCrawl$ = seqCrawlKey$(seqjI)
                    Else
                        seqLastError = "--scene '" + seqjSpec + "': sequence.txt has no TITLE to return to"
                    End If
                    SEQ_JumpToScene% = seqjAt
                End If
                Exit Function
            End If
        Next seqjI
        seqLastError = "--scene '" + seqjSpec + "': no crawl named '" + seqjCKey + "' (see --help for the list)"
        SEQ_JumpToScene% = -1 : Exit Function
    End If

    ' split trailing digits from type name
    seqjLast = Len(seqjSpec)
    Do While seqjLast > 0
        If Mid$(seqjSpec, seqjLast, 1) >= "0" And Mid$(seqjSpec, seqjLast, 1) <= "9" Then
            seqjLast = seqjLast - 1
        Else
            Exit Do
        End If
    Loop
    seqjType   = LCase$(Left$(seqjSpec, seqjLast))
    seqjHasNum = (seqjLast < Len(seqjSpec))
    If seqjHasNum Then seqjNum = Val(Mid$(seqjSpec, seqjLast + 1)) Else seqjNum = 0

    Select Case seqjType
        Case "title"
            seqjTaskKind    = SEQ_TITLE
            seqjTargetLabel = ""
        Case "emperor"
            seqjTaskKind    = SEQ_EMPEROR
            seqjTargetLabel = ""
        Case "crawl"
            seqjTaskKind    = SEQ_CRAWL
            If seqjNum = 0 Then seqjTargetLabel = "crawl0" Else seqjTargetLabel = "level" + LTrim$(Str$(seqjNum))
        Case "playing"
            seqjTaskKind    = SEQ_PLAY
            seqjPlaySub     = "playing"   ' matches combat or asteroid (not boss)
            seqjTargetLabel = "level" + LTrim$(Str$(seqjNum))
        Case "boss"
            seqjTaskKind    = SEQ_PLAY
            seqjPlaySub     = "boss"
            seqjTargetLabel = "level" + LTrim$(Str$(seqjNum))
        Case "dock"
            seqjTaskKind    = SEQ_DOCK
            seqjTargetLabel = "level" + LTrim$(Str$(seqjNum))
        Case Else
            seqLastError = "--scene '" + seqjSpec + "': unknown type '" + seqjType + "'"
            SEQ_JumpToScene% = -1 : Exit Function
    End Select

    ' scan sequence table
    seqjLabelFound = 0
    For seqjI = 0 To seqCount - 1
        If seqjTargetLabel <> "" And seqLabel$(seqjI) = seqjTargetLabel Then seqjLabelFound = -1
        If seqKind(seqjI) = seqjTaskKind Then
            If seqjTargetLabel = "" Or seqLabel$(seqjI) = seqjTargetLabel Then
                Dim seqjPType As String
                seqjPType = LCase$(SEQ_GetKV$(seqSval$(seqjI), "type"))
                Dim seqjMatch As Integer
                If Len(seqjPlaySub) = 0 Then
                    seqjMatch = -1
                ElseIf seqjPlaySub = "playing" Then
                    seqjMatch = (seqjPType = "combat" Or seqjPType = "asteroid")
                Else
                    seqjMatch = (seqjPType = seqjPlaySub)
                End If
                If seqjMatch Then
                    seqIdx = seqjI - 1
                    SEQ_JumpToScene% = seqjI
                    Exit Function
                End If
            End If
        End If
    Next seqjI

    ' build specific error
    If seqjTargetLabel <> "" And seqjLabelFound = 0 Then
        seqLastError = "--scene '" + seqjSpec + "': label '" + seqjTargetLabel + "' not found in sequence.txt"
    ElseIf seqjTaskKind = SEQ_DOCK Then
        seqLastError = "--scene '" + seqjSpec + "': label '" + seqjTargetLabel + "' has no DOCK task (there is no dock after the last stage)"
    ElseIf Len(seqjPlaySub) > 0 Then
        Dim seqjSubName As String
        If seqjPlaySub = "playing" Then seqjSubName = "combat or asteroid" Else seqjSubName = seqjPlaySub
        seqLastError = "--scene '" + seqjSpec + "': label '" + seqjTargetLabel + "' has no " + seqjSubName + " task"
    Else
        seqLastError = "--scene '" + seqjSpec + "': not found"
    End If
    SEQ_JumpToScene% = -1
End Function

' Format a sorted number list as [min-max] if contiguous (and seqfnRange), else [n,n,...].
Function SEQ_FmtNums$(seqfnNums() As Integer, seqfnCnt As Integer, seqfnRange As Integer)
    Dim seqfnJ As Integer, seqfnOut As String
    If seqfnRange And seqfnNums(seqfnCnt - 1) - seqfnNums(0) + 1 = seqfnCnt Then
        SEQ_FmtNums$ = "[" + LTrim$(Str$(seqfnNums(0))) + "-" + LTrim$(Str$(seqfnNums(seqfnCnt - 1))) + "]"
        Exit Function
    End If
    seqfnOut = "["
    For seqfnJ = 0 To seqfnCnt - 1
        If seqfnJ > 0 Then seqfnOut = seqfnOut + ","
        seqfnOut = seqfnOut + LTrim$(Str$(seqfnNums(seqfnJ)))
    Next seqfnJ
    SEQ_FmtNums$ = seqfnOut + "]"
End Function

' Valid --scene names for --help, one per line (each ending in Chr$(10)), grouped as
' ranges or lists. Walks SEQ_SCENE_TYPES, so it can only list types CLI_Parse accepts.
Function SEQ_SceneList$()
    Dim seqpI As Integer, seqpN As Integer, seqpLabel As String
    Dim seqpCNums(0 To SEQ_MAX - 1) As Integer, seqpCCnt As Integer
    Dim seqpPNums(0 To SEQ_MAX - 1) As Integer, seqpPCnt As Integer
    Dim seqpBNums(0 To SEQ_MAX - 1) As Integer, seqpBCnt As Integer
    Dim seqpDNums(0 To SEQ_MAX - 1) As Integer, seqpDCnt As Integer
    Dim seqpHasTitle As Integer, seqpHasEmp As Integer
    Dim seqpJ As Integer, seqpTypes As String, seqpType As String
    Dim seqpOut As String, seqpLine As String

    For seqpI = 0 To seqCount - 1
        seqpLabel = seqLabel$(seqpI)
        If seqpLabel = "crawl0" And seqKind(seqpI) = SEQ_CRAWL Then
            seqpCNums(seqpCCnt) = 0 : seqpCCnt = seqpCCnt + 1
        ElseIf seqpLabel = "title" And seqKind(seqpI) = SEQ_TITLE Then
            seqpHasTitle = -1
        ElseIf seqpLabel = "emperor" And seqKind(seqpI) = SEQ_EMPEROR Then
            seqpHasEmp = -1
        ElseIf Left$(seqpLabel, 5) = "level" Then
            seqpN = Val(Mid$(seqpLabel, 6))
            Select Case seqKind(seqpI)
                Case SEQ_CRAWL
                    seqpCNums(seqpCCnt) = seqpN : seqpCCnt = seqpCCnt + 1
                Case SEQ_DOCK
                    seqpDNums(seqpDCnt) = seqpN : seqpDCnt = seqpDCnt + 1
                Case SEQ_PLAY
                    Select Case LCase$(SEQ_GetKV$(seqSval$(seqpI), "type"))
                        Case "combat", "asteroid"
                            seqpPNums(seqpPCnt) = seqpN : seqpPCnt = seqpPCnt + 1
                        Case "boss"
                            seqpBNums(seqpBCnt) = seqpN : seqpBCnt = seqpBCnt + 1
                    End Select
            End Select
        End If
    Next seqpI

    seqpTypes = LTrim$(SEQ_SCENE_TYPES)
    Do While seqpTypes <> ""
        seqpJ = InStr(seqpTypes, " ")
        seqpType = Left$(seqpTypes, seqpJ - 1)
        seqpTypes = LTrim$(Mid$(seqpTypes, seqpJ + 1))
        seqpLine = ""
        Select Case seqpType
            Case "crawl"
                If seqpCCnt > 0 Then seqpLine = seqpType + SEQ_FmtNums$(seqpCNums(), seqpCCnt, -1)
            Case "playing"
                If seqpPCnt > 0 Then seqpLine = seqpType + SEQ_FmtNums$(seqpPNums(), seqpPCnt, -1)
            Case "boss"
                If seqpBCnt > 0 Then seqpLine = seqpType + SEQ_FmtNums$(seqpBNums(), seqpBCnt, -1)
            Case "dock"
                If seqpDCnt > 0 Then seqpLine = seqpType + SEQ_FmtNums$(seqpDNums(), seqpDCnt, 0)
            Case "title"
                If seqpHasTitle Then seqpLine = seqpType
            Case "emperor"
                If seqpHasEmp Then seqpLine = seqpType
            Case Else
                seqpLine = seqpType
        End Select
        If seqpLine <> "" Then seqpOut = seqpOut + "  " + seqpLine + Chr$(10)
    Loop
    SEQ_ListCrawls
    For seqpJ = 0 To seqCrawlCount - 1
        seqpLine = "  crawl:" + seqCrawlKey$(seqpJ)
        If Len(seqpLine) < 24 Then seqpLine = seqpLine + Space$(24 - Len(seqpLine))
        seqpOut = seqpOut + seqpLine + "(" + seqCrawlUse$(seqpJ) + ")" + Chr$(10)
    Next seqpJ
    SEQ_SceneList$ = seqpOut
End Function

' Print valid --scene names to file handle fh.
Sub SEQ_PrintScenes(seqpFH As Integer)
    Dim seqpsList As String, seqpsPos As Integer
    seqpsList = SEQ_SceneList$
    Do While seqpsList <> ""
        seqpsPos = InStr(seqpsList, Chr$(10))
        CLI_Emit seqpFH, Left$(seqpsList, seqpsPos - 1)
        seqpsList = Mid$(seqpsList, seqpsPos + 1)
    Loop
End Sub

' Advance to the next sequence step and execute it.
Sub SEQ_Advance()
    Dim seqaType As String, seqaMus As String, seqaTrig As Integer
    seqIdx = seqIdx + 1
    If seqIdx >= seqCount Then
        CR_CashOutWin
        telemExitReason = "win"
        TELEM_SessionEnd
        SEQ_RewindToTitle
        gameState = GS_TITLE
        MUS_SetCue "title"
        Exit Sub
    End If
    Select Case seqKind(seqIdx)
        Case SEQ_CRAWL
            StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
            CRAWL_Prep SEQ_GetKV$(seqSval$(seqIdx), "txt"), scrH
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus
            gameState = GS_CRAWL
        Case SEQ_EMPEROR
            introTimer = 0
            gameState  = GS_INTRO
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus Else MUS_SetCue "emperor"
        Case SEQ_PLAY
            seqaType = LCase$(SEQ_GetKV$(seqSval$(seqIdx), "type"))
            seqaMus  = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            Select Case seqaType
                Case "combat"
                    levelNum  = levelNum + 1
                    levelType = LEVEL_COMBAT
                    bltActive = 0
                    seqaTrig  = Val(SEQ_GetKV$(seqSval$(seqIdx), "trigger"))
                    If seqaTrig = 0 Then seqaTrig = 10
                    stageKills      = 0
                    spawnTimer      = 0
                    waveStageN      = 0
                    planetTimer     = 0   ' an unfinished arrival must not draw last chapter's planet here (#168)
                    planetBgR       = 3.0
                    planetBgAlpha   = 245.0
                    If settingNerf Then
                        stageKillTarget = CLng(seqaTrig * NERF_FACTOR)
                        If stageKillTarget < 1 Then stageKillTarget = 1
                    Else
                        stageKillTarget = seqaTrig
                    End If
                    If diffTime < (levelNum - 1) * (DIFF_RAMP_DURATION / DIFF_STAGE_COUNT) Then
                        diffTime = (levelNum - 1) * (DIFF_RAMP_DURATION / DIFF_STAGE_COUNT)
                    End If
                    diffScale = diffTime / DIFF_RAMP_DURATION
                    If diffScale > 1.0 Then diffScale = 1.0
                    MUS_SetCue seqaMus
                    StarfieldReset player.px - CAM_OFFSET_X, CAM_OFFSET_Y, 0
                    gameState = GS_PLAYING
                Case "boss"
                    ' stageKillTarget set to max so combat trigger won't re-fire during boss
                    levelType      = LEVEL_BOSS
                    stageKillTarget = 2147483647
                    boss.warnTimer = BOSS_WARN_FRAMES
                    gameState      = GS_PLAYING
                    SPK_Say GTEXT_Get$("speech_boss_warning")
                    ' per-phase CSV lists (one entry per boss phase); music cue applied in boss.bas at spawn
                    SEQ_SplitCSV SEQ_GetKV$(seqSval$(seqIdx), "mus"), bossMusList$(), bossMusCnt
                    SEQ_SplitCSV SEQ_GetKV$(seqSval$(seqIdx), "speech"), bossSpeechList$(), bossSpeechCnt
                    bossSeekStr = Val(SEQ_GetKV$(seqSval$(seqIdx), "seek"))   ' bullet homing strength
                    bossCfgHp   = Val(SEQ_GetKV$(seqSval$(seqIdx), "hp"))     ' 0 = bosses.ini boss_hp_default
                    Dim seqaMnvStr As String : seqaMnvStr = SEQ_GetKV$(seqSval$(seqIdx), "maneuver")
                    If Len(seqaMnvStr) = 0 Then seqaMnvStr = "flyover"
                    SEQ_SplitCSV seqaMnvStr, bossManeuverList$(), bossManeuverCnt
                    SEQ_SplitCSV UCase$(SEQ_GetKV$(seqSval$(seqIdx), "attack")), bossAttackList$(), bossAttackCnt
                Case "asteroid"
                    levelNum       = levelNum + 1
                    DBG_Print "[SEQ] PLAY asteroid fired: levelNum=" + Str$(levelNum) + " seqIdx=" + Str$(seqIdx)
                    levelType      = LEVEL_ASTEROID
                    stageKillTarget = 2147483647
                    planetTimer    = 0   ' an unfinished arrival must not draw last chapter's planet here (#168)
                    planetBgR      = 3.0
                    planetBgAlpha  = 245.0
                    astFieldStart  = tt
                    astDestName   = planetNames(levelNum)
                    astParsecs    = Val(SEQ_GetKV$(seqSval$(seqIdx), "trigger"))
                    If astParsecs = 0 Then astParsecs = 340
                    BELT_Init scrW, scrH
                    If diffTime < (levelNum - 1) * (DIFF_RAMP_DURATION / DIFF_STAGE_COUNT) Then
                        diffTime = (levelNum - 1) * (DIFF_RAMP_DURATION / DIFF_STAGE_COUNT)
                    End If
                    diffScale = diffTime / DIFF_RAMP_DURATION
                    If diffScale > 1.0 Then diffScale = 1.0
                    MUS_SetCue seqaMus
                    StarfieldReset player.px - CAM_OFFSET_X, CAM_OFFSET_Y, 0
                    gameState = GS_PLAYING
            End Select
        Case SEQ_TITLE
            CR_CashOutWin   ' leftover credits -> score first, so high score and leaderboard include them
            If score > highScore Then highScore = score : SETTINGS_Save
            telemExitReason = "win"
            TELEM_SessionEnd
            SEQ_RewindToTitle
            gameState = GS_TITLE
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus Else MUS_SetCue "title"
        Case SEQ_ARRIVE
            DBG_Print "[SEQ] ARRIVE fired: levelNum=" + Str$(levelNum) + " seqIdx=" + Str$(seqIdx)
            gameState     = GS_PLANET
            planetTimer   = 1
            planetR       = 40.0
            planetCurrent = levelNum
            planetNameIdx = levelNum
            DBG_Print "[SEQ] ARRIVE set: planetCurrent=" + Str$(planetCurrent) + " planetNameIdx=" + Str$(planetNameIdx)
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus Else MUS_SetCue "planet"
            CR_StageClear
        Case SEQ_DOCK
            DOCK_Enter
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus
    End Select
End Sub
