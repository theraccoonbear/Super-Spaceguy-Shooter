' crawlbrowse.bas -- `sss --crawls` dev screen: every named crawl (SEQ_ListCrawls)
' with its planned scroll speed at the chosen narration setting. ENTER plays the
' crawl through the normal crawl state, which returns here instead of advancing
' the sequence. The narration choice here is session-only: it is applied while a
' crawl plays and the saved setting is put back afterwards.

Dim Shared cbSel As Integer
Dim Shared cbLevel As Integer          ' 0 OFF, 1 SLOW, 2 NORMAL, 3 FAST
Dim Shared cbActive As Integer         ' 0 until the first frame after init or a crawl
Dim Shared cbSpeed(0 To SEQ_MAX - 1) As Single
Dim Shared cbUpWas As Integer, cbDnWas As Integer, cbLfWas As Integer, cbRtWas As Integer
Dim Shared cbEnterWas As Integer, cbEscWas As Integer
Dim Shared cbSaveNarr As Integer, cbSaveSpeed As Integer

Function CRAWLBROWSE_LevelName$(cblnL As Integer)
    Select Case cblnL
        Case 0 : CRAWLBROWSE_LevelName$ = "OFF"
        Case 1 : CRAWLBROWSE_LevelName$ = "SLOW"
        Case 3 : CRAWLBROWSE_LevelName$ = "FAST"
        Case Else : CRAWLBROWSE_LevelName$ = "NORMAL"
    End Select
End Function

' Same planning CRAWL_Prep does, for every listed crawl at cbLevel.
Sub CRAWLBROWSE_Plan ()
    Dim cbpI As Integer
    For cbpI = 0 To seqCrawlCount - 1
        CRAWL_Layout GTEXT_Get$(seqCrawlKey$(cbpI))
        CRAWL_PlanDurations cbLevel
        cbSpeed(cbpI) = CRAWL_PlanSpeed!(scrH, scrH - CRAWL_LINE_H, CRAWL_TOP_FADE)
    Next cbpI
End Sub

Sub CRAWLBROWSE_Init ()
    SEQ_ListCrawls
    cbSel = 0 : cbActive = 0
    cbSaveNarr = settingNarration : cbSaveSpeed = settingNarrSpeed
    cbLevel = settingNarration * settingNarrSpeed
    CRAWLBROWSE_Plan
End Sub

Sub CRAWLBROWSE_Update ()
    Dim cbI As Integer, cbY As Integer, cbClr As Integer, cbV As String
    Dim cbUp As Integer, cbDn As Integer, cbLf As Integer, cbRt As Integer, cbEnter As Integer, cbEsc As Integer

    cbUp = held(E3D_KEY_UP) : cbDn = held(E3D_KEY_DOWN) : cbLf = held(E3D_KEY_LEFT) : cbRt = held(E3D_KEY_RIGHT)
    cbEnter = KEY_Down%(13) Or (held(E3D_KEY_PAD_A) <> 0) : cbEsc = held(E3D_KEY_ESCAPE)
    If cbActive = 0 Then
        ' first frame here (startup or back from a crawl): ignore keys still held, restore the saved setting
        cbUpWas = -1 : cbDnWas = -1 : cbLfWas = -1 : cbRtWas = -1 : cbEnterWas = -1 : cbEscWas = -1
        settingNarration = cbSaveNarr : settingNarrSpeed = cbSaveSpeed
        MUS_SetCue "title"
        cbActive = -1
    End If

    If cbUp And cbUpWas = 0 Then cbSel = (cbSel + seqCrawlCount - 1) Mod seqCrawlCount
    If cbDn And cbDnWas = 0 Then cbSel = (cbSel + 1) Mod seqCrawlCount
    If cbLf And cbLfWas = 0 And cbLevel > 0 Then cbLevel = cbLevel - 1 : CRAWLBROWSE_Plan
    If cbRt And cbRtWas = 0 And cbLevel < 3 Then cbLevel = cbLevel + 1 : CRAWLBROWSE_Plan
    If cbEsc And cbEscWas = 0 Then SYSTEM
    cbUpWas = cbUp : cbDnWas = cbDn : cbLfWas = cbLf : cbRtWas = cbRt : cbEscWas = cbEsc

    If cbEnter And cbEnterWas = 0 And seqCrawlCount > 0 Then
        If cbLevel > 0 Then settingNarration = 1 : settingNarrSpeed = cbLevel Else settingNarration = 0
        CRAWL_Prep seqCrawlKey$(cbSel), scrH
        crawlNextState = GS_CRAWLS
        gameState = GS_CRAWL
        cbActive = 0
        Exit Sub
    End If
    cbEnterWas = cbEnter

    ' ---- render ----
    _Dest backBuffer
    Line (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    UI_DrawPanel 16, 8, scrW - 17, scrH - 19, "CRAWLS"
    FONT_PrintAlpha fontPalette(8), backBuffer, "BLOCK       USED AT       PX/S", 26, 30, 255
    For cbI = 0 To seqCrawlCount - 1
        cbY = 48 + cbI * 18
        If cbI = cbSel Then
            Line (22, cbY - 2)-(scrW - 23, cbY + 15), _RGBA(0, 40, 100, 180), BF
            cbClr = 14
        Else
            cbClr = 9
        End If
        cbV = LTrim$(Str$(Int(cbSpeed(cbI) * 10 + 0.5) / 10))
        FONT_PrintAlpha fontPalette(cbClr), backBuffer, seqCrawlKey$(cbI), 26, cbY, 255
        FONT_PrintAlpha fontPalette(cbClr), backBuffer, seqCrawlUse$(cbI), 122, cbY, 255
        FONT_PrintAlpha fontPalette(11), backBuffer, cbV, 258, cbY, 255
    Next cbI
    FONT_PrintCenteredAlpha fontPalette(15), backBuffer, "<  NARRATION: " + CRAWLBROWSE_LevelName$(cbLevel) + "  >", 206, scrW, 255
    FONT_PrintCenteredAlpha fontPalette(8), backBuffer, "up/dn select  ENTER play  ESC quit", scrH - 14, scrW, 255
    _Dest 0
    _PutImage , backBuffer, 0
End Sub
