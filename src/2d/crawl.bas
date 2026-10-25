' crawl.bas — stage narrative text crawl (upward scroll)
'
' Usage:
'   CRAWL_Prep "stage1", scrH   ' lay out block, plan scroll speed, reset scroll
'   gameState = GS_CRAWL        ' hand control to sssCrawl: in sss.bas
'
' Layout and speed planning live in crawllayout.bas.
'
' NOTE: QB64-PE hoists Dim to module scope — all local variable names
' must be unique across every Sub/Function in the compilation unit.
' Prefix convention: cp* Prep.

CONST CRAWL_SPEED     = 0.25   ' pixels per frame upward (fast-forward = 5x this)

DIM SHARED crawlScroll AS SINGLE
DIM SHARED crawlTimer AS INTEGER
DIM SHARED crawlParaIdx AS INTEGER
DIM SHARED crawlVel AS SINGLE          ' px/s, constant for the whole crawl (CRAWL_PlanSpeed!)

DIM SHARED crawlSpkOverlay AS INTEGER  ' 0=off 1=on; ` key toggles
DIM SHARED crawlBtWas AS INTEGER       ' edge-detect state for backtick
DIM SHARED crawlFFActive AS INTEGER    ' -1 while FF is active; tracks vol save/restore independent of spaceWas
DIM SHARED crawlNextState AS INTEGER   ' 0 = SEQ_Advance on exit; nonzero = jump to that gameState

' One scroll speed for the whole crawl: each paragraph's length is known up front
' (spoken at the narration preset, or read at CRAWL_READ_WPM with narration off), and
' CRAWL_PlanSpeed! picks the fastest speed at which every paragraph finishes on screen.
SUB CRAWL_Prep(cpKey AS STRING, cpStartY AS SINGLE)
    crawlTimer = 0 : crawlParaIdx = 0
    CRAWL_Layout GTEXT_Get$(cpKey)
    crawlScroll = cpStartY  ' start text at screen bottom — visible immediately with bottom fade
    CRAWL_PlanDurations settingNarration * settingNarrSpeed
    crawlVel = CRAWL_PlanSpeed!(cpStartY, scrH - CRAWL_LINE_H, CRAWL_TOP_FADE)
    crawlBtWas = 0
    crawlFFActive = 0
END SUB

' Called at both crawl exit points. Advances to crawlNextState if set, else SEQ_Advance.
Sub CRAWL_Finish()
    Dim cfNext As Integer
    cfNext = crawlNextState
    crawlNextState = 0
    If cfNext > 0 Then
        gameState = cfNext
        If cfNext = GS_GAMEOVER Then
            gameOverDelay = 90
            StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
            MUS_SetCue "gameover"
            SPK_Say sSpkGameOver
        End If
    Else
        SEQ_Advance
    End If
End Sub
