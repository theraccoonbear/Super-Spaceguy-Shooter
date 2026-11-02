' marquee_test.bas -- UI_Marquee$, the scrolling text window (#369)
'
' Drives src/2d/marquee.bas with plain numbers:
'   1. text that fits comes back unchanged, in both modes
'   2. continuous mode is the dock news ticker's old output, frame for frame
'   3. pause mode: holds on the start, scrolls one character per rate frames to the last
'      character, holds there, snaps back to the start and repeats
'   4. the window is always exactly width characters of the text, and the tick can be large
'
' Build: tools/dev test (builds and runs every test)
' Run:   builds/marquee_test   (exit 0 = all pass)

$CONSOLE:ONLY
OPTION _EXPLICIT

'$INCLUDE:'../src/2d/marquee.bas'

Dim Shared mtPass As Integer, mtFail As Integer

Sub MT_Assert (condition As Integer, label As String)
    If condition Then
        Print "PASS  " + label
        mtPass = mtPass + 1
    Else
        Print "FAIL  " + label
        mtFail = mtFail + 1
    End If
End Sub

' The dock news ticker as it was before it moved onto UI_Marquee$.
Function MT_OldNews$ (monText As String, monW As Integer, monRate As Integer, monTick As Long)
    Dim monLoop As String, monAt As Long
    If Len(monText) <= monW Then MT_OldNews$ = monText : Exit Function
    monLoop = monText + "  +++  "
    monAt = (monTick \ monRate) Mod Len(monLoop)
    MT_OldNews$ = Mid$(monLoop + monLoop, monAt + 1, monW)
End Function

Dim mtI As Long, mtOk As Integer, mtS As String, mtLong As String

Print "=== marquee_test ==="
Print ""

mtLong = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

Print "--- 1. text that fits ---"
MT_Assert UI_Marquee$("SHORT", 24, 7, 0, 0) = "SHORT" And UI_Marquee$("SHORT", 24, 7, 99999, 0) = "SHORT", "1.01  continuous: unchanged at any tick"
MT_Assert UI_Marquee$("SHORT", 24, 7, 0, -1) = "SHORT" And UI_Marquee$("SHORT", 24, 7, 99999, -1) = "SHORT", "1.02  pause: unchanged at any tick"
MT_Assert UI_Marquee$("ABCDE", 5, 7, 400, -1) = "ABCDE" And UI_Marquee$("ABCDE", 5, 7, 400, 0) = "ABCDE", "1.03  exactly the width fits"
MT_Assert UI_Marquee$("", 10, 7, 12, -1) = "",                "1.04  an empty text stays empty"
Print ""

Print "--- 2. continuous mode is the old news ticker ---"
mtS = "THE EMPEROR'S BLOCKADE OF THE REFINERY WORLD DRIVES UP THE FUEL PRICE"
mtOk = -1
For mtI = 0 To 3000
    If UI_Marquee$(mtS, 24, 7, mtI, 0) <> MT_OldNews$(mtS, 24, 7, mtI) Then mtOk = 0
Next mtI
MT_Assert mtOk,                                           "2.01  3001 ticks of a long line match the old output"
mtOk = -1
For mtI = 0 To 500
    If UI_Marquee$(mtLong, 10, 3, mtI, 0) <> MT_OldNews$(mtLong, 10, 3, mtI) Then mtOk = 0
Next mtI
MT_Assert mtOk,                                           "2.02  and for another width and rate"
MT_Assert UI_Marquee$(mtLong, 10, 7, 0, 0) = "ABCDEFGHIJ" And UI_Marquee$(mtLong, 10, 7, 7, 0) = "BCDEFGHIJK", "2.03  one character per rate frames"
MT_Assert UI_Marquee$(mtLong, 10, 7, 26 * 7, 0) = "  +++  ABC", "2.04  after the end comes the gap, then the start again"
Print ""

Print "--- 3. pause mode ---"
' ABCDEFGHIJKLMNOPQRSTUVWXYZ in 10: starts A..J, last window Q..Z, 16 steps; rate 5 -> scroll 80 frames
MT_Assert UI_Marquee$(mtLong, 10, 5, 0, -1) = "ABCDEFGHIJ", "3.01  frame 0 shows the start"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START - 1, -1) = "ABCDEFGHIJ", "3.02  the start holds for the whole hold"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 4, -1) = "ABCDEFGHIJ", "3.03  the first step is a full rate after the hold ends"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 5, -1) = "BCDEFGHIJK", "3.04  then one character per rate frames"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 50, -1) = "KLMNOPQRST", "3.05  ten steps in"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 16 * 5, -1) = "QRSTUVWXYZ", "3.06  the last character shows after (length - width) steps"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 16 * 5 + UI_MARQUEE_HOLD_END - 1, -1) = "QRSTUVWXYZ", "3.07  and holds for the end hold"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 16 * 5 + UI_MARQUEE_HOLD_END, -1) = "ABCDEFGHIJ", "3.08  then snaps straight back to the start"
MT_Assert UI_Marquee$(mtLong, 10, 5, UI_MARQUEE_HOLD_START + 16 * 5 + UI_MARQUEE_HOLD_END + UI_MARQUEE_HOLD_START - 1, -1) = "ABCDEFGHIJ", "3.09  the second pass holds on the start again"
MT_Assert UI_Marquee$(mtLong, 10, 5, 2 * (UI_MARQUEE_HOLD_START + 16 * 5 + UI_MARQUEE_HOLD_END) + UI_MARQUEE_HOLD_START + 5, -1) = "BCDEFGHIJK", "3.10  and repeats, cycle after cycle"
mtOk = -1
For mtI = 1 To 2000
    mtS = UI_Marquee$(mtLong, 10, 5, mtI, -1)
    If InStr(mtLong, mtS) = 0 Then mtOk = 0
Next mtI
MT_Assert mtOk,                                           "3.11  every window is a real stretch of the text (no gap, no wrap)"
mtOk = -1
For mtI = 1 To 2000
    If Asc(UI_Marquee$(mtLong, 10, 5, mtI, -1)) < Asc(UI_Marquee$(mtLong, 10, 5, mtI - 1, -1)) And UI_Marquee$(mtLong, 10, 5, mtI, -1) <> "ABCDEFGHIJ" Then mtOk = 0
Next mtI
MT_Assert mtOk,                                           "3.12  it only moves forward, except for the snap back to the start"
MT_Assert UI_Marquee$("ABCDEFGHIJK", 10, 7, UI_MARQUEE_HOLD_START + 7, -1) = "BCDEFGHIJK", "3.13  one character too long: a single step"
Print ""

Print "--- 4. width and tick ---"
mtOk = -1
For mtI = 0 To 5000 Step 7
    If Len(UI_Marquee$(mtLong, 10, 5, mtI, -1)) <> 10 Or Len(UI_Marquee$(mtLong, 10, 5, mtI, 0)) <> 10 Then mtOk = 0
Next mtI
MT_Assert mtOk,                                           "4.01  always exactly width characters"
MT_Assert UI_Marquee$(mtLong, 10, 5, 2000000000, -1) = UI_Marquee$(mtLong, 10, 5, 2000000000 Mod (UI_MARQUEE_HOLD_START + 16 * 5 + UI_MARQUEE_HOLD_END), -1), "4.02  a very large tick works like its place in the cycle"
MT_Assert UI_Marquee$(mtLong, 1, 1, UI_MARQUEE_HOLD_START + 25, -1) = "Z", "4.03  a one character window ends on the last character"
Print ""

Print "=== " + LTrim$(Str$(mtPass + mtFail)) + " tests: " _
    + LTrim$(Str$(mtPass)) + " passed, " + LTrim$(Str$(mtFail)) + " failed ==="
If mtFail > 0 Then System 1 Else System 0
