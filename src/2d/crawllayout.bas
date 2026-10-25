' crawllayout.bas -- crawl text layout and scroll-speed planning (no rendering,
' no game state), so tests can drive it with the real gametext and speech code.
'
'   CRAWL_Layout block$      wrap into crawlLines$, split into paragraphs
'   CRAWL_PlanDurations level   each paragraph's spoken (preset) or read (0 = off) seconds
'   v = CRAWL_PlanSpeed!(startY, trigY, topY)   one scroll speed for the crawl
'   CRAWL_Start block$, level, startY, trigY   all of the above, ready to run
'   evt = CRAWL_Step%(ffHeld, level)            one frame: scroll + speak paragraphs
'
' NOTE: QB64-PE hoists Dim to module scope -- all local variable names
' must be unique across every Sub/Function in the compilation unit.
' Prefix convention: cw* WrapPara, cp* Layout, cpf* PlanFits, cps* PlanSpeed, cpd* PlanDurations, cst* Start, cs* Step.

CONST CRAWL_MAX_LINES = 64
CONST CRAWL_CHARS     = 34     ' max chars per line (8px font, ~20px side margins)
CONST CRAWL_LINE_H    = 22     ' line height in pixels (FONT_CHAR_H + 6)
CONST CRAWL_TOP_FADE  = 48     ' height of top fade band in pixels
CONST CRAWL_MAX_PARAS = 16
CONST CRAWL_VEL_MIN   = 6      ' px/s slowest allowed scroll
CONST CRAWL_VEL_MAX   = 30     ' px/s fastest allowed scroll
CONST CRAWL_READ_WPM  = 200    ' narration-off reading pace

DIM SHARED crawlLines$(0 TO CRAWL_MAX_LINES - 1)
DIM SHARED crawlLineCount AS INTEGER
DIM SHARED crawlParaCount AS INTEGER
DIM SHARED crawlParaLine(0 TO CRAWL_MAX_PARAS - 1) AS INTEGER
DIM SHARED crawlParaLastLine(0 TO CRAWL_MAX_PARAS - 1) AS INTEGER
DIM SHARED crawlParaText$(0 TO CRAWL_MAX_PARAS - 1)
DIM SHARED crawlParaWords(0 TO CRAWL_MAX_PARAS - 1) AS INTEGER
DIM SHARED crawlParaDur(0 TO CRAWL_MAX_PARAS - 1) AS SINGLE   ' seconds; filled by the caller

' Running crawl (CRAWL_Start, then CRAWL_Step% once per 60 fps frame)
CONST CRAWL_SPEED = 0.25          ' px/frame; fast-forward scrolls at 5x this
DIM SHARED crawlScroll AS SINGLE    ' y of line 0
DIM SHARED crawlVel AS SINGLE       ' px/s, constant for the whole crawl (CRAWL_PlanSpeed!)
DIM SHARED crawlParaIdx AS INTEGER  ' next paragraph to speak
DIM SHARED crawlFFActive AS INTEGER ' -1 while fast-forward is held
DIM SHARED crawlTrigY AS SINGLE     ' a paragraph starts when its first line reaches this y
DIM SHARED crawlSaidIdx AS INTEGER  ' last paragraph handed to SPK_Say (-1 = none yet)
DIM SHARED crawlSaidCount AS INTEGER

' Strip ~X color codes; expand single digits to English words for speech.
Function CRAWL_StripColor$(scS As String)
    Dim scR As String, scI As Integer, scC As Integer, scH As Integer
    scR = "" : scI = 1
    Do While scI <= Len(scS)
        scC = Asc(Mid$(scS, scI, 1))
        If scC = 126 And scI < Len(scS) Then  ' ~ : check for color code
            scH = Asc(UCase$(Mid$(scS, scI + 1, 1)))
            If (scH >= 48 And scH <= 57) Or (scH >= 65 And scH <= 70) Then
                scI = scI + 2  ' skip ~X
            Else
                scR = scR + Chr$(scC) : scI = scI + 1
            End If
        ElseIf scC >= 48 And scC <= 57 Then  ' 0-9 -> word
            Select Case scC - 48
                Case 0 : scR = scR + " ZERO "
                Case 1 : scR = scR + " ONE "
                Case 2 : scR = scR + " TWO "
                Case 3 : scR = scR + " THREE "
                Case 4 : scR = scR + " FOUR "
                Case 5 : scR = scR + " FIVE "
                Case 6 : scR = scR + " SIX "
                Case 7 : scR = scR + " SEVEN "
                Case 8 : scR = scR + " EIGHT "
                Case 9 : scR = scR + " NINE "
            End Select
            scI = scI + 1
        Else
            scR = scR + Chr$(scC) : scI = scI + 1
        End If
    Loop
    CRAWL_StripColor$ = scR
End Function

' Returns visible text of s with ~X color codes stripped but otherwise unmodified
' (no digit expansion, no case change). Use for pixel-position math and word lookup.
Function CRAWL_VisText$(cvtS As String)
    Dim cvtR As String, cvtI As Integer, cvtC As Integer, cvtH As Integer
    cvtR = "" : cvtI = 1
    Do While cvtI <= Len(cvtS)
        cvtC = Asc(Mid$(cvtS, cvtI, 1))
        If cvtC = 126 And cvtI < Len(cvtS) Then
            cvtH = Asc(UCase$(Mid$(cvtS, cvtI + 1, 1)))
            If (cvtH >= 48 And cvtH <= 57) Or (cvtH >= 65 And cvtH <= 70) Then
                cvtI = cvtI + 2
            Else
                cvtR = cvtR + Chr$(cvtC) : cvtI = cvtI + 1
            End If
        Else
            cvtR = cvtR + Chr$(cvtC) : cvtI = cvtI + 1
        End If
    Loop
    CRAWL_VisText$ = cvtR
End Function

' Returns visible character count of s, excluding ~X color codes.
Function CRAWL_VisLen%(cwlS As String)
    Dim cwlI As Integer, cwlN As Integer, cwlC As Integer, cwlH As Integer
    cwlN = 0 : cwlI = 1
    Do While cwlI <= Len(cwlS)
        cwlC = Asc(Mid$(cwlS, cwlI, 1))
        If cwlC = 126 And cwlI < Len(cwlS) Then
            cwlH = Asc(UCase$(Mid$(cwlS, cwlI + 1, 1)))
            If (cwlH >= 48 And cwlH <= 57) Or (cwlH >= 65 And cwlH <= 70) Then
                cwlI = cwlI + 2
            Else
                cwlN = cwlN + 1 : cwlI = cwlI + 1
            End If
        Else
            cwlN = cwlN + 1 : cwlI = cwlI + 1
        End If
    Loop
    CRAWL_VisLen% = cwlN
End Function

' Returns the string index of the cwcN-th visible character, skipping ~X codes.
Function CRAWL_VisCut%(cwcS As String, cwcN As Integer)
    Dim cwcI As Integer, cwcVis As Integer, cwcC As Integer, cwcH As Integer
    cwcI = 1 : cwcVis = 0
    Do While cwcI <= Len(cwcS)
        cwcC = Asc(Mid$(cwcS, cwcI, 1))
        If cwcC = 126 And cwcI < Len(cwcS) Then
            cwcH = Asc(UCase$(Mid$(cwcS, cwcI + 1, 1)))
            If (cwcH >= 48 And cwcH <= 57) Or (cwcH >= 65 And cwcH <= 70) Then
                cwcI = cwcI + 2
            Else
                cwcVis = cwcVis + 1
                If cwcVis >= cwcN Then CRAWL_VisCut% = cwcI : Exit Function
                cwcI = cwcI + 1
            End If
        Else
            cwcVis = cwcVis + 1
            If cwcVis >= cwcN Then CRAWL_VisCut% = cwcI : Exit Function
            cwcI = cwcI + 1
        End If
    Loop
    CRAWL_VisCut% = Len(cwcS) + 1
End Function

Sub CRAWL_WrapPara(cwPara As String)
    Dim cwRem As String, cwCut As Integer, cwVCut As Integer
    cwRem = LTrim$(RTrim$(cwPara))
    Do While Len(cwRem) > 0
        If crawlLineCount >= CRAWL_MAX_LINES Then Exit Do
        If CRAWL_VisLen%(cwRem) <= CRAWL_CHARS Then
            crawlLines$(crawlLineCount) = cwRem
            crawlLineCount = crawlLineCount + 1
            Exit Do
        End If
        cwVCut = CRAWL_VisCut%(cwRem, CRAWL_CHARS)
        cwCut = cwVCut
        Do While cwCut > 0 And Mid$(cwRem, cwCut, 1) <> " "
            cwCut = cwCut - 1
        Loop
        If cwCut = 0 Then cwCut = cwVCut
        crawlLines$(crawlLineCount) = Left$(cwRem, cwCut)
        crawlLineCount = crawlLineCount + 1
        cwRem = LTrim$(Mid$(cwRem, cwCut + 1))
    Loop
End Sub

' Wraps a gametext block into crawlLines$ (color carried across lines) and splits it
' into paragraphs: runs of non-blank lines, with spoken text and word counts.
SUB CRAWL_Layout(cpBlock AS STRING)
    DIM cpPos AS LONG, cpNxt AS LONG, cpLn AS STRING
    DIM cpCI AS INTEGER, cpCJ AS INTEGER, cpCA AS INTEGER, cpLast AS STRING
    DIM cpWI AS INTEGER, cpWIn AS INTEGER
    crawlLineCount = 0
    IF LEN(cpBlock) = 0 THEN EXIT SUB
    cpPos = 1
    DO WHILE cpPos <= LEN(cpBlock)
        cpNxt = INSTR(cpPos, cpBlock, CHR$(10))
        IF cpNxt = 0 THEN cpNxt = LEN(cpBlock) + 1
        cpLn = MID$(cpBlock, cpPos, cpNxt - cpPos)
        cpPos = cpNxt + 1
        IF LEN(LTRIM$(RTRIM$(cpLn))) = 0 THEN
            IF crawlLineCount < CRAWL_MAX_LINES THEN
                crawlLines$(crawlLineCount) = ""
                crawlLineCount = crawlLineCount + 1
            END IF
        ELSE
            CRAWL_WrapPara cpLn
        END IF
    LOOP
    ' Forward pass: inject last-seen ~X at the start of any line that has none,
    ' so color carries across line boundaries and wrapped continuations.
    cpLast = "~7"
    FOR cpCI = 0 TO crawlLineCount - 1
        IF LEN(crawlLines$(cpCI)) > 0 THEN
            cpCA = 0
            IF LEN(crawlLines$(cpCI)) >= 2 AND LEFT$(crawlLines$(cpCI), 1) = "~" THEN
                cpCA = ASC(UCASE$(MID$(crawlLines$(cpCI), 2, 1)))
                IF NOT ((cpCA >= 48 AND cpCA <= 57) OR (cpCA >= 65 AND cpCA <= 70)) THEN cpCA = 0
            END IF
            IF cpCA = 0 THEN crawlLines$(cpCI) = cpLast + crawlLines$(cpCI)
            ' scan line for last ~X to carry forward
            FOR cpCJ = 1 TO LEN(crawlLines$(cpCI)) - 1
                IF MID$(crawlLines$(cpCI), cpCJ, 1) = "~" THEN
                    cpCA = ASC(UCASE$(MID$(crawlLines$(cpCI), cpCJ + 1, 1)))
                    IF (cpCA >= 48 AND cpCA <= 57) OR (cpCA >= 65 AND cpCA <= 70) THEN
                        cpLast = MID$(crawlLines$(cpCI), cpCJ, 2)
                    END IF
                END IF
            NEXT cpCJ
        END IF
    NEXT cpCI

    ' Build per-paragraph speech arrays; each paragraph fires separately when
    ' its first line scrolls onto screen, giving natural inter-paragraph silence.
    Dim cpSI As Integer, cpSLine As String, cpParaOpen As Integer
    crawlParaCount = 0 : cpParaOpen = 0
    For cpSI = 0 To crawlLineCount - 1
        cpSLine = LTrim$(RTrim$(CRAWL_StripColor$(crawlLines$(cpSI))))
        If Len(cpSLine) > 0 Then
            If Not cpParaOpen Then
                If crawlParaCount < CRAWL_MAX_PARAS Then
                    crawlParaLine(crawlParaCount) = cpSI
                    crawlParaText$(crawlParaCount) = ""
                    crawlParaCount = crawlParaCount + 1
                End If
                cpParaOpen = -1
            End If
            If crawlParaCount > 0 Then
                crawlParaText$(crawlParaCount - 1) = crawlParaText$(crawlParaCount - 1) + cpSLine + " "
                crawlParaLastLine(crawlParaCount - 1) = cpSI
            End If
        Else
            cpParaOpen = 0
        End If
    Next cpSI
    ' word counts drive the narration-off reading pace
    For cpWI = 0 To crawlParaCount - 1
        crawlParaWords(cpWI) = 0 : cpWIn = 0
        For cpCJ = 1 To Len(crawlParaText$(cpWI))
            If Mid$(crawlParaText$(cpWI), cpCJ, 1) = " " Then
                cpWIn = 0
            ElseIf cpWIn = 0 Then
                cpWIn = -1 : crawlParaWords(cpWI) = crawlParaWords(cpWI) + 1
            End If
        Next cpCJ
    Next cpWI
END SUB

' True if, scrolling at cpfV px/s from cpfStartY, every paragraph finishes before its
' last line reaches cpfTopY. Paragraph i starts when its first line reaches cpfTrigY,
' or when paragraph i-1 finishes, whichever is later.
Function CRAWL_PlanFits%(cpfV As Single, cpfStartY As Single, cpfTrigY As Single, cpfTopY As Single)
    Dim cpfI As Integer, cpfEnd As Single, cpfStart As Single, cpfDue As Single
    cpfEnd = 0
    For cpfI = 0 To crawlParaCount - 1
        cpfStart = (cpfStartY + crawlParaLine(cpfI) * CRAWL_LINE_H - cpfTrigY) / cpfV
        If cpfStart < cpfEnd Then cpfStart = cpfEnd
        cpfEnd = cpfStart + crawlParaDur(cpfI)
        cpfDue = (cpfStartY + crawlParaLastLine(cpfI) * CRAWL_LINE_H - cpfTopY) / cpfV
        If cpfEnd > cpfDue Then CRAWL_PlanFits% = 0 : Exit Function
    Next cpfI
    CRAWL_PlanFits% = -1
End Function

' The fastest single scroll speed in [CRAWL_VEL_MIN, CRAWL_VEL_MAX] at which every
' paragraph fits (CRAWL_PlanFits%). Slower always gives more time, so bisect.
' Returns CRAWL_VEL_MIN if even that doesn't fit.
Function CRAWL_PlanSpeed!(cpsStartY As Single, cpsTrigY As Single, cpsTopY As Single)
    Dim cpsLo As Single, cpsHi As Single, cpsMid As Single, cpsI As Integer
    If CRAWL_PlanFits%(CRAWL_VEL_MAX, cpsStartY, cpsTrigY, cpsTopY) Then CRAWL_PlanSpeed! = CRAWL_VEL_MAX : Exit Function
    If CRAWL_PlanFits%(CRAWL_VEL_MIN, cpsStartY, cpsTrigY, cpsTopY) = 0 Then CRAWL_PlanSpeed! = CRAWL_VEL_MIN : Exit Function
    cpsLo = CRAWL_VEL_MIN : cpsHi = CRAWL_VEL_MAX
    For cpsI = 1 To 24
        cpsMid = (cpsLo + cpsHi) / 2
        If CRAWL_PlanFits%(cpsMid, cpsStartY, cpsTrigY, cpsTopY) Then cpsLo = cpsMid Else cpsHi = cpsMid
    Next cpsI
    CRAWL_PlanSpeed! = cpsLo
End Function

' Fills crawlParaDur() for the laid-out paragraphs: spoken length at narration preset
' cpdLevel (1 SLOW, 2 NORMAL, 3 FAST), or reading time at CRAWL_READ_WPM when 0 (off).
Sub CRAWL_PlanDurations(cpdLevel As Integer)
    Dim cpdI As Integer
    For cpdI = 0 To crawlParaCount - 1
        If cpdLevel > 0 Then
            crawlParaDur(cpdI) = SPK_TextSamples&(crawlParaText$(cpdI), cpdLevel) / SAMPLE_RATE
        Else
            crawlParaDur(cpdI) = crawlParaWords(cpdI) / CRAWL_READ_WPM * 60
        End If
    Next cpdI
End Sub

' Lays out a block and plans its constant speed for narration level cstLevel (0 = off).
Sub CRAWL_Start(cstBlock As String, cstLevel As Integer, cstStartY As Single, cstTrigY As Single)
    CRAWL_Layout cstBlock
    CRAWL_PlanDurations cstLevel
    crawlVel = CRAWL_PlanSpeed!(cstStartY, cstTrigY, CRAWL_TOP_FADE)
    crawlScroll = cstStartY
    crawlTrigY = cstTrigY
    crawlParaIdx = 0 : crawlFFActive = 0
    crawlSaidIdx = -1 : crawlSaidCount = 0
End Sub

' One 60 fps frame of the crawl. csFF = fast-forward held. Returns 1 on the frame
' fast-forward starts, 2 on the frame it's released, else 0 (the caller handles music).
' On release, narration resumes at the first paragraph that hasn't reached the trigger
' line; this is resolved before triggering so a paragraph scrolled past is never spoken.
Function CRAWL_Step%(csFF As Integer, csLevel As Integer)
    Dim csEvt As Integer, csP As Integer
    If csFF Then
        If crawlFFActive = 0 Then crawlFFActive = -1 : SPK_Say "" : csEvt = 1
        crawlScroll = crawlScroll - CRAWL_SPEED * 5
        CRAWL_Step% = csEvt
        Exit Function
    End If
    If crawlFFActive Then
        crawlFFActive = 0 : csEvt = 2
        crawlParaIdx = crawlParaCount
        For csP = 0 To crawlParaCount - 1
            If crawlScroll + crawlParaLine(csP) * CRAWL_LINE_H > crawlTrigY Then crawlParaIdx = csP : Exit For
        Next csP
    End If
    crawlScroll = crawlScroll - crawlVel / 60
    If csLevel > 0 Then
        Do While crawlParaIdx < crawlParaCount
            If crawlScroll + crawlParaLine(crawlParaIdx) * CRAWL_LINE_H > crawlTrigY Then Exit Do
            If crawlParaIdx > 0 And SPK_IsPlaying% Then Exit Do
            SPK_Say crawlParaText$(crawlParaIdx)
            SPK_SetPreset csLevel
            crawlSaidIdx = crawlParaIdx : crawlSaidCount = crawlSaidCount + 1
            crawlParaIdx = crawlParaIdx + 1
        Loop
    End If
    CRAWL_Step% = csEvt
End Function
