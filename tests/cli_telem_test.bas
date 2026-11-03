' cli_telem_test.bas -- which launch flags imply --no-telem (src/sys/cliflags.bas, #418)
'
' Any --...-dev flag and the cheat/test flags switch telemetry off; a plain run, or one with
' only flags that don't change the session, leaves it on; a flag's value never counts.
' --telem cancels an implied off, --no-telem beats everything, and tokens match whole.
'
' Build: ./tools/buildqb tests/cli_telem_test.bas
' Run:   builds/cli_telem_test    (exit 0 = pass, exit 1 = any failure)

Option _Explicit
$Console:Only

'$INCLUDE:'../src/sys/cliflags.bas'

Dim Shared ctPassed As Integer, ctFailed As Integer

Sub CT_Assert(condition As Integer, testName As String)
    If condition Then
        Print "PASS  " + testName
        ctPassed = ctPassed + 1
    Else
        Print "FAIL  " + testName
        ctFailed = ctFailed + 1
    End If
End Sub

' line$ must be implied (want$ the flag named) or not (want$ = "")
Sub CT_Check(ctLine As String, ctWant As String)
    Dim ctReason As String, ctHit As Integer
    ctHit = CLI_ImpliesNoTelem%(ctLine, ctReason)
    If ctWant = "" Then
        CT_Assert ctHit = 0 And ctReason = "", "stays on: '" + ctLine + "'"
    Else
        CT_Assert ctHit <> 0 And ctReason = ctWant, "off by " + ctWant + ": '" + ctLine + "'"
    End If
End Sub



Sub CT_Decide(ctLine As String, ctOn As Integer, ctWhy As String)
    Dim ctW As String, ctR As Integer
    ctR = CLI_TelemDecision%(ctLine, ctW)
    CT_Assert ctR = ctOn And ctW = ctWhy, "decision " + LTrim$(Str$(ctOn)) + " [" + ctWhy + "]: '" + ctLine + "'"
End Sub

Print "=== cli_telem_test ==="

Print "--- -dev flags ---"
CT_Check "--backdrop-dev", "--backdrop-dev"
CT_Check "--explosion-dev", "--explosion-dev"
CT_Check "--thruster-dev", "--thruster-dev"
CT_Check "--enemy-dev", "--enemy-dev"
CT_Check "--anything-new-dev --debug", "--anything-new-dev"
CT_Check "--debug --backdrop-dev", "--backdrop-dev"
CT_Check "  --debug   --enemy-dev  ", "--enemy-dev"

Print "--- cheat and test flags ---"
CT_Check "--god", "--god"
CT_Check "--nerf", "--nerf"
CT_Check "--scene playing1", "--scene"
CT_Check "--bench out.txt --frames 100", "--bench"
CT_Check "--input-script tests/input/x.txt", "--input-script"
CT_Check "--explode a@10", "--explode"
CT_Check "--seed 1", "--seed"
CT_Check "--frames 60", "--frames"
CT_Check "--credits 5", "--credits"
CT_Check "--ships 3", "--ships"
CT_Check "--shields 4", "--shields"
CT_Check "--fuel 9", "--fuel"
CT_Check "--pup shield", "--pup"
CT_Check "--screenshot-at 5", "--screenshot-at"
CT_Check "--leaderboard-file x.json", "--leaderboard-file"
CT_Check "--debug --god --nerf", "--god"

Print "--- telemetry stays on ---"
CT_Check "", ""
CT_Check "--debug", ""
CT_Check "--difficulty hard", ""
CT_Check "--crawls --realtime --gate-tutorial --script-override", ""
CT_Check "--settings-dir /tmp/sss", ""
CT_Check "--god-mode", ""
CT_Check "--scenery", ""
CT_Check "--dev", ""
CT_Check "-dev", ""
CT_Check "--no-telem", ""

Print "--- a value is not a flag ---"
CT_Check "--settings-dir tests/foo-dev", ""
CT_Check "--settings-dir tests/foo-dev.txt --debug", ""
CT_Check "--input-script tests/foo-dev.txt", "--input-script"
CT_Check "--scene my-dev", "--scene"

Print "--- --telem and --no-telem precedence ---"
CT_Decide "", -1, ""
CT_Decide "--god", 0, "off, --god implies --no-telem"
CT_Decide "--god --telem", -1, "on, --telem overrides --god"
CT_Decide "--telem --god", -1, "on, --telem overrides --god"
CT_Decide "--backdrop-dev --telem --debug", -1, "on, --telem overrides --backdrop-dev"
CT_Decide "--god --no-telem", 0, "off, --no-telem"
CT_Decide "--no-telem", 0, "off, --no-telem"
CT_Decide "--god --telem --no-telem", 0, "off, --no-telem wins over --telem"
CT_Decide "--no-telem --telem --god", 0, "off, --no-telem wins over --telem"
CT_Decide "--telem", -1, "on, --telem given, no dev flag to override"
CT_Decide "--debug --difficulty hard", -1, ""
Print "--- the substring trap: --telem is not found in --no-telem ---"
CT_Decide "--no-telem --god", 0, "off, --no-telem"
CT_Decide "--no-telem-x --god", 0, "off, --god implies --no-telem"
CT_Decide "--telemetry --god", 0, "off, --god implies --no-telem"
CT_Decide "--settings-dir x--no-telem", -1, ""
CT_Decide "--settings-dir x--telem --god", 0, "off, --god implies --no-telem"
CT_Decide "--input-script tests/--telem.txt", 0, "off, --input-script implies --no-telem"

Print ""
Print "=== " + LTrim$(Str$(ctPassed + ctFailed)) + " tests: " + LTrim$(Str$(ctPassed)) + " passed, " + LTrim$(Str$(ctFailed)) + " failed ==="
If ctFailed > 0 Then System 1 Else System 0
