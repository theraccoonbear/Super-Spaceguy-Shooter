' bt_repro.bas -- minimal _SNDRAW repro for Bluetooth HFP activation bug
' Plays a continuous sad melody using only _SNDRAW (no _SNDOPEN, no capture).
' On Linux with PipeWire + Bluetooth headset: miniaudio's init enumerates capture
' devices, activates HFP alongside A2DP, and the BT link eventually stalls.
'
' Expected: melody plays indefinitely on BT headset.
' Actual:   audio cuts out after 1-4 minutes; BT link kills itself ~4 min later.
'
' Repro environment:
'   QB64-PE v4.x, Linux (Bazzite/Fedora), PipeWire + WirePlumber, BT headset (Sony).
'
' To observe:
'   journalctl -f | grep -iE 'avdtp|hfp|missing completion|link tx timeout|killing stalled'

Const SR       = 44100
Const BUFTGT   = 0.10   ' 100ms buffer target (same as game)

' Descending A-minor melody: Am pentatonic, two octaves, very slow
' A4 E4 D4 C4 A3 G3 E3 D3 -- loops
Dim mNotes(7) As Single
mNotes(0) = 440.00   ' A4
mNotes(1) = 329.63   ' E4
mNotes(2) = 293.66   ' D4
mNotes(3) = 261.63   ' C4
mNotes(4) = 220.00   ' A3
mNotes(5) = 196.00   ' G3
mNotes(6) = 164.81   ' E3
mNotes(7) = 146.83   ' D3

Dim mPhase    As Single
Dim mPhase2   As Single   ' sub-octave for body
Dim mFreq     As Single
Dim mNoteIdx  As Integer
Dim mNoteDur  As Long     ' samples per note
Dim mNotePos  As Long     ' position within current note
Const NOTELEN = SR * 0.65 ' ~650ms per note
Const FADELEN = 441       ' 10ms fade in/out

mFreq    = mNotes(0)
mNoteDur = NOTELEN
mNotePos = 0
mNoteIdx = 0

Screen _NewImage(320, 40, 32)
_Title "BT _SNDRAW repro -- ESC to quit"
Print "Playing sad melody via _SNDRAW only. Watch journalctl for BT events."

Do
    ' fill up to buffer target
    Dim mFill As Integer
    mFill = Int((BUFTGT - _SndRawLen) * SR)
    If mFill > 0 Then
        Dim mK As Integer
        For mK = 1 To mFill
            ' advance note position; switch note when done
            mNotePos = mNotePos + 1
            If mNotePos > mNoteDur Then
                mNoteIdx = (mNoteIdx + 1) Mod 8
                mFreq    = mNotes(mNoteIdx)
                mNotePos = 1
            End If

            ' amplitude envelope: 10ms fade in/out, silence last 15%
            Dim mEnv As Single
            Dim mSus As Long : mSus = CLng(mNoteDur * 0.85)
            If mNotePos < FADELEN Then
                mEnv = mNotePos / FADELEN
            ElseIf mNotePos > mSus Then
                mEnv = 0.0
            Else
                mEnv = 1.0
            End If

            ' two sine voices: fundamental + soft sub-octave
            mPhase  = mPhase  + 6.2832 * mFreq       / SR
            mPhase2 = mPhase2 + 6.2832 * (mFreq/2.0) / SR
            If mPhase  > 6.2832 Then mPhase  = mPhase  - 6.2832
            If mPhase2 > 6.2832 Then mPhase2 = mPhase2 - 6.2832

            Dim mSample As Single
            mSample = (Sin(mPhase) * 0.65 + Sin(mPhase2) * 0.25) * mEnv * 0.30

            _SndRaw mSample
        Next mK
    End If

    _Display
Loop Until _KeyDown(27)
