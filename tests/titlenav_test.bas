' titlenav_test.bas -- returning to the title from its sub-screens (src/state/titlenav.bas)
'
' Regression for #222: coming back from About / Leaderboard / Settings / Controls must not
' replay the title speech, and the ESC that closed the sub-screen must not reach the screen
' it returns to (the title reopened its COMMAND CONSOLE; Settings would close at once).
'
' Build: ./tools/buildqb tests/titlenav_test.bas
' Run:   builds/titlenav_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

' ── game-state constants (must match dims.bas) ──────────────────────────────
Const GS_TITLE       = 0
Const GS_PLAYING     = 1
Const GS_GAMEOVER    = 2
Const GS_PLANET      = 3
Const GS_CINEMATIC   = 4
Const GS_INTRO       = 5
Const GS_CRAWL       = 6
Const GS_OPTIONS     = 7
Const GS_ABOUT       = 8
Const GS_LEADIN      = 9
Const GS_CONSENT     = 10
Const GS_USERNAME    = 11
Const GS_LEADERBOARD = 12
Const GS_CONTROLS    = 13
Const GS_CRAWLS      = 14

Dim Shared gameState As Integer
Dim Shared escWas    As Integer
Dim Shared optEscWas As Integer

'$INCLUDE:'../src/state/titlenav.bas'

Dim Shared tnPassed As Integer, tnFailed As Integer

Sub TN_Assert (tnaCond As Integer, tnaName As String)
    If tnaCond Then
        Print "PASS  " + tnaName
        tnPassed = tnPassed + 1
    Else
        Print "FAIL  " + tnaName
        tnFailed = tnFailed + 1
    End If
End Sub

Dim tnSpeak As Integer

Print "=== titlenav_test ==="
Print ""

Print "--- title speech on entry ---"
tnSpeak = TITLE_SpeakOnEntry%(-1)
TN_Assert tnSpeak <> 0, "speaks on first boot (prevGameState = -1)"
tnSpeak = TITLE_SpeakOnEntry%(GS_GAMEOVER)
TN_Assert tnSpeak <> 0, "speaks after game over"
tnSpeak = TITLE_SpeakOnEntry%(GS_PLAYING)
TN_Assert tnSpeak <> 0, "speaks after aborting a game"
tnSpeak = TITLE_SpeakOnEntry%(GS_CRAWL)
TN_Assert tnSpeak <> 0, "speaks after a crawl"
tnSpeak = TITLE_SpeakOnEntry%(GS_CONSENT)
TN_Assert tnSpeak <> 0, "speaks after first-run consent"
tnSpeak = TITLE_SpeakOnEntry%(GS_USERNAME)
TN_Assert tnSpeak <> 0, "speaks after first-run callsign entry"
tnSpeak = TITLE_SpeakOnEntry%(GS_TITLE)
TN_Assert tnSpeak = 0, "silent while staying on the title"
tnSpeak = TITLE_SpeakOnEntry%(GS_ABOUT)
TN_Assert tnSpeak = 0, "silent returning from About"
tnSpeak = TITLE_SpeakOnEntry%(GS_LEADERBOARD)
TN_Assert tnSpeak = 0, "silent returning from Leaderboard"
tnSpeak = TITLE_SpeakOnEntry%(GS_OPTIONS)
TN_Assert tnSpeak = 0, "silent returning from Settings"
tnSpeak = TITLE_SpeakOnEntry%(GS_CONTROLS)
TN_Assert tnSpeak = 0, "silent returning from Controls"

Print ""
Print "--- ESC that closed the sub-screen is marked as seen ---"
gameState = GS_ABOUT : escWas = 0 : optEscWas = 0
TITLE_ReturnTo GS_TITLE
TN_Assert gameState = GS_TITLE, "About -> title lands on the title"
TN_Assert escWas <> 0, "title sees ESC as already held (console stays shut)"

gameState = GS_ABOUT : escWas = 0 : optEscWas = 0
TITLE_ReturnTo GS_OPTIONS
TN_Assert gameState = GS_OPTIONS, "About opened from Settings returns to Settings"
TN_Assert optEscWas <> 0, "Settings sees ESC as already held (does not close too)"

gameState = GS_LEADERBOARD : escWas = 0 : optEscWas = 0
TITLE_ReturnTo GS_TITLE
TN_Assert gameState = GS_TITLE And escWas <> 0, "Leaderboard -> title, console stays shut"

Print ""
Print "Passed:"; tnPassed; "  Failed:"; tnFailed
If tnFailed > 0 Then System 1
System 0
