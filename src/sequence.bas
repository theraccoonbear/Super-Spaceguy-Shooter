' sequence.bas -- linear game-flow sequencer
'
' sequence.txt block format:
'   label:id              section header (id appended -> --scene name "labelid")
'     TASK key=val ...    task line (must be indented)
'
' Task types: CRAWL EMPEROR TITLE PLAY ARRIVE
'   CRAWL  txt=<gtext-key>  mus=<cue>
'   EMPEROR mus=<cue>
'   TITLE  mus=<cue>
'   PLAY   type=combat|boss|asteroid  mus=<cue>  [trigger=<n>]
'     trigger: score units of 100 pts before combat phase ends (nerf: * NERF_FACTOR)
'   ARRIVE mus=<cue>
'
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

Dim Shared seqKind(0 To SEQ_MAX - 1)   As Integer
Dim Shared seqSval$(0 To SEQ_MAX - 1)
Dim Shared seqLabel$(0 To SEQ_MAX - 1)
Dim Shared seqCount     As Integer
Dim Shared seqIdx       As Integer
Dim Shared seqLastError As String

Sub SEQ_Add(seqaKind As Integer, seqaSval As String, seqaLabel As String)
    If seqCount >= SEQ_MAX Then Exit Sub
    seqKind(seqCount)   = seqaKind
    seqSval$(seqCount)  = seqaSval
    seqLabel$(seqCount) = seqaLabel
    seqCount = seqCount + 1
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
    ElseIf Len(seqjPlaySub) > 0 Then
        Dim seqjSubName As String
        If seqjPlaySub = "playing" Then seqjSubName = "combat or asteroid" Else seqjSubName = seqjPlaySub
        seqLastError = "--scene '" + seqjSpec + "': label '" + seqjTargetLabel + "' has no " + seqjSubName + " task"
    Else
        seqLastError = "--scene '" + seqjSpec + "': not found"
    End If
    SEQ_JumpToScene% = -1
End Function

' Print valid --scene names to file handle fh, derived from the loaded sequence table.
Sub SEQ_PrintScenes(seqpFH As Integer)
    Dim seqpI As Integer, seqpN As Integer, seqpLabel As String
    Dim seqpSeen$(0 To SEQ_MAX - 1), seqpSeenCount As Integer
    Dim seqpAlready As Integer, seqpJ As Integer

    For seqpI = 0 To seqCount - 1
        seqpLabel = seqLabel$(seqpI)
        If Len(seqpLabel) = 0 Then GoTo seqpNext

        ' skip if we've already processed this label
        seqpAlready = 0
        For seqpJ = 0 To seqpSeenCount - 1
            If seqpSeen$(seqpJ) = seqpLabel Then seqpAlready = -1
        Next seqpJ
        If seqpAlready Then GoTo seqpNext
        seqpSeen$(seqpSeenCount) = seqpLabel : seqpSeenCount = seqpSeenCount + 1

        ' emit scene names for this label
        If seqpLabel = "title" Then
            Print #seqpFH, "  title"
        ElseIf seqpLabel = "emperor" Or seqKind(seqpI) = SEQ_EMPEROR Then
            Print #seqpFH, "  emperor"
        ElseIf seqpLabel = "crawl0" Then
            Print #seqpFH, "  crawl0"
        ElseIf Left$(seqpLabel, 5) = "level" Then
            seqpN = Val(Mid$(seqpLabel, 6))
            ' scan all tasks in this label block
            For seqpJ = 0 To seqCount - 1
                If seqLabel$(seqpJ) = seqpLabel Then
                    Select Case seqKind(seqpJ)
                        Case SEQ_CRAWL
                            Print #seqpFH, "  crawl" + LTrim$(Str$(seqpN))
                        Case SEQ_PLAY
                            Select Case LCase$(SEQ_GetKV$(seqSval$(seqpJ), "type"))
                                Case "combat", "asteroid" : Print #seqpFH, "  playing" + LTrim$(Str$(seqpN))
                                Case "boss"               : Print #seqpFH, "  boss" + LTrim$(Str$(seqpN))
                            End Select
                    End Select
                End If
            Next seqpJ
        End If
        seqpNext:
    Next seqpI
End Sub

' Advance to the next sequence step and execute it.
Sub SEQ_Advance()
    Dim seqaType As String, seqaMus As String, seqaTrig As Integer
    seqIdx = seqIdx + 1
    If seqIdx >= seqCount Then
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
                    If settingNerf Then
                        stageScore = score + CLng(seqaTrig * 100 * NERF_FACTOR)
                    Else
                        stageScore = score + seqaTrig * 100
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
                    ' stageScore set to max so combat trigger won't re-fire during boss
                    stageScore     = 2147483647
                    boss.warnTimer = BOSS_WARN_FRAMES
                    Dim seqaBossWarn As String : seqaBossWarn = GTEXT_Get$("speech_boss_warning")
                    SPK_Say seqaBossWarn
                    ' music cue set in boss.bas when warn timer expires and boss spawns
                Case "asteroid"
                    levelNum      = levelNum + 1
                    levelType     = LEVEL_ASTEROID
                    stageScore    = 2147483647
                    astFieldStart = tt
                    astDestName   = planetNames(levelNum)
                    astParsecs    = Val(SEQ_GetKV$(seqSval$(seqIdx), "trigger"))
                    If astParsecs = 0 Then astParsecs = 340
                    fuelLevel     = ASTFIELD_DURATION * ASTFIELD_FUEL_DRAIN_PT * ASTFIELD_FUEL_FRAC
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
            If score > highScore Then highScore = score : SETTINGS_Save
            SEQ_RewindToTitle
            gameState = GS_TITLE
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus Else MUS_SetCue "title"
        Case SEQ_ARRIVE
            gameState     = GS_PLANET
            planetTimer   = 1
            planetCurrent = (planetCurrent Mod PLANET_COUNT) + 1
            planetNameIdx = (planetNameIdx Mod PLANET_COUNT) + 1
            seqaMus = SEQ_GetKV$(seqSval$(seqIdx), "mus")
            If Len(seqaMus) > 0 Then MUS_SetCue seqaMus Else MUS_SetCue "planet"
    End Select
End Sub
