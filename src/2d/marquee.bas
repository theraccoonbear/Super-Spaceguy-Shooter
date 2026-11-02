' marquee.bas -- text that does not fit its box, scrolled by the frame count (#369)
'
' UI_Marquee$(text$, width, rate, tick, pauseMode)  the width characters of text$ to show on frame tick
'   Text that fits is returned unchanged. Pure: the caller keeps the tick (any counter that rises one a frame).
'   pauseMode = 0  continuous: one character per rate frames round a loop of the text, "  +++  " between
'                  the end and the start (the dock's news ticker)
'   pauseMode <> 0 hold, scroll, hold, snap back: the start shows for UI_MARQUEE_HOLD_START frames, then
'                  one character per rate frames until the last character shows, which holds for
'                  UI_MARQUEE_HOLD_END frames, then it snaps back to the start and repeats
' Kept apart from ui.bas so tests can include it without the renderer.

Const UI_MARQUEE_HOLD_START = 180   ' 3 s at 60 fps
Const UI_MARQUEE_HOLD_END = 60      ' 1 s

Function UI_Marquee$ (umText As String, umWidth As Integer, umRate As Integer, umTick As Long, umPause As Integer)
    Dim umLoop As String, umAt As Long, umLast As Long, umT As Long, umCycle As Long
    If Len(umText) <= umWidth Then UI_Marquee$ = umText : Exit Function
    If umPause = 0 Then
        umLoop = umText + "  +++  "
        umAt = (umTick \ umRate) Mod Len(umLoop)
        UI_Marquee$ = Mid$(umLoop + umLoop, umAt + 1, umWidth)
    Else
        umLast = Len(umText) - umWidth
        umCycle = UI_MARQUEE_HOLD_START + umLast * umRate + UI_MARQUEE_HOLD_END
        umT = umTick Mod umCycle
        If umT < UI_MARQUEE_HOLD_START Then
            umAt = 0
        Else
            umAt = (umT - UI_MARQUEE_HOLD_START) \ umRate
            If umAt > umLast Then umAt = umLast
        End If
        UI_Marquee$ = Mid$(umText, umAt + 1, umWidth)
    End If
End Function
