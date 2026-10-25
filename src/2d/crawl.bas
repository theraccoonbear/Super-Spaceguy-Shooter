' crawl.bas — stage narrative text crawl (upward scroll)
'
' Usage:
'   CRAWL_Prep "stage1", scrH   ' lay out block, plan scroll speed, reset scroll
'   gameState = GS_CRAWL        ' hand control to sssCrawl: in sss.bas
'
' Layout, speed planning and the per-frame scroll/speech step (CRAWL_Step%) live in
' crawllayout.bas; this file keeps rendering-side state and the exit path.
'
' NOTE: QB64-PE hoists Dim to module scope — all local variable names
' must be unique across every Sub/Function in the compilation unit.
' Prefix convention: cp* Prep.

DIM SHARED crawlTimer AS INTEGER

DIM SHARED crawlSpkOverlay AS INTEGER  ' 0=off 1=on; ` key toggles
DIM SHARED crawlBtWas AS INTEGER       ' edge-detect state for backtick
DIM SHARED crawlNextState AS INTEGER   ' 0 = SEQ_Advance on exit; nonzero = jump to that gameState

SUB CRAWL_Prep(cpKey AS STRING, cpStartY AS SINGLE)
    crawlTimer = 0
    CRAWL_Start GTEXT_Get$(cpKey), settingNarration * settingNarrSpeed, cpStartY, scrH - CRAWL_LINE_H
    crawlBtWas = 0
END SUB

' Called at both crawl exit points. Advances to crawlNextState if set, else SEQ_Advance.
Sub CRAWL_Finish()
    Dim cfNext As Integer
    spkTimeScale = 1  ' leaving mid fast-forward must not leave speech at 5x
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
