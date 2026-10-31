' lbrd_test.bas -- leaderboard response parsing and name display (src/sys/lbrd.bas)
'
' Regression for #194: a callsign holding " or \ (escaped by JSON_S$ on the way up, and by
' Supabase on the way back) or } broke LBRD_Parse; names on the board keep their ~X color
' tokens and are cut by visible width, tokens taking none.
' #102: each row's difficulty level is parsed (missing or null = difficulty.ini's default), and
' the board shows the level's tag from the real difficulty.ini after the name; a made-up ini
' with an extra level shows its tag with no code change.
'
' Build: ./tools/buildqb tests/lbrd_test.bas
' Run:   builds/lbrd_test    (exit 0 = pass, exit 1 = any failure)

$CONSOLE:ONLY
$EMBED:'assets/config/difficulty.ini':'CFGDIFFICULTY'

Dim Shared DB_URL As String
Dim Shared DB_KEY As String
Const LBRD_MAX = 10
Dim Shared lbrdName(1 To LBRD_MAX)  As String
Dim Shared lbrdScore(1 To LBRD_MAX) As Long
Dim Shared lbrdDiff(1 To LBRD_MAX)  As String
Dim Shared lbrdCount    As Integer
Dim Shared lbrdPollDone As Integer

'$INCLUDE:'../src/gameplay/difficulty.bas'
'$INCLUDE:'../src/sys/config.bas'
'$INCLUDE:'../src/2d/font.bas'
'$INCLUDE:'../src/sys/json.bas'
'$INCLUDE:'../src/sys/lbrd.bas'

Dim Shared ltGetUrl As String
Sub HTTP_Get (hgUrl As String, hgKey As String, hgTag As String)
    ltGetUrl = hgUrl
End Sub

Function LT_LoadIni% (ltliSrc As String)
    cfgDifficulty = CFG_Parse$(ltliSrc)
    LT_LoadIni% = DLV_Load%
End Function

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

LT_Assert LT_LoadIni%(_EMBEDDED$("CFGDIFFICULTY")), "real difficulty.ini loads " + dlvLoadErr

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
ltStr = LBRD_DisplayName$(1, "~CRED~FWOLF", "normal")
LT_Assert ltStr = "~E~CRED~FWOLF", "rank 1 gold prefix, name tokens kept"
LT_Assert FONT_RichVisLen%(ltStr) = 7, "tokens take no width"
ltStr = LBRD_DisplayName$(2, "ACE", "normal")
LT_Assert ltStr = "~FACE", "rank 2 bright prefix"
ltStr = LBRD_DisplayName$(3, "ACE", "normal")
LT_Assert ltStr = "~FACE", "rank 3 bright prefix"
ltStr = LBRD_DisplayName$(4, "ACE", "normal")
LT_Assert ltStr = "~9ACE", "rank 4+ dim prefix"
ltStr = LBRD_DisplayName$(5, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "normal")
LT_Assert ltStr = "~9ABCDEFGHIJKLM", "long plain name cut to LBRD_NAME_COLS"
ltStr = LBRD_DisplayName$(2, "~AVERY~BLONG~CCALLSIGN~D12345", "normal")
LT_Assert ltStr = "~F~AVERY~BLONG~CCALLS", "long colored name cut by visible width, tokens kept"
LT_Assert FONT_RichVisLen%(ltStr) = LBRD_NAME_COLS, "cut name is exactly LBRD_NAME_COLS wide"
ltStr = LBRD_DisplayName$(6, "TILDE~Z~", "normal")
LT_Assert FONT_RichVisLen%(ltStr) = 8, "~ not followed by a hex digit is a visible char"

Print ""
Print "--- poll asks for each row's difficulty (#102) ---"
DB_URL = "https://example.test" : ltGetUrl = ""
LBRD_Poll
LT_Assert ltGetUrl = "https://example.test/top_scores?order=score.desc&limit=10&select=player_name,score,difficulty", "select=player_name,score,difficulty"
DB_URL = ""

Print ""
Print "--- difficulty parsed per row ---"
LBRD_Parse "[" + JSON_Obj$(JSON_S$("player_name", "HRD") + "," + JSON_N$("score", "900") + "," + JSON_S$("difficulty", "hard")) + "," _
    + "{" + ltQ + "difficulty" + ltQ + ":" + ltQ + "easy" + ltQ + "," + ltQ + "player_name" + ltQ + ":" + ltQ + "EZY" + ltQ + "," + ltQ + "score" + ltQ + ":800}," _
    + LT_Row$("OLD", 700) + "," _
    + "{" + ltQ + "player_name" + ltQ + ":" + ltQ + "NUL" + ltQ + "," + ltQ + "score" + ltQ + ":600," + ltQ + "difficulty" + ltQ + ":null}," _
    + JSON_Obj$(JSON_S$("player_name", "NEW") + "," + JSON_N$("score", "500") + "," + JSON_S$("difficulty", "nightmare")) + "]"
LT_Assert lbrdCount = 5, "five entries"
LT_Assert lbrdName(1) = "HRD" And lbrdScore(1) = 900 And lbrdDiff(1) = "hard", "difficulty after name and score"
LT_Assert lbrdName(2) = "EZY" And lbrdScore(2) = 800 And lbrdDiff(2) = "easy", "difficulty before name and score"
LT_Assert lbrdName(3) = "OLD" And lbrdDiff(3) = "normal", "no difficulty: the default level"
LT_Assert lbrdName(4) = "NUL" And lbrdDiff(4) = "normal", "null difficulty: the default level"
LT_Assert lbrdName(5) = "NEW" And lbrdDiff(5) = "nightmare", "a level this build doesn't know is kept as sent"
LBRD_Parse "[" + LT_Row$("A", 1) + "]"
LT_Assert lbrdCount = 1 And lbrdDiff(1) = "normal", "a reparse resets the row's level"

Print ""
Print "--- board name: the level's tag from difficulty.ini ---"
LT_Assert DLV_Tag$("hard") = "H" And DLV_Tag$("easy") = "E" And DLV_Tag$("normal") = "", "real ini tags: easy E, normal none, hard H"
ltStr = LBRD_DisplayName$(1, "ACE", "hard")
LT_Assert ltStr = "~EACE ~8H", "hard: gray H after the name"
ltStr = LBRD_DisplayName$(4, "ACE", "easy")
LT_Assert ltStr = "~9ACE ~8E", "easy: gray E after the name"
LT_Assert LBRD_DisplayName$(2, "ACE", "normal") = "~FACE", "normal (empty tag): name only"
LT_Assert LBRD_DisplayName$(2, "ACE", "nightmare") = "~FACE", "unknown level: name only"
ltStr = LBRD_DisplayName$(5, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", "hard")
LT_Assert ltStr = "~9ABCDEFGHIJK ~8H", "long name cut to make room for the tag"
LT_Assert FONT_RichVisLen%(ltStr) = LBRD_NAME_COLS, "name + tag exactly LBRD_NAME_COLS wide"
ltStr = LBRD_DisplayName$(2, "~AVERY~BLONG~CCALLSIGN~D12345", "hard")
LT_Assert ltStr = "~F~AVERY~BLONG~CCAL ~8H", "colored name cut by visible width before the tag"

Print ""
Print "--- a made-up difficulty.ini with an extra level ---"
LT_Assert LT_LoadIni%("levels=normal,hard,insane" + Chr$(10) + "default=normal" + Chr$(10) + "hard_tag=H" + Chr$(10) _
    + "insane_name=INSANE" + Chr$(10) + "insane_tag=~CXTREME" + Chr$(10) + "insane_boss_hp=2"), "3-level ini loads " + dlvLoadErr
ltStr = LBRD_DisplayName$(1, "ABCDEFGHIJKLMNOP", "insane")
LT_Assert ltStr = "~EABCDEFGHI ~8~CXTR", "extra level's tag (with its own color token) cut to LBRD_TAG_COLS"
LT_Assert FONT_RichVisLen%(ltStr) = LBRD_NAME_COLS, "still LBRD_NAME_COLS wide"
LT_Assert LBRD_DisplayName$(1, "ACE", "easy") = "~EACE", "easy isn't a level here: no tag"
LT_Assert LT_LoadIni%("levels=calm,storm" + Chr$(10) + "default=storm" + Chr$(10) + "storm_tag=S"), "2-level ini, default storm, loads " + dlvLoadErr
LBRD_Parse "[" + LT_Row$("OLD", 10) + "]"
LT_Assert lbrdDiff(1) = "storm", "no difficulty: this ini's default"
LT_Assert LBRD_DisplayName$(1, lbrdName(1), lbrdDiff(1)) = "~EOLD ~8S", "and its tag shows"
LT_Assert LT_LoadIni%(_EMBEDDED$("CFGDIFFICULTY")), "real difficulty.ini reloads"

Print ""
Print "Passed:"; ltPassed; "  Failed:"; ltFailed
If ltFailed > 0 Then System 1
System 0
