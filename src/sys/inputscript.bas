' inputscript.bas -- scripted input for headless, repeatable playtests:
'   sss --input-script <file> [--frames N] [--seed N]
' replaces the keyboard and gamepad with a per-frame script, so the same script and
' seed play the same game. Script lines:
'
'   <from> <to> KEY [KEY ...]   hold the KEYs on frames from..to (inclusive, 0-based)
'   # comment                   blank lines and comments are ignored
'
' KEYs: LEFT RIGHT UP DOWN FIRE ESC TAB. Example (tests/input/boss-hold-left.txt):
'   0 1500 LEFT FIRE
'
' No rendering or game state here, so tests can drive it:
'   ok = ISC_ParseLine%(line$)      add one script line; 0 if it's malformed (see iscError)
'   ok = ISC_Load%(path$)           load a file; 0 on any error (see iscError)
'   ISC_Apply frame, held()         fill held() for that frame (all other keys up)
'   ISC_Clear
' Local variable prefix: isc*

Const ISC_MAX = 256

Dim Shared iscCount As Integer, iscActive As Integer, iscError As String
Dim Shared iscFrom(1 To ISC_MAX) As Long, iscTo(1 To ISC_MAX) As Long, iscKey(1 To ISC_MAX) As Long

Sub ISC_Clear
    iscCount = 0 : iscActive = 0 : iscError = ""
End Sub

' Script key name -> held() slot (E3D_KEY_*, input.bas); 0 if unknown.
Function ISC_KeyCode&(iscName As String)
    Select Case UCase$(iscName)
    Case "LEFT"  : ISC_KeyCode& = E3D_KEY_LEFT
    Case "RIGHT" : ISC_KeyCode& = E3D_KEY_RIGHT
    Case "UP"    : ISC_KeyCode& = E3D_KEY_UP
    Case "DOWN"  : ISC_KeyCode& = E3D_KEY_DOWN
    Case "FIRE"  : ISC_KeyCode& = E3D_KEY_SPACE
    Case "ESC"   : ISC_KeyCode& = E3D_KEY_ESCAPE
    Case "TAB"   : ISC_KeyCode& = E3D_KEY_TAB
    Case Else    : ISC_KeyCode& = 0
    End Select
End Function

' Next space-separated token of iscLine$ from position iscP (advanced past it).
Function ISC_Token$(iscLine As String, iscP As Integer)
    Dim iscS As Integer
    Do While iscP <= Len(iscLine) And Mid$(iscLine, iscP, 1) = " "
        iscP = iscP + 1
    Loop
    iscS = iscP
    Do While iscP <= Len(iscLine) And Mid$(iscLine, iscP, 1) <> " "
        iscP = iscP + 1
    Loop
    ISC_Token$ = Mid$(iscLine, iscS, iscP - iscS)
End Function

Function ISC_IsNum%(iscT As String)
    Dim iscI As Integer
    ISC_IsNum% = 0
    If iscT = "" Then Exit Function
    For iscI = 1 To Len(iscT)
        If Mid$(iscT, iscI, 1) < "0" Or Mid$(iscT, iscI, 1) > "9" Then Exit Function
    Next iscI
    ISC_IsNum% = -1
End Function

Function ISC_ParseLine%(iscRaw As String)
    Dim iscLine As String, iscP As Integer, iscT As String, iscF As Long, iscTo2 As Long
    Dim iscK As Long, iscN As Integer
    ISC_ParseLine% = 0
    iscLine = LTrim$(RTrim$(iscRaw))
    iscP = InStr(iscLine, Chr$(9))
    Do While iscP > 0
        Mid$(iscLine, iscP, 1) = " " : iscP = InStr(iscLine, Chr$(9))
    Loop
    If iscLine = "" Or Left$(iscLine, 1) = "#" Then ISC_ParseLine% = -1 : Exit Function
    iscP = 1
    iscT = ISC_Token$(iscLine, iscP)
    If ISC_IsNum%(iscT) = 0 Then iscError = "bad start frame in: " + iscLine : Exit Function
    iscF = Val(iscT)
    iscT = ISC_Token$(iscLine, iscP)
    If ISC_IsNum%(iscT) = 0 Then iscError = "bad end frame in: " + iscLine : Exit Function
    iscTo2 = Val(iscT)
    If iscTo2 < iscF Then iscError = "end frame before start in: " + iscLine : Exit Function
    Do
        iscT = ISC_Token$(iscLine, iscP)
        If iscT = "" Then Exit Do
        iscK = ISC_KeyCode&(iscT)
        If iscK = 0 Then iscError = "unknown key '" + iscT + "' in: " + iscLine : Exit Function
        If iscCount >= ISC_MAX Then iscError = "more than" + Str$(ISC_MAX) + " key ranges" : Exit Function
        iscCount = iscCount + 1
        iscFrom(iscCount) = iscF : iscTo(iscCount) = iscTo2 : iscKey(iscCount) = iscK
        iscN = iscN + 1
    Loop
    If iscN = 0 Then iscError = "no keys in: " + iscLine : Exit Function
    ISC_ParseLine% = -1
End Function

Function ISC_Load%(iscPath As String)
    Dim iscFH As Integer, iscL As String
    ISC_Load% = 0
    ISC_Clear
    If _FileExists(iscPath) = 0 Then iscError = "input script not found: " + iscPath : Exit Function
    iscFH = FreeFile
    Open iscPath For Input As #iscFH
    Do While Not EOF(iscFH)
        Line Input #iscFH, iscL
        If ISC_ParseLine%(iscL) = 0 Then Close #iscFH : Exit Function
    Loop
    Close #iscFH
    iscActive = -1
    ISC_Load% = -1
End Function

Sub ISC_Apply(iscFrame As Long, iscHeld() As Integer)
    Dim iscA As Long
    For iscA = LBound(iscHeld) To UBound(iscHeld) : iscHeld(iscA) = 0 : Next iscA
    For iscA = 1 To iscCount
        If iscFrame >= iscFrom(iscA) And iscFrame <= iscTo(iscA) Then iscHeld(iscKey(iscA)) = -1
    Next iscA
End Sub
