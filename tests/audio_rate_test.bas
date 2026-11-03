' audio_rate_test.bas -- the synthesized audio against the stream the game produced before it followed
' the device rate (#400).
'
' Every sound effect buffer, the UI voice, the engine hum, the narration blip, two fixed speech
' lines and four fixed music runs (cue switches, crossfades, drum retriggers) are rendered through
' the real modules from a fixed seed and reduced to a length and an FNV-1a hash of the raw Single
' bits. The golden table below was captured from the code before #400 and must be reproduced bit
' for bit.
'
' Run it with the argument "dump" to print the table in the DATA format instead of checking it.
'
' Build: ./tools/buildqb tests/audio_rate_test.bas
' Run:   ./builds/audio_rate_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/music.mus':'MUSICDATA'
$EMBED:'assets/sequence.txt':'SEQTXT'
$EMBED:'assets/speech_dict.txt':'SPEECHDICT'

Const SAMPLE_RATE = 44100
Const SND_UI_MOVE   = 1
Const SND_UI_DENY   = 2
Const SND_UI_PUP    = 3
Const SND_UI_TYPE   = 4
Const SND_UI_DEL    = 5
Const SND_UI_COLOR  = 6
Const SND_UI_SPIN   = 7
Const SND_UI_SPIN_N = 39

Dim Shared volMusic As Single, volSfx As Single, volSpeech As Single
Sub DBG_Print (arMsg As String) : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/speech.bas'
'$INCLUDE:'../src/audio/snd.bas'
'$INCLUDE:'../src/audio/music.bas'

Const AR_MAX = 40
Dim Shared arName(0 To AR_MAX - 1) As String
Dim Shared arLen(0 To AR_MAX - 1) As Long
Dim Shared arHash(0 To AR_MAX - 1) As _Integer64
Dim Shared arN As Integer
Dim Shared arHv As _Integer64, arCnt As Long

Sub AR_HashBegin
    arHv = 2166136261
    arCnt = 0
End Sub

Sub AR_HashAdd (arV As Single)
    Dim arB As String, arI As Integer
    arB = MKS$(arV)
    For arI = 1 To 4
        arHv = ((arHv Xor Asc(Mid$(arB, arI, 1))) * 16777619) And 4294967295
    Next arI
    arCnt = arCnt + 1
End Sub

Sub AR_Record (arNm As String)
    arName(arN) = arNm : arLen(arN) = arCnt : arHash(arN) = arHv
    arN = arN + 1
End Sub

' Samples to render for arC authored samples; the same count in every run until the device rate is followed.
Function AR_Count& (arC As Long)
    AR_Count& = arC
End Function

Sub AR_Run
    Dim arK As Long, arI As Integer

    arN = 0
    RNG_Seed 20260401
    SND_Init

    AR_HashBegin : For arK = 0 To SND_SHOOT_LEN - 1 : AR_HashAdd sndShoot(arK) : Next arK : AR_Record "shoot"
    AR_HashBegin : For arK = 0 To SND_BOOM_LEN - 1 : AR_HashAdd sndBoom(arK) : Next arK : AR_Record "boom"
    AR_HashBegin : For arK = 0 To SND_HIT_LEN - 1 : AR_HashAdd sndHit(arK) : Next arK : AR_Record "hit"
    AR_HashBegin : For arK = 0 To SND_PUP_LEN - 1 : AR_HashAdd sndPup(arK) : Next arK : AR_Record "pup"
    AR_HashBegin : For arK = 0 To SND_WHOOSH_LEN - 1 : AR_HashAdd sndWhoosh(arK) : Next arK : AR_Record "whoosh"
    AR_HashBegin : For arK = 0 To SND_WHOOSH_LEN - 1 : AR_HashAdd sndWhooshMd(arK) : Next arK : AR_Record "whooshMd"
    AR_HashBegin : For arK = 0 To SND_WHOOSH_LEN - 1 : AR_HashAdd sndWhooshLg(arK) : Next arK : AR_Record "whooshLg"
    AR_HashBegin : For arK = 0 To SND_KICK_LEN - 1 : AR_HashAdd sndKick(arK) : Next arK : AR_Record "kick"
    AR_HashBegin : For arK = 0 To SND_SNARE_LEN - 1 : AR_HashAdd sndSnare(arK) : Next arK : AR_Record "snare"
    AR_HashBegin : For arK = 0 To SND_HIHAT_LEN - 1 : AR_HashAdd sndHihat(arK) : Next arK : AR_Record "hihat"
    AR_HashBegin : For arK = 0 To SND_TOM_LEN - 1 : AR_HashAdd sndTom(arK) : Next arK : AR_Record "tom"
    AR_HashBegin : For arK = 0 To SND_CRASH_LEN - 1 : AR_HashAdd sndCrash(arK) : Next arK : AR_Record "crash"
    AR_HashBegin : For arK = 0 To SND_OHAT_LEN - 1 : AR_HashAdd sndOHat(arK) : Next arK : AR_Record "ohat"
    AR_HashBegin : For arK = 0 To SND_DEATH_LEN - 1 : AR_HashAdd sndDeath(arK) : Next arK : AR_Record "death"
    AR_HashBegin : For arK = 0 To SND_UIMOVE_LEN - 1 : AR_HashAdd sndUiMove(arK) : Next arK : AR_Record "uiMove"
    AR_HashBegin : For arK = 0 To SND_UIDENY_LEN - 1 : AR_HashAdd sndUiDeny(arK) : Next arK : AR_Record "uiDeny"
    AR_HashBegin : For arK = 0 To SND_UITYPE_LEN - 1 : AR_HashAdd sndUiType(arK) : Next arK : AR_Record "uiType"
    AR_HashBegin : For arK = 0 To SND_UIDEL_LEN - 1 : AR_HashAdd sndUiDel(arK) : Next arK : AR_Record "uiDel"
    AR_HashBegin : For arK = 0 To SND_UICOL_LEN - 1 : AR_HashAdd sndUiCol(arK) : Next arK : AR_Record "uiCol"
    AR_HashBegin
    For arI = 0 To SND_UI_SPIN_N - 1
        For arK = 0 To SND_UISPIN_LEN - 1 : AR_HashAdd sndUiSpin(arI, arK) : Next arK
    Next arI
    AR_Record "uiSpin"

    ' the UI voice: a chime, retriggered mid-sound by a deny buzz (the old one fades out)
    AR_HashBegin
    SND_UiPlay SND_UI_PUP
    For arK = 0 To AR_Count&(1500) - 1 : AR_HashAdd SND_UiNext! : Next arK
    SND_UiPlay SND_UI_DENY
    For arK = 0 To AR_Count&(7000) - 1 : AR_HashAdd SND_UiNext! : Next arK
    AR_Record "uiVoice"

    ' engine hum phase, at the idle and the manoeuvre pitch
    AR_HashBegin
    sndEnginePhase = 0
    sndEngineFreq = 75.0
    For arK = 0 To AR_Count&(3000) - 1 : SND_EngineStep : AR_HashAdd sndEnginePhase : Next arK
    sndEngineFreq = 150.0
    For arK = 0 To AR_Count&(3000) - 1 : SND_EngineStep : AR_HashAdd sndEnginePhase : Next arK
    AR_Record "engine"

    ' narration blips: the length and plosive draws come from RNG_AUDIO
    AR_HashBegin
    RNG_Seed 777
    For arI = 1 To 6
        SND_Blip 180.0 + 45.0 * arI
        Do While sndBlipTimer > 0 : AR_HashAdd SND_BlipNext! : Loop
    Next arI
    AR_Record "blip"

    ' music: cue runs through the real mixer function
    MUS_Reset
    AR_HashBegin
    MUS_SetCue "title"
    For arK = 0 To AR_Count&(120000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musTitle"
    AR_HashBegin
    MUS_SetCue "game"
    For arK = 0 To AR_Count&(120000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musGame"
    AR_HashBegin
    MUS_SetCue "boss3"
    For arK = 0 To AR_Count&(60000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musBoss3"
    ' a switch while the previous crossfade is still running, then another
    AR_HashBegin
    MUS_SetCue "emperor"
    For arK = 0 To AR_Count&(1000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    MUS_SetCue "planet"
    For arK = 0 To AR_Count&(500) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    MUS_SetCue "crawl"
    For arK = 0 To AR_Count&(100000) - 1 : AR_HashAdd MUS_MusicSample! : Next arK
    AR_Record "musSwitch"

    ' speech: two fixed lines, one at natural speed and one at the FAST narration preset
    RNG_Seed 4242
    SPK_Init
    AR_HashBegin
    SPK_Say "Attention all pilots. The fleet departs at dawn."
    Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : AR_HashAdd spkSampleOut : Loop
    AR_Record "speechNatural"
    AR_HashBegin
    SPK_Say "Shields are holding, but the cruiser is closing fast."
    SPK_SetPreset 3
    Do While spkPhoneIdx < spkPhoneCount : SPK_Advance : AR_HashAdd spkSampleOut : Loop
    AR_Record "speechFast"
End Sub

Dim Shared arPassed As Integer, arFailed As Integer

Sub AR_Assert (arCond As Integer, arTestName As String)
    If arCond Then
        Print "PASS  " + arTestName
        arPassed = arPassed + 1
    Else
        Print "FAIL  " + arTestName
        arFailed = arFailed + 1
    End If
End Sub

Print "=== audio_rate_test ==="

AR_Run

If Command$ = "dump" Then
    Dim arD As Integer
    For arD = 0 To arN - 1
        Print "Data " + Chr$(34) + arName(arD) + Chr$(34) + "," + Str$(arLen(arD)) + "," + Str$(arHash(arD))
    Next arD
    System 0
End If

Dim arG As Integer, arGn As String, arGl As Long, arGh As _Integer64
Restore GoldenTable
For arG = 0 To arN - 1
    Read arGn, arGl, arGh
    AR_Assert arName(arG) = arGn, "table order: " + arGn
    AR_Assert arLen(arG) = arGl, arGn + ": length " + Str$(arLen(arG)) + " = golden " + Str$(arGl)
    AR_Assert arHash(arG) = arGh, arGn + ": samples are bit-identical to the golden"
Next arG

Print
Print "audio_rate_test:"; arPassed; "passed,"; arFailed; "failed"
If arFailed > 0 Then System 1
System 0

GoldenTable:
    Data "shoot", 2205, 4030601151
    Data "boom", 11025, 2693777716
    Data "hit", 8820, 2947879989
    Data "pup", 4410, 3434124993
    Data "whoosh", 22050, 3099864726
    Data "whooshMd", 22050, 2077622330
    Data "whooshLg", 22050, 3386246824
    Data "kick", 11025, 2087685240
    Data "snare", 4410, 3500971108
    Data "hihat", 2205, 125681085
    Data "tom", 19845, 3762369430
    Data "crash", 30870, 190447902
    Data "ohat", 11025, 1783914197
    Data "death", 32760, 19814737
    Data "uiMove", 1764, 4152414332
    Data "uiDeny", 5292, 1048475147
    Data "uiType", 1102, 191015633
    Data "uiDel", 3087, 3027762150
    Data "uiCol", 4851, 3257485782
    Data "uiSpin", 51597, 2901996156
    Data "uiVoice", 8500, 2494549898
    Data "engine", 6000, 1171652785
    Data "blip", 16286, 145993343
    Data "musTitle", 120000, 3701441537
    Data "musGame", 120000, 745643780
    Data "musBoss3", 60000, 587591859
    Data "musSwitch", 101500, 3518089085
    Data "speechNatural", 571752, 1302666785
    Data "speechFast", 170178, 771496315
