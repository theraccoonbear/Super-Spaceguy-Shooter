' lbrd.bas -- leaderboard polling and response parsing
'
' LBRD_Poll              enqueue a GET for the top-N scores (call once per title entry)
' LBRD_Parse body$       parse the top_scores JSON array into lbrdName$/lbrdScore/lbrdDiff$ arrays
' LBRD_JsonStr$(s$, q, e)  decode the JSON string whose opening quote is at q; e = closing quote (0 = unterminated)
' LBRD_DisplayName$(rank, name$, level$)  name as the board draws it: rank color token + name, then
'                        the level's DLV_Tag$ (if any) in gray, cut to LBRD_NAME_COLS visible chars in all
'
' Reads DB_URL, DB_KEY from sss.bas (empty = feature disabled)
' Writes lbrdName$(), lbrdScore(), lbrdDiff$(), lbrdCount, lbrdPollDone
'
' Local variable prefix: lb*

' 13 columns leave a gap before the score column (name at scrW\2-96, score at scrW\2+20)
Const LBRD_NAME_COLS = 13
Const LBRD_TAG_COLS = 3   ' a longer difficulty.ini tag is cut, so the name keeps most of the column

Sub LBRD_Poll ()
    If Len(DB_URL) = 0 Then Exit Sub
    Dim lbUrl As String
    lbUrl = DB_URL + "/top_scores?order=score.desc&limit=" + LTrim$(Str$(LBRD_MAX)) + "&select=player_name,score,difficulty"
    HTTP_Get lbUrl, DB_KEY, "leaderboard_poll"
    lbrdPollDone = -1
End Sub

Function LBRD_JsonStr$ (lbjS As String, lbjQ As Long, lbjEnd As Long)
    Dim lbjI As Long, lbjC As String, lbjOut As String, lbjU As Long
    lbjEnd = 0
    lbjI = lbjQ + 1
    Do While lbjI <= Len(lbjS)
        lbjC = Mid$(lbjS, lbjI, 1)
        If lbjC = Chr$(34) Then
            lbjEnd = lbjI
            LBRD_JsonStr$ = lbjOut
            Exit Function
        ElseIf lbjC = "\" Then
            lbjI = lbjI + 1
            Select Case Mid$(lbjS, lbjI, 1)
                Case "n" : lbjOut = lbjOut + Chr$(10)
                Case "r" : lbjOut = lbjOut + Chr$(13)
                Case "t" : lbjOut = lbjOut + Chr$(9)
                Case "b", "f"
                Case "u"
                    lbjU = Val("&H" + Mid$(lbjS, lbjI + 1, 4))
                    If lbjU >= 32 And lbjU <= 126 Then lbjOut = lbjOut + Chr$(lbjU) Else lbjOut = lbjOut + "?"
                    lbjI = lbjI + 4
                Case Else : lbjOut = lbjOut + Mid$(lbjS, lbjI, 1)  ' \" \\ \/
            End Select
        Else
            lbjOut = lbjOut + lbjC
        End If
        lbjI = lbjI + 1
    Loop
    LBRD_JsonStr$ = ""
End Function

' Parse a top_scores JSON array like:
'   [{"player_name":"ACE","score":1234,"difficulty":"hard"},{"player_name":"BOB","score":500},...]
' A row without a difficulty (or with null) is the default level, as the server stores it.
' Scans key/value pairs in order, so quotes and braces inside a name don't end it early.
' Stops at the first malformed object, keeping the entries before it.
Sub LBRD_Parse (lbBody As String)
    Dim lbPos As Long, lbEnd As Long
    Dim lbKey As String, lbStr As String, lbLit As String, lbCh As String
    Dim lbName As String, lbScr As Long, lbDiff As String
    Dim lbHasN As Integer, lbHasS As Integer

    lbrdCount = 0
    lbPos = 1
    Do While lbrdCount < LBRD_MAX
        lbPos = InStr(lbPos, lbBody, "{")
        If lbPos = 0 Then Exit Sub
        lbPos = lbPos + 1
        lbName = "" : lbScr = 0 : lbHasN = 0 : lbHasS = 0 : lbDiff = DLV_Default$
        Do
            Do While lbPos <= Len(lbBody)
                lbCh = Mid$(lbBody, lbPos, 1)
                If lbCh <> " " And lbCh <> "," And lbCh <> Chr$(9) And lbCh <> Chr$(10) And lbCh <> Chr$(13) Then Exit Do
                lbPos = lbPos + 1
            Loop
            If lbPos > Len(lbBody) Then Exit Sub
            If lbCh = "}" Then lbPos = lbPos + 1 : Exit Do
            If lbCh <> Chr$(34) Then Exit Sub
            lbKey = LBRD_JsonStr$(lbBody, lbPos, lbEnd)
            If lbEnd = 0 Then Exit Sub
            lbPos = InStr(lbEnd + 1, lbBody, ":")
            If lbPos = 0 Then Exit Sub
            lbPos = lbPos + 1
            Do While Mid$(lbBody, lbPos, 1) = " "
                lbPos = lbPos + 1
            Loop
            If Mid$(lbBody, lbPos, 1) = Chr$(34) Then
                lbStr = LBRD_JsonStr$(lbBody, lbPos, lbEnd)
                If lbEnd = 0 Then Exit Sub
                lbPos = lbEnd + 1
                If lbKey = "player_name" Then lbName = lbStr : lbHasN = -1
                If lbKey = "difficulty" Then lbDiff = lbStr
            Else
                lbLit = ""
                Do While lbPos <= Len(lbBody)
                    lbCh = Mid$(lbBody, lbPos, 1)
                    If lbCh = "," Or lbCh = "}" Or lbCh = " " Or lbCh = Chr$(10) Or lbCh = Chr$(13) Then Exit Do
                    lbLit = lbLit + lbCh
                    lbPos = lbPos + 1
                Loop
                If lbKey = "score" And Left$(lbLit, 1) >= "0" And Left$(lbLit, 1) <= "9" Then
                    lbScr = Val(lbLit) : lbHasS = -1
                End If
            End If
        Loop
        If lbHasN And lbHasS Then
            lbrdCount = lbrdCount + 1
            lbrdName(lbrdCount)  = lbName
            lbrdScore(lbrdCount) = lbScr
            lbrdDiff(lbrdCount)  = lbDiff
        End If
    Loop
End Sub

' Rank 1 gold, 2-3 bright white, the rest blue-gray; tokens in the name override it.
' A level with a tag (difficulty.ini <level>_tag) gets it after the name in gray; the name is
' cut shorter to make room, so name + tag still fit LBRD_NAME_COLS.
Function LBRD_DisplayName$ (lbdnRank As Integer, lbdnName As String, lbdnLevel As String)
    Dim lbdnPfx As String, lbdnTag As String
    If lbdnRank = 1 Then
        lbdnPfx = "~E"
    ElseIf lbdnRank <= 3 Then
        lbdnPfx = "~F"
    Else
        lbdnPfx = "~9"
    End If
    lbdnTag = FONT_RichTrunc$(DLV_Tag$(lbdnLevel), LBRD_TAG_COLS)
    If FONT_RichVisLen%(lbdnTag) = 0 Then
        LBRD_DisplayName$ = lbdnPfx + FONT_RichTrunc$(lbdnName, LBRD_NAME_COLS)
    Else
        LBRD_DisplayName$ = lbdnPfx + FONT_RichTrunc$(lbdnName, LBRD_NAME_COLS - 1 - FONT_RichVisLen%(lbdnTag)) + " ~8" + lbdnTag
    End If
End Function

' Return 1-based rank of score$ in lbrdScore(), or 0 if not in the list.
' Uses lbrdCount + 1 (just off the board) when score beats some entries.
Function LBRD_Rank% (lbCheck As Long)
    Dim lbR As Integer
    If lbrdCount = 0 Then LBRD_Rank% = 0 : Exit Function
    For lbR = 1 To lbrdCount
        If lbCheck >= lbrdScore(lbR) Then
            LBRD_Rank% = lbR
            Exit Function
        End If
    Next lbR
    LBRD_Rank% = 0
End Function
