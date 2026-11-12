' spk_prosody_test.bas -- the voice's phrase intonation (IN, #236) and its knobs (assets/config/speech.ini)
'
' Pitch is per word: flat inside a word, so it only changes at a word boundary. A sentence ends on
' a fall, a comma or question on a lift, at most accents_per_phrase words of a clause are raised,
' every pitch sits on the step grid inside the tables' range, and no knob changes a duration.
' The shipped speech.ini holds the defaults SPK_Init sets, and an out-of-range value is refused.
'
' Build: ./tools/buildqb tests/spk_prosody_test.bas
' Run:   ./builds/spk_prosody_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/config/speech.ini':'CFGSPEECH'

Sub DBG_Print(spDbgMsg As String) : End Sub

'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/audio/speechcfg.bas'

Dim Shared spPassed As Integer, spFailed As Integer

Sub SP_Assert(spCond As Integer, spName As String)
    If spCond Then
        Print "PASS  " + spName
        spPassed = spPassed + 1
    Else
        Print "FAIL  " + spName
        spFailed = spFailed + 1
    End If
End Sub

' Pitch of each word of the queue, in semitones from SPK_IN_REF (spWord), and whether every word is flat.
Dim Shared spWord(0 To 255) As Single, spWordN As Integer, spFlat As Integer
Sub SP_Words
    Dim spI As Integer, spIn As Integer, spF As Single
    spWordN = 0 : spFlat = -1 : spIn = 0
    For spI = 0 To spkPhoneCount - 1
        If spkPhones(spI) = SPK_SIL Then
            spIn = 0
        Else
            spF = 12 * Log(spkPF0(spI) / SPK_IN_REF) / Log(2)
            If spIn = 0 Then
                spWord(spWordN) = spF : spWordN = spWordN + 1 : spIn = -1
            ElseIf Abs(spF - spWord(spWordN - 1)) > 0.001 Then
                spFlat = 0
            End If
        End If
    Next spI
End Sub

Function SP_OnGrid% ()
    Dim spI As Integer, spF As Single, spR As Single
    SP_OnGrid% = -1
    For spI = 0 To spkPhoneCount - 1
        spF = 12 * Log(spkPF0(spI) / SPK_IN_REF) / Log(2)
        spR = spF / spkPk(SPK_PK_STEP)
        If spF < SPK_IN_LO - 0.001 Or spF > SPK_IN_HI + 0.001 Then SP_OnGrid% = 0
        If spkPhones(spI) <> SPK_SIL And Abs(spR - Int(spR + 0.5)) > 0.001 Then SP_OnGrid% = 0
    Next spI
End Function

Print "=== spk_prosody_test ==="
Print ""

SPK_Init
Dim spI As Integer, spSame As Integer, spOk As Integer, spRises As Integer, spQ1 As Long, spQ2 As Long

Print "--- speech.ini ---"
spOk = SPK_ProsodyLoad%(_EMBEDDED$("CFGSPEECH"))
SP_Assert spOk, "the shipped speech.ini loads (" + spkCfgErr + ")"
spSame = -1
For spI = 0 To SPK_PK_N - 1
    If spkPk(spI) <> spkPkDef(spI) Then spSame = 0 : Print "      "; spkPkKey(spI); " ini"; spkPk(spI); " default"; spkPkDef(spI)
Next spI
SP_Assert spSame, "it holds the defaults SPK_Init sets (tests and the game hear the same voice)"
SP_Assert SPK_ProsodyLoad%("final_fall_semitones=99") = 0 And spkPk(SPK_PK_FALL) = spkPkDef(SPK_PK_FALL), "an out-of-range value is refused and the knobs are kept"
SP_Assert SPK_ProsodyLoad%("accent_semitones=3") And spkPk(SPK_PK_ACC) = 3 And spkPk(SPK_PK_FALL) = spkPkDef(SPK_PK_FALL), "a key overrides its knob, a missing key is its default"
spOk = SPK_ProsodyLoad%(_EMBEDDED$("CFGSPEECH"))

Print "--- pitch per word ---"
SPK_Say "Shields are failing. The fleet is closing."
SP_Words
SP_Assert spFlat, "pitch is flat inside every word"
SP_Assert SP_OnGrid%, "every pitch is on the step grid, inside the tables' range"
SP_Assert spWord(2) < spWord(1), "the last word before a period falls (" + Str$(spWord(2)) + " after" + Str$(spWord(1)) + ")"
SP_Assert spWord(6) < spWord(5), "and in the next sentence (" + Str$(spWord(6)) + " after" + Str$(spWord(5)) + ")"
SP_Assert spWord(3) > spWord(2), "a new sentence starts above the fall"
SP_Assert spWord(0) >= spWord(1), "one accent per phrase: the accented first word is not below the next"

SPK_Say "Shields are holding, but the cruiser is closing."
SP_Words
SP_Assert spWord(2) > spWord(1), "the last word before a comma lifts (" + Str$(spWord(2)) + " after" + Str$(spWord(1)) + ")"
spRises = 0
For spI = 4 To spWordN - 2
    If spWord(spI) > spWord(spI - 1) + 0.001 Then spRises = spRises + 1
Next spI
SP_Assert spRises <= spkPk(SPK_PK_NACC), "after the comma at most accents_per_phrase words step up (" + Str$(spRises) + ")"
SP_Assert spWord(spWordN - 1) < spWord(spWordN - 2), "the sentence still ends on a fall"

SPK_Say "Shields failing?"
SP_Words
SP_Assert spWord(1) > spWord(0) Or spWord(1) > SPK_IN_START, "a question ends on a lift (" + Str$(spWord(1)) + ")"

Print "--- knobs ---"
SPK_Say "All systems critical. Operator override."
SPK_SetPreset 2
spQ1 = SPK_QueueSamples&
SPK_PkSet SPK_PK_SPREAD, 1
SP_Words
SP_Assert spFlat = 0, "stress_pitch_spread above 0 puts the old stress pitches back inside words"
SPK_PkSet SPK_PK_SPREAD, 0
SPK_PkSet SPK_PK_STEP, 2
SP_Words
SP_Assert SP_OnGrid%, "step_semitones 2: every pitch is a multiple of 2 semitones"
SPK_PkSet SPK_PK_FALL, 8 : SPK_PkSet SPK_PK_ACC, 6 : SPK_PkSet SPK_PK_LOUD, 6 : SPK_PkSet SPK_PK_LIQ, 3
spQ2 = SPK_QueueSamples&
SP_Assert spQ1 = spQ2, "no knob changes the line's length (" + Str$(spQ1) + " =" + Str$(spQ2) + ")"
SPK_PkSet SPK_PK_STEP, 99
SP_Assert spkPk(SPK_PK_STEP) = spkPkMax(SPK_PK_STEP), "a nudge is clamped to the knob's range"

Print ""
Print "=== " + LTrim$(Str$(spPassed + spFailed)) + " tests: " + LTrim$(Str$(spPassed)) + " passed, " + LTrim$(Str$(spFailed)) + " failed ==="
If spFailed > 0 Then System 1 Else System 0
