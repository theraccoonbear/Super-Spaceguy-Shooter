' Writes a line to the CLI output stream. On Windows the QB64-PE console has no
' Win32 CON: device to OPEN, so output must go through _DEST _CONSOLE + PRINT
' instead of a file handle; the caller is expected to have already done
' _CONSOLE ON / _DEST _CONSOLE on Windows before calling this.
Sub CLI_Emit(ceFH As Integer, ceMsg As String)
    If InStr(_OS$, "WIN") Then
        Print ceMsg
    Else
        Print #ceFH, ceMsg
    End If
End Sub

Sub CLI_Parse()
    Dim cliLine As String : cliLine = Command$
    Dim cliFH As Integer
    Dim cliPos As Integer, cliI As Integer

    If InStr(cliLine, "--version") > 0 Or cliLine = "-v" Or Left$(cliLine, 3) = "-v " Then
        cliFH = FreeFile
        If InStr(_OS$, "WIN") Then
            _Console On
            _Dest _Console
        Else
            Open "/dev/stdout" For Output As #cliFH
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
    telemOn     = (InStr(cliLine, "--telem") > 0)

    cliPos = InStr(cliLine, "--scene ")
    If cliPos > 0 Then
        cliScene = Mid$(cliLine, cliPos + 8)
        cliPos = InStr(cliScene, " ")
        If cliPos > 0 Then cliScene = Left$(cliScene, cliPos - 1)
        cliScene = LTrim$(RTrim$(cliScene))
    End If

    If cliScene <> "" Then
        cliI = Len(cliScene)
        Do While cliI > 0
            If Mid$(cliScene, cliI, 1) >= "0" And Mid$(cliScene, cliI, 1) <= "9" Then cliI = cliI - 1 Else Exit Do
        Loop
        cliSceneType = LCase$(Left$(cliScene, cliI))
        If cliSceneType <> "title" And cliSceneType <> "crawl" And cliSceneType <> "playing" And cliSceneType <> "boss" Then
            GAME_Usage("unknown scene type '" + cliSceneType + "'")
        End If
    End If
End Sub
