' leadin.bas -- studio / producer logo lead-in screens (GS_LEADIN)
' PNGs are baked into the binary via $EMBED; no external files needed at runtime.
' Renders directly into backBuffer with a fade-in / hold / fade-out envelope.
'
' Card order: 1 = CTUT Game Studios, 2 = Cogikel Heavy Industries
' Game boots into GS_LEADIN; transitions to GS_TITLE when both cards complete.
' Does not replay (liDone session flag).  Any keypress skips the current card.

Dim Shared liCard  As Integer    ' 1=ctut, 2=cogikel, 0=done
Dim Shared liTimer As Integer
Dim Shared liImg(1 To 2) As Long ' loaded PNG handles

Const LI_ENABLED = 1             ' set to 0 to skip lead-ins entirely
Const LI_HOLD    = 200           ' frames to hold each card (~3s at 60fps)
Const LI_FADE    = 35            ' fade-in / fade-out window in frames

Sub LEADIN_Init()
    If LI_ENABLED = 0 Then SEQ_Advance : Exit Sub
    Dim liCtutData As String, liCogData As String
    liCtutData = _EMBEDDED$("CTUTPNG")
    liCogData  = _EMBEDDED$("COGIKELPNG")
    DBG_Print "[leadin] ctut embed len=" + LTrim$(Str$(Len(liCtutData))) + "  cogikel embed len=" + LTrim$(Str$(Len(liCogData)))
    liImg(1) = _LOADIMAGE(liCtutData, 32, "memory")
    liImg(2) = _LOADIMAGE(liCogData,  32, "memory")
    DBG_Print "[leadin] img(1)=" + LTrim$(Str$(liImg(1))) + "  img(2)=" + LTrim$(Str$(liImg(2)))
    liCard = 1 : liTimer = 0
End Sub

Sub LEADIN_Update()
    Dim liAlpha As Integer
    Dim liKey   As Long

    If liCard = 0 Then gameState = GS_TITLE : Exit Sub

    liTimer = liTimer + 1

    If liTimer < LI_FADE Then
        liAlpha = liTimer * 255 \ LI_FADE
    ElseIf liTimer > LI_HOLD - LI_FADE Then
        liAlpha = (LI_HOLD - liTimer) * 255 \ LI_FADE
        If liAlpha < 0 Then liAlpha = 0
    Else
        liAlpha = 255
    End If

    _Dest backBuffer
    _DONTBLEND backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 0), BF
    If liImg(liCard) <> 0 Then
        _PutImage (0, 0)-(scrW - 1, scrH - 1), liImg(liCard), backBuffer
    End If
    If liAlpha < 255 Then
        _BLEND backBuffer
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, 255 - liAlpha), BF
    End If
    _BLEND backBuffer
    _Dest 0
    _PutImage , backBuffer, 0

    liKey = _KEYHIT
    If liTimer >= LI_HOLD Or liKey > 0 Then
        liCard = liCard + 1
        If liCard > 2 Then
            liCard = 0
            _FREEIMAGE liImg(1) : _FREEIMAGE liImg(2)
            SEQ_Advance
        Else
            liTimer = 0
        End If
    End If

    MUS_Fill 0
End Sub
