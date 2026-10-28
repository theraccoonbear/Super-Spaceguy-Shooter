' callsign_pad_test.bas -- the callsign screen's input (src/state/usernamelogic.bas) driven by
' scripted input through the real input path (ISC_Apply -> E3D_PadMap -> held() / KEY_Hit&):
' spelling a name on the pad's letter spinner, wrap-around both ways, hold-to-repeat, B
' delete, Y color (one character only, ~X tokens zero width), Start done, Back skip, cursor
' moves stepping over ~X tokens, the length cap, and switching between keyboard and pad
' mid-entry on the same string, and the UI sound (uiSfx) each action asks for.
'
' Build: ./tools/buildqb tests/callsign_pad_test.bas
' Run:   builds/callsign_pad_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY

Sub DBG_Print (cpDbg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'
'$INCLUDE:'../src/sys/inputscript.bas'
'$INCLUDE:'../src/2d/textedit.bas'
'$INCLUDE:'../src/state/usernamelogic.bas'

Dim Shared cpPassed As Integer, cpFailed As Integer
Dim Shared cpS As String, cpC As Integer, cpSfx As String

Sub CP_Assert (cpaCond As Integer, cpaName As String)
    If cpaCond Then
        Print "PASS  " + cpaName
        cpPassed = cpPassed + 1
    Else
        Print "FAIL  " + cpaName + "   (s=" + Chr$(34) + cpS + Chr$(34) + " cur=" + LTrim$(Str$(cpC)) + " sfx=" + cpSfx + ")"
        cpFailed = cpFailed + 1
    End If
End Sub

' Fresh input state and a script from lines separated by "/".
Sub CP_Script (cpsLines As String)
    Dim cpsP As Integer, cpsQ As Integer, cpsOk As Integer
    ISC_Clear
    iscActive = -1
    For cpsP = 0 To 32767 : held(cpsP) = 0 : keyPrevHeld(cpsP) = 0 : Next cpsP
    For cpsP = 1 To E3D_PAD_MAX_BTNS : inpPadBtnWas(cpsP) = 0 : Next cpsP
    For cpsP = 1 To 4 : inpPadAxWas(cpsP) = 0 : Next cpsP
    inpLastDev = INP_DEV_KEYS : inpKeysWas = 0
    unRepDir = 0 : unRepN = 0
    cpsP = 1
    Do While cpsP <= Len(cpsLines)
        cpsQ = InStr(cpsP, cpsLines, "/")
        If cpsQ = 0 Then cpsQ = Len(cpsLines) + 1
        cpsOk = ISC_ParseLine%(Mid$(cpsLines, cpsP, cpsQ - cpsP))
        If cpsOk = 0 Then Print "bad script line: "; iscError
        cpsP = cpsQ + 1
    Loop
End Sub

Function CP_I$ (cpiId As Integer)
    CP_I$ = LTrim$(Str$(cpiId)) + ","
End Function

' The screen on cprName$ with the cursor at cprCur, frames 0..cprLast of the script; returns
' UN_DONE / UN_SKIP on the frame one comes (stopping there), else UN_NONE. cpSfx collects the
' UI sounds asked for (uiSfx), one per frame as the main loop plays them.
Function CP_Run% (cprName As String, cprCur As Integer, cprScript As String, cprLast As Long)
    Dim cprF As Long, cprR As Integer
    cpS = cprName : cpC = cprCur
    cpSfx = "" : uiSfx = 0
    CP_Script cprScript
    CP_Run% = UN_NONE
    For cprF = 0 To cprLast
        KEY_FrameBegin
        ISC_Apply cprF, held()
        cprR = UN_Input%(cpS, cpC, UN_MAX_LEN)
        If uiSfx Then cpSfx = cpSfx + CP_I$(uiSfx) : uiSfx = 0
        If cprR = UN_DONE Or cprR = UN_SKIP Then CP_Run% = cprR : Exit Function
    Next cprF
End Function

Print "=== callsign_pad_test ==="
Print ""

Dim cpR As Integer

E3D_KeyDefaults
E3D_PadSelect "Microsoft X-Box 360 pad", 11, 8

Print "--- spelling on the pad ---"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_UP", 4)
CP_Assert cpS = "A" And cpC = 0, "up on the empty box: A, cursor on it"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_UP/4 4 PAD_A", 6)
CP_Assert cpS = "AA" And cpC = 1, "pad A on the last letter appends an A and moves onto it"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_UP/4 4 PAD_A/6 6 PAD_DPAD_UP/8 8 PAD_DPAD_UP/10 10 PAD_DPAD_RIGHT/12 12 PAD_DPAD_UP/14 14 PAD_DPAD_UP/16 16 PAD_DPAD_UP/18 18 PAD_DPAD_UP/20 20 PAD_START", 30)
CP_Assert cpR = UN_DONE And cpS = "ACE", "up, A, up x2, right, up x4, Start: ACE, done"
cpR = CP_Run%("", 0, "2 2 PAD_UP/4 4 PAD_RIGHT/6 6 PAD_DOWN", 8)
CP_Assert cpS = "A." And cpC = 1, "the stick spins and moves like the d-pad"
cpR = CP_Run%("AB", 0, "2 2 PAD_A", 4)
CP_Assert cpS = "AB" And cpC = 1, "pad A mid-name only moves on"
cpR = CP_Run%("ACE", 3, "2 2 PAD_A/4 4 PAD_A", 6)
CP_Assert cpR = UN_NONE, "pad A never confirms"

Print ""
Print "--- wrap-around and repeat ---"
cpR = CP_Run%("A", 0, "2 2 PAD_DPAD_DOWN", 4)
CP_Assert cpS = ".", "down from A wraps to ."
cpR = CP_Run%(".", 0, "2 2 PAD_DPAD_UP", 4)
CP_Assert cpS = "A", "up from . wraps to A"
cpR = CP_Run%("Z9", 0, "2 2 PAD_DPAD_UP/4 4 PAD_A/6 6 PAD_DPAD_UP/8 8 PAD_DPAD_UP", 10)
CP_Assert cpS = "0-", "Z -> 0, 9 -> space -> -"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_DOWN", 4)
CP_Assert cpS = ".", "down on the empty box: ."
cpR = CP_Run%("a", 0, "2 2 PAD_DPAD_UP", 4)
CP_Assert cpS = "B", "a typed lower-case letter spins on as its capital"
cpR = CP_Run%("!", 0, "2 2 PAD_DPAD_DOWN", 4)
CP_Assert cpS = ".", "a character outside the set spins in from the end"
cpR = CP_Run%("A", 0, "2 29 PAD_DPAD_UP", 29)
CP_Assert cpS = "D", "held up: one step, then after the delay one every few frames (28 frames: D)"
cpR = CP_Run%("A", 0, "2 30 PAD_DPAD_UP", 30)
CP_Assert cpS = "E", "held up one frame longer: E"
cpR = CP_Run%("A", 0, "2 15 PAD_DPAD_UP", 20)
CP_Assert cpS = "B", "a short hold is one step"
cpR = CP_Run%("A", 0, "2 30 PAD_DPAD_DOWN", 30)
CP_Assert cpS = "9", "held down repeats too, wrapping: . - space 9"

Print ""
Print "--- B delete ---"
cpR = CP_Run%("ACEA", 3, "2 2 PAD_B", 4)
CP_Assert cpS = "ACE" And cpC = 2, "B on the last letter deletes it, cursor back on E"
cpR = CP_Run%("ACEA", 3, "2 2 PAD_B/4 4 PAD_B", 6)
CP_Assert cpS = "AC" And cpC = 1, "B again: AC, on C"
cpR = CP_Run%("ACE", 0, "2 2 PAD_B", 4)
CP_Assert cpS = "CE" And cpC = 0, "B on the first letter: CE, on C"
cpR = CP_Run%("ACE", 3, "2 2 PAD_B", 4)
CP_Assert cpS = "AC" And cpC = 2, "B on the empty slot past the end is a backspace"
cpR = CP_Run%("", 0, "2 2 PAD_B", 4)
CP_Assert cpS = "" And cpR = UN_NONE, "B on an empty box: nothing, and no skip"

Print ""
Print "--- Y color ---"
cpR = CP_Run%("ACE", 1, "2 2 PAD_Y", 4)
CP_Assert cpS = "A~0C~FE" And cpC = 1, "Y on C: C alone takes color 0"
CP_Assert TXE_VisCol%(cpS, 0, Len(cpS)) = 3, "the tokens aren't letters: still 3 wide"
cpR = CP_Run%("ACE", 1, "2 2 PAD_Y/4 4 PAD_Y", 6)
CP_Assert cpS = "A~1C~FE", "Y again: the same token cycles to 1"
cpR = CP_Run%("ACE", 1, "2 2 PAD_Y/4 4 PAD_Y/6 6 PAD_A/8 8 PAD_Y", 10)
CP_Assert cpS = "A~1C~0E" And cpC = 4, "A steps over the token onto E; Y recolors E alone"
cpR = CP_Run%("~3ACE", 2, "2 2 PAD_A/4 4 PAD_Y", 6)
CP_Assert cpS = "~3A~4C~3E", "a typed ~3: C cycles from 3 to 4, E stays 3"
cpR = CP_Run%("AB~E", 4, "2 2 PAD_Y", 4)
CP_Assert cpS = "AB~E", "Y on the empty slot: nothing"
cpR = CP_Run%("ABCDEFGHIJKLMNOPQRSTUVWXYZ01234", 1, "2 2 PAD_Y", 4)
CP_Assert Len(cpS) = 31, "Y that would pass the length cap: nothing"
cpR = CP_Run%("A~0C~FE", 1, "2 2 PAD_DPAD_UP", 4)
CP_Assert cpS = "A~0D~FE", "spinning a colored letter keeps its color"

Print ""
Print "--- cursor over ~X tokens ---"
cpR = CP_Run%("A~3BC", 5, "2 2 PAD_DPAD_LEFT", 4)
CP_Assert UN_SpinAt%(cpS, cpC) = 5, "left from the end: on C"
cpR = CP_Run%("A~3BC", 5, "2 2 PAD_DPAD_LEFT/4 4 PAD_DPAD_LEFT", 6)
CP_Assert UN_SpinAt%(cpS, cpC) = 4, "left again: on B"
cpR = CP_Run%("A~3BC", 5, "2 2 PAD_DPAD_LEFT/4 4 PAD_DPAD_LEFT/6 6 PAD_LEFT", 8)
CP_Assert UN_SpinAt%(cpS, cpC) = 1 And cpC = 0, "left again steps over ~3 onto A in one press"
cpR = CP_Run%("A~3BC", 0, "2 2 PAD_DPAD_LEFT", 4)
CP_Assert cpC = 0, "left on the first letter stays"
cpR = CP_Run%("AB~3", 4, "2 2 PAD_DPAD_UP", 4)
CP_Assert cpS = "AB~3A" And UN_SpinAt%(cpS, cpC) = 5, "a letter added past a trailing ~3 lands after it (takes its color)"
cpR = CP_Run%("ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", 31, "2 2 PAD_A/4 4 PAD_DPAD_UP", 6)
CP_Assert Len(cpS) = 32 And cpC = 32, "at the length cap, A moves past the end but adds nothing"

Print ""
Print "--- done and skip ---"
cpR = CP_Run%("ACE", 3, "2 2 PAD_START", 4)
CP_Assert cpR = UN_DONE, "Start: done"
cpR = CP_Run%("ACE", 3, "2 2 PAD_SELECT", 4)
CP_Assert cpR = UN_SKIP And cpS = "ACE", "Back: skip"
cpR = CP_Run%("ACE", 3, "2 2 ENTER", 4)
CP_Assert cpR = UN_DONE, "ENTER: done"
cpR = CP_Run%("ACE", 3, "2 2 ESC", 4)
CP_Assert cpR = UN_SKIP, "ESC: skip"
cpR = CP_Run%("", 0, "4 4 A/6 6 C/8 8 E/10 10 7/14 14 ENTER", 16)
CP_Assert cpR = UN_DONE And cpS = "ace7", "the playthrough's typed a c e 7 ENTER"

Print ""
Print "--- switching device mid-entry ---"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_UP/4 4 PAD_A/6 6 B/8 8 PAD_DPAD_UP/10 10 C/12 12 ENTER", 14)
CP_Assert cpR = UN_DONE And cpS = "AbcB", "pad A, A; key b; pad spins the A under the cursor to B; key c; ENTER"
cpR = CP_Run%("AB", 0, "2 2 PAD_A/4 4 RIGHT", 6)
CP_Assert cpC = 2, "an arrow key after the pad moves once (keyboard), not twice"
cpR = CP_Run%("AB", 1, "2 2 PAD_DPAD_LEFT/4 4 UP/6 6 DOWN", 8)
CP_Assert cpS = "AB", "arrow keys up / down never spin"
cpR = CP_Run%("AB", 1, "2 2 PAD_DPAD_LEFT/4 4 X", 6)
CP_Assert cpS = "xAB" And cpC = 1, "typing after a pad move inserts at the pad's cursor"
cpR = CP_Run%("AB", 2, "2 2 BACKSPACE/4 4 PAD_DPAD_UP", 6)
CP_Assert cpS = "AA" And cpC = 1, "backspace then the pad: the empty slot past the end gets an A"

Print ""
Print "--- UI sounds (uiSfx) ---"
Dim cpCap As String : cpCap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
CP_Assert Len(UN_SPIN_SET) = SND_UI_SPIN_N, "one spinner tick per UN_SPIN_SET character (SND_UI_SPIN_N)"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_UP", 4)
CP_Assert cpSfx = CP_I$(SND_UI_SPIN), "up on the empty box: A's tick, the lowest"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_DOWN", 4)
CP_Assert cpSfx = CP_I$(SND_UI_SPIN + SND_UI_SPIN_N - 1), "down on the empty box: .'s tick, the highest"
cpR = CP_Run%("A", 0, "2 30 PAD_DPAD_UP", 30)
CP_Assert cpSfx = CP_I$(SND_UI_SPIN + 1) + CP_I$(SND_UI_SPIN + 2) + CP_I$(SND_UI_SPIN + 3) + CP_I$(SND_UI_SPIN + 4), "held up: one tick per step, rising B C D E"
cpR = CP_Run%("", 0, "2 2 PAD_DPAD_UP/4 4 PAD_A", 6)
CP_Assert cpSfx = CP_I$(SND_UI_SPIN) + CP_I$(SND_UI_TYPE), "pad A appending a letter: type click"
cpR = CP_Run%("AB", 0, "2 2 PAD_A/4 4 PAD_DPAD_LEFT", 6)
CP_Assert cpSfx = "", "pad A / left only moving the cursor: silent"
cpR = CP_Run%(cpCap, 32, "2 2 PAD_A", 4)
CP_Assert cpSfx = CP_I$(SND_UI_DENY), "pad A at the length cap: deny"
cpR = CP_Run%(cpCap, 31, "2 2 PAD_A/4 4 PAD_DPAD_UP", 6)
CP_Assert cpSfx = CP_I$(SND_UI_DENY), "spin on the empty slot at the cap: deny"
cpR = CP_Run%("ACEA", 3, "2 2 PAD_B", 4)
CP_Assert cpSfx = CP_I$(SND_UI_DEL), "pad B delete: falling blip"
cpR = CP_Run%("", 0, "2 2 PAD_B", 4)
CP_Assert cpSfx = "", "pad B with nothing to delete: silent"
cpR = CP_Run%("ACE", 1, "2 2 PAD_Y", 4)
CP_Assert cpSfx = CP_I$(SND_UI_COLOR), "pad Y color: shimmer"
cpR = CP_Run%("ABCDEFGHIJKLMNOPQRSTUVWXYZ01234", 1, "2 2 PAD_Y", 4)
CP_Assert cpSfx = CP_I$(SND_UI_DENY), "pad Y over the cap: deny"
cpR = CP_Run%("AB~E", 4, "2 2 PAD_Y", 4)
CP_Assert cpSfx = "", "pad Y on the empty slot: silent"
cpR = CP_Run%("ACE", 3, "2 2 PAD_START", 4)
CP_Assert cpSfx = CP_I$(SND_UI_OK), "Start with 3 characters: confirm"
cpR = CP_Run%("AC", 2, "2 2 PAD_START", 4)
CP_Assert cpR = UN_DONE And cpSfx = CP_I$(SND_UI_DENY), "Start with 2 characters: deny"
cpR = CP_Run%("", 0, "2 2 PAD_START", 4)
CP_Assert cpSfx = CP_I$(SND_UI_OK), "Start on an empty box (an auto callsign follows): confirm"
cpR = CP_Run%("ACE", 3, "2 2 PAD_SELECT", 4)
CP_Assert cpSfx = CP_I$(SND_UI_BACK), "Back skip: back"
cpR = CP_Run%("", 0, "4 4 A/6 6 C/8 8 E/10 10 7/14 14 ENTER", 16)
CP_Assert cpSfx = CP_I$(SND_UI_TYPE) + CP_I$(SND_UI_TYPE) + CP_I$(SND_UI_TYPE) + CP_I$(SND_UI_TYPE) + CP_I$(SND_UI_OK), "typed a c e 7 ENTER: four clicks, confirm"
cpR = CP_Run%("AC", 2, "2 2 ENTER", 4)
CP_Assert cpSfx = CP_I$(SND_UI_DENY), "ENTER with 2 characters: deny"
cpR = CP_Run%("ACE", 3, "2 2 ESC", 4)
CP_Assert cpSfx = CP_I$(SND_UI_BACK), "ESC skip: back"
cpR = CP_Run%("AB", 2, "2 2 BACKSPACE/4 4 BACKSPACE/6 6 BACKSPACE", 8)
CP_Assert cpSfx = CP_I$(SND_UI_DEL) + CP_I$(SND_UI_DEL), "backspace: a blip per character removed, silent once empty"
cpR = CP_Run%(cpCap, 32, "2 2 X", 4)
CP_Assert cpSfx = CP_I$(SND_UI_DENY), "typing at the cap: deny"
cpR = CP_Run%("~", 1, "2 2 3", 4)
CP_Assert cpS = "~3" And cpSfx = CP_I$(SND_UI_COLOR), "typing the digit that completes ~3: shimmer"
cpR = CP_Run%("AB", 2, "2 2 RIGHT/4 4 LEFT", 6)
CP_Assert cpSfx = "", "keyboard cursor keys: silent"

Print ""
Print "=== " + LTrim$(Str$(cpPassed + cpFailed)) + " tests: " + LTrim$(Str$(cpPassed)) + " passed, " + LTrim$(Str$(cpFailed)) + " failed ==="
If cpFailed > 0 Then System 1
System 0
