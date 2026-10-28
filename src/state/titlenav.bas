' titlenav.bas -- coming back to the title (or Settings) from the screens it opens
'
' TITLE_SpeakOnEntry%  -1 when entering the title from tsePrev should play the title speech
' TITLE_ReturnTo       leave a sub-screen for trtState without its ESC reaching that screen

Function TITLE_SpeakOnEntry% (tsePrev As Integer)
    Select Case tsePrev
        Case GS_TITLE, GS_OPTIONS, GS_CONTROLS, GS_ABOUT, GS_LEADERBOARD, GS_REMAP
            TITLE_SpeakOnEntry% = 0
        Case Else
            TITLE_SpeakOnEntry% = -1
    End Select
End Function

' ESC is still held on the first frame of the screen we land on; marking it already seen
' keeps the title from toggling its console open (and Settings from closing straight away).
Sub TITLE_ReturnTo (trtState As Integer)
    gameState = trtState
    escWas = -1
    optEscWas = -1
End Sub
