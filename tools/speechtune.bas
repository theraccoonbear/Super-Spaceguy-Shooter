' speechtune.bas -- standalone voice-tuning tool for the speech synthesizer (#236).
'
' Picks a line the game speaks (assets/gametext.txt) or one you type, renders it to a sample buffer
' with the game's own speech.bas (src/audio/speechrender.bas), and plays it from a playhead you can
' scrub, loop and replay. Nudging a setting re-renders the line and keeps the playhead time, so the
' effect of a change on the same syllable is heard at once. S writes the settings to
' assets/config/speech.ini, R reads them back.
'
' Keys: Up/Down (or Tab) pick a setting, Left/Right change it (off/on, Slow/Normal/Fast), , . scrub 1 s
' (< > 0.25 s), PgUp/PgDn change line, Space play/pause, Enter restart, [ ] L loop, T type a line, S, R, Q.
' A setting row that has no effect under the current switches is drawn dim (SPK_PkInactive$).
'
' Build: tools/buildqb tools/speechtune.bas   (in the container: tools/dev speechtune builds and opens it)
' Run:   builds/speechtune                    (from the repo root: it finds assets/config/speech.ini there)
Option _Explicit
'$INCLUDE:'../src/sys/failfast.bi'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'

Sub DBG_Print (tkDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/audio/speechcfg.bas'
'$INCLUDE:'../src/sys/gametext.bas'
'$INCLUDE:'../src/2d/crawllayout.bas'
'$INCLUDE:'../src/audio/speechrender.bas'

Const TK_W = 960
Const TK_H = 672
Const TK_INI = "assets/config/speech.ini"
Const TK_ROWS = SPK_PK_N + SPK_FX_N + 1   ' knobs, clarity features, the preset
Const TK_ROW_PRESET = SPK_PK_N + SPK_FX_N
Const TK_HOLD = 20       ' frames a key is held before it repeats
Const TK_REPEAT = 4      ' frames between repeats
Const TK_QUEUE = 0.06    ' seconds of audio kept queued in the device
Const TK_GAIN = 0.8
Const TK_TL_X = 24       ' timeline bar
Const TK_TL_Y = 124
Const TK_TL_W = 912
Const TK_TL_H = 26
Const TK_BIG = 4         ' scale of the current-word text

Dim Shared tkHeld(0 To 63) As Integer
Dim Shared tkLine As Integer          ' index into tnLineTxt, or -1 for a typed line
Dim Shared tkText As String           ' the line being tuned
Dim Shared tkCustom As String
Dim Shared tkSel As Integer           ' selected settings row
Dim Shared tkPreset As Integer        ' 1 Slow, 2 Normal, 3 Fast
Dim Shared tkMsg As String, tkMsgUntil As Double
Dim Shared tkEntering As Integer, tkEntry As String
Dim Shared tkIoFail As Integer, tkIoPath As String, tkIoText As String
Dim Shared tkWordImg As Long, tkWordIdx As Integer
Dim Shared tkQuit As Integer
Dim Shared tkCol(0 To 9) As Long

Dim Shared tkMain As Long, tkWantSave As Integer
Dim tkArgs As String, tkShot As String, tkP As Integer, tkI As Integer
tkMain = _NewImage(TK_W, TK_H, 32)
Screen tkMain
_Title "Speech tune"
tkWordImg = 0 : tkWordIdx = -2
tkCol(0) = _RGB32(18, 20, 28)      ' background
tkCol(1) = _RGB32(34, 38, 52)      ' panel
tkCol(2) = _RGB32(225, 228, 238)   ' text
tkCol(3) = _RGB32(130, 138, 160)   ' dim text
tkCol(4) = _RGB32(255, 214, 90)    ' accent
tkCol(5) = _RGB32(60, 96, 170)     ' loop region
tkCol(6) = _RGB32(70, 150, 220)    ' selected row
tkCol(7) = _RGB32(120, 235, 160)   ' on
tkCol(8) = _RGB32(255, 120, 110)   ' off, errors
tkCol(9) = _RGB32(80, 86, 108)     ' ticks

AUD_SetRate _SndRate
SPK_Init
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
TUNE_LoadLines
tkPreset = 2
tkSel = SPK_PK_FALL
TK_Reload
If tnLineN > 0 Then TK_PickLine 0 Else TK_Custom "NO LINES"
_KeyClear
tkArgs = Command$
tkP = InStr(tkArgs, "--screenshot ")
If tkP > 0 Then
    tkShot = LTrim$(Mid$(tkArgs, tkP + 13))
    If InStr(tkShot, " ") > 0 Then tkShot = Left$(tkShot, InStr(tkShot, " ") - 1)
    If Left$(tkShot, 1) <> "/" Then tkShot = _StartDir$ + "/" + tkShot
    tkP = InStr(tkArgs, "--line ")
    If tkP > 0 Then
        tkI = Val(Mid$(tkArgs, tkP + 7)) - 1
        If tkI >= 0 And tkI < tnLineN Then TK_PickLine tkI
    End If
    tnPlaying = 0 : tnPos = tnLen * 0.4 : tnLoopA = tnLen * 0.25 : tnLoopB = tnLen * 0.6 : tnLooping = -1
    TK_Draw
    _SaveImage tkShot, tkMain
    System 0
End If
Do
    _Limit 60
    If tkEntering Then TK_EntryKeys Else TK_Keys
    If tkWantSave Then
        tkWantSave = 0
        GoSub tkDoSave
        If tkIoFail Then TK_Say "Could not write " + TK_INI Else TK_Say "Saved " + TK_INI
    End If
    If tkQuit Then Exit Do
    TK_Feed
    TK_Draw
    _Display
Loop
_SndRawDone
System 0

tkDoSave:
tkIoFail = 0
On Error GoTo tkSaveFail
Open tkIoPath For Output As #1
If tkIoFail = 0 Then Print #1, tkIoText; : Close #1
On Error GoTo SSS_FailFast
Return
tkSaveFail:
tkIoFail = -1
Resume Next

Function TK_Down% (tdC As Long)
    Dim tdN As Integer
    tdN = _KeyDown(tdC)
    If tdC >= 97 And tdC <= 122 Then tdN = tdN Or _KeyDown(tdC - 32)
    TK_Down% = (tdN <> 0)
End Function

' A key's press (and, with tpRep, its repeats while held). tpSlot is the key's own counter.
Function TK_Press% (tpC As Long, tpSlot As Integer, tpRep As Integer)
    TK_Press% = 0
    If TK_Down%(tpC) Then
        tkHeld(tpSlot) = tkHeld(tpSlot) + 1
        If tkHeld(tpSlot) = 1 Then TK_Press% = -1
        If tpRep And tkHeld(tpSlot) > TK_HOLD And (tkHeld(tpSlot) - TK_HOLD) Mod TK_REPEAT = 0 Then TK_Press% = -1
    Else
        tkHeld(tpSlot) = 0
    End If
End Function

Function TK_Shift% ()
    TK_Shift% = (_KeyDown(100303) Or _KeyDown(100304)) <> 0
End Function

Sub TK_Say (tsMsg As String)
    tkMsg = tsMsg : tkMsgUntil = Timer + 4
End Sub

Function TK_IniPath$ ()
    Dim tipA As String
    tipA = _StartDir$ + "/" + TK_INI
    If _FileExists(tipA) Then TK_IniPath$ = tipA : Exit Function
    tipA = _Cwd$ + "/../" + TK_INI
    If _FileExists(tipA) Then TK_IniPath$ = tipA : Exit Function
    TK_IniPath$ = ""
End Function

Sub TK_Rerender
    TUNE_RenderKeep tkText, tkPreset
End Sub

Sub TK_Reload
    Dim trP As String
    trP = TK_IniPath$
    If trP = "" Then
        TK_Say "speech.ini not found: run from the repo root"
    ElseIf SPK_ProsodyLoad%(_ReadFile$(trP)) Then
        TK_Say "Reloaded " + TK_INI
    Else
        TK_Say spkCfgErr
    End If
    If Len(tkText) > 0 Then TK_Rerender
End Sub

Sub TK_Save
    Dim tsvP As String
    tsvP = TK_IniPath$
    If tsvP = "" Then TK_Say "speech.ini not found: run from the repo root" : Exit Sub
    tkIoPath = tsvP
    tkIoText = SPK_ProsodySave$(_ReadFile$(tsvP))
    tkWantSave = -1
End Sub

Sub TK_PickLine (tpIdx As Integer)
    tkLine = tpIdx
    tkText = tnLineTxt(tpIdx)
    TUNE_NewLine tkText, tkPreset
    tnPlaying = -1
End Sub

Sub TK_Custom (tcTxt As String)
    tkLine = -1
    tkText = tcTxt
    TUNE_NewLine tkText, tkPreset
    tnPlaying = -1
End Sub

Sub TK_Step (tsD As Integer)
    Dim tsN As Integer, tsWas As Integer
    If tnLineN = 0 Then Exit Sub
    tsWas = tnPlaying
    tsN = tkLine + tsD
    If tkLine < 0 Then tsN = 0
    If tsN < 0 Then tsN = tnLineN - 1
    If tsN >= tnLineN Then tsN = 0
    TK_PickLine tsN
    tnPlaying = tsWas
End Sub

' Change the selected row by tnD (-1 / +1) and re-render. On/off rows (the features and Glide pitch)
' take Left = off, Right = on; the preset steps Slow / Normal / Fast.
Sub TK_Nudge (tnD As Integer)
    Dim tnF As Integer
    If tkSel < SPK_PK_N Then
        If tkSel = SPK_PK_GPITCH Then
            SPK_PkSet tkSel, -(tnD > 0)
        Else
            SPK_PkSet tkSel, spkPk(tkSel) + tnD * spkPkInc(tkSel)
        End If
    ElseIf tkSel < TK_ROW_PRESET Then
        tnF = tkSel - SPK_PK_N
        spkFx(tnF) = (tnD > 0)
    Else
        tkPreset = tkPreset + tnD
        If tkPreset < 1 Then tkPreset = 1
        If tkPreset > 3 Then tkPreset = 3
    End If
    TK_Rerender
End Sub

' "" when row trR is in play with the current settings, else why it has no effect
Function TK_RowInactive$ (triR As Integer)
    If triR < SPK_PK_N Then TK_RowInactive$ = SPK_PkInactive$(triR) Else TK_RowInactive$ = ""
End Function

Sub TK_Keys
    If TK_Press%(27, 0, 0) Or TK_Press%(113, 1, 0) Then tkQuit = -1
    If TK_Press%(9, 2, 0) Then
        If TK_Shift% Then tkSel = (tkSel + TK_ROWS - 1) Mod TK_ROWS Else tkSel = (tkSel + 1) Mod TK_ROWS
    End If
    If TK_Press%(20480, 3, -1) Then tkSel = (tkSel + 1) Mod TK_ROWS
    If TK_Press%(18432, 4, -1) Then tkSel = (tkSel + TK_ROWS - 1) Mod TK_ROWS
    If TK_Press%(19200, 5, -1) Then TK_Nudge -1
    If TK_Press%(19712, 6, -1) Then TK_Nudge 1
    If TK_Press%(32, 7, 0) Then
        If tnPos >= tnLen Then tnPos = 0
        tnPlaying = (tnPlaying = 0)
    End If
    If TK_Press%(13, 8, 0) Then tnPos = 0 : tnPlaying = -1
    If TK_Press%(44, 9, -1) Then TUNE_Scrub -1
    If TK_Press%(46, 10, -1) Then TUNE_Scrub 1
    If TK_Press%(60, 11, -1) Then TUNE_Scrub -0.25
    If TK_Press%(62, 12, -1) Then TUNE_Scrub 0.25
    If TK_Press%(91, 13, 0) Then TUNE_SetLoopStart : TK_Say "Loop starts at " + TK_Time$(tnPos)
    If TK_Press%(93, 14, 0) Then TUNE_SetLoopEnd : TK_Say "Loop ends at " + TK_Time$(tnPos)
    If TK_Press%(108, 15, 0) Then tnLooping = (tnLooping = 0)
    If TK_Press%(18688, 16, 0) Then TK_Step -1
    If TK_Press%(20736, 17, 0) Then TK_Step 1
    If TK_Press%(115, 18, 0) Then TK_Save
    If TK_Press%(114, 19, 0) Then TK_Reload
    If TK_Press%(116, 20, 0) Then
        tkEntering = -1 : tkEntry = tkCustom
        _KeyClear
    End If
End Sub

Sub TK_EntryKeys
    Dim tekK As String
    Do
        tekK = InKey$
        If tekK = "" Then Exit Do
        If tekK = Chr$(13) Then
            tkEntering = 0 : tkCustom = tkEntry
            If Len(LTrim$(tkEntry)) > 0 Then TK_Custom tkEntry
            _KeyClear
            TK_Settle
            Exit Do
        ElseIf tekK = Chr$(27) Then
            tkEntering = 0 : _KeyClear : TK_Settle : Exit Do
        ElseIf tekK = Chr$(8) Then
            If Len(tkEntry) > 0 Then tkEntry = Left$(tkEntry, Len(tkEntry) - 1)
        ElseIf Len(tekK) = 1 And Asc(tekK) >= 32 And Len(tkEntry) < 200 Then
            tkEntry = tkEntry + tekK
        End If
    Loop
End Sub

' Keep the device topped up to TK_QUEUE seconds from the playhead.
Sub TK_Feed
    Dim tfN As Integer
    If tnPlaying = 0 Then Exit Sub
    Do While _SndRawLen < TK_QUEUE And tfN < 8192 And tnPlaying
        _SndRaw TUNE_Next! * TK_GAIN
        tfN = tfN + 1
    Loop
End Sub

Function TK_Time$ (ttS As Long)
    Dim ttMs As Long
    ttMs = CLng(ttS * 1000# / SAMPLE_RATE)
    TK_Time$ = LTrim$(Str$(ttMs \ 60000)) + ":" + Right$("0" + LTrim$(Str$((ttMs \ 1000) Mod 60)), 2) + "." + LTrim$(Str$((ttMs \ 100) Mod 10))
End Function

Function TK_X& (txS As Long)
    If tnLen = 0 Then TK_X& = TK_TL_X : Exit Function
    TK_X& = TK_TL_X + CLng(txS * CDbl(TK_TL_W) / tnLen)
End Function

' The playhead as heard: what has been queued to the device but not yet played is subtracted.
Function TK_Heard& ()
    Dim thP As Long
    thP = tnPos
    If tnPlaying Then thP = thP - CLng(_SndRawLen * SAMPLE_RATE)
    If thP < 0 Then thP = 0
    If thP > tnLen Then thP = tnLen
    TK_Heard& = thP
End Function

Sub TK_Text (tx As Integer, ty As Integer, ttTxt As String, ttCol As Long)
    Color ttCol, 0
    _PrintMode _KeepBackground
    _PrintString (tx, ty), ttTxt
End Sub

Function TK_OnOff$ (tooV As Integer)
    If tooV Then TK_OnOff$ = "on" Else TK_OnOff$ = "off"
End Function

Function TK_Value$ (tvR As Integer)
    If tvR < SPK_PK_N Then
        If tvR = SPK_PK_GPITCH Then TK_Value$ = TK_OnOff$(spkPk(tvR) >= 0.5) Else TK_Value$ = SPK_Num$(spkPk(tvR))
    ElseIf tvR < TK_ROW_PRESET Then
        TK_Value$ = TK_OnOff$(spkFx(tvR - SPK_PK_N))
    Else
        TK_Value$ = TK_PresetName$(tkPreset)
    End If
End Function

Function TK_PresetName$ (chI As Integer)
    If chI = 1 Then
        TK_PresetName$ = "Slow"
    ElseIf chI = 2 Then
        TK_PresetName$ = "Normal"
    Else
        TK_PresetName$ = "Fast"
    End If
End Function

Function TK_Name$ (tnR As Integer)
    If tnR < SPK_PK_N Then
        TK_Name$ = SPK_PkName$(tnR)
    ElseIf tnR < TK_ROW_PRESET Then
        TK_Name$ = SPK_FxName$(tnR - SPK_PK_N)
    Else
        TK_Name$ = "Speed preset"
    End If
End Function

Function TK_Range$ (trR As Integer)
    If trR < SPK_PK_N Then
        If trR = SPK_PK_GPITCH Then TK_Range$ = "off or on" Else TK_Range$ = SPK_Num$(spkPkMin(trR)) + " to " + SPK_Num$(spkPkMax(trR))
    ElseIf trR < TK_ROW_PRESET Then
        TK_Range$ = "off or on"
    Else
        TK_Range$ = "Slow to Fast"
    End If
End Function

Function TK_Desc$ (tdR As Integer)
    If tdR < SPK_PK_N Then
        TK_Desc$ = SPK_PkDesc$(tdR)
    ElseIf tdR < TK_ROW_PRESET Then
        TK_Desc$ = SPK_FxDesc$(tdR - SPK_PK_N)
    Else
        TK_Desc$ = "How fast the line is spoken (narration setting)"
    End If
End Function

' Print tdwTxt wrapped to tdwCols columns from (tdwX, tdwY), at most tdwRows rows; a longer text ends in ...
Sub TK_Wrapped (tdwX As Integer, tdwY As Integer, tdwTxt As String, tdwCols As Integer, tdwRows As Integer, tdwCol As Long)
    Dim tdwRem As String, tdwCut As Integer, tdwR As Integer
    tdwRem = tdwTxt
    For tdwR = 0 To tdwRows - 1
        If Len(tdwRem) = 0 Then Exit For
        If Len(tdwRem) <= tdwCols Then
            TK_Text tdwX, tdwY + tdwR * 16, tdwRem, tdwCol
            tdwRem = ""
        Else
            tdwCut = tdwCols
            Do While tdwCut > 0 And Mid$(tdwRem, tdwCut + 1, 1) <> " "
                tdwCut = tdwCut - 1
            Loop
            If tdwCut = 0 Then tdwCut = tdwCols
            If tdwR = tdwRows - 1 Then
                TK_Text tdwX, tdwY + tdwR * 16, Left$(tdwRem, tdwCols - 3) + "...", tdwCol
            Else
                TK_Text tdwX, tdwY + tdwR * 16, RTrim$(Left$(tdwRem, tdwCut)), tdwCol
            End If
            tdwRem = LTrim$(Mid$(tdwRem, tdwCut + 1))
        End If
    Next tdwR
End Sub

Sub TK_Draw
    Dim tdI As Integer, tdY As Integer, tdHead As String, tdHeard As Long, tdW As Integer, tdX As Long
    Dim tdRowCol As Long, tdBig As String, tdImg As Long, tdWhy As String
    Line (0, 0)-(TK_W - 1, TK_H - 1), tkCol(0), BF
    ' header and line
    If tkLine >= 0 Then
        tdHead = "Line " + LTrim$(Str$(tkLine + 1)) + " of " + LTrim$(Str$(tnLineN)) + "   " + tnLineKey(tkLine)
    Else
        tdHead = "Typed line"
    End If
    TK_Text 24, 10, tdHead, tkCol(3)
    If tkEntering Then
        TK_Text 24, 30, "Type a line, Enter speaks it, Esc cancels:", tkCol(4)
        TK_Wrapped 24, 48, tkEntry + "_", 110, 3, tkCol(2)
    Else
        Line (16, 28)-(TK_W - 17, 82), tkCol(1), BF
        TK_Wrapped 24, 32, tkText, 110, 3, tkCol(2)
    End If
    ' timeline
    tdHeard = TK_Heard&
    Line (TK_TL_X, TK_TL_Y)-(TK_TL_X + TK_TL_W, TK_TL_Y + TK_TL_H), tkCol(1), BF
    If tnLoopB > tnLoopA Then
        If tnLooping Then
            Line (TK_X&(tnLoopA), TK_TL_Y)-(TK_X&(tnLoopB), TK_TL_Y + TK_TL_H), tkCol(5), BF
        Else
            Line (TK_X&(tnLoopA), TK_TL_Y)-(TK_X&(tnLoopB), TK_TL_Y + TK_TL_H), tkCol(9), B
        End If
    End If
    For tdI = 0 To tnWordN - 1
        tdX = TK_X&(tnWordAt(tdI))
        Line (tdX, TK_TL_Y + TK_TL_H - 10)-(tdX, TK_TL_Y + TK_TL_H), tkCol(3)
    Next tdI
    tdI = TUNE_WordAt%(tdHeard)
    If tdI >= 0 Then Line (TK_X&(tnWordAt(tdI)), TK_TL_Y + TK_TL_H - 4)-(TK_X&(tnWordEnd(tdI)), TK_TL_Y + TK_TL_H), tkCol(4), BF
    tdX = TK_X&(tdHeard)
    Line (tdX - 1, TK_TL_Y - 4)-(tdX + 1, TK_TL_Y + TK_TL_H + 4), tkCol(2), BF
    tdHead = TK_Time$(tdHeard) + " / " + TK_Time$(tnLen)
    If tnPlaying Then tdHead = tdHead + "   playing" Else tdHead = tdHead + "   paused"
    If tnLooping Then tdHead = tdHead + "   loop " + TK_Time$(tnLoopA) + " to " + TK_Time$(tnLoopB) Else tdHead = tdHead + "   loop off (region " + TK_Time$(tnLoopA) + " to " + TK_Time$(tnLoopB) + ")"
    If tnCut Then tdHead = tdHead + "   (line cut at the buffer limit)"
    TK_Text TK_TL_X, TK_TL_Y + TK_TL_H + 8, tdHead, tkCol(3)
    ' the word under the playhead, large
    If tdI <> tkWordIdx Then
        tkWordIdx = tdI
        If tkWordImg <> 0 Then _FreeImage tkWordImg : tkWordImg = 0
        If tdI >= 0 Then
            tdBig = tnWordTxt(tdI)
            tkWordImg = _NewImage(8 * Len(tdBig), 16, 32)
            _Dest tkWordImg
            Line (0, 0)-(8 * Len(tdBig) - 1, 15), tkCol(0), BF
            Color tkCol(4), tkCol(0)
            _PrintString (0, 0), tdBig
            _Dest tkMain
        End If
    End If
    If tkWordImg <> 0 Then
        tdW = _Width(tkWordImg) * TK_BIG
        If tdW > TK_W - 48 Then tdW = TK_W - 48
        _PutImage (24, 170)-(24 + tdW - 1, 170 + 16 * TK_BIG - 1), tkWordImg, tkMain
    End If
    ' settings
    TK_Text 24, 246, "Setting", tkCol(3)
    TK_Text 304, 246, "Value", tkCol(3)
    TK_Text 392, 246, "Range", tkCol(3)
    TK_Text 504, 246, "What it does", tkCol(3)
    For tdI = 0 To TK_ROWS - 1
        tdY = 264 + tdI * 18
        tdWhy = TK_RowInactive$(tdI)
        If tdI = tkSel Then
            Line (16, tdY - 1)-(TK_W - 17, tdY + 16), tkCol(6), BF
            tdRowCol = tkCol(0)
        ElseIf Len(tdWhy) > 0 Then
            tdRowCol = tkCol(9)
        Else
            tdRowCol = tkCol(2)
        End If
        TK_Text 24, tdY, TK_Name$(tdI), tdRowCol
        If tdI <> tkSel And Len(tdWhy) = 0 Then
            If tdI = SPK_PK_GPITCH Or (tdI >= SPK_PK_N And tdI < TK_ROW_PRESET) Then
                If TK_Value$(tdI) = "on" Then TK_Text 304, tdY, TK_Value$(tdI), tkCol(7) Else TK_Text 304, tdY, TK_Value$(tdI), tkCol(8)
            Else
                TK_Text 304, tdY, TK_Value$(tdI), tkCol(4)
            End If
        Else
            TK_Text 304, tdY, TK_Value$(tdI), tdRowCol
        End If
        If tdI = tkSel Then
            TK_Text 392, tdY, TK_Range$(tdI), tkCol(0)
        ElseIf Len(tdWhy) > 0 Then
            TK_Text 392, tdY, TK_Range$(tdI), tkCol(9)
        Else
            TK_Text 392, tdY, TK_Range$(tdI), tkCol(3)
        End If
        If tdI = tkSel And Len(tdWhy) > 0 Then TK_Text 504, tdY, tdWhy, tdRowCol Else TK_Text 504, tdY, TK_Desc$(tdI), tdRowCol
    Next tdI
    ' message and help
    If Timer < tkMsgUntil Then TK_Text 24, 576, tkMsg, tkCol(4) Else TK_Text 24, 576, "", tkCol(3)
    TK_Text 24, 598, "Space play/pause   Enter restart   , . scrub 1 s (Shift: 0.25 s)   [ ] loop start/end   L loop on/off", tkCol(3)
    TK_Text 24, 614, "Up/Down pick a setting (or Tab)   Left/Right change it (off/on, Slow/Normal/Fast)   PgUp/PgDn line   T type a line", tkCol(3)
    TK_Text 24, 630, "Dim rows have no effect with the current switches   S save speech.ini   R reload speech.ini   Esc quit", tkCol(3)
End Sub

' After typing, keys still held (Enter, Esc) must be let go before they act as commands.
Sub TK_Settle
    Dim tsmI As Integer
    For tsmI = 0 To 63 : tkHeld(tsmI) = 1000 : Next tsmI
End Sub
