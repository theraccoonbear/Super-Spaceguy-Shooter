' musrender.bas -- render music.mus cues offline to WAV files (22.05 kHz mono 16-bit), for
' auditioning without the game, and print each cue's peak and RMS.
'
' Build: tools/buildqb tools/musrender.bas      (or in the container: tools/dev shell ./tools/buildqb tools/musrender.bas)
' Run:   builds/musrender <cue|all> <seconds> <outdir>
'        e.g. builds/musrender all 30 builds/music  ->  builds/music/<cue>.wav for every cue
'        builds/musrender seq silence:4,crawl:8,emperor:6 builds/music  ->  builds/music/sequence.wav:
'        cues set one after another the way the game sets them (silence = no cue yet)
Option _Explicit
$CONSOLE:ONLY
$EMBED:'assets/music.mus':'MUSICDATA'

Const SAMPLE_RATE = 44100
Const SND_UI_MOVE   = 1
Const SND_UI_DENY   = 2
Const SND_UI_PUP    = 3
Const SND_UI_TYPE   = 4
Const SND_UI_DEL    = 5
Const SND_UI_COLOR  = 6
Const SND_UI_SPIN   = 7
Const SND_UI_SPIN_N = 39

Dim Shared volMusic As Single, volSfx As Single, volSpeech As Single, spkSampleOut As Single
Sub SPK_Advance () : End Sub

'$INCLUDE:'../src/sys/rng.bas'
'$INCLUDE:'../src/audio/snd.bas'
'$INCLUDE:'../src/audio/music.bas'

Dim mrArgs As String, mrCue As String, mrSecs As Single, mrDir As String, mrP As Integer
Dim mrI As Integer, mrDone As Integer, mrList As String
Dim Shared mrSegCue(0 To 31) As String, mrSegAt(0 To 31) As Long, mrSegN As Integer, mrSegI As Integer, mrPos As Long
mrArgs = LTrim$(RTrim$(Command$))
mrP = InStr(mrArgs, " ")
If mrP = 0 Then Print "usage: musrender <cue|all> <seconds> <outdir>" : System 1
mrCue = Left$(mrArgs, mrP - 1) : mrArgs = LTrim$(Mid$(mrArgs, mrP + 1))
mrP = InStr(mrArgs, " ")
If mrP = 0 Then Print "usage: musrender <cue|all> <seconds> <outdir>" : System 1
mrList = Left$(mrArgs, mrP - 1) : mrSecs = Val(mrList) : mrDir = LTrim$(Mid$(mrArgs, mrP + 1))
If mrCue <> "seq" And (mrSecs <= 0 Or mrSecs > 120) Then Print "seconds must be 1..120" : System 1
If Left$(mrDir, 1) <> "/" And Mid$(mrDir, 2, 1) <> ":" Then mrDir = _StartDir$ + "/" + mrDir
If Right$(mrDir, 1) = "/" Then mrDir = Left$(mrDir, Len(mrDir) - 1)
On Error GoTo mrFail
If _DirExists(mrDir) = 0 Then MkDir mrDir

SND_Init
If mrCue = "seq" Then
    MR_Render mrList, mrDir + "/sequence.wav"
    System 0
End If
For mrI = 0 To musCueCnt - 1
    If mrCue = "all" Or mrCue = musCueN$(mrI) Then
        MR_Render musCueN$(mrI) + ":" + LTrim$(Str$(mrSecs)), mrDir + "/" + musCueN$(mrI) + ".wav"
        mrDone = mrDone + 1
    End If
Next mrI
If mrDone = 0 Then Print "no cue named " + mrCue : System 1
System 0
mrFail:
Print "musrender: error" + Str$(Err) + " on line" + Str$(_ErrorLine)
System 1

' 44.1 kHz from the real mixer, (1 2 1)/4 low-passed and decimated to 22.05 kHz, the last
' 50 ms faded so the file doesn't end on a click.
Sub MR_Render (mrRList As String, mrRPath As String)
    Dim mrRN As Long, mrRK As Long, mrRA As Single, mrRB As Single, mrRPrev As Single
    Dim mrRY As Single, mrRPk As Single, mrRSum As Double, mrRFade As Long, mrRV As Long
    Dim mrRBuf As String, mrRF As Integer, mrRRest As String, mrRItem As String, mrRP As Integer, mrRAt As Double
    ' "cue:secs,cue:secs,..." -> segment start samples
    mrSegN = 0 : mrRAt = 0 : mrRRest = mrRList + ","
    Do While Len(mrRRest) > 0 And mrSegN < 32
        mrRP = InStr(mrRRest, ",")
        mrRItem = Left$(mrRRest, mrRP - 1) : mrRRest = Mid$(mrRRest, mrRP + 1)
        If InStr(mrRItem, ":") > 0 Then
            mrSegCue(mrSegN) = Left$(mrRItem, InStr(mrRItem, ":") - 1)
            mrSegAt(mrSegN) = CLng(mrRAt * SAMPLE_RATE)
            mrRAt = mrRAt + Val(Mid$(mrRItem, InStr(mrRItem, ":") + 1))
            mrSegN = mrSegN + 1
        End If
    Loop
    If mrSegN = 0 Or mrRAt <= 0 Or mrRAt > 120 Then Print "bad list (cue:secs,..., 120 s at most): " + mrRList : System 1
    mrRN = CLng(mrRAt * SAMPLE_RATE / 2)
    mrRFade = SAMPLE_RATE / 20
    MUS_Reset
    mrSegI = 0 : mrPos = 0
    mrRF = FreeFile
    If _FileExists(mrRPath) Then Kill mrRPath
    Open mrRPath For Binary As #mrRF
    mrRBuf = MR_WavHeader$(mrRN)
    Put #mrRF, , mrRBuf : mrRBuf = ""
    For mrRK = 0 To mrRN - 1
        mrRA = MR_Next!
        mrRB = MR_Next!
        mrRY = (mrRPrev + 2 * mrRA + mrRB) / 4
        mrRPrev = mrRB
        If Abs(mrRA) > mrRPk Then mrRPk = Abs(mrRA)
        If Abs(mrRB) > mrRPk Then mrRPk = Abs(mrRB)
        mrRSum = mrRSum + CDbl(mrRA) * mrRA + CDbl(mrRB) * mrRB
        If mrRK > mrRN - mrRFade Then mrRY = mrRY * (mrRN - mrRK) / mrRFade
        mrRV = CLng(mrRY * 32767)
        If mrRV > 32767 Then mrRV = 32767
        If mrRV < -32767 Then mrRV = -32767
        mrRBuf = mrRBuf + MKI$(mrRV)
        If Len(mrRBuf) >= 8192 Then Put #mrRF, , mrRBuf : mrRBuf = ""
    Next mrRK
    If Len(mrRBuf) > 0 Then Put #mrRF, , mrRBuf
    Close #mrRF
    Print Left$(mrRList, 40) + Space$(12 - Len(Left$(mrRList, 12))) + " peak" + Str$(mrRPk) + "  rms" + Str$(CSng(Sqr(mrRSum / (2 * mrRN)))) + "  -> " + mrRPath
End Sub

' The next mixer sample, setting each segment's cue when its start time comes.
Function MR_Next!
    Do While mrSegI < mrSegN
        If mrSegAt(mrSegI) > mrPos Then Exit Do
        If mrSegCue(mrSegI) <> "silence" Then MUS_SetCue mrSegCue(mrSegI)
        mrSegI = mrSegI + 1
    Loop
    mrPos = mrPos + 1
    MR_Next! = MUS_MusicSample!
End Function

Function MR_WavHeader$ (mrHN As Long)
    Dim mrHRate As Long : mrHRate = SAMPLE_RATE / 2
    MR_WavHeader$ = "RIFF" + MKL$(36 + mrHN * 2) + "WAVE" + "fmt " + MKL$(16) + MKI$(1) + MKI$(1) + MKL$(mrHRate) + MKL$(mrHRate * 2) + MKI$(2) + MKI$(16) + "data" + MKL$(mrHN * 2)
End Function
