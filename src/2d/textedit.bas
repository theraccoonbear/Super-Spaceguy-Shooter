' textedit.bas -- one-line text editing over a raw string that may hold ~X color tokens.
' Pure: no drawing and no input reads. The callsign screen (src/state/username.bas) drives it;
' tests/textedit_test.bas covers it.
'
' Cursor and scroll are raw offsets into the string: 0 = before the first char. A ~X pair
' (X = 0-9/A-F, the FONT_PrintRichAlpha color code) is zero width and moves/deletes as one.
'
'   TXE_IsTok%(s$, p)                 -1 if a ~X token starts at raw char p (1-based)
'   TXE_Left%(s$, cur) / TXE_Right%   the cursor one step left / right
'   handled = TXE_Key%(s$, cur, key&, maxLen)  apply one KEY_Hit& code to s$ and cur
'   TXE_VisCol%(s$, fromRaw, toRaw)   visible columns between two raw offsets
'   TXE_Scroll%(s$, cur, scroll, cols)  scroll offset keeping the cursor inside a cols-wide box
'   TXE_ColorAt$(s$, raw)             the last ~X token before raw offset, "" if none
' Local variable prefix: txe*

Const TXE_KEY_LEFT  = 19200
Const TXE_KEY_RIGHT = 19712
Const TXE_KEY_HOME  = 18176
Const TXE_KEY_END   = 20224
Const TXE_KEY_DEL   = 21248
Const TXE_KEY_BKSP  = 8

Function TXE_IsTok% (txeS As String, txeP As Integer)
    Dim txeH As Integer
    TXE_IsTok% = 0
    If txeP < 1 Or txeP >= Len(txeS) Then Exit Function
    If Mid$(txeS, txeP, 1) <> "~" Then Exit Function
    txeH = Asc(UCase$(Mid$(txeS, txeP + 1, 1)))
    If (txeH >= 48 And txeH <= 57) Or (txeH >= 65 And txeH <= 70) Then TXE_IsTok% = -1
End Function

Function TXE_Left% (txeLS As String, txeLC As Integer)
    If txeLC <= 0 Then TXE_Left% = 0 : Exit Function
    If txeLC >= 2 And TXE_IsTok%(txeLS, txeLC - 1) Then
        TXE_Left% = txeLC - 2
    Else
        TXE_Left% = txeLC - 1
    End If
End Function

Function TXE_Right% (txeRS As String, txeRC As Integer)
    If txeRC >= Len(txeRS) Then TXE_Right% = Len(txeRS) : Exit Function
    If TXE_IsTok%(txeRS, txeRC + 1) Then
        TXE_Right% = txeRC + 2
    Else
        TXE_Right% = txeRC + 1
    End If
End Function

Function TXE_Key% (txeKS As String, txeKC As Integer, txeKey As Long, txeMax As Integer)
    Dim txeN As Integer
    If txeKC < 0 Then txeKC = 0
    If txeKC > Len(txeKS) Then txeKC = Len(txeKS)
    TXE_Key% = -1
    Select Case txeKey
        Case TXE_KEY_LEFT : txeKC = TXE_Left%(txeKS, txeKC)
        Case TXE_KEY_RIGHT : txeKC = TXE_Right%(txeKS, txeKC)
        Case TXE_KEY_HOME : txeKC = 0
        Case TXE_KEY_END : txeKC = Len(txeKS)
        Case TXE_KEY_BKSP
            txeN = txeKC - TXE_Left%(txeKS, txeKC)
            txeKS = Left$(txeKS, txeKC - txeN) + Mid$(txeKS, txeKC + 1)
            txeKC = txeKC - txeN
        Case TXE_KEY_DEL
            txeN = TXE_Right%(txeKS, txeKC) - txeKC
            txeKS = Left$(txeKS, txeKC) + Mid$(txeKS, txeKC + txeN + 1)
        Case 32 To 126
            If Len(txeKS) < txeMax Then
                txeKS = Left$(txeKS, txeKC) + Chr$(txeKey) + Mid$(txeKS, txeKC + 1)
                txeKC = txeKC + 1
            End If
        Case Else
            TXE_Key% = 0
    End Select
End Function

' A token that straddles toRaw (cursor between its ~ and X) is zero width, as it renders.
Function TXE_VisCol% (txeVS As String, txeFrom As Integer, txeTo As Integer)
    Dim txeVI As Integer, txeVN As Integer
    txeVI = txeFrom + 1
    Do While txeVI <= txeTo
        If TXE_IsTok%(txeVS, txeVI) Then
            txeVI = txeVI + 2
        Else
            txeVN = txeVN + 1 : txeVI = txeVI + 1
        End If
    Loop
    TXE_VisCol% = txeVN
End Function

' Columns 0..cols-1 are visible; the cursor needs a column of its own at the end of the text.
Function TXE_Scroll% (txeSS As String, txeSC As Integer, txeOff As Integer, txeCols As Integer)
    Dim txeO As Integer, txeP As Integer
    txeO = txeOff
    If txeO > txeSC Then txeO = txeSC
    If txeO < 0 Then txeO = 0
    If txeO > 0 And TXE_IsTok%(txeSS, txeO) Then txeO = txeO - 1
    Do While TXE_VisCol%(txeSS, txeO, txeSC) > txeCols - 1
        txeO = TXE_Right%(txeSS, txeO)
    Loop
    Do While txeO > 0
        txeP = TXE_Left%(txeSS, txeO)
        If TXE_VisCol%(txeSS, txeP, Len(txeSS)) > txeCols - 1 Then Exit Do
        txeO = txeP
    Loop
    TXE_Scroll% = txeO
End Function

Function TXE_ColorAt$ (txeCS As String, txeRaw As Integer)
    Dim txeCI As Integer, txeTok As String
    For txeCI = 1 To txeRaw - 1
        If TXE_IsTok%(txeCS, txeCI) Then txeTok = Mid$(txeCS, txeCI, 2)
    Next txeCI
    TXE_ColorAt$ = txeTok
End Function
