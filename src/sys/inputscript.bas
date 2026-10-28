' inputscript.bas -- scripted input for headless, repeatable playtests:
'   sss --input-script <file> [--frames N] [--seed N]
' replaces the keyboard and gamepad with a per-frame script, so the same script and
' seed play the same game. Script lines:
'
'   <from> <to> KEY [KEY ...]   hold the KEYs on frames from..to (inclusive, 0-based)
'   # comment                   blank lines and comments are ignored
'
' KEYs: LEFT RIGHT UP DOWN FIRE (= SPACE) ESC TAB ENTER BACKSPACE BACKTICK F1-F12,
' any letter A-Z (held as both its upper- and lower-case code), any digit 0-9, and
' #<code> for any other _KEYDOWN code (e.g. #21248 = Delete). Example
' (tests/input/boss-hold-left.txt):
'   0 1500 LEFT FIRE
'
' Gamepad: scripted pad input sets the raw pad state (padRawAxis / padRawBtn) and runs
' E3D_PadMap, exactly as a real controller's input does. Raw: PADBTN<n> holds button n,
' PADAXIS<n>- / PADAXIS<n>+ push axis n fully negative / positive. Named, in the default
' (Xbox 360 / xpad) layout: PAD_A PAD_B PAD_X PAD_Y PAD_START PAD_SELECT, the left stick
' PAD_LEFT PAD_RIGHT PAD_UP PAD_DOWN, the d-pad PAD_DPAD_LEFT PAD_DPAD_RIGHT PAD_DPAD_UP
' PAD_DPAD_DOWN. PAD_A holds SPACE and the PAD_A slot, PAD_START holds ESCAPE and
' PAD_START, the stick and d-pad hold the arrow slots; like a real pad they never show
' up in KEY_Down% or KEY_Hit&.
'
' Game code reads keys through KEY_Down% / KEY_Hit& (never _KEYDOWN / _KEYHIT directly),
' so every key in a script reaches every screen. KEY_Hit& reports one press per range,
' on its first frame, as _KEYHIT would (letters as unshifted lower case).
'
' Menus read logical actions, so the keyboard and the pad drive them alike:
'   KEY_FrameBegin                  once per frame, before held() is refilled
'   hit = KEY_Pressed%(slot)        held(slot) went down this frame
'   hit = KEY_Confirm%              ENTER or pad A pressed this frame
'   hit = KEY_Back%                 ESC, pad B or pad Start pressed this frame
' A press is seen on the one frame it goes down, so the button that opens a screen is
' never re-read by the screen it opens.
'
' No rendering or game state here, so tests can drive it:
'   ok = ISC_ParseLine%(line$)      add one script line; 0 if it's malformed (see iscError)
'   ok = ISC_Load%(path$)           load a file; 0 on any error (see iscError)
'   ISC_Apply frame, held()         fill held() for that frame (all other keys up), queue presses
'   down = KEY_Down%(code)          is the key down this frame (script, else _KEYDOWN)
'   code = KEY_Hit&                 next queued key press, 0 if none (script, else _KEYHIT)
'   ISC_Clear
' Local variable prefix: isc*

Const ISC_MAX = 1024
' script codes for the pad's raw state (never a real key code): PADBTN<n> is
' ISC_PAD_BTN - n, PADAXIS<n>- is ISC_PAD_AXNEG - n, PADAXIS<n>+ is ISC_PAD_AXPOS - n
Const ISC_PAD_BTN   = -1000
Const ISC_PAD_AXNEG = -2000
Const ISC_PAD_AXPOS = -3000

Dim Shared iscCount As Integer, iscActive As Integer, iscError As String
Dim Shared keyPrevHeld(0 To 32767) As Integer
Dim Shared iscFrom(1 To ISC_MAX) As Long, iscTo(1 To ISC_MAX) As Long, iscKey(1 To ISC_MAX) As Long
Dim Shared iscAlt(1 To ISC_MAX) As Long
Dim Shared iscFrame As Long
Dim Shared iscHitQ(1 To ISC_MAX) As Long, iscHitHead As Integer, iscHitTail As Integer

Sub ISC_Clear
    iscCount = 0 : iscActive = 0 : iscError = ""
    iscFrame = -1 : iscHitHead = 0 : iscHitTail = 0
End Sub

' Script key name -> its _KEYDOWN code (which is also its held() slot when it has one)
' and, for letters, the other case's code. Returns 0 if the name is unknown.
Function ISC_KeyInfo%(iscName As String, iscCode As Long, iscAltCode As Long)
    Dim iscU As String, iscFn As Long
    iscU = UCase$(iscName)
    iscCode = 0 : iscAltCode = 0
    Select Case iscU
    Case "LEFT"      : iscCode = E3D_KEY_LEFT
    Case "RIGHT"     : iscCode = E3D_KEY_RIGHT
    Case "UP"        : iscCode = E3D_KEY_UP
    Case "DOWN"      : iscCode = E3D_KEY_DOWN
    Case "FIRE", "SPACE" : iscCode = E3D_KEY_SPACE
    Case "ESC"       : iscCode = E3D_KEY_ESCAPE
    Case "TAB"       : iscCode = E3D_KEY_TAB
    Case "ENTER"     : iscCode = 13
    Case "BACKSPACE" : iscCode = 8
    Case "BACKTICK"  : iscCode = 96
    Case "F11"       : iscCode = 34048
    Case "F12"       : iscCode = 34304
    Case "PAD_A"      : iscCode = ISC_PAD_BTN - E3D_CTRL_BTN_FIRE
    Case "PAD_B"      : iscCode = ISC_PAD_BTN - E3D_CTRL_BTN_B
    Case "PAD_X"      : iscCode = ISC_PAD_BTN - E3D_CTRL_BTN_X
    Case "PAD_Y"      : iscCode = ISC_PAD_BTN - E3D_CTRL_BTN_Y
    Case "PAD_START"  : iscCode = ISC_PAD_BTN - E3D_CTRL_BTN_START
    Case "PAD_SELECT" : iscCode = ISC_PAD_BTN - E3D_CTRL_BTN_SELECT
    Case "PAD_LEFT"   : iscCode = ISC_PAD_AXNEG - E3D_CTRL_AXIS_X
    Case "PAD_RIGHT"  : iscCode = ISC_PAD_AXPOS - E3D_CTRL_AXIS_X
    Case "PAD_UP"     : iscCode = ISC_PAD_AXNEG - E3D_CTRL_AXIS_Y
    Case "PAD_DOWN"   : iscCode = ISC_PAD_AXPOS - E3D_CTRL_AXIS_Y
    Case "PAD_DPAD_LEFT"  : iscCode = ISC_PAD_AXNEG - E3D_CTRL_HAT_X
    Case "PAD_DPAD_RIGHT" : iscCode = ISC_PAD_AXPOS - E3D_CTRL_HAT_X
    Case "PAD_DPAD_UP"    : iscCode = ISC_PAD_AXNEG - E3D_CTRL_HAT_Y
    Case "PAD_DPAD_DOWN"  : iscCode = ISC_PAD_AXPOS - E3D_CTRL_HAT_Y
    Case Else
        If Len(iscU) = 1 And iscU >= "A" And iscU <= "Z" Then
            iscCode = Asc(LCase$(iscU)) : iscAltCode = Asc(iscU)
        ElseIf Len(iscU) = 1 And iscU >= "0" And iscU <= "9" Then
            iscCode = Asc(iscU)
        ElseIf Left$(iscU, 1) = "F" And ISC_IsNum%(Mid$(iscU, 2)) Then
            iscFn = Val(Mid$(iscU, 2))
            If iscFn >= 1 And iscFn <= 10 Then iscCode = 15104 + (iscFn - 1) * 256
        ElseIf Left$(iscU, 6) = "PADBTN" And ISC_IsNum%(Mid$(iscU, 7)) Then
            iscFn = Val(Mid$(iscU, 7))
            If iscFn >= 1 And iscFn <= E3D_PAD_MAX_BTNS Then iscCode = ISC_PAD_BTN - iscFn
        ElseIf Left$(iscU, 7) = "PADAXIS" And Len(iscU) > 8 And ISC_IsNum%(Mid$(iscU, 8, Len(iscU) - 8)) Then
            iscFn = Val(Mid$(iscU, 8, Len(iscU) - 8))
            If iscFn >= 1 And iscFn <= E3D_PAD_MAX_AXES Then
                If Right$(iscU, 1) = "-" Then iscCode = ISC_PAD_AXNEG - iscFn
                If Right$(iscU, 1) = "+" Then iscCode = ISC_PAD_AXPOS - iscFn
            End If
        ElseIf Left$(iscU, 1) = "#" And ISC_IsNum%(Mid$(iscU, 2)) Then
            iscCode = Val(Mid$(iscU, 2))
        End If
    End Select
    ISC_KeyInfo% = (iscCode <> 0)
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
    Dim iscK As Long, iscK2 As Long, iscN As Integer
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
        If ISC_KeyInfo%(iscT, iscK, iscK2) = 0 Then iscError = "unknown key '" + iscT + "' in: " + iscLine : Exit Function
        If iscCount >= ISC_MAX Then iscError = "more than" + Str$(ISC_MAX) + " key ranges" : Exit Function
        iscCount = iscCount + 1
        iscFrom(iscCount) = iscF : iscTo(iscCount) = iscTo2 : iscKey(iscCount) = iscK : iscAlt(iscCount) = iscK2
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

' Scripted pad input sets the raw pad state, then runs the real pad mapping (E3D_PadMap).
Sub ISC_Apply(iscFrameNo As Long, iscHeld() As Integer)
    Dim iscA As Long, iscK As Long, iscKAny As Integer
    iscFrame = iscFrameNo
    iscKAny = 0
    For iscA = LBound(iscHeld) To UBound(iscHeld) : iscHeld(iscA) = 0 : Next iscA
    For iscA = 1 To E3D_PAD_MAX_AXES : padRawAxis(iscA) = 0 : Next iscA
    For iscA = 1 To E3D_PAD_MAX_BTNS : padRawBtn(iscA) = 0 : Next iscA
    For iscA = 1 To iscCount
        If iscFrameNo >= iscFrom(iscA) And iscFrameNo <= iscTo(iscA) Then
            iscK = iscKey(iscA)
            Select Case iscK
            Case ISC_PAD_BTN - E3D_PAD_MAX_BTNS To ISC_PAD_BTN - 1     : padRawBtn(ISC_PAD_BTN - iscK) = 1
            Case ISC_PAD_AXNEG - E3D_PAD_MAX_AXES To ISC_PAD_AXNEG - 1 : padRawAxis(ISC_PAD_AXNEG - iscK) = -1
            Case ISC_PAD_AXPOS - E3D_PAD_MAX_AXES To ISC_PAD_AXPOS - 1 : padRawAxis(ISC_PAD_AXPOS - iscK) = 1
            Case Else
                If iscK > 0 And iscK <= UBound(iscHeld) Then iscHeld(iscK) = -1
                If iscK > 0 Then iscKAny = -1
            End Select
        End If
        If iscFrameNo = iscFrom(iscA) And iscKey(iscA) > 0 And iscHitTail < ISC_MAX Then
            iscHitTail = iscHitTail + 1 : iscHitQ(iscHitTail) = iscKey(iscA)
        End If
    Next iscA
    INP_NoteKeys iscKAny
    E3D_PadMap iscHeld()
End Sub

Sub KEY_FrameBegin
    Dim keyFbI As Long
    For keyFbI = 0 To 32767 : keyPrevHeld(keyFbI) = held(keyFbI) : Next keyFbI
End Sub

Function KEY_Pressed%(keyPSlot As Long)
    KEY_Pressed% = (held(keyPSlot) <> 0 And keyPrevHeld(keyPSlot) = 0)
End Function

Function KEY_Confirm%
    KEY_Confirm% = KEY_Pressed%(E3D_KEY_ENTER) Or KEY_Pressed%(E3D_KEY_PAD_A)
End Function

' ESC's slot is also set by pad Start
Function KEY_Back%
    KEY_Back% = KEY_Pressed%(E3D_KEY_ESCAPE) Or KEY_Pressed%(E3D_KEY_PAD_B)
End Function

Function KEY_Down%(iscDCode As Long)
    Dim iscDA As Integer
    If iscActive = 0 Then KEY_Down% = _KeyDown(iscDCode) : Exit Function
    KEY_Down% = 0
    For iscDA = 1 To iscCount
        If iscFrame >= iscFrom(iscDA) And iscFrame <= iscTo(iscDA) Then
            If iscKey(iscDA) = iscDCode Or iscAlt(iscDA) = iscDCode Then KEY_Down% = -1 : Exit Function
        End If
    Next iscDA
End Function

Function KEY_Hit&
    If iscActive = 0 Then KEY_Hit& = _KeyHit : Exit Function
    KEY_Hit& = 0
    If iscHitHead >= iscHitTail Then iscHitHead = 0 : iscHitTail = 0 : Exit Function
    iscHitHead = iscHitHead + 1
    KEY_Hit& = iscHitQ(iscHitHead)
End Function
