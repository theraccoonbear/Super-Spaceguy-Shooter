' sequence.bas — linear game-flow sequencer
'
' Define the complete scene order once in SEQ_Init; call SEQ_Advance to move
' to the next step.  To reorder the game, change the SEQ_Add calls in SEQ_Init.
' To add a new scene type, add a Const and a Case in SEQ_Advance.
'
' All callers:
'   game.bas GAME_NewGame      : SEQ_Init : SEQ_Advance
'   sss.bas  GS_INTRO SPACE    : SEQ_Advance
'   sss.bas  GS_CRAWL ends     : SEQ_Advance
'   stage.bas cinematic done   : SEQ_Advance

Const SEQ_MAX     = 32
Const SEQ_CRAWL   = 1   ' text crawl (seqSval$ = GTEXT block key)
Const SEQ_EMPEROR = 2   ' antagonist reveal image (GS_INTRO)
Const SEQ_PLAY    = 3   ' gameplay (GS_PLAYING)
Const SEQ_TITLE   = 4   ' title screen (GS_TITLE)

Dim Shared seqKind(0 To SEQ_MAX - 1) As Integer
Dim Shared seqSval$(0 To SEQ_MAX - 1)
Dim Shared seqCount As Integer
Dim Shared seqIdx   As Integer

Sub SEQ_Add(seqaKind As Integer, seqaSval As String)
    If seqCount >= SEQ_MAX Then Exit Sub
    seqKind(seqCount) = seqaKind
    seqSval$(seqCount) = seqaSval
    seqCount = seqCount + 1
End Sub

' Populate the complete game sequence.  Call once at game start.
Sub SEQ_Init()
    seqCount = 0 : seqIdx = -1
    SEQ_Add SEQ_CRAWL,   "intro"   ' prologue
    SEQ_Add SEQ_EMPEROR, ""        ' antagonist reveal
    SEQ_Add SEQ_TITLE,   ""        ' main menu
    SEQ_Add SEQ_CRAWL,   "stage1"  ' chapter 1
    SEQ_Add SEQ_PLAY,    ""        ' stage 1
    SEQ_Add SEQ_CRAWL,   "stage2"  ' chapter 2
    SEQ_Add SEQ_PLAY,    ""        ' stage 2
    SEQ_Add SEQ_CRAWL,   "stage3"  ' chapter 3
    SEQ_Add SEQ_PLAY,    ""        ' stage 3
    SEQ_Add SEQ_CRAWL,   "stage4"  ' chapter 4
    SEQ_Add SEQ_PLAY,    ""        ' stage 4
    SEQ_Add SEQ_CRAWL,   "stage5"  ' chapter 5
    SEQ_Add SEQ_PLAY,    ""        ' stage 5
    SEQ_Add SEQ_CRAWL,   "stage6"  ' chapter 6
    SEQ_Add SEQ_PLAY,    ""        ' stage 6
    SEQ_Add SEQ_CRAWL,   "outro"   ' epilogue
    SEQ_Add SEQ_TITLE,   ""        ' title screen
End Sub

' Rewind seqIdx to the first SEQ_TITLE waypoint so GAME_NewGame advances into stage 1.
Sub SEQ_RewindToTitle()
    Dim seqrI As Integer
    For seqrI = 0 To seqCount - 1
        If seqKind(seqrI) = SEQ_TITLE Then
            seqIdx = seqrI
            Exit Sub
        End If
    Next seqrI
End Sub

' Parse a scene spec string (e.g. "playing1", "crawl0", "boss2", "title") and set
' seqIdx so the next SEQ_Advance call lands on that scene.  For "bossN", also sets
' score = stageScore so the boss triggers on the first gameplay frame.
' Returns the target sequence index, or -1 if the spec is unknown/not found.
Function SEQ_JumpToScene%(seqjSpec As String)
    Dim seqjI As Integer, seqjLast As Integer
    Dim seqjType As String, seqjNum As Integer, seqjHasNum As Integer
    Dim seqjKind As Integer, seqjBoss As Integer
    Dim seqjCount As Integer, seqjHit As Integer

    ' split trailing digit(s) from type name
    seqjLast = Len(seqjSpec)
    Do While seqjLast > 0
        If Mid$(seqjSpec, seqjLast, 1) >= "0" And Mid$(seqjSpec, seqjLast, 1) <= "9" Then
            seqjLast = seqjLast - 1
        Else
            Exit Do
        End If
    Loop
    seqjType = LCase$(Left$(seqjSpec, seqjLast))
    seqjHasNum = (seqjLast < Len(seqjSpec))
    If seqjHasNum Then
        seqjNum = Val(Mid$(seqjSpec, seqjLast + 1))
    Else
        seqjNum = 0
    End If

    seqjBoss = 0
    Select Case seqjType
        Case "title"   : seqjKind = SEQ_TITLE
        Case "crawl"   : seqjKind = SEQ_CRAWL    ' 0-indexed: crawl0=intro, crawl1=stage1
        Case "playing" : seqjKind = SEQ_PLAY      ' 1-indexed: playing1=stage 1
        Case "boss"    : seqjKind = SEQ_PLAY : seqjBoss = -1
        Case Else      : SEQ_JumpToScene% = -1 : Exit Function
    End Select

    seqjCount = 0
    For seqjI = 0 To seqCount - 1
        If seqKind(seqjI) = seqjKind Then
            seqjHit = 0
            ' crawl and bare type names (no digit) are 0-indexed; playing/boss with digit are 1-indexed
            If seqjType = "crawl" Or Not seqjHasNum Then
                If seqjCount = seqjNum Then seqjHit = -1
            Else
                If seqjCount = seqjNum - 1 Then seqjHit = -1
            End If
            If seqjHit Then
                seqIdx = seqjI - 1
                If seqjBoss Then score = stageScore
                SEQ_JumpToScene% = seqjI
                Exit Function
            End If
            seqjCount = seqjCount + 1
        End If
    Next seqjI

    SEQ_JumpToScene% = -1
End Function

' Advance to the next sequence step and execute it.
Sub SEQ_Advance()
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
            CRAWL_Prep seqSval$(seqIdx), scrH
            gameState = GS_CRAWL
        Case SEQ_EMPEROR
            introTimer = 0
            gameState = GS_INTRO
            MUS_SetCue "emperor"
        Case SEQ_PLAY
            StarfieldReset player.px - CAM_OFFSET_X, CAM_OFFSET_Y, 0
            gameState = GS_PLAYING
            MUS_SetCue "game"
        Case SEQ_TITLE
            If score > highScore Then highScore = score : SETTINGS_Save
            SEQ_RewindToTitle
            gameState = GS_TITLE
            MUS_SetCue "title"
    End Select
End Sub
