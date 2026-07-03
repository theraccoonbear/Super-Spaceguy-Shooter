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

' Advance to the next sequence step and execute it.
Sub SEQ_Advance()
    seqIdx = seqIdx + 1
    If seqIdx >= seqCount Then
        gameState = GS_TITLE
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
            SND_ResetEmperorBGM
        Case SEQ_PLAY
            StarfieldReset player.px - CAM_OFFSET_X, CAM_OFFSET_Y, 0
            gameState = GS_PLAYING
        Case SEQ_TITLE
            gameState = GS_TITLE
    End Select
End Sub
