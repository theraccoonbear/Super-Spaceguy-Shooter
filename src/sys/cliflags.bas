' Which launch flags make a session unrepresentative, so telemetry and score submission
' stay off for it (#418). Pure: it reads only its arguments.

' 1 when cliLine$ holds a flag that implies --no-telem, with the first such flag in
' reason$ (else ""). Whole space-separated tokens are compared, so a flag's value never
' counts: "--input-script tests/foo-dev.txt" is caused by --input-script, and
' "--settings-dir tests/foo-dev" is a plain run. A token counts as a dev flag when it
' starts with "--" and ends in "-dev", which covers flags added later.
Function CLI_ImpliesNoTelem% (cliLine As String, reason As String)
    Dim cnRest As String, cnTok As String, cnPos As Integer
    reason = "" : CLI_ImpliesNoTelem% = 0
    cnRest = LTrim$(cliLine)
    Do While cnRest <> ""
        cnPos = InStr(cnRest, " ")
        If cnPos = 0 Then cnPos = Len(cnRest) + 1
        cnTok = Left$(cnRest, cnPos - 1)
        cnRest = LTrim$(Mid$(cnRest, cnPos + 1))
        If Left$(cnTok, 2) = "--" Then
            If Len(cnTok) > 6 And Right$(cnTok, 4) = "-dev" Then
                reason = cnTok : CLI_ImpliesNoTelem% = -1 : Exit Function
            End If
            Select Case cnTok
                Case "--god", "--nerf", "--scene", "--bench", "--input-script", "--explode", _
                     "--seed", "--frames", "--credits", "--ships", "--shields", "--fuel", "--pup", _
                     "--screenshot-at", "--leaderboard-file"
                    reason = cnTok : CLI_ImpliesNoTelem% = -1 : Exit Function
            End Select
        End If
    Loop
End Function
