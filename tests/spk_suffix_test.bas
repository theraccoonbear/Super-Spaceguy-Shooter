' spk_suffix_test.bas -- the plural and possessive -S that SPK_Say adds to a dictionary stem (#236)
'
' A word missing from the dictionary whose stem (without the S) is in it, and a word-final 's
' possessive, get the suffix by the stem's last phoneme: IH0 Z after a sibilant (S Z SH ZH CH JH),
' S after another voiceless consonant (P T K F TH HH), Z otherwise. A word found directly keeps its
' own pronunciation, and an s' possessive is the plain plural. Runs against the real baked dictionary.
'
' Build: ./tools/buildqb tests/spk_suffix_test.bas
' Run:   ./builds/spk_suffix_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
'$INCLUDE:'../src/sys/failfast.bi'

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/sys/audiorate.bas'
'$INCLUDE:'../src/engine3d.bi'
'$INCLUDE:'../src/sys/dims.bas'

$EMBED:'assets/speech_dict.txt':'SPEECHDICT'

Sub DBG_Print(sxDbgMsg As String) : End Sub

'$INCLUDE:'../src/audio/speech.bas'

Dim Shared sxPassed As Integer, sxFailed As Integer

Sub SX_Assert(sxCond As Integer, sxName As String)
    If sxCond Then
        Print "PASS  " + sxName
        sxPassed = sxPassed + 1
    Else
        Print "FAIL  " + sxName
        sxFailed = sxFailed + 1
    End If
End Sub

' The queued phonemes as ARPAbet tokens (vowels with their stress digit), silences left out.
Function SX_Phones$()
    Dim sxI As Integer, sxN As Integer, sxP As Integer, sxQ As Integer, sxT As String, sxOut As String
    For sxI = 0 To spkPhoneCount - 1
        If spkPhones(sxI) <> SPK_SIL Then
            sxN = 0 : sxP = 1
            Do
                sxQ = InStr(sxP, SPK_NAMES, " ")
                If sxQ = 0 Then sxQ = Len(SPK_NAMES) + 1
                If sxN = spkPhones(sxI) Then sxT = Mid$(SPK_NAMES, sxP, sxQ - sxP) : Exit Do
                sxN = sxN + 1 : sxP = sxQ + 1
            Loop
            If spkPhones(sxI) <= SPK_UW Then sxT = sxT + LTrim$(Str$(spkStress(sxI)))
            If Len(sxOut) > 0 Then sxOut = sxOut + " "
            sxOut = sxOut + sxT
        End If
    Next sxI
    SX_Phones$ = sxOut
End Function

Sub SX_Check(sxText As String, sxWant As String, sxWhat As String)
    Dim sxGot As String
    SPK_Say sxText
    sxGot = SX_Phones$
    SX_Assert sxGot = sxWant, sxWhat + ": " + sxText + " -> " + sxGot + "  (want " + sxWant + ")"
End Sub

Print "=== spk_suffix_test ==="
Print ""

SPK_Init
Dim sxIdx As Integer

Print "--- the stems these cases rely on are (or are not) in the dictionary ---"
SPK_DictFind "EMPERORS", sxIdx : SX_Assert sxIdx < 0, "EMPERORS is not in the dictionary (plural fallback)"
SPK_DictFind "LINKS", sxIdx : SX_Assert sxIdx < 0, "LINKS is not in the dictionary (plural fallback)"
SPK_DictFind "DRONES", sxIdx : SX_Assert sxIdx >= 0, "DRONES is in the dictionary"
SPK_DictFind "PILOTS", sxIdx : SX_Assert sxIdx >= 0, "PILOTS is in the dictionary"

Print "--- plural fallback ---"
SX_Check "EMPERORS", "EH1 M P ER0 ER0 Z", "voiced stem: Z"
SX_Check "LINKS", "L IH1 NG K S", "voiceless stem: S"

Print "--- possessive 's ---"
SX_Check "BOSS'S", "B AA1 S IH0 Z", "sibilant stem ending in s: IH0 Z"
SX_Check "ASH'S", "AE1 SH IH0 Z", "sibilant SH: IH0 Z"
SX_Check "SPACE'S", "S P EY1 S IH0 Z", "sibilant S: IH0 Z"
SX_Check "GROTUK'S", "G R OW0 T AO1 K S", "voiceless stop: S"
SX_Check "EARTH'S", "ER1 TH S", "voiceless fricative: S"
SX_Check "EMPEROR'S", "EH1 M P ER0 ER0 Z", "voiced consonant: Z"
SX_Check "GALAXY'S", "G AE1 L AH0 K S IY0 Z", "vowel: Z"
SX_Check "the empire's fleet", "DH AH0 EH1 M P AY0 ER0 Z F L IY1 T", "mid-sentence, lower case"

Print "--- found directly, or s' possessive: no second S ---"
SX_Check "DRONES", "D R OW1 N Z", "dictionary plural"
SX_Check "SHIPS", "SH IH1 P S", "dictionary plural"
SX_Check "PILOTS'", "P AY1 L AH0 T S", "s' possessive of a dictionary plural"

Print "--- word records and timing ---"
SPK_Say "Grotuk's fleet."
SX_Assert spkWordCount = 2, "two words recorded (" + LTrim$(Str$(spkWordCount)) + ")"
SX_Assert spkWordText$(0) = "GROTUK" And spkPhones(spkWordEnd(0)) = SPK_SIL And spkPhones(spkWordEnd(0) - 1) = SPK_S, "the possessive S belongs to the first word, which still ends on its silence"
SX_Assert spkWordStart(1) = spkWordEnd(0) + 1, "the next word starts right after it"
Dim sxQ As Long, sxN As Long
SPK_SetPreset 2
sxQ = SPK_QueueSamples&
Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : sxN = sxN + 1 : Loop
SX_Assert sxQ = sxN, "SPK_QueueSamples& (" + LTrim$(Str$(sxQ)) + ") = samples synthesized (" + LTrim$(Str$(sxN)) + ")"

Print ""
Print "=== " + LTrim$(Str$(sxPassed + sxFailed)) + " tests: " + LTrim$(Str$(sxPassed)) + " passed, " + LTrim$(Str$(sxFailed)) + " failed ==="
If sxFailed > 0 Then System 1 Else System 0
