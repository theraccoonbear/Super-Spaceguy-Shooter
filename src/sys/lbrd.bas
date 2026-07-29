' lbrd.bas -- leaderboard polling and response parsing
'
' LBRD_Poll              enqueue a GET for the top-N scores (call once per title entry)
' LBRD_Parse body$       parse Supabase JSON array into lbrdName$/lbrdScore arrays
'
' Reads DB_URL, DB_KEY from sss.bas (empty = feature disabled)
' Writes lbrdName$(), lbrdScore(), lbrdCount, lbrdPollDone
'
' Local variable prefix: lb*

Sub LBRD_Poll ()
    If Len(DB_URL) = 0 Then Exit Sub
    Dim lbUrl As String
    lbUrl = DB_URL + "/top_scores?order=score.desc&limit=" + LTrim$(Str$(LBRD_MAX)) + "&select=player_name,score"
    HTTP_Get lbUrl, DB_KEY, "leaderboard_poll"
    lbrdPollDone = -1
End Sub

' Parse a Supabase JSON array like:
'   [{"player_name":"ACE","score":1234},{"player_name":"BOB","score":500},...]
' Extraction is a linear scan -- no full parser needed for this fixed shape.
Sub LBRD_Parse (lbBody As String)
    Dim lbI    As Integer
    Dim lbPos  As Integer
    Dim lbEnd  As Integer
    Dim lbName As String
    Dim lbScr  As Long
    Dim lbHasN As Integer, lbHasS As Integer

    lbrdCount = 0
    lbPos = 1
    lbI   = 0

    Do While lbPos <= Len(lbBody) And lbrdCount < LBRD_MAX
        ' find next object open-brace
        lbPos = InStr(lbPos, lbBody, "{")
        If lbPos = 0 Then Exit Do

        ' find matching close-brace (objects are flat -- no nested braces in this response)
        lbEnd = InStr(lbPos, lbBody, "}")
        If lbEnd = 0 Then Exit Do

        Dim lbObj As String
        lbObj = Mid$(lbBody, lbPos, lbEnd - lbPos + 1)
        lbPos = lbEnd + 1

        lbName = "" : lbScr = 0 : lbHasN = 0 : lbHasS = 0

        ' extract "player_name":"VALUE"
        Dim lbNP As Integer
        lbNP = InStr(lbObj, Chr$(34) + "player_name" + Chr$(34))
        If lbNP > 0 Then
            lbNP = InStr(lbNP, lbObj, ":")
            If lbNP > 0 Then
                Dim lbNQ1 As Integer, lbNQ2 As Integer
                lbNQ1 = InStr(lbNP, lbObj, Chr$(34))
                If lbNQ1 > 0 Then
                    lbNQ2 = InStr(lbNQ1 + 1, lbObj, Chr$(34))
                    If lbNQ2 > 0 Then
                        lbName = Mid$(lbObj, lbNQ1 + 1, lbNQ2 - lbNQ1 - 1)
                        lbHasN = -1
                    End If
                End If
            End If
        End If

        ' extract "score":NUMBER
        Dim lbSP As Integer
        lbSP = InStr(lbObj, Chr$(34) + "score" + Chr$(34))
        If lbSP > 0 Then
            lbSP = InStr(lbSP, lbObj, ":")
            If lbSP > 0 Then
                Dim lbSStart As Integer, lbSEnd As Integer, lbSC As String
                lbSStart = lbSP + 1
                Do While lbSStart <= Len(lbObj) And Mid$(lbObj, lbSStart, 1) = " "
                    lbSStart = lbSStart + 1
                Loop
                lbSEnd = lbSStart
                Do While lbSEnd <= Len(lbObj)
                    lbSC = Mid$(lbObj, lbSEnd, 1)
                    If lbSC >= "0" And lbSC <= "9" Then
                        lbSEnd = lbSEnd + 1
                    Else
                        Exit Do
                    End If
                Loop
                If lbSEnd > lbSStart Then
                    lbScr = Val(Mid$(lbObj, lbSStart, lbSEnd - lbSStart))
                    lbHasS = -1
                End If
            End If
        End If

        If lbHasN And lbHasS Then
            lbrdCount = lbrdCount + 1
            lbrdName(lbrdCount)  = lbName
            lbrdScore(lbrdCount) = lbScr
        End If
    Loop
End Sub

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
