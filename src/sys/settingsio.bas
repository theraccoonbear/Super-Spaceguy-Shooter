' settingsio.bas -- persistent settings: sss_settings.ini in the per-user settings dir (#284)
'
' settingsDir is where the file lives; sss.bas picks it at startup (the per-user dir, else the
' launch folder, else "" = read-only session, #283). SETTINGS_DirFor$ is the per-OS rule.

Const SETTINGS_FILE = "sss_settings.ini"

' The per-user settings dir for an OS (the _OS$ string), or "" when its base can't be told.
' sdXdg / sdAppData / sdHome are the XDG_CONFIG_HOME, APPDATA and HOME environment values.
Function SETTINGS_DirFor$ (sdOs As String, sdXdg As String, sdAppData As String, sdHome As String)
    SETTINGS_DirFor$ = ""
    If InStr(sdOs, "WIN") > 0 Then
        If Len(sdAppData) > 0 Then SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdAppData) + "\sss"
    ElseIf InStr(sdOs, "MAC") > 0 Then
        If Len(sdHome) > 0 Then SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdHome) + "/Library/Application Support/sss"
    Else
        If Left$(sdXdg, 1) = "/" Then
            SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdXdg) + "/sss"
        ElseIf Len(sdHome) > 0 Then
            SETTINGS_DirFor$ = SETTINGS_TrimSlash$(sdHome) + "/.config/sss"
        End If
    End If
End Function

Function SETTINGS_TrimSlash$ (tsPath As String)
    Dim tsOut As String : tsOut = tsPath
    Do While Len(tsOut) > 1 And (Right$(tsOut, 1) = "/" Or Right$(tsOut, 1) = "\")
        tsOut = Left$(tsOut, Len(tsOut) - 1)
    Loop
    SETTINGS_TrimSlash$ = tsOut
End Function

' The folder holding parPath, or "" when it has no parent left.
Function SETTINGS_Parent$ (parPath As String)
    Dim parI As Integer, parCh As String
    SETTINGS_Parent$ = ""
    For parI = Len(parPath) - 1 To 1 Step -1
        parCh = Mid$(parPath, parI, 1)
        If parCh = "/" Or parCh = "\" Then SETTINGS_Parent$ = Left$(parPath, parI - 1) : Exit Function
    Next parI
End Function

' First run in a new settings dir: copy an existing launch-folder file over, leaving the original.
' Returns -1 when it copied, 0 when there was nothing to do.
Function SETTINGS_Migrate% (smSrc As String, smDst As String)
    Dim smB As Integer, smData As String
    SETTINGS_Migrate% = 0
    If _FileExists(smDst) Or _FileExists(smSrc) = 0 Then Exit Function
    smData = _ReadFile$(smSrc)
    smB = FreeFile
    Open smDst For Binary As #smB
    Put #smB, , smData
    Close #smB
    SETTINGS_Migrate% = -1
End Function

Sub SETTINGS_Save ()
    If Len(settingsDir) = 0 Then Exit Sub
    SETTINGS_SaveFile settingsDir + "/" + SETTINGS_FILE
End Sub

Sub SETTINGS_SaveFile (sfsPath As String)
    Dim sfH As Integer, sfText As String, sfPos As Long, sfNl As Long
    If ioReadOnly Then Exit Sub
    sfText = SETTINGS_Serialize$
    sfH = FreeFile
    Open sfsPath For Output As #sfH
    sfPos = 1
    Do
        sfNl = InStr(sfPos, sfText, Chr$(10))
        If sfNl = 0 Then Exit Do
        Print #sfH, Mid$(sfText, sfPos, sfNl - sfPos)
        sfPos = sfNl + 1
    Loop
    Close #sfH
    If debugMode Then
        If camF.angleLocked Then
            DBG_Print "[settings] saved  cam_phi=" + LTrim$(Str$(camF.orbitPhi)) + "  cam_r=" + LTrim$(Str$(camF.orbitR))
        Else
            DBG_Print "[settings] saved"
        End If
    End If
End Sub

Sub SETTINGS_Load ()
    If Len(settingsDir) > 0 Then SETTINGS_LoadFile settingsDir + "/" + SETTINGS_FILE Else SETTINGS_LoadFile ""
    If Len(telemPlayerID) < 32 Then
        telemPlayerID = TELEM_NewUUID$
        SETTINGS_Save
    End If
    If Len(leaderboardPlayerID) < 32 Then
        leaderboardPlayerID = TELEM_NewUUID$
        SETTINGS_Save
    End If
    E3D_PadReselect
End Sub

Sub SETTINGS_LoadFile (sfPath As String)
    camF.orbitTheta = _PI(1.0) : camF.orbitPhi = CAM_DEFAULT_PHI : camF.orbitR = CAM_DEFAULT_R : camF.angleLocked = 0
    If Len(sfPath) > 0 And _FILEEXISTS(sfPath) Then
        SETTINGS_Parse _ReadFile$(sfPath)
        If debugMode Then
            If camF.angleLocked Then
                DBG_Print "[settings] loaded  cam_phi=" + LTrim$(Str$(camF.orbitPhi)) + "  cam_r=" + LTrim$(Str$(camF.orbitR))
            Else
                DBG_Print "[settings] loaded"
            End If
        End If
    Else
        settingTutorialDone = 0
    End If
End Sub
