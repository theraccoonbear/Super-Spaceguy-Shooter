' seq_stubs.bi -- collaborator stubs shared by the sequencer tests (seq_dispatch_test,
' seq_trace_test, seq_graph_test). Include after src/sys/dims.bas and before
' src/sys/sequence.bas. Shared state comes from the real dims.bas, never from copies here.

Dim Shared stLastCue As String
Sub MUS_SetCue(c As String)         : stLastCue = c : End Sub
Sub CRAWL_Prep(k As String, h As Single) : End Sub
Sub SETTINGS_Save()                 : End Sub
Sub CR_StageClear()                 : End Sub
Sub CR_CashOutWin()                 : End Sub
Sub DOCK_Enter()                    : gameState = GS_DOCK : End Sub
Sub SPK_Say(s As String)            : End Sub
Function GTEXT_Get$(k As String)    : GTEXT_Get$ = "" : End Function
Sub DBG_Print(s As String)          : End Sub
Sub TELEM_SessionEnd()              : End Sub
