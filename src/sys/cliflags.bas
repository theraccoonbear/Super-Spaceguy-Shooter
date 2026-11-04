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

' Whether telemetry runs this session (-1 on, 0 off), with in why$ the rule that decided it
' for the --debug line (empty for a plain run). Precedence: --no-telem always wins, then
' --telem cancels an implied off, then CLI_ImpliesNoTelem%. --telem leaves consent alone.
' Tokens are compared whole, so --telem is never found inside --no-telem.
Function CLI_TelemDecision% (cliLine As String, why As String)
    Dim cdRest As String, cdTok As String, cdPos As Integer
    Dim cdNo As Integer, cdYes As Integer, cdFlag As String
    cdRest = LTrim$(cliLine)
    Do While cdRest <> ""
        cdPos = InStr(cdRest, " ")
        If cdPos = 0 Then cdPos = Len(cdRest) + 1
        cdTok = Left$(cdRest, cdPos - 1)
        cdRest = LTrim$(Mid$(cdRest, cdPos + 1))
        If cdTok = "--no-telem" Then cdNo = -1
        If cdTok = "--telem" Then cdYes = -1
    Loop
    why = ""
    If cdNo Then
        CLI_TelemDecision% = 0
        If cdYes Then why = "off, --no-telem wins over --telem" Else why = "off, --no-telem"
        Exit Function
    End If
    If CLI_ImpliesNoTelem%(cliLine, cdFlag) = 0 Then
        CLI_TelemDecision% = -1
        If cdYes Then why = "on, --telem given, no dev flag to override"
    ElseIf cdYes Then
        CLI_TelemDecision% = -1
        why = "on, --telem overrides " + cdFlag
    Else
        CLI_TelemDecision% = 0
        why = "off, " + cdFlag + " implies --no-telem"
    End If
End Function
