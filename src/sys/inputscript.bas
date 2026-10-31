' inputscript.bas -- scripted input for headless, repeatable playtests:
'   sss --input-script <file> [--frames N] [--seed N]
' replaces the keyboard and gamepad with a per-frame script, so the same script and
' seed play the same game. Script lines:
'
'   <from> <to> KEY [KEY ...]   hold the KEYs on frames from..to (inclusive, 0-based)
'   # comment                   blank lines and comments are ignored
'
' A line can also follow the game instead of the clock (#328):
'   @<trigger> +<offset> [<len> | *] [every <n>] KEY [KEY ...]
' holds the KEYs <offset> frames after each entry into <trigger>, for <len> frames
' (default 1), or with * for as long as the trigger lasts; "every <n>" repeats that hold
' every n frames. A number after the offset is always the length, so a digit key needs
' one first: @GS_USERNAME +3 1 7. Triggers:
'   GS_<STATE>          a game state, named as DBG_StateName$ names it (GS_TITLE, GS_CRAWL...)
'   label:<name>        a sequence step label from assets/sequence.txt (label:level3),
'                       entered when the current step's label becomes <name>
'   either + #<n>       only its nth entry (GS_TITLE#1 = the first title, not the last)
' A triggered line holds only while its trigger is current: leaving the state or label
' lets go, so a hold never leaks into the next screen. +0 is the first frame the game
' runs in that state, the frame the milestone log gives it. For example:
'   @GS_CRAWL +60 1 FIRE ESC            skip every crawl as soon as it lets you
'   @GS_PLAYING +0 * FIRE               fire through every flight
'   @GS_PLAYING +0 60 every 240 LEFT    LEFT for the first 60 of every 240 frames
'
' A script can also say how it must be launched (#324), so it can't be paired with the
' wrong seed or flags:
'   #! seed 1                   as --seed 1
'   #! args --god --nerf        launch flags (repeatable); not --seed, --frames, --input-script
'   #! frames 20000             as --frames 20000
' The header's flags are added to the command line's. Giving one there too is fine when
' the values match; a different value (--seed 7 against "#! seed 1") is an error unless
' --script-override, and then the command line wins. A colon after the key is allowed;
' the render harness's group / shots / mask keys are skipped; any other key is an error.
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
'   ok = ISC_MergeArgs%(cli$, override, out$)  out$ = cli$ plus the header; 0 on a contradiction
'   ISC_SetContext state$, label$   where the game is this frame, for @ lines (before ISC_Apply)
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
Dim Shared iscHdrSeed As String, iscHdrFrames As String, iscHdrArgs As String
' @ lines: iscTrig 0 = by frame, ISC_TRIG_STATE / ISC_TRIG_LABEL = on entry to iscTrigName
' (its iscTrigNth entry only, 0 = every one); then iscFrom is the offset, iscLen the hold
' (ISC_LEN_ALL = while the trigger lasts), iscEvery the repeat (0 = once). iscEntry is the
' frame of the current entry (-1 = not in it), iscSeen the entries so far.
Const ISC_TRIG_STATE = 1
Const ISC_TRIG_LABEL = 2
Const ISC_LEN_ALL = -1
Const ISC_STATES = " GS_TITLE GS_PLAYING GS_GAMEOVER GS_PLANET GS_CINEMATIC GS_INTRO GS_CRAWL GS_OPTIONS GS_ABOUT GS_LEADIN GS_CONSENT GS_USERNAME GS_LEADERBOARD GS_CONTROLS GS_CRAWLS GS_DOCK GS_REMAP "
Dim Shared iscTrig(1 To ISC_MAX) As Integer, iscTrigName(1 To ISC_MAX) As String, iscTrigNth(1 To ISC_MAX) As Integer
Dim Shared iscLen(1 To ISC_MAX) As Long, iscEvery(1 To ISC_MAX) As Long
Dim Shared iscEntry(1 To ISC_MAX) As Long, iscSeen(1 To ISC_MAX) As Integer, iscOn(1 To ISC_MAX) As Integer
Dim Shared iscCtxState As String, iscCtxLabel As String, iscPrevState As String, iscPrevLabel As String

Sub ISC_Clear
    iscCount = 0 : iscActive = 0 : iscError = ""
    iscHdrSeed = "" : iscHdrFrames = "" : iscHdrArgs = ""
    iscFrame = -1 : iscHitHead = 0 : iscHitTail = 0
    iscCtxState = "" : iscCtxLabel = "" : iscPrevState = "" : iscPrevLabel = ""
End Sub

Sub ISC_SetContext(iscSCState As String, iscSCLabel As String)
    iscCtxState = UCase$(iscSCState) : iscCtxLabel = UCase$(iscSCLabel)
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
    If Left$(iscLine, 2) = "#!" Then ISC_ParseLine% = ISC_ParseHeader%(Mid$(iscLine, 3), iscLine) : Exit Function
    If iscLine = "" Or Left$(iscLine, 1) = "#" Then ISC_ParseLine% = -1 : Exit Function
    If Left$(iscLine, 1) = "@" Then ISC_ParseLine% = ISC_ParseEvent%(iscLine) : Exit Function
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
        iscTrig(iscCount) = 0 : iscOn(iscCount) = 0
        iscN = iscN + 1
    Loop
    If iscN = 0 Then iscError = "no keys in: " + iscLine : Exit Function
    ISC_ParseLine% = -1
End Function

' An "@" line: @<trigger>[#n] +<offset> [<len> | *] [every <n>] KEY ...
Function ISC_ParseEvent%(iscELine As String)
    Dim iscEP As Integer, iscET As String, iscEKind As Integer, iscEName As String, iscENth As Integer
    Dim iscEOff As Long, iscELen As Long, iscEEvery As Long, iscEK As Long, iscEK2 As Long, iscEN As Integer
    Dim iscEHash As Integer
    ISC_ParseEvent% = 0
    iscEP = 2
    iscET = UCase$(ISC_Token$(iscELine, iscEP))
    iscEHash = InStr(iscET, "#")
    If iscEHash > 0 Then
        If ISC_IsNum%(Mid$(iscET, iscEHash + 1)) = 0 Then iscError = "bad #<entry> in: " + iscELine : Exit Function
        iscENth = Val(Mid$(iscET, iscEHash + 1))
        If iscENth < 1 Then iscError = "entries count from #1 in: " + iscELine : Exit Function
        iscET = Left$(iscET, iscEHash - 1)
    End If
    If Left$(iscET, 6) = "LABEL:" Then
        iscEKind = ISC_TRIG_LABEL : iscEName = Mid$(iscET, 7)
        If iscEName = "" Then iscError = "label: needs a name in: " + iscELine : Exit Function
    Else
        If iscET = "" Or InStr(ISC_STATES, " " + iscET + " ") = 0 Then iscError = "unknown trigger '" + iscET + "' (a GS_ state or label:<name>) in: " + iscELine : Exit Function
        iscEKind = ISC_TRIG_STATE : iscEName = iscET
    End If
    iscET = ISC_Token$(iscELine, iscEP)
    If Left$(iscET, 1) <> "+" Or ISC_IsNum%(Mid$(iscET, 2)) = 0 Then iscError = "bad +<offset> in: " + iscELine : Exit Function
    iscEOff = Val(Mid$(iscET, 2))
    iscELen = 1
    iscET = ISC_Token$(iscELine, iscEP)
    If iscET = "*" Then
        iscELen = ISC_LEN_ALL : iscET = ISC_Token$(iscELine, iscEP)
    ElseIf ISC_IsNum%(iscET) Then
        iscELen = Val(iscET) : iscET = ISC_Token$(iscELine, iscEP)
        If iscELen < 1 Then iscError = "hold length must be at least 1 in: " + iscELine : Exit Function
    End If
    If UCase$(iscET) = "EVERY" Then
        iscET = ISC_Token$(iscELine, iscEP)
        If ISC_IsNum%(iscET) = 0 Then iscError = "every needs a frame count in: " + iscELine : Exit Function
        iscEEvery = Val(iscET)
        If iscELen = ISC_LEN_ALL Or iscELen >= iscEEvery Then iscError = "every <n> needs a hold shorter than n in: " + iscELine : Exit Function
        iscET = ISC_Token$(iscELine, iscEP)
    End If
    Do
        If iscET = "" Then Exit Do
        If ISC_KeyInfo%(iscET, iscEK, iscEK2) = 0 Then iscError = "unknown key '" + iscET + "' in: " + iscELine : Exit Function
        If iscCount >= ISC_MAX Then iscError = "more than" + Str$(ISC_MAX) + " key ranges" : Exit Function
        iscCount = iscCount + 1
        iscKey(iscCount) = iscEK : iscAlt(iscCount) = iscEK2
        iscTrig(iscCount) = iscEKind : iscTrigName(iscCount) = iscEName : iscTrigNth(iscCount) = iscENth
        iscFrom(iscCount) = iscEOff : iscLen(iscCount) = iscELen : iscEvery(iscCount) = iscEEvery
        iscEntry(iscCount) = -1 : iscSeen(iscCount) = 0 : iscOn(iscCount) = 0
        iscEN = iscEN + 1
        iscET = ISC_Token$(iscELine, iscEP)
    Loop
    If iscEN = 0 Then iscError = "no keys (a number after the offset is the length) in: " + iscELine : Exit Function
    ISC_ParseEvent% = -1
End Function

' A "#!" header line: seed N, frames N or args <flags>; a colon after the key is optional.
' group, shots and mask are tests/render/run.sh's, so the game skips them.
Function ISC_ParseHeader%(iscHBody As String, iscHWhole As String)
    Dim iscHP As Integer, iscHKey As String, iscHRest As String, iscHArgs As String
    ISC_ParseHeader% = 0
    iscHP = 1
    iscHKey = LCase$(ISC_Token$(iscHBody, iscHP))
    If Right$(iscHKey, 1) = ":" Then iscHKey = Left$(iscHKey, Len(iscHKey) - 1)
    iscHRest = LTrim$(Mid$(iscHBody, iscHP))
    Select Case iscHKey
    Case "seed", "frames"
        If ISC_IsNum%(iscHRest) = 0 Then iscError = "header " + iscHKey + " needs one whole number in: " + iscHWhole : Exit Function
        If iscHKey = "seed" Then
            If iscHdrSeed <> "" Then iscError = "header seed given twice in: " + iscHWhole : Exit Function
            iscHdrSeed = iscHRest
        Else
            If iscHdrFrames <> "" Then iscError = "header frames given twice in: " + iscHWhole : Exit Function
            iscHdrFrames = iscHRest
        End If
    Case "args"
        If ISC_CheckArgs%(iscHRest, iscHArgs) = 0 Then iscError = iscError + " in: " + iscHWhole : Exit Function
        iscHdrArgs = LTrim$(iscHdrArgs + " " + iscHArgs)
    Case "group", "shots", "mask"
    Case Else
        iscError = "unknown header key '" + iscHKey + "' (seed, args or frames) in: " + iscHWhole : Exit Function
    End Select
    ISC_ParseHeader% = -1
End Function

' A launch flag in "#! args": 1 = takes no value, 2 = takes one, 0 = not allowed there.
Function ISC_ArgKind%(iscAK As String)
    Select Case iscAK
    Case "--god", "--nerf", "--crawls", "--debug", "--no-telem"
        ISC_ArgKind% = 1
    Case "--scene", "--difficulty", "--credits", "--ships", "--shields", "--fuel", "--pup", "--screenshot-at", "--leaderboard-file", "--seed", "--frames"
        ISC_ArgKind% = 2
    Case Else
        ISC_ArgKind% = 0
    End Select
End Function

' Checks a "#! args" value and returns it single-spaced in iscCAOut; 0 (see iscError) if bad.
Function ISC_CheckArgs%(iscCA As String, iscCAOut As String)
    Dim iscCAP As Integer, iscCAT As String, iscCAV As String, iscCAK As Integer
    ISC_CheckArgs% = 0
    iscCAOut = "" : iscCAP = 1
    Do
        iscCAT = ISC_Token$(iscCA, iscCAP)
        If iscCAT = "" Then Exit Do
        If iscCAT = "--seed" Or iscCAT = "--frames" Then iscError = "header args: use '#! " + Mid$(iscCAT, 3) + "' for " + iscCAT : Exit Function
        iscCAK = ISC_ArgKind%(iscCAT)
        If iscCAK = 0 Then iscError = "header args can't take '" + iscCAT + "'" : Exit Function
        iscCAOut = iscCAOut + " " + iscCAT
        If iscCAK = 2 Then
            iscCAV = ISC_Token$(iscCA, iscCAP)
            If iscCAV = "" Or Left$(iscCAV, 2) = "--" Then iscError = "header args: " + iscCAT + " needs a value" : Exit Function
            iscCAOut = iscCAOut + " " + iscCAV
        End If
    Loop
    If iscCAOut = "" Then iscError = "header args is empty" : Exit Function
    iscCAOut = Mid$(iscCAOut, 2)
    ISC_CheckArgs% = -1
End Function

' Is the token iscFF on the launch line iscFL? iscFV gets the token after it.
Function ISC_FindArg%(iscFL As String, iscFF As String, iscFV As String)
    Dim iscFP As Integer, iscFT As String
    ISC_FindArg% = 0
    iscFV = "" : iscFP = 1
    Do
        iscFT = ISC_Token$(iscFL, iscFP)
        If iscFT = "" Then Exit Function
        If iscFT = iscFF Then iscFV = ISC_Token$(iscFL, iscFP) : ISC_FindArg% = -1 : Exit Function
    Loop
End Function

' iscMOut = the launch line iscMCli plus the loaded header's seed, frames and args. A flag
' the launch line already has is kept as it is; one it gives a different value is an error
' unless iscMOverride (--script-override), and then the launch line's value wins.
Function ISC_MergeArgs%(iscMCli As String, iscMOverride As Integer, iscMOut As String)
    Dim iscMHdr As String, iscMP As Integer, iscMF As String, iscMV As String, iscMCV As String
    ISC_MergeArgs% = 0
    iscMOut = iscMCli
    iscMHdr = iscHdrArgs
    If iscHdrSeed <> "" Then iscMHdr = iscMHdr + " --seed " + iscHdrSeed
    If iscHdrFrames <> "" Then iscMHdr = iscMHdr + " --frames " + iscHdrFrames
    iscMP = 1
    Do
        iscMF = ISC_Token$(iscMHdr, iscMP)
        If iscMF = "" Then Exit Do
        iscMV = ""
        If ISC_ArgKind%(iscMF) = 2 Then iscMV = ISC_Token$(iscMHdr, iscMP)
        If ISC_FindArg%(iscMCli, iscMF, iscMCV) Then
            If iscMV <> "" And iscMCV <> iscMV And iscMOverride = 0 Then
                iscError = "the input script's header says " + iscMF + " " + iscMV + " but the command line says " + iscMF + " " + iscMCV + "; drop " + iscMF + " from the command line, or add --script-override to use its value"
                Exit Function
            End If
        Else
            iscMOut = iscMOut + " " + iscMF
            If iscMV <> "" Then iscMOut = iscMOut + " " + iscMV
        End If
    Loop
    ISC_MergeArgs% = -1
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
    Dim iscA As Long, iscK As Long, iscKAny As Integer, iscFirst As Integer
    Dim iscStateIn As Integer, iscLabelIn As Integer
    iscFrame = iscFrameNo
    iscStateIn = (iscCtxState <> iscPrevState) : iscLabelIn = (iscCtxLabel <> iscPrevLabel)
    iscPrevState = iscCtxState : iscPrevLabel = iscCtxLabel
    iscKAny = 0
    For iscA = LBound(iscHeld) To UBound(iscHeld) : iscHeld(iscA) = 0 : Next iscA
    For iscA = 1 To E3D_PAD_MAX_AXES : padRawAxis(iscA) = 0 : Next iscA
    For iscA = 1 To E3D_PAD_MAX_BTNS : padRawBtn(iscA) = 0 : Next iscA
    For iscA = 1 To iscCount
        If iscTrig(iscA) = 0 Then
            iscOn(iscA) = (iscFrameNo >= iscFrom(iscA) And iscFrameNo <= iscTo(iscA))
            iscFirst = (iscFrameNo = iscFrom(iscA))
        Else
            ISC_EventStep iscA, iscFrameNo, iscStateIn, iscLabelIn, iscFirst
        End If
        If iscOn(iscA) Then
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
        If iscFirst And iscKey(iscA) > 0 And iscHitTail < ISC_MAX Then
            iscHitTail = iscHitTail + 1 : iscHitQ(iscHitTail) = iscKey(iscA)
        End If
    Next iscA
    INP_NoteKeys iscKAny
    E3D_PadMap iscHeld()
End Sub

' One @ line this frame: an entry into its trigger (its nth, if it names one) starts it and
' leaving lets go. Sets iscOn(a), and iscESFirst on the first frame of each hold.
Sub ISC_EventStep(iscESA As Long, iscESFrame As Long, iscESStateIn As Integer, iscESLabelIn As Integer, iscESFirst As Integer)
    Dim iscESIn As Integer, iscESCur As String, iscESRel As Long, iscESPh As Long
    iscESFirst = 0 : iscOn(iscESA) = 0
    If iscTrig(iscESA) = ISC_TRIG_STATE Then
        iscESIn = iscESStateIn : iscESCur = iscCtxState
    Else
        iscESIn = iscESLabelIn : iscESCur = iscCtxLabel
    End If
    If iscESIn Then
        iscEntry(iscESA) = -1
        If iscESCur = iscTrigName(iscESA) Then
            iscSeen(iscESA) = iscSeen(iscESA) + 1
            If iscTrigNth(iscESA) = 0 Or iscSeen(iscESA) = iscTrigNth(iscESA) Then iscEntry(iscESA) = iscESFrame
        End If
    End If
    If iscEntry(iscESA) < 0 Then Exit Sub
    iscESRel = iscESFrame - iscEntry(iscESA) - iscFrom(iscESA)
    If iscESRel < 0 Then Exit Sub
    If iscEvery(iscESA) > 0 Then
        iscESPh = iscESRel Mod iscEvery(iscESA)
        iscOn(iscESA) = (iscESPh < iscLen(iscESA)) : iscESFirst = (iscESPh = 0)
    Else
        iscOn(iscESA) = (iscLen(iscESA) = ISC_LEN_ALL Or iscESRel < iscLen(iscESA)) : iscESFirst = (iscESRel = 0)
    End If
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
        If iscOn(iscDA) Then
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
