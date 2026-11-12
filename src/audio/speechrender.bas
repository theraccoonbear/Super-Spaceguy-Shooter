' speechrender.bas -- render a line of speech to a sample buffer and play it back from a movable
' playhead (tools/speechtune.bas, #236). No display, no audio device: tests drive it headless.
'
'   TUNE_LoadLines            list the game's spoken paragraphs (gametext.txt blocks, split as the crawl splits them)
'   TUNE_Render text$, preset render the line with the current speech.bas settings (spkPk, spkFx) into tnBuf
'   TUNE_RenderKeep text$, preset   the same, keeping the playhead time and the loop region (clamped to the new length)
'   TUNE_WordAt%(sample&)     index of the word at a sample, -1 in a pause
'   TUNE_Next!                the next playback sample (silence once stopped); moves the playhead, wraps the loop
'   TUNE_Scrub secs!, TUNE_SetLoopStart, TUNE_SetLoopEnd   playhead and loop arithmetic
'
' Rendering replaces the queued utterance (SPK_Say), sets the speed to the preset, puts spkHold at 0
' and spkTimeScale at 1, reseeds the shared RNG (RNG_Seed TUNE_SEED, so a render is repeatable: the
' voice noise comes from the seeded stream) and clears the two synth carry-overs from the line before
' it (spkWaveStep, spkGainB). It leaves spkPk and spkFx (the settings) alone. The game never calls it.
' Needs rng.bas, audiorate.bas, speech.bas, gametext.bas and crawllayout.bas.

Const TUNE_SEED = 4242
Const TUNE_MAX_SAMPLES = 3000000   ' 62 s at 48 kHz; a longer line is cut
Const TUNE_MAX_LINES = 512

Dim Shared tnBuf(0 To TUNE_MAX_SAMPLES - 1) As Single
Dim Shared tnLen As Long
Dim Shared tnCut As Integer                         ' the line was longer than the buffer
Dim Shared tnWordN As Integer
Dim Shared tnWordAt(0 To SPK_MAX_WORDS - 1) As Long ' first sample of each word
Dim Shared tnWordEnd(0 To SPK_MAX_WORDS - 1) As Long ' one past its last sample (its trailing silence included)
Dim Shared tnWordTxt(0 To SPK_MAX_WORDS - 1) As String
Dim Shared tnPos As Long                            ' playhead: next sample to play
Dim Shared tnPlaying As Integer
Dim Shared tnLooping As Integer
Dim Shared tnLoopA As Long, tnLoopB As Long         ' loop region [A, B)
Dim Shared tnLineN As Integer
Dim Shared tnLineKey(0 To TUNE_MAX_LINES - 1) As String
Dim Shared tnLineTxt(0 To TUNE_MAX_LINES - 1) As String

Sub TUNE_Render (tnrText As String, tnrPreset As Integer)
    Dim tnrI As Integer, tnrAt As Long, tnrOff(0 To SPK_PHONE_MAX) As Long
    spkHold = 0 : spkTimeScale = 1
    SPK_Say tnrText
    SPK_SetPreset tnrPreset
    tnrAt = 0
    For tnrI = 0 To spkPhoneCount - 1
        tnrOff(tnrI) = tnrAt
        tnrAt = tnrAt + SPK_PhoneDur&(spkPhones(tnrI), spkStress(tnrI))
    Next tnrI
    tnrOff(spkPhoneCount) = tnrAt
    RNG_Seed TUNE_SEED
    spkWaveStep = 0 : spkGainB = 0
    tnLen = 0
    Do While spkPhoneIdx < spkPhoneCount And tnLen < TUNE_MAX_SAMPLES
        SPK_Advance
        tnBuf(tnLen) = spkSampleOut
        tnLen = tnLen + 1
    Loop
    tnCut = (spkPhoneIdx < spkPhoneCount)
    tnWordN = spkWordCount
    For tnrI = 0 To tnWordN - 1
        tnWordAt(tnrI) = tnrOff(spkWordStart(tnrI))
        tnWordEnd(tnrI) = tnrOff(spkWordEnd(tnrI) + 1)
        If tnWordAt(tnrI) > tnLen Then tnWordAt(tnrI) = tnLen
        If tnWordEnd(tnrI) > tnLen Then tnWordEnd(tnrI) = tnLen
        tnWordTxt(tnrI) = spkWordText$(tnrI)
    Next tnrI
End Sub

' A new line: playhead at the start, stopped, the loop region the whole line, looping off.
Sub TUNE_NewLine (tnlText As String, tnlPreset As Integer)
    TUNE_Render tnlText, tnlPreset
    tnPos = 0 : tnPlaying = 0 : tnLooping = 0 : tnLoopA = 0 : tnLoopB = tnLen
End Sub

Sub TUNE_RenderKeep (trkText As String, trkPreset As Integer)
    Dim trkOldLen As Long
    trkOldLen = tnLen
    TUNE_Render trkText, trkPreset
    If tnPos > tnLen Then tnPos = tnLen
    If tnLoopB = trkOldLen Or tnLoopB > tnLen Then tnLoopB = tnLen
    If tnLoopA > tnLoopB Then tnLoopA = 0
End Sub

Function TUNE_WordAt% (twS As Long)
    Dim twI As Integer
    TUNE_WordAt% = -1
    For twI = 0 To tnWordN - 1
        If twS >= tnWordAt(twI) And twS < tnWordEnd(twI) Then TUNE_WordAt% = twI : Exit Function
    Next twI
End Function

Function TUNE_Next! ()
    TUNE_Next! = 0
    If tnPlaying = 0 Or tnLen = 0 Then Exit Function
    If tnLooping And tnLoopB > tnLoopA And tnPos >= tnLoopB Then tnPos = tnLoopA
    If tnPos >= tnLen Then tnPlaying = 0 : Exit Function
    TUNE_Next! = tnBuf(tnPos)
    tnPos = tnPos + 1
    If tnLooping And tnLoopB > tnLoopA And tnPos >= tnLoopB Then tnPos = tnLoopA
End Function

' Move the playhead tsSecs seconds (negative = back), clamped to the line.
Sub TUNE_Scrub (tsSecs As Single)
    Dim tsNew As Double
    tsNew = tnPos + tsSecs * SAMPLE_RATE
    If tsNew < 0 Then tsNew = 0
    If tsNew > tnLen Then tsNew = tnLen
    tnPos = CLng(tsNew)
End Sub

' [ : the loop starts at the playhead; a loop that would then be empty runs to the end of the line.
Sub TUNE_SetLoopStart
    tnLoopA = tnPos
    If tnLoopB <= tnLoopA Then tnLoopB = tnLen
End Sub

' ] : the loop ends at the playhead; a loop that would then be empty starts at 0.
Sub TUNE_SetLoopEnd
    tnLoopB = tnPos
    If tnLoopA >= tnLoopB Then tnLoopA = 0
End Sub

' The game's spoken paragraphs, in gametext.txt order. Each block is split the way the crawl splits
' it (CRAWL_Layout): runs of lines, colour codes stripped, digits spelled. The palette block is a
' colour chart, not speech.
Sub TUNE_LoadLines
    Dim tlP As Long, tlQ As Long, tlK As String, tlI As Integer
    tnLineN = 0
    tlP = 1
    Do While tlP <= Len(sssBlkStore$)
        tlQ = InStr(tlP, sssBlkStore$, Chr$(3))
        If tlQ = 0 Then Exit Do
        tlK = Mid$(sssBlkStore$, tlP, tlQ - tlP)
        tlP = InStr(tlQ, sssBlkStore$, Chr$(4))
        If tlP = 0 Then tlP = Len(sssBlkStore$) + 1
        tlP = tlP + 1
        If tlK <> "palette" Then
            CRAWL_Layout GTEXT_Get$(tlK)
            For tlI = 0 To crawlParaCount - 1
                If tnLineN < TUNE_MAX_LINES And Len(LTrim$(RTrim$(crawlParaText$(tlI)))) > 0 Then
                    tnLineKey(tnLineN) = tlK + " " + LTrim$(Str$(tlI + 1))
                    tnLineTxt(tnLineN) = LTrim$(RTrim$(crawlParaText$(tlI)))
                    tnLineN = tnLineN + 1
                End If
            Next tlI
        End If
    Loop
End Sub
