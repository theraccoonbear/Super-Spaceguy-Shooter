' musrender.bas -- render music.mus cues offline to WAV files (22.05 kHz mono 16-bit), for
' auditioning without the game, and print each cue's peak and RMS.
'
' Build: tools/buildqb tools/musrender.bas      (or in the container: tools/dev shell ./tools/buildqb tools/musrender.bas)
' Run:   builds/musrender <cue|all> <seconds> <outdir>
'        e.g. builds/musrender all 30 builds/music  ->  builds/music/<cue>.wav for every cue
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
Dim mrI As Integer, mrDone As Integer
mrArgs = LTrim$(RTrim$(Command$))
mrP = InStr(mrArgs, " ")
If mrP = 0 Then Print "usage: musrender <cue|all> <seconds> <outdir>" : System 1
mrCue = Left$(mrArgs, mrP - 1) : mrArgs = LTrim$(Mid$(mrArgs, mrP + 1))
mrP = InStr(mrArgs, " ")
If mrP = 0 Then Print "usage: musrender <cue|all> <seconds> <outdir>" : System 1
mrSecs = Val(Left$(mrArgs, mrP - 1)) : mrDir = LTrim$(Mid$(mrArgs, mrP + 1))
If mrSecs <= 0 Or mrSecs > 120 Then Print "seconds must be 1..120" : System 1
If Left$(mrDir, 1) <> "/" And Mid$(mrDir, 2, 1) <> ":" Then mrDir = _StartDir$ + "/" + mrDir
If Right$(mrDir, 1) = "/" Then mrDir = Left$(mrDir, Len(mrDir) - 1)
On Error GoTo mrFail
If _DirExists(mrDir) = 0 Then MkDir mrDir

SND_Init
For mrI = 0 To musCueCnt - 1
    If mrCue = "all" Or mrCue = musCueN$(mrI) Then
        MR_Render musCueN$(mrI), mrSecs, mrDir + "/" + musCueN$(mrI) + ".wav"
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
Sub MR_Render (mrRCue As String, mrRSecs As Single, mrRPath As String)
    Dim mrRN As Long, mrRK As Long, mrRA As Single, mrRB As Single, mrRPrev As Single
    Dim mrRY As Single, mrRPk As Single, mrRSum As Double, mrRFade As Long, mrRV As Long
    Dim mrRBuf As String, mrRF As Integer
    mrRN = CLng(mrRSecs * SAMPLE_RATE / 2)
    mrRFade = SAMPLE_RATE / 20
    MUS_SetCue mrRCue
    mrRF = FreeFile
    If _FileExists(mrRPath) Then Kill mrRPath
    Open mrRPath For Binary As #mrRF
    mrRBuf = MR_WavHeader$(mrRN)
    Put #mrRF, , mrRBuf : mrRBuf = ""
    For mrRK = 0 To mrRN - 1
        mrRA = MUS_MusicSample!
        mrRB = MUS_MusicSample!
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
    Print mrRCue + String$(12 - Len(mrRCue), " ") + " peak" + Str$(mrRPk) + "  rms" + Str$(CSng(Sqr(mrRSum / (2 * mrRN)))) + "  -> " + mrRPath
End Sub

Function MR_WavHeader$ (mrHN As Long)
    Dim mrHRate As Long : mrHRate = SAMPLE_RATE / 2
    MR_WavHeader$ = "RIFF" + MKL$(36 + mrHN * 2) + "WAVE" + "fmt " + MKL$(16) + MKI$(1) + MKI$(1) + MKL$(mrHRate) + MKL$(mrHRate * 2) + MKI$(2) + MKI$(16) + "data" + MKL$(mrHN * 2)
End Function
