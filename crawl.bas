' crawl.bas — stage narrative text crawl (upward scroll)
'
' Usage:
'   CRAWL_Prep "stage1", scrH   ' word-wrap block, reset scroll
'   gameState = GS_CRAWL        ' hand control to sssCrawl: in sss.bas
'
' NOTE: QB64-PE hoists Dim to module scope — all local variable names
' must be unique across every Sub/Function in the compilation unit.
' Prefix convention: cw* WrapPara, cp* Prep.

CONST CRAWL_MAX_LINES = 64
CONST CRAWL_CHARS     = 34     ' max chars per line (8px font, ~20px side margins)
CONST CRAWL_LINE_H    = 22     ' line height in pixels (FONT_CHAR_H + 6)
CONST CRAWL_SPEED     = 0.25   ' pixels per frame upward
CONST CRAWL_TOP_FADE  = 48     ' height of top fade band in pixels

DIM SHARED crawlLines$(0 TO 63)
DIM SHARED crawlLineCount AS INTEGER
DIM SHARED crawlScroll AS SINGLE
DIM SHARED crawlTimer AS INTEGER
DIM SHARED crawlSpeechText$
DIM SHARED crawlSpeechDone AS INTEGER

CONST CRAWL_MAX_PARAS = 16
DIM SHARED crawlParaCount AS INTEGER
DIM SHARED crawlParaLine(0 TO CRAWL_MAX_PARAS - 1) AS INTEGER
DIM SHARED crawlParaLastLine(0 TO CRAWL_MAX_PARAS - 1) AS INTEGER
DIM SHARED crawlParaText$(0 TO CRAWL_MAX_PARAS - 1)
DIM SHARED crawlParaIdx AS INTEGER
DIM SHARED crawlPrevRate AS SINGLE
DIM SHARED crawlRateScale AS SINGLE  ' uniform rate for whole crawl; computed in CRAWL_Prep

DIM crawlIdx AS INTEGER
DIM crawlLY AS INTEGER
DIM crawlFY AS INTEGER
DIM SHARED crawlSpkOverlay AS INTEGER  ' 0=off 1=on; ` key toggles
DIM SHARED crawlBtWas AS INTEGER       ' edge-detect state for backtick
DIM SHARED crawlFFActive AS INTEGER    ' -1 while FF is active; tracks vol save/restore independent of spaceWas

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

SUB CRAWL_Prep(cpKey AS STRING, cpStartY AS SINGLE)
    DIM cpBlock AS STRING, cpPos AS LONG, cpNxt AS LONG, cpLn AS STRING
    DIM cpCI AS INTEGER, cpCJ AS INTEGER, cpCA AS INTEGER, cpLast AS STRING
    DIM cpAllText AS STRING, cpAllI AS INTEGER, cpNatural AS LONG, cpNatJ AS INTEGER, cpSyncPx AS SINGLE
    crawlLineCount = 0
    crawlTimer = 0
    cpBlock = GTEXT_Get$(cpKey)
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
    crawlScroll = cpStartY  ' start text at screen bottom — visible immediately with bottom fade

    ' Build per-paragraph speech arrays; each paragraph fires separately when
    ' its first line scrolls onto screen, giving natural inter-paragraph silence.
    Dim cpSI As Integer, cpSLine As String, cpParaOpen As Integer
    crawlParaCount = 0 : crawlParaIdx = 0 : crawlPrevRate = 1.0 : cpParaOpen = 0
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
    ' Compute a single uniform speech rate for the whole crawl: speech fills the window
    ' from the first paragraph's trigger point to the last line exiting the top fade band.
    ' All paragraphs then speak at this same rate, avoiding per-paragraph pace variation.
    crawlRateScale = 1.0
    If settingNarration And crawlParaCount > 0 Then
        cpAllText = ""
        For cpAllI = 0 To crawlParaCount - 1
            cpAllText = cpAllText + crawlParaText$(cpAllI)
        Next cpAllI
        SPK_Say cpAllText  ' dry-run: fills phoneme queue for counting only
        cpNatural = 0
        For cpNatJ = 0 To spkPhoneCount - 1
            cpNatural = cpNatural + spkDur(spkPhones(cpNatJ), spkStress(cpNatJ))
        Next cpNatJ
        If cpNatural > 0 Then
            cpSyncPx = (cpStartY - CRAWL_LINE_H - CRAWL_TOP_FADE) _
                     + (crawlParaLastLine(crawlParaCount - 1) - crawlParaLine(0)) * CRAWL_LINE_H
            crawlRateScale = (cpSyncPx / CRAWL_SPEED * SAMPLE_RATE / 60.0) / cpNatural
            If crawlRateScale < 0.60 Then crawlRateScale = 0.60
            If crawlRateScale > 1.20 Then crawlRateScale = 1.20
        End If
        spkPhoneCount = 0 : spkPhoneIdx = 0  ' reset dry-run queue; no audio plays yet
    End If
    crawlSpeechDone = 0
    crawlBtWas = 0
    crawlFFActive = 0
END SUB
