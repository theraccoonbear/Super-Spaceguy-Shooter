' textedit_test.bas -- one-line text editing for the callsign box (src/2d/textedit.bas)
'
' Covers #193: names longer than 12 chars up to the max, insert at the cursor, backspace and
' delete either side of it, left/right/home/end, ~X color tokens moving and deleting as one,
' non-editing keys left alone, and the scroll offset keeping the cursor inside the box.
'
' Build: ./tools/buildqb tests/textedit_test.bas
' Run:   builds/textedit_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

'$INCLUDE:'../src/2d/textedit.bas'

Dim Shared tePassed As Integer, teFailed As Integer
Dim Shared teS As String, teC As Integer

Sub TE_Assert (teaCond As Integer, teaName As String)
    If teaCond Then
        Print "PASS  " + teaName
        tePassed = tePassed + 1
    Else
        Print "FAIL  " + teaName + "   (s=" + Chr$(34) + teS + Chr$(34) + " cur=" + LTrim$(Str$(teC)) + ")"
        teFailed = teFailed + 1
    End If
End Sub

' Type each char of teTxt$ at the cursor.
Sub TE_Type (teTxt As String, teMax As Integer)
    Dim teTI As Integer, teTU As Integer
    For teTI = 1 To Len(teTxt)
        teTU = TXE_Key%(teS, teC, Asc(Mid$(teTxt, teTI, 1)), teMax)
    Next teTI
End Sub

Sub TE_Press (teKey As Long, teTimes As Integer)
    Dim tePI As Integer, tePU As Integer
    For tePI = 1 To teTimes
        tePU = TXE_Key%(teS, teC, teKey, 32)
    Next tePI
End Sub

Dim teUsed As Integer, teOff As Integer, teI As Integer, teOk As Integer

Print "=== textedit_test ==="
Print ""

Print "--- length ---"
teS = "" : teC = 0
TE_Type "MAVERICKTHEGREAT", 32
TE_Assert teS = "MAVERICKTHEGREAT" And teC = 16, "a 16-char name types in full (no 12-char cap)"
teS = "" : teC = 0
TE_Type "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789", 32
TE_Assert teS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345" And teC = 32, "typing stops at the max length (32)"
teUsed = TXE_Key%(teS, teC, Asc("Z"), 32)
TE_Assert teUsed <> 0 And Len(teS) = 32, "a key at the max is consumed but adds nothing"

Print "--- insert, backspace, delete ---"
teS = "GOOSE" : teC = 5
TE_Press TXE_KEY_LEFT, 3
TE_Assert teC = 2, "left x3 from the end: cursor at 2"
TE_Type "XY", 32
TE_Assert teS = "GOXYOSE" And teC = 4, "typing mid-string inserts at the cursor"
TE_Press TXE_KEY_BKSP, 1
TE_Assert teS = "GOXOSE" And teC = 3, "backspace deletes the char before the cursor"
TE_Press TXE_KEY_DEL, 1
TE_Assert teS = "GOXSE" And teC = 3, "delete removes the char at the cursor, cursor stays"
TE_Press TXE_KEY_HOME, 1
TE_Assert teC = 0, "home: cursor at 0"
TE_Press TXE_KEY_BKSP, 1
TE_Assert teS = "GOXSE" And teC = 0, "backspace at the start does nothing"
TE_Press TXE_KEY_END, 1
TE_Assert teC = 5, "end: cursor at the length"
TE_Press TXE_KEY_DEL, 1
TE_Assert teS = "GOXSE" And teC = 5, "delete at the end does nothing"
TE_Press TXE_KEY_RIGHT, 1
TE_Assert teC = 5, "right at the end stays put"
TE_Press TXE_KEY_HOME, 1
TE_Press TXE_KEY_LEFT, 1
TE_Assert teC = 0, "left at the start stays put"
teS = "ICE" : teC = 99
TE_Press TXE_KEY_LEFT, 1
TE_Assert teC = 2, "an out-of-range cursor is clamped before the key applies"

Print "--- ~X color tokens ---"
teS = "AB~3CD" : teC = 4
TE_Press TXE_KEY_LEFT, 1
TE_Assert teC = 2, "left skips a ~X pair as one step"
TE_Press TXE_KEY_RIGHT, 1
TE_Assert teC = 4, "right skips a ~X pair as one step"
TE_Press TXE_KEY_BKSP, 1
TE_Assert teS = "ABCD" And teC = 2, "backspace after a token deletes the whole pair"
teS = "AB~eCD" : teC = 2
TE_Press TXE_KEY_DEL, 1
TE_Assert teS = "ABCD" And teC = 2, "delete before a token (lower-case hex) deletes the pair"
teS = "A~ZB" : teC = 3
TE_Press TXE_KEY_LEFT, 1
TE_Assert teC = 2, "~ before a non-hex char is plain text: left moves one"
teS = "AB" : teC = 1
TE_Type "~", 32
TE_Type "5", 32
TE_Assert teS = "A~5B" And teC = 3, "typing ~ then a hex digit builds a token"
teOk = TXE_IsTok%(teS, 2)
TE_Assert teOk <> 0, "TXE_IsTok% sees the new token"
teOk = TXE_IsTok%("AB~", 3)
TE_Assert teOk = 0, "a trailing ~ is not a token"

Print "--- non-editing keys ---"
teS = "VIPER" : teC = 5
teUsed = TXE_Key%(teS, teC, 18432, 32)
TE_Assert teUsed = 0 And teS = "VIPER" And teC = 5, "up arrow is not an editing key"
teUsed = TXE_Key%(teS, teC, 0, 32)
TE_Assert teUsed = 0 And teS = "VIPER", "no key: nothing happens"
teUsed = TXE_Key%(teS, teC, 15104, 32)
TE_Assert teUsed = 0 And teS = "VIPER", "F1 is not an editing key"

Print "--- visible columns ---"
teI = TXE_VisCol%("AB~3CD", 0, 6)
TE_Assert teI = 4, "tokens are zero width"
teI = TXE_VisCol%("AB~3CD", 2, 3)
TE_Assert teI = 0, "a cursor between ~ and its digit sits before the token"
teS = TXE_ColorAt$("~1AB~4CD", 6)
TE_Assert teS = "~4", "ColorAt: the last token before the offset"
teS = TXE_ColorAt$("~1AB~4CD", 4)
TE_Assert teS = "~1", "ColorAt: a later token does not count"
teS = TXE_ColorAt$("ABC", 3)
TE_Assert teS = "", "ColorAt: no token gives empty"

Print "--- scrolling (box of 10 columns) ---"
teS = "ABCDEFGHIJKLMNOPQRST"
teOff = TXE_Scroll%(teS, 20, 0, 10)
TE_Assert teOff = 11, "cursor at the end of 20 chars: 9 chars + cursor visible"
teI = TXE_VisCol%(teS, teOff, 20)
TE_Assert teI = 9, "the end cursor sits in the last column"
teOff = TXE_Scroll%(teS, 5, 11, 10)
TE_Assert teOff = 5, "moving left past the window scrolls back to the cursor"
teOff = TXE_Scroll%(teS, 0, 11, 10)
TE_Assert teOff = 0, "home scrolls to 0"
teOff = TXE_Scroll%(teS, 12, 5, 10)
TE_Assert teOff = 5, "a cursor inside the window does not scroll"
teOff = TXE_Scroll%("ABCDE", 5, 3, 10)
TE_Assert teOff = 0, "text that now fits pulls the scroll back to 0"
teOff = TXE_Scroll%("ABCDEFGHIJKLMN", 14, 11, 10)
TE_Assert teOff = 5, "after deleting from a scrolled name the window refills from the left"
teOff = TXE_Scroll%("~1ABCDEFGHIJKL", 14, 0, 10)
teI = TXE_VisCol%("~1ABCDEFGHIJKL", teOff, 14)
TE_Assert teOff = 5 And teI = 9, "a leading token does not take a column"
teOff = TXE_Scroll%("AB~3CDEFGHIJKLM", 3, 3, 10)
teOk = TXE_IsTok%("AB~3CDEFGHIJKLM", teOff)
TE_Assert teOff = 2 And teOk = 0, "a scroll offset never splits a token"
For teI = 0 To 32
    teS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
    teOff = TXE_Scroll%(teS, teI, 0, 18)
    If teI < teOff Or TXE_VisCol%(teS, teOff, teI) > 17 Then Exit For
Next teI
TE_Assert teI = 33, "every cursor in a 32-char name is visible in the 18-col box"

Print ""
Print "=== " + LTrim$(Str$(tePassed + teFailed)) + " tests: " + LTrim$(Str$(tePassed)) + " passed, " + LTrim$(Str$(teFailed)) + " failed ==="
If teFailed > 0 Then System 1 Else System 0
