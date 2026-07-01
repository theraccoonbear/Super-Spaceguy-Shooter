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

DIM SHARED crawlLines$(0 TO 63)
DIM SHARED crawlLineCount AS INTEGER
DIM SHARED crawlScroll AS SINGLE
DIM SHARED crawlTimer AS INTEGER
DIM crawlIdx AS INTEGER
DIM crawlLY AS INTEGER
DIM crawlFY AS INTEGER

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
    crawlScroll = cpStartY + CRAWL_LINE_H * 2
END SUB
