Sub CLI_Parse()
    Dim cliLine As String : cliLine = Command$
    Dim cliFH As Integer
    Dim cliPos As Integer, cliI As Integer, cliVal As String
    Dim cliNumOk As Integer

    If InStr(cliLine, "--version") > 0 Or cliLine = "-v" Or Left$(cliLine, 3) = "-v " Then
        cliFH = FreeFile
        If InStr(_OS$, "WIN") Then
            _Console On
            _Dest _Console
        Else
            Open "/dev/stdout" For Append As #cliFH
        End If
        CLI_Emit cliFH, "Super Spaceguy Shooter " + VERSION$
        If InStr(_OS$, "WIN") = 0 Then Close #cliFH
        System
    End If

    If InStr(cliLine, "--help") > 0 Or cliLine = "-h" Or Left$(cliLine, 3) = "-h " Then
        GAME_Usage("")
    End If

    godMode     = (InStr(cliLine, "--god")   > 0)
    settingNerf = (InStr(cliLine, "--nerf")  > 0)
    debugMode   = (InStr(cliLine, "--debug") > 0)
    telemOn     = (InStr(cliLine, "--no-telem") = 0)
    cliCrawls   = (InStr(cliLine, "--crawls") > 0)

    cliPos = InStr(cliLine, "--scene ")
    If cliPos > 0 Then
        cliScene = Mid$(cliLine, cliPos + 8)
        cliPos = InStr(cliScene, " ")
        If cliPos > 0 Then cliScene = Left$(cliScene, cliPos - 1)
        cliScene = LTrim$(RTrim$(cliScene))
    End If

    ' --input-script <file> (no spaces in the path), --frames N, --seed N
    cliVal = CLI_Value$(cliLine, "--input-script ")
    If cliVal <> "" Then
        ' the process runs from the executable's folder; relative paths mean the launch folder
        If Left$(cliVal, 1) <> "/" And Mid$(cliVal, 2, 1) <> ":" Then cliVal = _StartDir$ + "/" + cliVal
        If ISC_Load%(cliVal) = 0 Then GAME_Usage(iscError)
    End If
    ' --leaderboard-file <file>: a canned top_scores response, parsed as if the poll returned it
    cliVal = CLI_Value$(cliLine, "--leaderboard-file ")
    If cliVal <> "" Then
        If Left$(cliVal, 1) <> "/" And Mid$(cliVal, 2, 1) <> ":" Then cliVal = _StartDir$ + "/" + cliVal
        If _FileExists(cliVal) = 0 Then GAME_Usage("leaderboard file not found: " + cliVal)
        LBRD_Parse _ReadFile$(cliVal)
    End If
    cliVal = CLI_Value$(cliLine, "--frames ")
    If cliVal <> "" Then
        If ISC_IsNum%(cliVal) = 0 Then GAME_Usage("--frames needs a whole number, got '" + cliVal + "'")
        cliFrames = Val(cliVal)
    End If
    cliVal = CLI_Value$(cliLine, "--credits ")
    If cliVal <> "" Then
        If CR_ParseArg%(cliVal, cliCredits) = 0 Then GAME_Usage("--credits needs a whole number 0 or more, got '" + cliVal + "'")
    End If
    cliVal = CLI_Value$(cliLine, "--ships ")
    If cliVal <> "" Then
        cliNumOk = CR_ParseArg%(cliVal, cliShips)
        If cliNumOk = 0 Or cliShips < 1 Then GAME_Usage("--ships needs a whole number 1 or more, got '" + cliVal + "'")
    End If
    cliVal = CLI_Value$(cliLine, "--shields ")
    If cliVal <> "" Then
        cliNumOk = CR_ParseArg%(cliVal, cliShields)
        If cliNumOk = 0 Or cliShields < 1 Then GAME_Usage("--shields needs a whole number 1 or more, got '" + cliVal + "'")
    End If
    cliVal = CLI_Value$(cliLine, "--seed ")
    If cliVal <> "" Then
        If ISC_IsNum%(cliVal) = 0 Then GAME_Usage("--seed needs a whole number, got '" + cliVal + "'")
        cliSeed = Val(cliVal) : cliSeedSet = -1
    End If
    ' seed every random stream before anything draws (sound tables, the player id)
    If cliSeedSet Then RNG_Seed cliSeed Else RNG_Seed RNG_ClockSeed~&

    cliVal = CLI_Value$(cliLine, "--screenshot-at ")
    Do While cliVal <> ""
        cliPos = InStr(cliVal, ",")
        If cliPos = 0 Then cliPos = Len(cliVal) + 1
        If ISC_IsNum%(Left$(cliVal, cliPos - 1)) = 0 Then GAME_Usage("--screenshot-at needs frame numbers like 300,900, got '" + Left$(cliVal, cliPos - 1) + "'")
        If cliShotN >= UBound(cliShotAt) Then GAME_Usage("--screenshot-at takes at most" + Str$(UBound(cliShotAt)) + " frames")
        cliShotN = cliShotN + 1
        cliShotAt(cliShotN) = Val(Left$(cliVal, cliPos - 1))
        cliVal = Mid$(cliVal, cliPos + 1)
    Loop

    If LCase$(Left$(cliScene, 6)) = "crawl:" Then
        cliSceneType = "crawl:"
    ElseIf cliScene <> "" Then
        cliI = Len(cliScene)
        Do While cliI > 0
            If Mid$(cliScene, cliI, 1) >= "0" And Mid$(cliScene, cliI, 1) <= "9" Then cliI = cliI - 1 Else Exit Do
        Loop
        cliSceneType = LCase$(Left$(cliScene, cliI))
        If cliSceneType <> "title" And cliSceneType <> "crawl" And cliSceneType <> "playing" And cliSceneType <> "boss" And cliSceneType <> "dock" And cliSceneType <> "consent" And cliSceneType <> "username" Then
            GAME_Usage("unknown scene type '" + cliSceneType + "'")
        End If
    End If
End Sub

' The word after cvFlag$ (which includes its trailing space) in cvLine$, or "".
Function CLI_Value$(cvLine As String, cvFlag As String)
    Dim cvPos As Integer, cvV As String
    CLI_Value$ = ""
    cvPos = InStr(cvLine, cvFlag)
    If cvPos = 0 Then Exit Function
    cvV = LTrim$(Mid$(cvLine, cvPos + Len(cvFlag)))
    cvPos = InStr(cvV, " ")
    If cvPos > 0 Then cvV = Left$(cvV, cvPos - 1)
    CLI_Value$ = cvV
End Function
