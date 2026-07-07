' tools/musicplayer.bas -- standalone preview tool for music.mus cues
'
' Build: from repo root — <qb64pe-dir>/qb64pe -x tools/musicplayer.bas -o builds/musicplayer
'
' Controls: up/down to select, space/enter to play, ESC to quit
$EMBED:'assets/music.mus':'MUSICDATA'

Const SAMPLE_RATE = 44100

Dim Shared volMusic  As Single : volMusic  = 1.0
Dim Shared volSfx    As Single : volSfx    = 0.9
Dim Shared volSpeech As Single : volSpeech = 0.0
Dim Shared spkSampleOut As Single

'$INCLUDE:'../snd.bas'
'$INCLUDE:'../music.bas'

' ---- main ----

Dim mpSel      As Integer : mpSel = 0
Dim mpPlaying  As Integer : mpPlaying = -1
Dim mpI        As Integer
Dim mpY        As Integer
Dim mpKey      As Long
Dim mpLabel$

Screen _NewImage(640, 420, 32)
_Title "SSS Music Player"

SND_Init
If musCueCnt > 0 Then
    MUS_SetCue musCueN$(0)
    mpPlaying = 0
End If

Do
    mpKey = _KeyHit
    Select Case mpKey
        Case 18432  ' up arrow
            mpSel = mpSel - 1
            If mpSel < 0 Then mpSel = musCueCnt - 1
        Case 20480  ' down arrow
            mpSel = (mpSel + 1) Mod musCueCnt
        Case 32, 13  ' space or enter
            MUS_SetCue musCueN$(mpSel)
            mpPlaying = mpSel
        Case 27  ' ESC
            Exit Do
    End Select

    CLS
    Color _RGB(0, 200, 255)
    _PrintString (8, 8), "SSS MUSIC PLAYER"
    Color _RGB(80, 80, 80)
    _PrintString (8, 28), "up/dn: select   space/enter: play   esc: quit"
    Color _RGB(50, 50, 50)
    _PrintString (8, 48), String$(78, 45)  ' separator

    For mpI = 0 To musCueCnt - 1
        mpY = 64 + mpI * 22
        mpLabel$ = musCueN$(mpI)
        mpLabel$ = mpLabel$ + String$(16 - Len(mpLabel$), 32)
        mpLabel$ = mpLabel$ + LTrim$(Str$(musCueBPM(mpI))) + " bpm"
        mpLabel$ = mpLabel$ + "   " + LTrim$(Str$(musCueVCnt(mpI))) + " voices"
        If musCueDrum(mpI) >= 0 Then mpLabel$ = mpLabel$ + "   drums"
        If mpI = mpPlaying Then
            Color _RGB(80, 255, 80)
            _PrintString (8, mpY), ">> " + mpLabel$ + "   [PLAYING]"
        ElseIf mpI = mpSel Then
            Color _RGB(255, 240, 80)
            _PrintString (8, mpY), ">  " + mpLabel$
        Else
            Color _RGB(160, 160, 160)
            _PrintString (8, mpY), "   " + mpLabel$
        End If
    Next mpI

    _Display
    MUS_Fill 0
Loop

System

Sub SPK_Advance()
End Sub
