' inputscript_test.bas — scripted input for headless playtests (src/sys/inputscript.bas)
'
' Drives the real module: parsing (ranges, several keys, comments, blanks, tabs, case),
' rejecting malformed lines, ISC_Apply holding exactly the scripted keys on the
' scripted frames (inclusive ends, overlapping ranges, everything else up), any-key
' names (letters in both cases, digits, F-keys, #code), KEY_Down% on/off frames
' (including codes above 32767), KEY_Hit& press order, a missing file, the PAD_* gamepad
' names (same held() slots as a real controller, invisible to KEY_Down%/KEY_Hit&), and
' the menu actions KEY_Pressed% / KEY_Confirm% / KEY_Back% (one press, not a hold), the raw
' pad tokens (PADBTN<n>, PADAXIS<n>+/-, PAD_DPAD_*) going through E3D_PadMap, and a d-pad +
' A/B walk through the title console into Settings and back, and the #! header (seed, args,
' frames: parsing, rejects, merging into the launch line, --script-override), and @ lines
' (state and label triggers, offsets, lengths, *, every, #n, re-triggering on each entry,
' letting go on leaving, mixed with frame lines, rejects).
'
' Build: ./tools/buildqb tests/inputscript_test.bas
' Run:   ./tests/inputscript_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Dim Shared held(0 To 32767) As Integer  ' the game's held() (dims.bas); KEY_Pressed% reads it

' game states and the shared vars src/state/titlenav.bas uses (must match dims.bas)
Const GS_TITLE       = 0
Const GS_OPTIONS     = 7
Const GS_ABOUT       = 8
Const GS_LEADERBOARD = 12
Const GS_CONTROLS    = 13
Const GS_REMAP       = 16
Dim Shared gameState As Integer, escWas As Integer, optEscWas As Integer

'$INCLUDE:'../src/3d/input.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/state/titlenav.bas'

Dim Shared isPassed As Integer, isFailed As Integer
Dim Shared isHeld(0 To 32767) As Integer
Dim isOk As Integer, isOk2 As Integer, isOk3 As Integer

Sub IS_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        isPassed = isPassed + 1
    Else
        Print "FAIL  " + testName
        isFailed = isFailed + 1
    End If
End Sub

' Number of held() slots that are down.
Function IS_Down%
    Dim isI As Long, isN As Integer
    For isI = 0 To 32767
        If isHeld(isI) Then isN = isN + 1
    Next isI
    IS_Down% = isN
End Function

Print "=== inputscript_test ==="
Print ""

Print "--- parsing ---"
ISC_Clear
isOk = ISC_ParseLine%("0 10 LEFT")
IS_Assert isOk And iscCount = 1, "one key, one range"
isOk = ISC_ParseLine%("  5   20  fire  Up ")
IS_Assert isOk And iscCount = 3, "several keys, extra spaces, any case"
isOk = ISC_ParseLine%("7" + Chr$(9) + "8" + Chr$(9) + "ESC")
IS_Assert isOk And iscCount = 4, "tabs separate too"
isOk = ISC_ParseLine%("# just a comment") And ISC_ParseLine%("") And ISC_ParseLine%("   ")
IS_Assert isOk And iscCount = 4, "comments and blank lines add nothing"
IS_Assert iscFrom(2) = 5 And iscTo(2) = 20 And iscKey(2) = E3D_KEY_SPACE And iscKey(3) = E3D_KEY_UP, "FIRE is SPACE; ranges stored"

Print "--- rejects ---"
isOk = ISC_ParseLine%("10 5 LEFT")
IS_Assert isOk = 0 And InStr(iscError, "before start") > 0, "end before start"
isOk = ISC_ParseLine%("x 5 LEFT")
IS_Assert isOk = 0 And InStr(iscError, "start frame") > 0, "non-numeric start"
isOk = ISC_ParseLine%("1 y LEFT")
IS_Assert isOk = 0 And InStr(iscError, "end frame") > 0, "non-numeric end"
isOk = ISC_ParseLine%("-1 5 LEFT")
IS_Assert isOk = 0, "negative frame"
isOk = ISC_ParseLine%("1 5 JUMP")
IS_Assert isOk = 0 And InStr(iscError, "JUMP") > 0, "unknown key named in the error"
isOk = ISC_ParseLine%("1 5")
IS_Assert isOk = 0 And InStr(iscError, "no keys") > 0, "a range with no keys"

Print "--- ISC_Apply ---"
ISC_Clear
IS_Assert ISC_ParseLine%("10 20 LEFT FIRE"), "load: 10-20 LEFT FIRE"
IS_Assert ISC_ParseLine%("15 30 UP"), "load: 15-30 UP"
isHeld(E3D_KEY_DOWN) = -1 : isHeld(500) = -1
ISC_Apply 9, isHeld()
IS_Assert IS_Down% = 0, "before any range: nothing held, stale keys cleared"
ISC_Apply 10, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_SPACE) And IS_Down% = 2, "first frame of a range is held"
ISC_Apply 17, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_SPACE) And isHeld(E3D_KEY_UP) And IS_Down% = 3, "overlapping ranges combine"
ISC_Apply 20, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And IS_Down% = 3, "last frame of a range is held (inclusive)"
ISC_Apply 21, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) = 0 And isHeld(E3D_KEY_UP) And IS_Down% = 1, "after a range ends its keys come up"
ISC_Apply 31, isHeld()
IS_Assert IS_Down% = 0, "after every range: nothing held"

Print "--- any key ---"
ISC_Clear
isOk = ISC_ParseLine%("0 0 a 5 ENTER BACKSPACE SPACE BACKTICK F1 F10 F11 F12 #21248")
IS_Assert isOk And iscCount = 11, "letters, digits, named keys, F-keys and #code parse"
IS_Assert iscKey(1) = 97 And iscAlt(1) = 65, "a letter is its lower- and upper-case code"
IS_Assert iscKey(2) = 53 And iscKey(3) = 13 And iscKey(4) = 8 And iscKey(5) = 32 And iscKey(6) = 96, "5 ENTER BACKSPACE SPACE BACKTICK codes"
IS_Assert iscKey(7) = 15104 And iscKey(8) = 17408 And iscKey(9) = 34048 And iscKey(10) = 34304, "F1 F10 F11 F12 codes"
IS_Assert iscKey(11) = 21248, "#<code> is that code"
isOk = ISC_ParseLine%("0 0 F13")
isOk2 = ISC_ParseLine%("0 0 #")
isOk3 = ISC_ParseLine%("0 0 AB")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0, "F13, bare #, two letters are unknown"
isOk = ISC_ParseLine%("0 0 #x1")
IS_Assert isOk = 0 And InStr(iscError, "#x1") > 0, "non-numeric #code rejected"

Print "--- KEY_Down ---"
ISC_Clear
IS_Assert ISC_ParseLine%("10 20 A F11 LEFT"), "load: 10-20 A F11 LEFT"
iscActive = -1
ISC_Apply 9, isHeld()
IS_Assert KEY_Down%(65) = 0 And KEY_Down%(97) = 0 And KEY_Down%(34048) = 0, "before the range: up"
ISC_Apply 10, isHeld()
IS_Assert KEY_Down%(65) And KEY_Down%(97), "letter down as upper and lower case"
IS_Assert KEY_Down%(34048), "F11 (code above 32767) down"
IS_Assert KEY_Down%(19200) And isHeld(E3D_KEY_LEFT), "LEFT is down to KEY_Down and held()"
IS_Assert isHeld(97) And IS_Down% = 2, "letter fills its held() slot; F11 has none"
IS_Assert KEY_Down%(66) = 0 And KEY_Down%(98) = 0, "other letters stay up"
ISC_Apply 20, isHeld()
IS_Assert KEY_Down%(97) And KEY_Down%(34048), "last frame still down"
ISC_Apply 21, isHeld()
IS_Assert KEY_Down%(97) = 0 And KEY_Down%(34048) = 0 And KEY_Down%(19200) = 0, "after the range: up"

Print "--- KEY_Hit ---"
Dim isHit1 As Long, isHit2 As Long, isHit3 As Long, isHit4 As Long
ISC_Clear
IS_Assert ISC_ParseLine%("5 9 Y ENTER"), "load: 5-9 Y ENTER"
IS_Assert ISC_ParseLine%("7 7 #21248"), "load: 7-7 #21248"
iscActive = -1
ISC_Apply 4, isHeld()
isHit1 = KEY_Hit&
IS_Assert isHit1 = 0, "nothing queued before any range"
ISC_Apply 5, isHeld()
isHit1 = KEY_Hit&
isHit2 = KEY_Hit&
isHit3 = KEY_Hit&
IS_Assert isHit1 = 121 And isHit2 = 13 And isHit3 = 0, "first frame of a range: one press each, in script order, then 0"
ISC_Apply 6, isHeld()
isHit1 = KEY_Hit&
IS_Assert isHit1 = 0, "holding a key does not repeat the press"
ISC_Apply 7, isHeld()
isHit1 = KEY_Hit&
IS_Assert isHit1 = 21248, "a later range's press arrives on its first frame"
ISC_Clear
IS_Assert ISC_ParseLine%("1 1 Q") And ISC_ParseLine%("2 2 ESC"), "load: 1 Q, 2 ESC"
iscActive = -1
ISC_Apply 1, isHeld()
ISC_Apply 2, isHeld()
isHit1 = KEY_Hit&
isHit2 = KEY_Hit&
isHit3 = KEY_Hit&
isHit4 = KEY_Hit&
IS_Assert isHit1 = 113 And isHit2 = 27 And isHit3 = 0 And isHit4 = 0, "unread presses stay queued across frames, in order"

Print "--- gamepad ---"
ISC_Clear
isOk = ISC_ParseLine%("0 0 PAD_A PAD_B PAD_X PAD_Y PAD_START PAD_SELECT pad_left PAD_RIGHT PAD_UP PAD_DOWN")
IS_Assert isOk And iscCount = 10, "PAD_ buttons and stick directions parse, any case"
isOk = ISC_ParseLine%("0 0 PAD_Z")
IS_Assert isOk = 0 And InStr(iscError, "PAD_Z") > 0, "unknown pad name rejected"
ISC_Clear
IS_Assert ISC_ParseLine%("10 12 PAD_A"), "load: 10-12 PAD_A"
IS_Assert ISC_ParseLine%("20 20 PAD_START"), "load: 20 PAD_START"
IS_Assert ISC_ParseLine%("30 30 PAD_SELECT PAD_B PAD_X PAD_Y"), "load: 30 PAD_SELECT PAD_B PAD_X PAD_Y"
IS_Assert ISC_ParseLine%("40 40 PAD_LEFT PAD_DOWN"), "load: 40 PAD_LEFT PAD_DOWN"
IS_Assert ISC_ParseLine%("50 50 PAD_B"), "load: 50 PAD_B"
iscActive = -1
ISC_Apply 10, isHeld()
isHit1 = KEY_Hit&
IS_Assert isHeld(E3D_KEY_SPACE) And isHeld(E3D_KEY_PAD_A) And IS_Down% = 2, "PAD_A holds SPACE (fire) and the PAD_A slot, like the real pad"
IS_Assert KEY_Down%(32) = 0 And isHit1 = 0, "PAD_A is not a keyboard key: no KEY_Down, no KEY_Hit"
ISC_Apply 20, isHeld()
IS_Assert isHeld(E3D_KEY_ESCAPE) And isHeld(E3D_KEY_PAD_START) And IS_Down% = 2, "PAD_START holds ESCAPE and PAD_START"
IS_Assert KEY_Down%(27) = 0, "PAD_START is not the ESC key"
ISC_Apply 30, isHeld()
IS_Assert isHeld(E3D_KEY_TAB) And isHeld(E3D_KEY_PAD_SELECT) And isHeld(E3D_KEY_PAD_B) And isHeld(E3D_KEY_PAD_X) And isHeld(E3D_KEY_PAD_Y) And isHeld(E3D_KEY_SPACE) And IS_Down% = 6, "PAD_SELECT holds TAB + its slot; B also holds SPACE; X Y their own slots"
ISC_Apply 40, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_DOWN) And IS_Down% = 2, "stick fills the arrow slots"
IS_Assert KEY_Down%(19200) = 0 And KEY_Down%(20480) = 0, "stick is not the arrow keys"
ISC_Apply 41, isHeld()
IS_Assert IS_Down% = 0, "pad state clears when its range ends"
ISC_Apply 50, isHeld()
IS_Assert isHeld(E3D_KEY_SPACE) And isHeld(E3D_KEY_PAD_B) And isHeld(E3D_KEY_PAD_A) = 0 And IS_Down% = 2, "PAD_B holds SPACE (fire, for Nintendo-layout pads) and its own PAD_B slot, not PAD_A"

Print "--- menu actions ---"
Dim isP1 As Integer, isP2 As Integer, isP3 As Integer
ISC_Clear
IS_Assert ISC_ParseLine%("5 7 PAD_A"), "load: 5-7 PAD_A"
IS_Assert ISC_ParseLine%("10 10 ENTER"), "load: 10 ENTER"
IS_Assert ISC_ParseLine%("15 16 PAD_B"), "load: 15-16 PAD_B"
IS_Assert ISC_ParseLine%("20 20 ESC"), "load: 20 ESC"
IS_Assert ISC_ParseLine%("25 25 PAD_START"), "load: 25 PAD_START"
IS_Assert ISC_ParseLine%("30 31 PAD_DOWN"), "load: 30-31 PAD_DOWN"
iscActive = -1
KEY_FrameBegin : ISC_Apply 4, held()
isP1 = KEY_Confirm% : isP2 = KEY_Back%
IS_Assert isP1 = 0 And isP2 = 0, "nothing pressed: no confirm, no back"
KEY_FrameBegin : ISC_Apply 5, held()
isP1 = KEY_Confirm% : isP2 = KEY_Pressed%(E3D_KEY_PAD_A)
IS_Assert isP1 = -1 And isP2 = -1, "pad A press is a confirm (-1)"
KEY_FrameBegin : ISC_Apply 6, held()
isP1 = KEY_Confirm%
IS_Assert isP1 = 0, "holding A is not another confirm"
KEY_FrameBegin : ISC_Apply 10, held()
isP1 = KEY_Confirm%
IS_Assert isP1 = -1, "ENTER press is a confirm"
KEY_FrameBegin : ISC_Apply 15, held()
isP1 = KEY_Back% : isP2 = KEY_Confirm%
isP3 = KEY_Pressed%(E3D_KEY_SPACE)
IS_Assert isP1 = -1 And isP2 = 0 And isP3 = -1, "pad B press is a back, not a confirm (it also presses SPACE, to fire)"
KEY_FrameBegin : ISC_Apply 16, held()
isP1 = KEY_Back%
IS_Assert isP1 = 0, "holding B is not another back"
KEY_FrameBegin : ISC_Apply 20, held()
isP1 = KEY_Back%
IS_Assert isP1 = -1, "ESC press is a back"
KEY_FrameBegin : ISC_Apply 24, held()
KEY_FrameBegin : ISC_Apply 25, held()
isP1 = KEY_Back% : isP2 = KEY_Pressed%(E3D_KEY_PAD_START)
IS_Assert isP1 = -1 And isP2 = -1, "pad Start press is a back"
KEY_FrameBegin : ISC_Apply 30, held()
isP1 = KEY_Pressed%(E3D_KEY_DOWN)
KEY_FrameBegin : ISC_Apply 31, held()
isP2 = KEY_Pressed%(E3D_KEY_DOWN)
KEY_FrameBegin : ISC_Apply 32, held()
isP3 = KEY_Pressed%(E3D_KEY_DOWN)
IS_Assert isP1 = -1 And isP2 = 0 And isP3 = 0, "stick down: one press, then held, then released"

Print "--- raw pad tokens ---"
ISC_Clear
isOk = ISC_ParseLine%("0 0 PADBTN1 padbtn32 PADAXIS1- PADAXIS16+ PAD_DPAD_UP PAD_DPAD_DOWN PAD_DPAD_LEFT PAD_DPAD_RIGHT")
IS_Assert isOk And iscCount = 8, "PADBTN<n>, PADAXIS<n>+/-, PAD_DPAD_* parse, any case"
isOk = ISC_ParseLine%("0 0 PADBTN0")
isOk2 = ISC_ParseLine%("0 0 PADBTN33")
isOk3 = ISC_ParseLine%("0 0 PADAXIS17+")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0, "PADBTN0, PADBTN33, PADAXIS17+ are out of range"
isOk = ISC_ParseLine%("0 0 PADAXIS3")
isOk2 = ISC_ParseLine%("0 0 PADAXIS+")
IS_Assert isOk = 0 And isOk2 = 0, "PADAXIS needs a number and a + or -"
ISC_Clear
IS_Assert ISC_ParseLine%("10 10 PADBTN1"), "load: 10 PADBTN1"
IS_Assert ISC_ParseLine%("11 11 PADAXIS8-"), "load: 11 PADAXIS8-"
IS_Assert ISC_ParseLine%("12 12 PAD_DPAD_RIGHT"), "load: 12 PAD_DPAD_RIGHT"
IS_Assert ISC_ParseLine%("13 13 PADBTN9 PADAXIS3+"), "load: 13 PADBTN9 PADAXIS3+ (Guide, trigger)"
IS_Assert ISC_ParseLine%("14 14 PAD_DPAD_UP PAD_DOWN"), "load: 14 PAD_DPAD_UP PAD_DOWN"
iscActive = -1
ISC_Apply 10, isHeld()
IS_Assert padRawBtn(1) = 1 And isHeld(E3D_KEY_SPACE) And isHeld(E3D_KEY_PAD_A) And IS_Down% = 2, "PADBTN1 is the raw A button -> SPACE + PAD_A"
ISC_Apply 11, isHeld()
IS_Assert padRawBtn(1) = 0 And padRawAxis(8) = -1 And isHeld(E3D_KEY_UP) And IS_Down% = 1, "PADAXIS8- is d-pad up -> UP, and last frame's button is released"
ISC_Apply 12, isHeld()
IS_Assert padRawAxis(7) = 1 And padRawAxis(8) = 0 And isHeld(E3D_KEY_RIGHT) And IS_Down% = 1, "PAD_DPAD_RIGHT sets axis 7 +1 -> RIGHT"
ISC_Apply 13, isHeld()
IS_Assert padRawBtn(9) = 1 And padRawAxis(3) = 1 And IS_Down% = 0, "unmapped controls (Guide, a trigger) press nothing"
ISC_Apply 14, isHeld()
IS_Assert isHeld(E3D_KEY_DOWN) And isHeld(E3D_KEY_UP) = 0 And IS_Down% = 1, "stick and d-pad both full on one axis: one direction, the stick (the d-pad wins only when pushed further)"

Print "--- d-pad + A/B menu walk ---"
' Title console and Settings, driven by d-pad and A/B only, reading exactly what
' GS_TITLE_Update / OPTS_Update read (KEY_Pressed / KEY_Confirm / held PAD_B), with
' the real TITLE_ReturnTo. Those Subs draw to the screen, so a $CONSOLE:ONLY test can't
' call them directly; the walk mirrors their input lines.
Dim isFr As Long, isConsole As Integer, isConSel As Integer, isOptSel As Integer
Dim isDnWas As Integer, isUpWas As Integer, isOptDn As Integer, isOptUp As Integer, isOptEsc As Integer
Dim isLog As String
ISC_Clear
IS_Assert ISC_ParseLine%("2 3 PAD_SELECT"), "load: 2-3 PAD_SELECT (BACK opens the console)"
IS_Assert ISC_ParseLine%("6 7 PAD_DPAD_DOWN"), "load: 6-7 PAD_DPAD_DOWN"
IS_Assert ISC_ParseLine%("10 11 PAD_DPAD_DOWN"), "load: 10-11 PAD_DPAD_DOWN"
IS_Assert ISC_ParseLine%("14 15 PAD_A"), "load: 14-15 PAD_A (pick SETTINGS)"
IS_Assert ISC_ParseLine%("18 19 PAD_DPAD_DOWN"), "load: 18-19 PAD_DPAD_DOWN"
IS_Assert ISC_ParseLine%("22 23 PAD_DPAD_DOWN"), "load: 22-23 PAD_DPAD_DOWN"
IS_Assert ISC_ParseLine%("26 27 PAD_DPAD_UP"), "load: 26-27 PAD_DPAD_UP"
IS_Assert ISC_ParseLine%("30 31 PAD_B"), "load: 30-31 PAD_B (back to the title)"
iscActive = -1
gameState = GS_TITLE : escWas = 0 : optEscWas = 0
isConsole = 0 : isConSel = 0 : isOptSel = 0
For isFr = 0 To 40
    KEY_FrameBegin
    ISC_Apply isFr, held()
    If gameState = GS_TITLE Then
        If KEY_Pressed%(E3D_KEY_PAD_SELECT) Then isConsole = 1 - isConsole : isConSel = 0 : isLog = isLog + " console"
        If isConsole Then
            If KEY_Pressed%(E3D_KEY_UP) Then isConSel = (isConSel + 5) Mod 6
            If KEY_Pressed%(E3D_KEY_DOWN) Then isConSel = (isConSel + 1) Mod 6 : isLog = isLog + " con" + LTrim$(Str$(isConSel))
            isP1 = KEY_Confirm%
            If isP1 And isConSel = 2 Then
                gameState = GS_OPTIONS : isConsole = 0 : isLog = isLog + " SETTINGS"
                isOptUp = -1 : isOptDn = 0 : optEscWas = -1
            End If
        End If
    ElseIf gameState = GS_OPTIONS Then
        isUpWas = (held(E3D_KEY_UP) <> 0) : isDnWas = (held(E3D_KEY_DOWN) <> 0)
        isOptEsc = (held(E3D_KEY_ESCAPE) <> 0) Or (held(E3D_KEY_PAD_B) <> 0)
        If isUpWas And Not isOptUp Then isOptSel = (isOptSel + 5) Mod 6 : isLog = isLog + " opt" + LTrim$(Str$(isOptSel))
        If isDnWas And Not isOptDn Then isOptSel = (isOptSel + 1) Mod 6 : isLog = isLog + " opt" + LTrim$(Str$(isOptSel))
        If isOptEsc And Not optEscWas Then TITLE_ReturnTo GS_TITLE : isLog = isLog + " TITLE"
        isOptUp = isUpWas : isOptDn = isDnWas
        If gameState = GS_OPTIONS Then optEscWas = isOptEsc
    End If
Next isFr
Print "      walk:" + isLog
IS_Assert isLog = " console con1 con2 SETTINGS opt1 opt2 opt1 TITLE", "BACK opens, d-pad down x2 to SETTINGS, A opens it, d-pad down/down/up moves, B returns"
IS_Assert gameState = GS_TITLE And escWas <> 0 And isConsole = 0, "back on the title, console shut, ESC marked seen"

Print "--- @ trigger lines: parsing ---"
ISC_Clear
isOk = ISC_ParseLine%("@GS_CRAWL +60 1 FIRE ESC")
IS_Assert isOk And iscCount = 2 And iscTrig(1) = ISC_TRIG_STATE And iscTrigName(1) = "GS_CRAWL" And iscFrom(1) = 60 And iscLen(1) = 1 And iscKey(2) = E3D_KEY_ESCAPE, "state trigger, offset, length, two keys"
isOk = ISC_ParseLine%("@GS_PLAYING +0 * FIRE")
IS_Assert isOk And iscLen(3) = ISC_LEN_ALL And iscEvery(3) = 0, "* = held while the state lasts"
isOk = ISC_ParseLine%("  @gs_playing" + Chr$(9) + "+0 60 every 240 left ")
IS_Assert isOk And iscTrigName(4) = "GS_PLAYING" And iscLen(4) = 60 And iscEvery(4) = 240 And iscKey(4) = E3D_KEY_LEFT, "every, any case, tabs"
isOk = ISC_ParseLine%("@label:level3 +5 UP")
IS_Assert isOk And iscTrig(5) = ISC_TRIG_LABEL And iscTrigName(5) = "LEVEL3" And iscLen(5) = 1, "label trigger, length defaults to 1"
isOk = ISC_ParseLine%("@GS_TITLE#1 +0 P")
IS_Assert isOk And iscTrigNth(6) = 1 And iscTrigName(6) = "GS_TITLE", "#n: one entry only"
isOk = ISC_ParseLine%("@label:outro#2 +0 every 3 ENTER")
IS_Assert isOk And iscTrigNth(7) = 2 And iscTrigName(7) = "OUTRO" And iscEvery(7) = 3, "label with #n and every"

Print "--- @ trigger lines: rejects ---"
isOk = ISC_ParseLine%("@GS_NOPE +0 FIRE")
IS_Assert isOk = 0 And InStr(iscError, "unknown trigger 'GS_NOPE'") > 0, "unknown state named: " + iscError
isOk = ISC_ParseLine%("@level3 +0 FIRE")
IS_Assert isOk = 0 And InStr(iscError, "label:") > 0, "a bare label needs label:"
isOk = ISC_ParseLine%("@ +0 FIRE")
isOk2 = ISC_ParseLine%("@label: +0 FIRE")
IS_Assert isOk = 0 And isOk2 = 0, "empty trigger, empty label"
isOk = ISC_ParseLine%("@GS_TITLE 0 FIRE")
isOk2 = ISC_ParseLine%("@GS_TITLE +x FIRE")
isOk3 = ISC_ParseLine%("@GS_TITLE +-1 FIRE")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0 And InStr(iscError, "+<offset>") > 0, "offset must be +<n>"
isOk = ISC_ParseLine%("@GS_TITLE +0")
isOk2 = ISC_ParseLine%("@GS_TITLE +0 *")
IS_Assert isOk = 0 And isOk2 = 0 And InStr(iscError, "no keys") > 0, "no keys"
isOk = ISC_ParseLine%("@GS_TITLE +0 2 JUMP")
IS_Assert isOk = 0 And InStr(iscError, "'JUMP'") > 0, "unknown key"
isOk = ISC_ParseLine%("@GS_TITLE#0 +0 P")
isOk2 = ISC_ParseLine%("@GS_TITLE#x +0 P")
isOk3 = ISC_ParseLine%("@GS_TITLE# +0 P")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0, "bad #n"
isOk = ISC_ParseLine%("@GS_TITLE +0 0 P")
IS_Assert isOk = 0 And InStr(iscError, "at least 1") > 0, "zero-length hold"
isOk = ISC_ParseLine%("@GS_PLAYING +0 * every 10 LEFT")
isOk2 = ISC_ParseLine%("@GS_PLAYING +0 10 every 10 LEFT")
isOk3 = ISC_ParseLine%("@GS_PLAYING +0 5 every LEFT")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0, "every needs a number above the hold"
isOk = ISC_ParseLine%("@GS_USERNAME +3 7")
IS_Assert isOk = 0 And InStr(iscError, "is the length") > 0, "a lone number is the length, not a digit key"
IS_Assert iscCount = 7, "rejected lines add no keys"
isOk = ISC_ParseLine%("@GS_USERNAME +3 1 7")
IS_Assert isOk And iscCount = 8 And iscKey(8) = Asc("7") And iscLen(8) = 1, "a digit key after an explicit length"

Print "--- @ trigger lines: playing ---"
Dim isHits As String
ISC_Clear
isOk = ISC_ParseLine%("@GS_CRAWL +3 2 FIRE ESC") And ISC_ParseLine%("0 100 UP")
isOk = isOk And ISC_ParseLine%("@GS_PLAYING +2 * TAB") And ISC_ParseLine%("@GS_PLAYING +0 2 every 5 LEFT")
isOk = isOk And ISC_ParseLine%("@label:level3 +1 DOWN") And ISC_ParseLine%("@GS_TITLE#2 +0 P")
IS_Assert isOk, "load: crawl skip, absolute UP, flight hold and weave, label, second title"
iscActive = -1
IS_Frame 0, "GS_LEADIN", ""
IS_Assert isHeld(E3D_KEY_UP) And IS_Down% = 1 And IS_Hits$ = Str$(E3D_KEY_UP), "before any trigger: only the absolute line"
IS_Frame 1, "GS_LEADIN", ""
IS_Frame 2, "GS_CRAWL", "crawl0"
IS_Frame 4, "GS_CRAWL", "crawl0"
IS_Assert IS_Down% = 1, "entry at 2, +3: not yet at 4"
IS_Frame 5, "GS_CRAWL", "crawl0"
IS_Assert isHeld(E3D_KEY_SPACE) And isHeld(E3D_KEY_ESCAPE) And IS_Down% = 3, "held at entry+3 alongside the absolute line"
IS_Assert KEY_Down%(E3D_KEY_ESCAPE) And KEY_Down%(E3D_KEY_LEFT) = 0, "KEY_Down% sees @ lines"
IS_Assert IS_Hits$ = " 32 27", "one press per key on the hold's first frame"
IS_Frame 6, "GS_CRAWL", "crawl0"
IS_Assert isHeld(E3D_KEY_SPACE) And IS_Hits$ = "", "second frame held, no new press"
IS_Frame 7, "GS_CRAWL", "crawl0"
IS_Assert isHeld(E3D_KEY_SPACE) = 0, "released after its length"
IS_Frame 10, "GS_PLAYING", "level3"
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_TAB) = 0 And isHeld(E3D_KEY_DOWN) = 0, "play entered: weave starts at +0, TAB waits for +2, label waits for +1"
IS_Frame 11, "GS_PLAYING", "level3"
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_DOWN), "label trigger at +1"
IS_Frame 12, "GS_PLAYING", "level3"
IS_Assert isHeld(E3D_KEY_TAB) And isHeld(E3D_KEY_LEFT) = 0 And isHeld(E3D_KEY_DOWN) = 0, "TAB from +2; weave off after 2 of 5"
isHits = IS_Hits$
IS_Frame 15, "GS_PLAYING", "level3"
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_TAB) And IS_Hits$ = Str$(E3D_KEY_LEFT), "weave repeats every 5, pressed again"
IS_Frame 16, "GS_PLAYING", "level4"
IS_Assert isHeld(E3D_KEY_TAB) And isHeld(E3D_KEY_LEFT), "label change alone doesn't restart a state line"
IS_Frame 17, "GS_PLAYING", "level4"
IS_Assert isHeld(E3D_KEY_LEFT) = 0 And isHeld(E3D_KEY_DOWN) = 0, "weave phase keeps counting from the state's entry"
IS_Frame 500, "GS_PLAYING", "level4"
IS_Assert isHeld(E3D_KEY_TAB) And isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_UP) = 0, "* still held long after; absolute line ended"
IS_Frame 501, "GS_DOCK", "level4"
IS_Assert IS_Down% = 0, "leaving the state lets go of * and the weave"
IS_Frame 502, "GS_CRAWL", "level4"
IS_Frame 504, "GS_PLAYING", "level4"
IS_Frame 505, "GS_CRAWL", "level4"
IS_Assert IS_Down% = 0, "crawl entered again at 505"
IS_Frame 508, "GS_CRAWL", "level4"
IS_Assert isHeld(E3D_KEY_ESCAPE) And isHeld(E3D_KEY_SPACE), "re-triggers on each entry"
IS_Frame 509, "GS_PLANET", "level4"
IS_Assert IS_Down% = 0, "leaving mid-hold lets go"
IS_Frame 510, "GS_CRAWL", "level3"
IS_Frame 511, "GS_PLAYING", "level3"
IS_Assert isHeld(E3D_KEY_DOWN), "label entered again: fires again"
IS_Frame 520, "GS_TITLE", "title"
IS_Assert isHeld(E3D_KEY_P) = 0, "#2: first title ignored"
IS_Frame 521, "GS_PLAYING", "level1"
IS_Frame 530, "GS_TITLE", "title"
IS_Assert isHeld(E3D_KEY_P), "#2: second title fires"
IS_Frame 531, "GS_PLAYING", "level1"
IS_Frame 540, "GS_TITLE", "title"
IS_Assert isHeld(E3D_KEY_P) = 0, "#2: third title ignored"
isHits = IS_Hits$
ISC_Clear
isOk = ISC_ParseLine%("@GS_TITLE +0 * P") And ISC_ParseLine%("0 5 LEFT")
iscActive = -1
ISC_Apply 0, isHeld()
IS_Assert isHeld(E3D_KEY_LEFT) And isHeld(E3D_KEY_P) = 0, "no ISC_SetContext (render scenes, older tests): @ lines never fire"

Print "--- #! header ---"
ISC_Clear
isOk = ISC_ParseLine%("#! seed 1") And ISC_ParseLine%("#!frames: 20000") And ISC_ParseLine%("  #! ARGS  --god" + Chr$(9) + "--scene   boss3 ")
IS_Assert isOk And iscCount = 0, "seed, frames, args: parsed, no key ranges"
IS_Assert iscHdrSeed = "1" And iscHdrFrames = "20000" And iscHdrArgs = "--god --scene boss3", "header values stored (any case, colon, spacing)"
isOk = ISC_ParseLine%("#! args: --nerf")
IS_Assert isOk And iscHdrArgs = "--god --scene boss3 --nerf", "args lines add up"
isOk = ISC_ParseLine%("#! group: gameplay") And ISC_ParseLine%("#! shots: 220,250") And ISC_ParseLine%("#! mask: 1,2,3,4")
IS_Assert isOk And iscHdrArgs = "--god --scene boss3 --nerf", "render harness keys skipped"

isOk = ISC_ParseLine%("#! colour red")
IS_Assert isOk = 0 And InStr(iscError, "unknown header key 'colour'") > 0, "unknown key rejected: " + iscError
isOk = ISC_ParseLine%("#!")
IS_Assert isOk = 0 And InStr(iscError, "unknown header key") > 0, "bare #! rejected"
isOk = ISC_ParseLine%("#! seed one")
isOk2 = ISC_ParseLine%("#! frames")
isOk3 = ISC_ParseLine%("#! frames 1 2")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0 And InStr(iscError, "whole number") > 0, "seed/frames need one whole number"
isOk = ISC_ParseLine%("#! seed 2")
IS_Assert isOk = 0 And InStr(iscError, "twice") > 0 And iscHdrSeed = "1", "second seed rejected"
isOk = ISC_ParseLine%("#! args --fly")
IS_Assert isOk = 0 And InStr(iscError, "can't take '--fly'") > 0, "unknown flag rejected: " + iscError
isOk = ISC_ParseLine%("#! args god")
isOk2 = ISC_ParseLine%("#! args --input-script x.txt")
isOk3 = ISC_ParseLine%("#! args --script-override")
IS_Assert isOk = 0 And isOk2 = 0 And isOk3 = 0, "non-flags, --input-script, --script-override rejected"
isOk = ISC_ParseLine%("#! args --seed 3")
IS_Assert isOk = 0 And InStr(iscError, "'#! seed'") > 0, "--seed in args points at '#! seed': " + iscError
isOk = ISC_ParseLine%("#! args --scene")
isOk2 = ISC_ParseLine%("#! args --scene --god")
IS_Assert isOk = 0 And isOk2 = 0 And InStr(iscError, "needs a value") > 0, "value flag without its value rejected"
isOk = ISC_ParseLine%("#! args")
IS_Assert isOk = 0 And InStr(iscError, "empty") > 0, "empty args rejected"
IS_Assert iscHdrArgs = "--god --scene boss3 --nerf", "rejected lines leave the header as it was"

Print "--- header merged into the launch line ---"
Dim isMerged As String
ISC_Clear
isOk = ISC_ParseLine%("#! seed 1") And ISC_ParseLine%("#! frames 20000") And ISC_ParseLine%("#! args --god --nerf --scene playing1")
isOk = isOk And ISC_MergeArgs%("--input-script p.txt", 0, isMerged)
IS_Assert isOk And isMerged = "--input-script p.txt --god --nerf --scene playing1 --seed 1 --frames 20000", "header applied: " + isMerged
isOk = ISC_MergeArgs%("--seed 1 --god --frames 20000 --input-script p.txt --debug", 0, isMerged)
IS_Assert isOk And isMerged = "--seed 1 --god --frames 20000 --input-script p.txt --debug --nerf --scene playing1", "matching CLI values kept, not doubled; extra CLI flags kept: " + isMerged
isOk = ISC_MergeArgs%("--input-script p.txt --seed 7", 0, isMerged)
IS_Assert isOk = 0 And InStr(iscError, "header says --seed 1 but the command line says --seed 7") > 0 And InStr(iscError, "--script-override") > 0, "seed mismatch is an error: " + iscError
isOk = ISC_MergeArgs%("--frames 300 --input-script p.txt", 0, isMerged)
IS_Assert isOk = 0 And InStr(iscError, "--frames 20000") > 0, "frames mismatch is an error"
isOk = ISC_MergeArgs%("--scene boss3 --input-script p.txt", 0, isMerged)
IS_Assert isOk = 0 And InStr(iscError, "--scene playing1") > 0, "args value mismatch is an error"
isOk = ISC_MergeArgs%("--input-script p.txt --seed 7 --scene boss3 --script-override", -1, isMerged)
IS_Assert isOk And isMerged = "--input-script p.txt --seed 7 --scene boss3 --script-override --god --nerf --frames 20000", "--script-override: command line wins, rest of header added: " + isMerged
ISC_Clear
isOk = ISC_ParseLine%("# a plain comment") And ISC_ParseLine%("0 5 LEFT")
isOk = isOk And ISC_MergeArgs%("--input-script p.txt --seed 7 --god", 0, isMerged)
IS_Assert isOk And isMerged = "--input-script p.txt --seed 7 --god", "no header: launch line unchanged"

Print "--- files ---"
isOk = ISC_Load%("no/such/script.txt")
IS_Assert isOk = 0 And InStr(iscError, "not found") > 0 And iscActive = 0, "missing file: error, not active"
Dim isTmp As String, isTmpFH As Integer
isTmp = "inputscript_test_header.tmp"
isTmpFH = FreeFile
Open isTmp For Output As #isTmpFH
Print #isTmpFH, "# header test"
Print #isTmpFH, "#! seed 1"
Print #isTmpFH, "#! args --god --nerf"
Print #isTmpFH, "#! frames 20000"
Print #isTmpFH, "0 1 FIRE"
Close #isTmpFH
isOk = ISC_Load%(isTmp)
IS_Assert isOk And iscActive And iscCount = 1 And iscHdrSeed = "1" And iscHdrFrames = "20000" And iscHdrArgs = "--god --nerf", "file with a header loads it"
Open isTmp For Output As #isTmpFH
Print #isTmpFH, "#! sede 1"
Close #isTmpFH
isOk = ISC_Load%(isTmp)
IS_Assert isOk = 0 And iscActive = 0 And InStr(iscError, "'sede'") > 0, "file with a bad header key fails to load"
Kill isTmp

Print ""
Print "=== " + LTrim$(Str$(isPassed + isFailed)) + " tests: " + LTrim$(Str$(isPassed)) + " passed, " + LTrim$(Str$(isFailed)) + " failed ==="
If isFailed > 0 Then System 1 Else System 0

' One scripted frame at a game state and sequence label.
Sub IS_Frame(isFfNo As Long, isFfState As String, isFfLabel As String)
    ISC_SetContext isFfState, isFfLabel
    ISC_Apply isFfNo, isHeld()
End Sub

' The queued presses, drained, as " code code ...".
Function IS_Hits$
    Dim isHk As Long, isHs As String
    Do
        isHk = KEY_Hit&
        If isHk = 0 Then Exit Do
        isHs = isHs + Str$(isHk)
    Loop
    IS_Hits$ = isHs
End Function

' stub: input.bas logs devices through debug.bas, which this test doesn't include
Sub DBG_Print(isDbgMsg As String)
End Sub
