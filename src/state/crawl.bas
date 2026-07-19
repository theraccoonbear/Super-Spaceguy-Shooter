Sub GS_CRAWL_Update ()
    Dim crawlIdx As Integer
    Dim crawlLY As Integer
    Dim crawlFY As Integer
    Dim crawlSpkW As String
    Dim crawlHiVis As String, crawlHiViU As String, crawlHiPos As Integer, crawlHiX As Integer
    Dim crawlSpkOcc As Integer, crawlHiPara As Integer
    Dim crawlScanI As Integer, crawlScanV As String, crawlScanP As Integer
    Dim crawlPriorOcc As Integer, crawlLineOcc As Integer, crawlHiLB As Integer, crawlHiRB As Integer
    Dim crawlFFHint As String
    Dim crawlFFHX As Integer
    Dim crawlResI As Integer
    Dim crawlResP As Integer
    Dim crawlSyncS As Single
    Dim crawlSyncEla As Long
    Dim crawlSyncJ As Integer
    Dim crawlSyncDur As Long
    Dim crawlSyncPD As Long

    ' on first frame (crawlTimer=0 set by CRAWL_Prep), reset starfield to crawl camera
    IF crawlTimer = 0 THEN
        StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
        MUS_SetCue "crawl"
    END IF
    tt = tt + 0.025
    crawlTimer = crawlTimer + 1
    IF held(E3D_KEY_SPACE) AND crawlTimer > 60 THEN
        crawlScroll = crawlScroll - CRAWL_SPEED * 5
    ELSE
        crawlScroll = crawlScroll - CRAWL_SPEED
    END IF
    ' Fire each paragraph's speech when its first line scrolls near the bottom.
    ' All paragraphs use the same crawlRateScale (computed in CRAWL_Prep) so the
    ' entire narration fills the crawl window at a consistent pace.
    IF settingNarration AND (held(E3D_KEY_SPACE) AND crawlTimer > 60) = 0 THEN
        DO WHILE crawlParaIdx < crawlParaCount
            IF crawlScroll + crawlParaLine(crawlParaIdx) * CRAWL_LINE_H > scrH - CRAWL_LINE_H THEN EXIT DO
            IF crawlParaIdx > 0 AND SPK_IsPlaying% THEN EXIT DO
            SPK_Say crawlParaText$(crawlParaIdx)
            spkRateScale = crawlRateScale
            crawlParaIdx = crawlParaIdx + 1
        LOOP
    ELSE
        crawlParaIdx = crawlParaCount  ' narration off: mark all paragraphs done
    END IF

    cam.POS.x = -CAM_OFFSET_X : cam.POS.y = CAM_OFFSET_Y : cam.POS.z = 0
    cam.target.x = CAM_LEAD_X : cam.target.y = 0 : cam.target.z = 0
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat
    E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    crawlSpkW = SPK_CurWord$
    crawlSpkOcc = SPK_CurWordOcc%
    crawlHiPara = crawlParaIdx - 1 : IF crawlHiPara < 0 THEN crawlHiPara = 0

    FOR crawlIdx = 0 TO crawlLineCount - 1
        crawlLY = INT(crawlScroll + crawlIdx * CRAWL_LINE_H)
        IF crawlLY > -CRAWL_LINE_H AND crawlLY < scrH THEN
            IF LEN(crawlLines$(crawlIdx)) > 0 THEN
                FONT_PrintCenteredRichAlpha fontPalette(), backBuffer, crawlLines$(crawlIdx), crawlLY, scrW, 255
                IF LEN(crawlSpkW) > 0 AND crawlIdx >= crawlParaLine(crawlHiPara) AND crawlIdx <= crawlParaLastLine(crawlHiPara) THEN
                    crawlHiVis = CRAWL_VisText$(crawlLines$(crawlIdx))
                    crawlHiViU = UCASE$(crawlHiVis)
                    crawlPriorOcc = 0
                    FOR crawlScanI = crawlParaLine(crawlHiPara) TO crawlIdx - 1
                        crawlScanV = UCASE$(CRAWL_VisText$(crawlLines$(crawlScanI)))
                        crawlScanP = 1
                        DO
                            crawlScanP = INSTR(crawlScanP, crawlScanV, crawlSpkW)
                            IF crawlScanP = 0 THEN EXIT DO
                            crawlHiLB = 0 : IF crawlScanP > 1 THEN crawlHiLB = ASC(MID$(crawlScanV, crawlScanP - 1, 1))
                            crawlHiRB = 0 : IF crawlScanP + LEN(crawlSpkW) <= LEN(crawlScanV) THEN crawlHiRB = ASC(MID$(crawlScanV, crawlScanP + LEN(crawlSpkW), 1))
                            IF (crawlHiLB < 65 OR crawlHiLB > 90) AND (crawlHiRB < 65 OR crawlHiRB > 90) THEN crawlPriorOcc = crawlPriorOcc + 1
                            crawlScanP = crawlScanP + LEN(crawlSpkW)
                        LOOP
                    NEXT crawlScanI
                    crawlHiPos = 1 : crawlLineOcc = 0
                    DO
                        crawlHiPos = INSTR(crawlHiPos, crawlHiViU, crawlSpkW)
                        IF crawlHiPos = 0 THEN EXIT DO
                        crawlHiLB = 0 : IF crawlHiPos > 1 THEN crawlHiLB = ASC(MID$(crawlHiViU, crawlHiPos - 1, 1))
                        crawlHiRB = 0 : IF crawlHiPos + LEN(crawlSpkW) <= LEN(crawlHiViU) THEN crawlHiRB = ASC(MID$(crawlHiViU, crawlHiPos + LEN(crawlSpkW), 1))
                        IF (crawlHiLB < 65 OR crawlHiLB > 90) AND (crawlHiRB < 65 OR crawlHiRB > 90) THEN
                            IF crawlPriorOcc + crawlLineOcc = crawlSpkOcc THEN
                                crawlHiX = (scrW - CRAWL_VisLen%(crawlLines$(crawlIdx)) * FONT_CHAR_W) \ 2
                                crawlHiX = crawlHiX + (crawlHiPos - 1) * FONT_CHAR_W
                                FONT_PrintAlpha fontPalette(11), backBuffer, MID$(crawlHiVis, crawlHiPos, LEN(crawlSpkW)), crawlHiX, crawlLY, 255
                                EXIT DO
                            END IF
                            crawlLineOcc = crawlLineOcc + 1
                        END IF
                        crawlHiPos = crawlHiPos + LEN(crawlSpkW)
                    LOOP
                END IF
            END IF
        END IF
    NEXT crawlIdx

    FOR crawlFY = 0 TO 47
        LINE (0, crawlFY)-(scrW - 1, crawlFY), _RGBA(0, 0, 5, 255 - crawlFY * 5), BF
    NEXT crawlFY
    FOR crawlFY = 0 TO 31
        LINE (0, scrH - 1 - crawlFY)-(scrW - 1, scrH - 1 - crawlFY), _RGBA(0, 0, 5, 200 - crawlFY * 6), BF
    NEXT crawlFY

    IF crawlSpkOverlay AND LEN(crawlSpkW) > 0 THEN
        LINE (0, scrH - FONT_CHAR_H - 3)-(LEN(crawlSpkW) * FONT_CHAR_W + 7, scrH - 1), _RGB(0, 20, 60), BF
        FONT_PrintAlpha fontPalette(10), backBuffer, crawlSpkW, 4, scrH - FONT_CHAR_H - 1, 255
    END IF
    IF crawlTimer > 60 AND held(E3D_KEY_SPACE) THEN
        crawlFFHint = ">> FAST FORWARD <<"
        crawlFFHX = (scrW - LEN(crawlFFHint) * FONT_CHAR_W) \ 2
        LINE (crawlFFHX - 5, scrH - FONT_CHAR_H - 5)-(crawlFFHX + LEN(crawlFFHint) * FONT_CHAR_W + 4, scrH - 1), _RGBA(0, 8, 24, 210), BF
        FONT_PrintAlpha fontPalette(14), backBuffer, crawlFFHint, crawlFFHX, scrH - FONT_CHAR_H - 2, 255
    END IF

    IF crawlScroll + crawlLineCount * CRAWL_LINE_H < -20 THEN
        crawlParaIdx = crawlParaCount : SPK_Say ""
        fxVCRActive = 0 : IF crawlFFActive THEN volMusic = crawlFFVolSave : crawlFFActive = 0
        escWas = held(E3D_KEY_ESCAPE)
        CRAWL_Finish
        EXIT SUB
    END IF
    IF crawlTimer > 60 THEN
        IF held(E3D_KEY_SPACE) THEN
            IF crawlFFActive = 0 THEN
                crawlFFVolSave = volMusic : volMusic = 0 : SPK_Say "" : crawlFFActive = -1
            END IF
            IF held(E3D_KEY_ESCAPE) THEN
                fxVCRActive = 0 : volMusic = crawlFFVolSave : crawlFFActive = 0 : SPK_Say ""
                escWas = -1
                CRAWL_Finish : EXIT SUB
            END IF
            fxVCRActive = -1
            IF settingNarration AND (crawlTimer MOD 4) = 0 THEN SND_Blip 400 + INT(RND * 1200)
        ELSE
            IF crawlFFActive THEN
                volMusic = crawlFFVolSave : crawlFFActive = 0
                IF settingNarration THEN
                    crawlResI = -1
                    FOR crawlResP = crawlParaCount - 1 TO 0 STEP -1
                        IF crawlScroll + crawlParaLine(crawlResP) * CRAWL_LINE_H <= scrH - CRAWL_LINE_H THEN
                            crawlResI = crawlResP : EXIT FOR
                        END IF
                    NEXT crawlResP
                    IF crawlResI < 0 THEN
                        crawlParaIdx = 0
                    ELSE
                        SPK_Say crawlParaText$(crawlResI)
                        spkRateScale = crawlRateScale
                        crawlSyncS = (scrH - CRAWL_LINE_H) - crawlParaLine(crawlResI) * CRAWL_LINE_H
                        crawlSyncEla = CLNG((crawlSyncS - crawlScroll) / CRAWL_SPEED / 60.0 * SAMPLE_RATE)
                        crawlSyncJ = 0 : crawlSyncDur = 0
                        DO WHILE crawlSyncJ < spkPhoneCount
                            crawlSyncPD = CLNG(spkDur(spkPhones(crawlSyncJ), spkStress(crawlSyncJ)) * crawlRateScale)
                            IF crawlSyncDur + crawlSyncPD > crawlSyncEla THEN EXIT DO
                            crawlSyncDur = crawlSyncDur + crawlSyncPD
                            crawlSyncJ = crawlSyncJ + 1
                        LOOP
                        IF crawlSyncJ >= spkPhoneCount THEN
                            spkPhoneCount = 0 : spkPhoneIdx = 0 : spkSamplePos = 0
                        ELSE
                            spkPhoneIdx = crawlSyncJ : spkSamplePos = 0
                        END IF
                        crawlParaIdx = crawlResI + 1
                    END IF
                ELSE
                    crawlParaIdx = crawlParaCount
                END IF
            END IF
            fxVCRActive = 0
        END IF
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    IF _KEYDOWN(96) THEN
        IF crawlBtWas = 0 THEN crawlSpkOverlay = 1 - crawlSpkOverlay
        crawlBtWas = -1
    ELSE
        crawlBtWas = 0
    END IF

    _DEST 0 : _PUTIMAGE , backBuffer, 0
    FX_VCRNoise scrW, scrH
    MUS_Fill 0
End Sub
