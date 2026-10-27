' lbrd_test.bas -- leaderboard response parsing and name display (src/sys/lbrd.bas)
'
' Regression for #194: a callsign holding " or \ (escaped by JSON_S$ on the way up, and by
' Supabase on the way back) or } broke LBRD_Parse; names on the board keep their ~X color
' tokens and are cut by visible width, tokens taking none.
'
' Build: ./tools/buildqb tests/lbrd_test.bas
' Run:   builds/lbrd_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY

Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Const LBRD_MAX = 10
Dim Shared lbrdName(1 To LBRD_MAX)  As String
Dim Shared lbrdScore(1 To LBRD_MAX) As Long
Dim Shared lbrdCount    As Integer
Dim Shared lbrdPollDone As Integer

'$INCLUDE:'../src/2d/font.bas'
'$INCLUDE:'../src/sys/json.bas'
'$INCLUDE:'../src/sys/lbrd.bas'

Sub HTTP_Get (hgUrl As String, hgKey As String, hgTag As String)
End Sub

Dim Shared ltPassed As Integer, ltFailed As Integer

Sub LT_Assert (ltaCond As Integer, ltaName As String)
    If ltaCond Then
        Print "PASS  " + ltaName
        ltPassed = ltPassed + 1
    Else
        Print "FAIL  " + ltaName
        ltFailed = ltFailed + 1
    End If
End Sub

Function LT_Row$ (ltrName As String, ltrScore As Long)
    LT_Row$ = JSON_Obj$(JSON_S$("player_name", ltrName) + "," + JSON_N$("score", LTrim$(Str$(ltrScore))))
End Function

Dim ltQ As String : ltQ = Chr$(34)
Dim ltBody As String, ltStr As String, ltEnd As Long, ltI As Integer
Dim ltNames(1 To 9) As String

Print "=== lbrd_test ==="
Print ""

Print "--- plain response ---"
LBRD_Parse "[{" + ltQ + "player_name" + ltQ + ":" + ltQ + "ACE" + ltQ + "," + ltQ + "score" + ltQ + ":1234},{" _
    + ltQ + "player_name" + ltQ + ":" + ltQ + "BOB" + ltQ + "," + ltQ + "score" + ltQ + ":500}]"
LT_Assert lbrdCount = 2, "two entries"
LT_Assert lbrdName(1) = "ACE" And lbrdScore(1) = 1234, "first entry"
LT_Assert lbrdName(2) = "BOB" And lbrdScore(2) = 500, "second entry"

LBRD_Parse "[]"
LT_Assert lbrdCount = 0, "empty array gives no entries"

Print ""
Print "--- names survive the JSON_S$ round trip ---"
ltNames(1) = "QUOTE" + ltQ + "KID"
ltNames(2) = "BACK\SLASH"
ltNames(3) = "BRACE}NAME{"
ltNames(4) = "A" + ltQ + "score"
ltNames(5) = "~CRED~FWOLF"
ltNames(6) = ltQ
ltNames(7) = "\"
ltNames(8) = "x\" + ltQ + "y,:"
ltNames(9) = "TRAIL\\"
ltBody = "["
For ltI = 1 To 9
    If ltI > 1 Then ltBody = ltBody + ","
    ltBody = ltBody + LT_Row$(ltNames(ltI), 1000 - ltI)
Next ltI
ltBody = ltBody + "]"
LBRD_Parse ltBody
LT_Assert lbrdCount = 9, "all nine escaped names parsed"
For ltI = 1 To 9
    LT_Assert lbrdName(ltI) = ltNames(ltI) And lbrdScore(ltI) = 1000 - ltI, "name " + LTrim$(Str$(ltI)) + " decoded: " + ltNames(ltI)
Next ltI

Print ""
Print "--- layout variations ---"
LBRD_Parse "[ { " + ltQ + "player_name" + ltQ + " : " + ltQ + "ACE" + ltQ + " ,  " + ltQ + "score" + ltQ + " : 12 } ," + Chr$(10) _
    + " {" + ltQ + "score" + ltQ + ":34," + ltQ + "player_name" + ltQ + ":" + ltQ + "REV" + ltQ + "} ]"
LT_Assert lbrdCount = 2, "whitespace and newlines between tokens"
LT_Assert lbrdName(1) = "ACE" And lbrdScore(1) = 12, "spaced entry"
LT_Assert lbrdName(2) = "REV" And lbrdScore(2) = 34, "score before player_name"

LBRD_Parse "[{" + ltQ + "player_name" + ltQ + ":null," + ltQ + "score" + ltQ + ":5}," + LT_Row$("OK", 7) + "," _
    + "{" + ltQ + "player_name" + ltQ + ":" + ltQ + "NOSCORE" + ltQ + "}]"
LT_Assert lbrdCount = 1 And lbrdName(1) = "OK", "entries missing a name or score are skipped"

LBRD_Parse "[" + LT_Row$("GOOD", 9) + ",{" + ltQ + "player_name" + ltQ + ":" + ltQ + "BAD"
LT_Assert lbrdCount = 1 And lbrdName(1) = "GOOD", "unterminated name keeps the entries before it"

ltBody = "["
For ltI = 1 To 12
    If ltI > 1 Then ltBody = ltBody + ","
    ltBody = ltBody + LT_Row$("P" + LTrim$(Str$(ltI)), 100 - ltI)
Next ltI
LBRD_Parse ltBody + "]"
LT_Assert lbrdCount = LBRD_MAX And lbrdName(LBRD_MAX) = "P10", "capped at LBRD_MAX"

Print ""
Print "--- JSON string decoding ---"
ltBody = ltQ + "A" + Chr$(92) + "u0042" + Chr$(92) + "u00e9" + Chr$(92) + "/" + Chr$(92) + "n" + ltQ + "tail"
ltStr = LBRD_JsonStr$(ltBody, 1, ltEnd)
LT_Assert ltStr = "AB?/" + Chr$(10), "\uXXXX, \/ and \n decode (non-ASCII becomes ?)"
LT_Assert ltEnd = Len(ltBody) - 4, "end is the closing quote"
ltStr = LBRD_JsonStr$(ltQ + "open\" + ltQ, 1, ltEnd)
LT_Assert ltEnd = 0, "escaped final quote is unterminated"

Print ""
Print "--- board name: rank color + visible-width cut ---"
ltStr = LBRD_DisplayName$(1, "~CRED~FWOLF")
LT_Assert ltStr = "~E~CRED~FWOLF", "rank 1 gold prefix, name tokens kept"
LT_Assert FONT_RichVisLen%(ltStr) = 7, "tokens take no width"
ltStr = LBRD_DisplayName$(2, "ACE")
LT_Assert ltStr = "~FACE", "rank 2 bright prefix"
ltStr = LBRD_DisplayName$(3, "ACE")
LT_Assert ltStr = "~FACE", "rank 3 bright prefix"
ltStr = LBRD_DisplayName$(4, "ACE")
LT_Assert ltStr = "~9ACE", "rank 4+ dim prefix"
ltStr = LBRD_DisplayName$(5, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
LT_Assert ltStr = "~9ABCDEFGHIJKLM", "long plain name cut to LBRD_NAME_COLS"
ltStr = LBRD_DisplayName$(2, "~AVERY~BLONG~CCALLSIGN~D12345")
LT_Assert ltStr = "~F~AVERY~BLONG~CCALLS", "long colored name cut by visible width, tokens kept"
LT_Assert FONT_RichVisLen%(ltStr) = LBRD_NAME_COLS, "cut name is exactly LBRD_NAME_COLS wide"
ltStr = LBRD_DisplayName$(6, "TILDE~Z~")
LT_Assert FONT_RichVisLen%(ltStr) = 8, "~ not followed by a hex digit is a visible char"

Print ""
Print "Passed:"; ltPassed; "  Failed:"; ltFailed
If ltFailed > 0 Then System 1
System 0
