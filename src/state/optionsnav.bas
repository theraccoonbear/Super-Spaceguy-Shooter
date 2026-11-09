' optionsnav.bas -- which Settings rows show, and how Settings is entered and left, no drawing
'
' OPT_ROW_* are the rows' ids; the screen lists them in this order.
' n = OPTS_RowCount%        rows shown: all of them from the title, only the ones that are safe
'                           mid-run when optReturn <> 0
' id = OPTS_RowId%(idx)     the id of the idx-th row shown
' OPTS_OpenFromPause ret    enter Settings from the pause dialog of state ret (the run stays frozen)
' OPTS_Leave                ESC / back: to the pause dialog's state when opened from it, else the title
' In-run, CALLSIGN (changes the player), DIFFICULTY and NARRATION (rescale speech already queued for
' the run's timers) are hidden. musHold keeps music and narration still while Settings is up.
' Local variable prefix: on*

Const OPT_ROW_MUSIC      = 0
Const OPT_ROW_SFX        = 1
Const OPT_ROW_SPEECH     = 2
Const OPT_ROW_NARRATION  = 3
Const OPT_ROW_FULLSCREEN = 4
Const OPT_ROW_DIFFICULTY = 5
Const OPT_ROW_CALLSIGN   = 6
Const OPT_ROW_CONTROLS   = 7
Const OPT_ROWS_ALL       = 8

Function OPTS_RowCount%
    If optReturn = 0 Then OPTS_RowCount% = OPT_ROWS_ALL Else OPTS_RowCount% = 5
End Function

Function OPTS_RowId% (onIdx As Integer)
    OPTS_RowId% = onIdx
    If optReturn = 0 Then Exit Function
    Select Case onIdx
        Case 3 : OPTS_RowId% = OPT_ROW_FULLSCREEN
        Case 4 : OPTS_RowId% = OPT_ROW_CONTROLS
    End Select
End Function

Sub OPTS_OpenFromPause (onRet As Integer)
    optReturn = onRet
    optSel = 0 : optLfRpt = 0 : optRtRpt = 0
    optUpWas = -1 : optDnWas = -1 : optLfWas = -1 : optRtWas = -1 : optAboutWas = -1
    optEscWas = -1
    musHold = -1
    gameState = GS_OPTIONS
End Sub

Sub OPTS_Leave
    Dim onDest As Integer
    If optReturn = 0 Then
        TITLE_ReturnTo GS_TITLE
    Else
        onDest = optReturn
        optReturn = 0 : musHold = 0
        TITLE_ReturnTo onDest
        escYWas = -1 : escNWas = -1 : escCWas = -1 : escKWas = -1 : escSWas = -1
    End If
End Sub
