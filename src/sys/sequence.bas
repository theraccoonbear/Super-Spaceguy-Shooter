' sequence.bas -- game-flow sequencer: named blocks, each naming its successor
'
' sequence.txt block format:
'   label:id [secret]       block header (id appended -> --scene name "labelid")
'     NEXT <label:id> | end   last line of the block: the block that follows; end = deliberate terminal (the run is over)
'     secret: block no other block's next reaches; only an explicit jump enters it
'     TASK key=val ...    task line (must be indented); a block's tasks run in order
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
        Print #ceFH, ceMsg; Chr$(10);
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
Const SEQ_BLK_MAX = 32
Dim Shared seqTaskBlk(0 To SEQ_MAX - 1) As Integer   ' block index of each task
Dim Shared seqBlkName$(0 To SEQ_BLK_MAX - 1)
Dim Shared seqBlkNext$(0 To SEQ_BLK_MAX - 1)         ' "" = header named no next; "end" = deliberate terminal
Dim Shared seqBlkFirst(0 To SEQ_BLK_MAX - 1) As Integer
Dim Shared seqBlkLen(0 To SEQ_BLK_MAX - 1) As Integer
Dim Shared seqBlkSecret(0 To SEQ_BLK_MAX - 1) As Integer
Dim Shared seqBlkClosed(0 To SEQ_BLK_MAX - 1) As Integer   ' its NEXT step was seen; nothing may follow it
Dim Shared seqBlkCount  As Integer
Dim Shared seqJumpTo    As Integer   ' task SEQ_JumpToScene wants SEQ_Advance to land on, whatever block precedes it
Dim Shared seqLoadErr   As String    ' first problem SEQ_Load hit (overflow, bad header, task outside a block); "" = clean
Dim Shared seqCount     As Integer
Dim Shared seqIdx       As Integer
Dim Shared seqLastError As String
Dim Shared seqRunActive As Integer   ' -1 from a run's first PLAY until the run ends: reaching TITLE only ends a run that started (#331)

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

' The block label of task seqlI ("level3"); "" when out of range.
Function seqLabel$(seqlI As Integer)
    If seqlI < 0 Or seqlI >= seqCount Then seqLabel$ = "" Else seqLabel$ = seqBlkName$(seqTaskBlk(seqlI))
End Function

Function SEQ_FindBlock%(seqfbName As String)
    Dim seqfbI As Integer
    SEQ_FindBlock% = -1
    For seqfbI = 0 To seqBlkCount - 1
        If seqBlkName$(seqfbI) = seqfbName Then SEQ_FindBlock% = seqfbI : Exit Function
    Next seqfbI
End Function

' First task reached by entering block seqebB, following next past any empty blocks;
' -1 when the chain ends (terminal, no next, dangling next, or a loop of empty blocks).
Function SEQ_EnterBlock%(seqebB As Integer)
    Dim seqebN As Integer, seqebCur As Integer
    seqebCur = seqebB
    For seqebN = 0 To SEQ_BLK_MAX
        If seqebCur < 0 Then Exit For
        If seqBlkLen(seqebCur) > 0 Then SEQ_EnterBlock% = seqBlkFirst(seqebCur) : Exit Function
        seqebCur = SEQ_FindBlock%(seqBlkNext$(seqebCur))
    Next seqebN
    SEQ_EnterBlock% = -1
End Function

' The task that follows task seqniI: the next one in its block, else the first task of the
' block its NEXT names. seqniI = -1 starts at the first block. -1 = the sequence ends here.
Function SEQ_NextIdx%(seqniI As Integer)
    Dim seqniB As Integer
    If seqBlkCount = 0 Or seqniI >= seqCount Then SEQ_NextIdx% = -1 : Exit Function
    If seqniI < 0 Then SEQ_NextIdx% = SEQ_EnterBlock%(0) : Exit Function
    seqniB = seqTaskBlk(seqniI)
    If seqniI + 1 < seqBlkFirst(seqniB) + seqBlkLen(seqniB) Then SEQ_NextIdx% = seqniI + 1 : Exit Function
    SEQ_NextIdx% = SEQ_EnterBlock%(SEQ_FindBlock%(seqBlkNext$(seqniB)))
End Function

' Static checks on the loaded sequence; "" when sound, else one problem per line (each ending
' in Chr$(10)): load errors, a block with no tasks or no NEXT, a NEXT naming no block, and
' non-secret blocks not reachable from the first block through NEXT.
Function SEQ_Validate$()
    Dim seqvI As Integer, seqvB As Integer, seqvN As Integer, seqvOut As String
    Dim seqvSeen(0 To SEQ_BLK_MAX - 1) As Integer
    If Len(seqLoadErr) > 0 Then seqvOut = seqvOut + seqLoadErr + Chr$(10)
    If seqBlkCount = 0 Then seqvOut = seqvOut + "no blocks" + Chr$(10)
    For seqvI = 0 To seqBlkCount - 1
        If seqBlkLen(seqvI) = 0 Then seqvOut = seqvOut + "block '" + seqBlkName$(seqvI) + "' has no tasks" + Chr$(10)
        If seqBlkNext$(seqvI) = "" Then
            seqvOut = seqvOut + "dead end: block '" + seqBlkName$(seqvI) + "' has no NEXT step (use NEXT end for a terminal)" + Chr$(10)
        ElseIf seqBlkNext$(seqvI) <> "end" And SEQ_FindBlock%(seqBlkNext$(seqvI)) < 0 Then
            seqvOut = seqvOut + "dangling next: block '" + seqBlkName$(seqvI) + "' -> '" + seqBlkNext$(seqvI) + "'" + Chr$(10)
        End If
    Next seqvI
    If seqBlkCount > 0 Then
        seqvB = 0
        For seqvN = 0 To SEQ_BLK_MAX
            If seqvB < 0 Then Exit For
            If seqvSeen(seqvB) Then Exit For
            seqvSeen(seqvB) = -1
            seqvB = SEQ_FindBlock%(seqBlkNext$(seqvB))
        Next seqvN
    End If
    For seqvI = 0 To seqBlkCount - 1
        If seqBlkSecret(seqvI) = 0 And seqvSeen(seqvI) = 0 Then
            seqvOut = seqvOut + "unreachable: block '" + seqBlkName$(seqvI) + "' (mark it secret, or point a NEXT at it)" + Chr$(10)
        End If
    Next seqvI
    SEQ_Validate$ = seqvOut
End Function

' The leg after the current task (the dock): its PLAY tasks up to the next ARRIVE, as the
' combat kill triggers summed, the boss fights' secs= summed (#90), the boss fights with no
' secs= (economy.ini fuel_boss_secs each) and asteroid fields (SUP_LegNeed!'s fuel need).
' All zero when no leg follows.
Sub SEQ_NextLeg(seqnKills As Long, seqnBossSecs As Single, seqnBoss As Integer, seqnAst As Integer)
    Dim seqnI As Integer, seqnStep As Integer, seqnType As String, seqnSecs As String
    seqnKills = 0 : seqnBossSecs = 0 : seqnBoss = 0 : seqnAst = 0
    seqnI = seqIdx
    For seqnStep = 1 To SEQ_MAX
        seqnI = SEQ_NextIdx%(seqnI)
        If seqnI < 0 Then Exit For
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
    Next seqnStep
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

Sub SEQ_LoadFail(seqlfMsg As String)
    If Len(seqLoadErr) = 0 Then seqLoadErr = seqlfMsg
End Sub

Sub SEQ_Add(seqaKind As Integer, seqaSval As String)
    If seqBlkCount = 0 Then SEQ_LoadFail "task before any block header: " + seqaSval : Exit Sub
    If seqBlkClosed(seqBlkCount - 1) Then SEQ_LoadFail "block '" + seqBlkName$(seqBlkCount - 1) + "': task after NEXT (NEXT must be the last line)" : Exit Sub
    If seqCount >= SEQ_MAX Then SEQ_LoadFail "more than SEQ_MAX (" + LTrim$(Str$(SEQ_MAX)) + ") tasks": Exit Sub
    seqKind(seqCount)   = seqaKind
    seqSval$(seqCount)  = seqaSval
    seqTaskBlk(seqCount) = seqBlkCount - 1
    seqBlkLen(seqBlkCount - 1) = seqBlkLen(seqBlkCount - 1) + 1
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

' A NEXT step: the block's exit, not a task (no seqKind entry). The target drops its colon
' ("level:2" -> "level2"); "end" is the deliberate terminal. A conditional prefix can later
' go before NEXT without changing this line's shape.
Sub SEQ_SetNext(seqsnTarget As String)
    Dim seqsnB As Integer, seqsnColon As Integer, seqsnT As String
    If seqBlkCount = 0 Then SEQ_LoadFail "NEXT before any block header" : Exit Sub
    seqsnB = seqBlkCount - 1
    If seqBlkClosed(seqsnB) Then SEQ_LoadFail "block '" + seqBlkName$(seqsnB) + "': second NEXT" : Exit Sub
    seqBlkClosed(seqsnB) = -1
    seqsnT = LTrim$(RTrim$(seqsnTarget))
    If Len(seqsnT) = 0 Then SEQ_LoadFail "block '" + seqBlkName$(seqsnB) + "': NEXT with no target" : Exit Sub
    seqsnColon = InStr(seqsnT, ":")
    If seqsnColon > 0 Then seqsnT = Left$(seqsnT, seqsnColon - 1) + Mid$(seqsnT, seqsnColon + 1)
    seqBlkNext$(seqsnB) = seqsnT
End Sub

' A block header line: "name:id [secret]". The name drops its colon ("level:2" -> "level2"),
' so a NEXT target is written the same way as the header it names.
Sub SEQ_AddBlock(seqabLine As String)
    Dim seqabRest As String, seqabSp As Integer, seqabHead As String, seqabTok As String
    Dim seqabSecret As Integer, seqabB As Integer, seqabColon As Integer
    seqabSp = InStr(seqabLine, " ")
    If seqabSp = 0 Then seqabHead = seqabLine : seqabRest = "" Else seqabHead = Left$(seqabLine, seqabSp - 1) : seqabRest = LTrim$(Mid$(seqabLine, seqabSp + 1))
    seqabColon = InStr(seqabHead, ":")
    If seqabColon > 0 Then seqabHead = Left$(seqabHead, seqabColon - 1) + Mid$(seqabHead, seqabColon + 1)
    Do While Len(seqabRest) > 0
        seqabSp = InStr(seqabRest, " ")
        If seqabSp = 0 Then seqabTok = seqabRest : seqabRest = "" Else seqabTok = Left$(seqabRest, seqabSp - 1) : seqabRest = LTrim$(Mid$(seqabRest, seqabSp + 1))
        If LCase$(seqabTok) = "secret" Then
            seqabSecret = -1
        ElseIf LCase$(Left$(seqabTok, 5)) = "next=" Then
            SEQ_LoadFail "block '" + seqabHead + "': next= on a header is not supported; end the block with a NEXT step"
        Else
            SEQ_LoadFail "block '" + seqabHead + "': unknown header field '" + seqabTok + "'"
        End If
    Loop
    If SEQ_FindBlock%(seqabHead) >= 0 Then SEQ_LoadFail "duplicate block '" + seqabHead + "'" : Exit Sub
    If seqBlkCount >= SEQ_BLK_MAX Then SEQ_LoadFail "more than SEQ_BLK_MAX (" + LTrim$(Str$(SEQ_BLK_MAX)) + ") blocks" : Exit Sub
    seqabB = seqBlkCount
    seqBlkName$(seqabB)  = seqabHead
    seqBlkNext$(seqabB)  = ""
    seqBlkClosed(seqabB) = 0
    seqBlkFirst(seqabB)  = seqCount
    seqBlkLen(seqabB)    = 0
    seqBlkSecret(seqabB) = seqabSecret
    seqBlkCount = seqBlkCount + 1
End Sub

' Parse the embedded sequence.txt block format and populate the sequence table.
Sub SEQ_Load(seqlData As String)
    Dim seqlI As Integer, seqlNL As Integer
    Dim seqlRaw As String, seqlLine As String
    Dim seqlKindStr As String, seqlSval As String, seqlSp As Integer
    seqCount = 0 : seqIdx = -1 : seqBlkCount = 0 : seqJumpTo = -1 : seqLoadErr = ""
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
                Case "CRAWL"            : SEQ_Add SEQ_CRAWL,   seqlSval
                Case "CARD", "EMPEROR"  : SEQ_Add SEQ_EMPEROR,  seqlSval
                Case "TITLE"            : SEQ_Add SEQ_TITLE,    seqlSval
                Case "PLAY"             : SEQ_Add SEQ_PLAY,     seqlSval
                Case "ARRIVE"           : SEQ_Add SEQ_ARRIVE,   seqlSval
                Case "DOCK"             : SEQ_Add SEQ_DOCK,     seqlSval
                Case "NEXT"             : SEQ_SetNext seqlSval
                Case Else               : SEQ_LoadFail "unknown task type '" + seqlKindStr + "'"
            End Select
        Else
            SEQ_AddBlock seqlLine
        End If
        seqlNext:
    Loop
End Sub

' Rewind seqIdx to the first SEQ_TITLE waypoint.
Sub SEQ_RewindToTitle()
    Dim seqrI As Integer
    seqJumpTo = -1
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
                    seqIdx = seqCrawlAt(seqjI) - 1 : seqJumpTo = seqCrawlAt(seqjI)
                    SEQ_JumpToScene% = seqCrawlAt(seqjI)
                Else
                    seqjAt = -1
                    For seqjLast = 0 To seqCount - 1
                        If seqKind(seqjLast) = SEQ_TITLE Then seqjAt = seqjLast : Exit For
                    Next seqjLast
                    If seqjAt >= 0 Then
                        seqIdx = seqjAt - 1 : seqJumpTo = seqjAt
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
                    seqIdx = seqjI - 1 : seqJumpTo = seqjI
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

' The run was won (the outro's TITLE, or past the end of the table): cash out, high score,
' session end. Does nothing when no run is in progress, e.g. SPACE on the intro emperor
' card also lands on a TITLE task (#331).
Sub SEQ_EndRunWin()
    If seqRunActive = 0 Then Exit Sub
    seqRunActive = 0
    CR_CashOutWin   ' leftover credits -> score first, so high score and leaderboard include them
    If score > highScore Then highScore = score : SETTINGS_Save
    telemExitReason = "win"
    TELEM_SessionEnd
End Sub

' Quit from the pause menu: the run ends without a cash-out, and the game parks at the title.
Sub SEQ_QuitRun()
    telemExitReason = "quit"
    TELEM_SessionEnd
    seqRunActive = 0
    SEQ_RewindToTitle
    gameState = GS_TITLE
    MUS_SetCue "title"
End Sub

' The process is being closed (window close, title QUIT): a run still in progress ends once as
' exit=quit, like the pause menu's quit but without parking at the title. No run, no session end.
Sub SEQ_QuitProcess()
    If seqRunActive = 0 Then Exit Sub
    seqRunActive = 0
    telemExitReason = "quit"
    TELEM_SessionEnd
End Sub

' Advance to the next sequence step and execute it.
Sub SEQ_Advance()
    Dim seqaType As String, seqaMus As String, seqaTrig As Integer
    If seqJumpTo = seqIdx + 1 Then seqIdx = seqJumpTo Else seqIdx = SEQ_NextIdx%(seqIdx)
    seqJumpTo = -1
    If seqIdx < 0 Then seqIdx = seqCount
    If seqIdx >= seqCount Then
        SEQ_EndRunWin
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
            seqRunActive = -1
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
            SEQ_EndRunWin
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
