' usernamelogic.bas -- the callsign screen's input, no drawing (username.bas draws it)
'
' r = UN_Input%(s$, cur, maxLen)   once per frame; edits s$ / cur and returns UN_NONE, UN_EDIT,
'                                  UN_DONE or UN_SKIP.
' Keyboard (always): ENTER / SPACE done, ESC skip, any other key goes to TXE_Key%.
' Pad (while INP_LastDevice% is the pad) is an arcade letter spinner: up / down spin the
' character under the cursor through UN_SPIN_SET (wrapping; held, it repeats after
' UN_REP_DELAY frames, then every UN_REP_EVERY), left / right move one character, A = next
' character, B = delete, Y = cycle its ~X color, Start = done, Back = skip. Both edit the
' same string and cursor, so switching device mid-entry carries straight on.
'
' The pad's character under the cursor is the first one at or after cur, ~X tokens skipped;
' none means the empty slot past the end, where up / down / right add a character. Moving
' on from the last character appends an "A".
'   p = UN_SpinAt%(s$, cur)               raw index (1-based) of that character, 0 = empty slot
'   UN_PadSpin s$, cur, dir, maxLen       dir 1 = next in UN_SPIN_SET, -1 = previous
'   UN_PadLeft s$, cur                    onto the previous character
'   UN_PadNext s$, cur, maxLen            onto the next character (appending at the end)
'   UN_PadDel s$, cur                     delete it and step back (the empty slot: backspace)
'   UN_PadColor s$, cur, maxLen           its color to the next ~X code; the rest keep theirs
' Local variable prefix: ul*

Const UN_NONE = 0
Const UN_EDIT = 1
Const UN_DONE = 2
Const UN_SKIP = 3
Const UN_SPIN_SET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -."
Const UN_REP_DELAY = 18
Const UN_REP_EVERY = 5

Dim Shared unRepDir As Integer, unRepN As Integer

Function UN_SpinAt% (ulAS As String, ulAC As Integer)
    Dim ulAP As Integer
    ulAP = ulAC + 1
    Do While TXE_IsTok%(ulAS, ulAP)
        ulAP = ulAP + 2
    Loop
    If ulAP > Len(ulAS) Then ulAP = 0
    UN_SpinAt% = ulAP
End Function

Sub UN_PadAppend (ulPS As String, ulPC As Integer, ulPCh As String, ulPMax As Integer)
    If Len(ulPS) >= ulPMax Then Exit Sub
    ulPS = ulPS + ulPCh
    ulPC = Len(ulPS) - 1
End Sub

Sub UN_PadSpin (ulSS As String, ulSC As Integer, ulSDir As Integer, ulSMax As Integer)
    Dim ulSP As Integer, ulSI As Integer, ulSN As Integer
    ulSN = Len(UN_SPIN_SET)
    ulSP = UN_SpinAt%(ulSS, ulSC)
    If ulSP = 0 Then
        If ulSDir > 0 Then UN_PadAppend ulSS, ulSC, Left$(UN_SPIN_SET, 1), ulSMax Else UN_PadAppend ulSS, ulSC, Right$(UN_SPIN_SET, 1), ulSMax
        Exit Sub
    End If
    ' a character outside the set (typed on the keyboard) spins in from either end
    ulSI = InStr(UN_SPIN_SET, UCase$(Mid$(ulSS, ulSP, 1)))
    If ulSI = 0 And ulSDir < 0 Then ulSI = ulSN + 1
    ulSI = ((ulSI - 1 + ulSDir) Mod ulSN + ulSN) Mod ulSN + 1
    Mid$(ulSS, ulSP, 1) = Mid$(UN_SPIN_SET, ulSI, 1)
End Sub

Sub UN_PadLeft (ulLS As String, ulLC As Integer)
    Dim ulLP As Integer, ulLX As Integer
    ulLP = UN_SpinAt%(ulLS, ulLC)
    ulLX = ulLC
    Do While ulLX > 0
        ulLX = TXE_Left%(ulLS, ulLX)
        If UN_SpinAt%(ulLS, ulLX) <> ulLP Then ulLC = ulLX : Exit Sub
    Loop
End Sub

Sub UN_PadNext (ulNS As String, ulNC As Integer, ulNMax As Integer)
    Dim ulNP As Integer
    ulNP = UN_SpinAt%(ulNS, ulNC)
    If ulNP > 0 Then
        ulNC = ulNP
        If UN_SpinAt%(ulNS, ulNC) > 0 Then Exit Sub
    End If
    UN_PadAppend ulNS, ulNC, "A", ulNMax
End Sub

Sub UN_PadDel (ulDS As String, ulDC As Integer)
    Dim ulDP As Integer, ulDX As Integer
    ulDP = UN_SpinAt%(ulDS, ulDC)
    If ulDP > 0 Then
        ulDS = Left$(ulDS, ulDP - 1) + Mid$(ulDS, ulDP + 1)
        UN_PadLeft ulDS, ulDC
        Exit Sub
    End If
    ulDX = ulDC
    UN_PadLeft ulDS, ulDX
    ulDP = UN_SpinAt%(ulDS, ulDX)
    If ulDP = 0 Then Exit Sub
    ulDS = Left$(ulDS, ulDP - 1) + Mid$(ulDS, ulDP + 1)
    ulDC = ulDC - 1
End Sub

' A token goes right before the character, and the color in force before goes back on right
' after it when more text follows, so only this character changes.
Sub UN_PadColor (ulCS As String, ulCC As Integer, ulCMax As Integer)
    Dim ulCP As Integer, ulCOld As String, ulCNew As String, ulCPre As Integer, ulCRest As Integer, ulCAdd As Integer
    ulCP = UN_SpinAt%(ulCS, ulCC)
    If ulCP = 0 Then Exit Sub
    ulCOld = TXE_ColorAt$(ulCS, ulCP)
    If ulCOld = "" Then ulCOld = "~F"
    ulCNew = Mid$("0123456789ABCDEF", InStr("0123456789ABCDEF", UCase$(Right$(ulCOld, 1))) Mod 16 + 1, 1)
    ulCPre = 0
    If ulCP >= 3 Then ulCPre = TXE_IsTok%(ulCS, ulCP - 2)
    ulCRest = 0
    If UN_SpinAt%(ulCS, ulCP) > 0 And TXE_IsTok%(ulCS, ulCP + 1) = 0 Then ulCRest = -1
    ulCAdd = 0
    If ulCPre = 0 Then ulCAdd = 2
    If ulCRest Then ulCAdd = ulCAdd + 2
    If Len(ulCS) + ulCAdd > ulCMax Then Exit Sub
    If ulCRest Then ulCS = Left$(ulCS, ulCP) + ulCOld + Mid$(ulCS, ulCP + 1)
    If ulCPre Then
        Mid$(ulCS, ulCP - 1, 1) = ulCNew
    Else
        ulCS = Left$(ulCS, ulCP - 1) + "~" + ulCNew + Mid$(ulCS, ulCP)
    End If
End Sub

Function UN_Input% (ulIS As String, ulIC As Integer, ulIMax As Integer)
    Dim ulIKey As Long, ulIS0 As String, ulIC0 As Integer, ulIHeld As Integer, ulIRep As Integer
    UN_Input% = UN_NONE
    ulIKey = KEY_Hit&
    Select Case ulIKey
        Case 0
        Case 13, 32 : UN_Input% = UN_DONE : Exit Function
        Case 27 : UN_Input% = UN_SKIP : Exit Function
        Case Else
            If TXE_Key%(ulIS, ulIC, ulIKey, ulIMax) Then UN_Input% = UN_EDIT
    End Select
    If INP_LastDevice% <> INP_DEV_PAD Then unRepDir = 0 : Exit Function
    If KEY_Pressed%(E3D_KEY_PAD_START) Then UN_Input% = UN_DONE : Exit Function
    If KEY_Pressed%(E3D_KEY_PAD_SELECT) Then UN_Input% = UN_SKIP : Exit Function

    ulIS0 = ulIS : ulIC0 = ulIC
    If ulIC < 0 Then ulIC = 0
    If ulIC > Len(ulIS) Then ulIC = Len(ulIS)
    If KEY_Pressed%(E3D_KEY_UP) Then
        unRepDir = 1 : unRepN = 0 : UN_PadSpin ulIS, ulIC, 1, ulIMax
    ElseIf KEY_Pressed%(E3D_KEY_DOWN) Then
        unRepDir = -1 : unRepN = 0 : UN_PadSpin ulIS, ulIC, -1, ulIMax
    Else
        ulIHeld = 0
        If unRepDir > 0 And held(E3D_KEY_UP) <> 0 Then ulIHeld = -1
        If unRepDir < 0 And held(E3D_KEY_DOWN) <> 0 Then ulIHeld = -1
        If ulIHeld Then
            unRepN = unRepN + 1
            ulIRep = unRepDir
            If unRepN >= UN_REP_DELAY And (unRepN - UN_REP_DELAY) Mod UN_REP_EVERY = 0 Then UN_PadSpin ulIS, ulIC, ulIRep, ulIMax
        Else
            unRepDir = 0
        End If
    End If
    If KEY_Pressed%(E3D_KEY_LEFT) Then UN_PadLeft ulIS, ulIC
    If KEY_Pressed%(E3D_KEY_RIGHT) Or KEY_Pressed%(E3D_KEY_PAD_A) Then UN_PadNext ulIS, ulIC, ulIMax
    If KEY_Pressed%(E3D_KEY_PAD_B) Then UN_PadDel ulIS, ulIC
    If KEY_Pressed%(E3D_KEY_PAD_Y) Then UN_PadColor ulIS, ulIC, ulIMax
    If ulIS <> ulIS0 Or ulIC <> ulIC0 Then UN_Input% = UN_EDIT
End Function
