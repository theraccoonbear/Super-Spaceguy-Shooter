' tutorialplay.bas -- the tutorial run's side of the step runner (#240)
'
' src/sys/tutorial.bas runs the script; this file is its link to the game:
'   TUT_Begin%        start the script for the tutorial block (GAME_StartTutorial)
'   TUT_Frame         once per flying frame: fill the runner's snapshot, step it, act on its requests
'   TUT_Draw          the HUD outline, the instructor's panel, the prompt and the waiver meter
'   TUT_NotePickup    a canister was caught (GS_PLAYING_PupGrab)
'   TUT_Finish        leave the tutorial: record tutorial_done, then New Game (gated) or the title
'   TUT_Abandon       leave through the pause menu's retreat: counts as skipped
'   TUT_StartFromTitle  the title's start: the tutorial first on a fresh install, else a New Game
' The instructor speaks through SPK_Say and shows the same text on screen; the narration skip
' key (ENTER, pad nova button) taps to skip a line and held 2 seconds files a waiver and leaves;
' N (pad roll button) skips to the next lesson.
' Local variable prefix: tg*

Const TUT_FEED_GAP = 90      ' frames between canisters / bolts fed to a WAIT
Const TUT_SHIP_GAP = 90      ' frames between streamed drones
Const TUT_SHOW_HOLD = 20     ' frames of holding before the waiver meter shows

Dim Shared tutShipN As Integer
Dim Shared tutLastShip As Long, tutLastFeed As Long
Dim Shared tutDodged As Long, tutGot(1 To 3) As Long, tutMoved As Single
Dim Shared tutPrevPY As Single, tutPrevPZ As Single, tutHavePrev As Integer
Dim Shared tutEbOn(1 To MAX_EBULLETS) As Integer, tutEbX(1 To MAX_EBULLETS) As Single
Dim Shared tutLsnWas As Integer
Dim Shared tutLeaving As Integer
Dim Shared tutStreamWas As Integer, tutFireWas As Integer
Dim Shared tutLoggedLesson As Integer
Dim Shared tutLoggedPc As Integer
Dim Shared tutShown(0 To 3) As String, tutShownN As Integer

Function TUT_Begin%
    Dim tgName As String, tgSrc As String, tgProb As String, tgDown As Integer
    tgName = LCase$(SEQ_GetKV$(seqSval$(seqIdx), "script"))
    Select Case tgName
        Case "tutorial" : tgSrc = _EMBEDDED$("TUTSCRIPT")
        Case Else
            seqLastError = "the tutorial block names no known script= ('" + tgName + "')"
            TUT_Begin% = 0 : Exit Function
    End Select
    If TUT_Parse%(tgSrc) = 0 Then tgProb = tutErrors Else tgProb = TUT_Validate$
    If Len(tgProb) > 0 Then
        seqLastError = "tutorial script: " + tgProb
        TUT_Begin% = 0 : Exit Function
    End If
    stageKillTarget = 2147483647   ' the script ends the run, not the combat kill count
    stageKills = 0
    TUT_Start
    tutShipN = 0 : tutLastShip = -9999 : tutLastFeed = -9999
    tutDodged = 0 : tutMoved = 0 : tutHavePrev = 0 : tutLsnWas = -1 : tutLeaving = 0
    tutStreamWas = 0 : tutFireWas = 0 : tutLoggedLesson = 0 : tutLoggedPc = -1 : tutShownN = 0
    tutGot(1) = 0 : tutGot(2) = 0 : tutGot(3) = 0
    TUT_ClearTracking
    tgDown = (held(E3D_KEY_ENTER) <> 0) Or (held(E3D_KEY_PAD_Y) <> 0)
    TUT_SkipReset tgDown
    TUT_Begin% = -1
End Function

Sub TUT_ClearTracking
    Dim tgI As Integer
    For tgI = 1 To MAX_EBULLETS : tutEbOn(tgI) = 0 : Next tgI
End Sub

Sub TUT_NotePickup (tgKind As Integer)
    If tutorialRun = 0 Then Exit Sub
    Select Case tgKind
        Case PUP_SHIELD : tutGot(1) = tutGot(1) + 1
        Case PUP_FUEL   : tutGot(2) = tutGot(2) + 1
        Case Else       : tutGot(3) = tutGot(3) + 1
    End Select
End Sub

' Everything the script put in play goes: a skipped lesson starts clean.
Sub TUT_Flush
    Dim tgI As Integer
    For tgI = 1 To MAX_ENEMIES   : enemies(tgI).active = 0 : enemyFireTimer(tgI) = 0 : Next tgI
    For tgI = 1 To MAX_EBULLETS  : ebullets(tgI).active = 0 : Next tgI
    For tgI = 1 To MAX_ASTEROIDS : asteroids(tgI).active = 0 : Next tgI
    For tgI = 1 To MAX_POWERUPS  : powerups(tgI).active = 0 : Next tgI
    TUT_ClearTracking
End Sub

Function TUT_ActiveShips%
    Dim tgI As Integer, tgN As Integer
    For tgI = 1 To MAX_ENEMIES
        If enemies(tgI).active Then tgN = tgN + 1
    Next tgI
    TUT_ActiveShips% = tgN
End Function

Sub TUT_PlaceShip (tgFire As Integer)
    Dim tgI As Integer, tgIdx As Integer
    For tgI = 1 To MAX_ENEMIES
        If enemies(tgI).active = 0 Then
            If tutShipN < 2 Then tgIdx = 0 Else tgIdx = (tutShipN - 1) Mod 6
            tutShipN = tutShipN + 1
            enemies(tgI).active = -1
            enemies(tgI).meshIdx = fTypeToMesh(tgIdx)
            enemies(tgI).px = player.px + 30
            enemies(tgI).py = player.py + (RNG!(RNG_GAME) * 2 - 1) * 4
            enemies(tgI).pz = player.pz + (RNG!(RNG_GAME) * 2 - 1) * 6
            enemies(tgI).vx = -0.07 * dlvFEnemySpeed
            enemies(tgI).vy = 0 : enemies(tgI).vz = 0
            enemies(tgI).rx = 0 : enemies(tgI).ry = 0 : enemies(tgI).rz = 0 : enemies(tgI).dry = 0
            enemies(tgI).scl = 1.0
            enemies(tgI).strafeCool = 9999
            If tgFire Then enemyFireTimer(tgI) = (1.5 + RNG!(RNG_GAME) * 1.5) * dlvFEnemyFire Else enemyFireTimer(tgI) = 99999
            Exit For
        End If
    Next tgI
End Sub

' One enemy bolt, 26 units out, aimed at where the ship is now.
Sub TUT_PlaceBolt
    Dim tgI As Integer, tgDX As Single, tgDY As Single, tgDZ As Single, tgMag As Single
    For tgI = 1 To MAX_EBULLETS
        If ebullets(tgI).active = 0 Then
            ebullets(tgI).active = -1
            ebullets(tgI).meshIdx = MESH_ENEMY
            ebullets(tgI).px = player.px + 26
            ebullets(tgI).py = player.py + (RNG!(RNG_GAME) * 2 - 1) * 5
            ebullets(tgI).pz = player.pz + (RNG!(RNG_GAME) * 2 - 1) * 7
            tgDX = player.px - ebullets(tgI).px
            tgDY = player.py - ebullets(tgI).py
            tgDZ = player.pz - ebullets(tgI).pz
            tgMag = SQR(tgDX * tgDX + tgDY * tgDY + tgDZ * tgDZ)
            ebullets(tgI).vx = tgDX / tgMag * EBULLET_SPEED
            ebullets(tgI).vy = tgDY / tgMag * EBULLET_SPEED
            ebullets(tgI).vz = tgDZ / tgMag * EBULLET_SPEED
            ebullets(tgI).scl = 1.0
            Exit For
        End If
    Next tgI
End Sub

Sub TUT_PlaceAsteroid
    Dim tgI As Integer
    For tgI = 1 To MAX_ASTEROIDS
        If asteroids(tgI).active = 0 Then
            asteroids(tgI).active = -1
            asteroids(tgI).meshIdx = MESH_ASTEROID
            asteroids(tgI).px = player.px + 40
            asteroids(tgI).py = player.py + (RNG!(RNG_GAME) * 2 - 1) * 1.5
            asteroids(tgI).pz = player.pz + (RNG!(RNG_GAME) * 2 - 1) * 1.5
            asteroids(tgI).vx = -0.2 : asteroids(tgI).vy = 0 : asteroids(tgI).vz = 0
            asteroids(tgI).drx = 0.6 : asteroids(tgI).dry = 0.9 : asteroids(tgI).drz = 0.3
            asteroids(tgI).scl = 1.4
            asteroids(tgI).life = 0
            asteroids(tgI).strafeCool = 0
            Exit For
        End If
    Next tgI
End Sub

Sub TUT_PlacePup (tgKind As Integer)
    Dim tgI As Integer
    For tgI = 1 To MAX_POWERUPS
        If powerups(tgI).active = 0 Then
            powerups(tgI).active = -1
            powerups(tgI).meshIdx = WAVE_PupMesh%(tgKind)
            powerups(tgI).px = player.px + 24
            powerups(tgI).py = player.py + (RNG!(RNG_GAME) * 2 - 1) * 1.5
            powerups(tgI).pz = player.pz + (RNG!(RNG_GAME) * 2 - 1) * 2.5
            powerups(tgI).vx = -pupSpeed
            powerups(tgI).rx = 0 : powerups(tgI).ry = 0 : powerups(tgI).rz = 0
            powerups(tgI).drx = 0 : powerups(tgI).dry = 0 : powerups(tgI).drz = 0
            If powerups(tgI).meshIdx = MESH_PUP_POINTS Then powerups(tgI).drx = 3.0 Else powerups(tgI).dry = 2.0 : powerups(tgI).rz = 15
            powerups(tgI).scl = 1.0
            Exit For
        End If
    Next tgI
End Sub

Sub TUT_Place (tgType As String, tgFire As Integer)
    Select Case tgType
        Case "ship"     : TUT_PlaceShip tgFire
        Case "bolt"     : TUT_PlaceBolt
        Case "asteroid" : TUT_PlaceAsteroid
        Case "shield"   : TUT_PlacePup PUP_SHIELD
        Case "fuel"     : TUT_PlacePup PUP_FUEL
        Case "points"   : TUT_PlacePup PUP_POINTS
    End Select
End Sub

Sub TUT_Speak (tgKey As String)
    Dim tgTxt As String
    tgTxt = TUT_Text$(tgKey)
    TUT_Wrap tgTxt, TUT_WRAP_W, tutShown(), tutShownN
    SPK_Say tgTxt
    SPK_SetPreset settingNarrSpeed
End Sub

Function TUT_PupIdx% (tgMesh As Integer)
    Select Case WAVE_PupKind%(tgMesh)
        Case PUP_SHIELD : TUT_PupIdx% = 1
        Case PUP_FUEL   : TUT_PupIdx% = 2
        Case Else       : TUT_PupIdx% = 3
    End Select
End Function

' Fills the runner's snapshot from the game.
Sub TUT_Snapshot
    Dim tgI As Integer, tgDY As Single, tgDZ As Single
    If tutHavePrev Then
        tgDY = player.py - tutPrevPY : tgDZ = player.pz - tutPrevPZ
        tutMoved = tutMoved + SQR(tgDY * tgDY + tgDZ * tgDZ)
    End If
    tutPrevPY = player.py : tutPrevPZ = player.pz : tutHavePrev = -1
    ' a bolt that left play well behind the ship went past; one that left at the ship hit it
    tutInBolts = 0
    For tgI = 1 To MAX_EBULLETS
        If tutEbOn(tgI) And ebullets(tgI).active = 0 Then
            If tutEbX(tgI) < player.px - 4 Then tutDodged = tutDodged + 1
        End If
        tutEbOn(tgI) = ebullets(tgI).active
        tutEbX(tgI) = ebullets(tgI).px
        If ebullets(tgI).active Then tutInBolts = tutInBolts + 1
    Next tgI
    tutInHazards = 0
    For tgI = 1 To MAX_ASTEROIDS
        If asteroids(tgI).active Then tutInHazards = tutInHazards + 1
    Next tgI
    tutInPups(1) = 0 : tutInPups(2) = 0 : tutInPups(3) = 0
    For tgI = 1 To MAX_POWERUPS
        If powerups(tgI).active Then tutInPups(TUT_PupIdx%(powerups(tgI).meshIdx)) = tutInPups(TUT_PupIdx%(powerups(tgI).meshIdx)) + 1
    Next tgI
    tutInMoved = tutMoved
    tutInOrbit = (camF.orbitMode <> 0)
    tutInShots = telemShotsFired
    tutInHits = telemShotsHit
    tutInKills = stageKills
    tutInDodged = tutDodged
    For tgI = 1 To 3 : tutInGot(tgI) = tutGot(tgI) : Next tgI
    tutInSpeaking = (SPK_IsPlaying% <> 0)
End Sub

Sub TUT_Frame
    Dim tgSkip As Integer, tgDown As Integer, tgLsn As Integer, tgNeed As Long, tgI As Integer
    If tutorialRun = 0 Then tutActive = 0 : tutLeaving = 0 : Exit Sub
    If tutActive = 0 And tutLeaving = 0 Then Exit Sub
    If gameState <> GS_PLAYING Then Exit Sub

    If tutLeaving Then
        If SPK_IsPlaying% = 0 Then TUT_Finish
        Exit Sub
    End If

    tgDown = (held(E3D_KEY_ENTER) <> 0) Or (held(E3D_KEY_PAD_Y) <> 0)
    tgSkip = TUT_SkipTick%(tgDown)
    tgLsn = KEY_Down%(78) Or KEY_Down%(110) Or held(E3D_KEY_PAD_X)
    tutInSkipLesson = (tgLsn <> 0 And tutLsnWas = 0)
    tutLsnWas = (tgLsn <> 0)
    tutInSkipLine = (tgSkip = TUT_SKIP_TAP)

    If tgSkip = TUT_SKIP_EXIT Then
        tutActive = 0 : tutLeaving = -1
        SPK_Say ""
        tutSayKey = "tut_waiver"
        TUT_Speak "tut_waiver"
        DBG_MilestoneWrite LTrim$(Str$(gameFrame)) + " TUT waiver"
        Exit Sub
    End If

    TUT_Snapshot
    TUT_Tick

    If tutOutFlush Then TUT_Flush
    If tutOutSilence Then SPK_Say ""
    If Len(tutOutSay) > 0 Then TUT_Speak tutOutSay
    If Len(tutOutSpawn) > 0 Then
        For tgI = 1 To tutOutSpawnN
            TUT_Place tutOutSpawn, 0
        Next tgI
    End If
    If Len(tutOutFeed) > 0 Then
        If gameFrame - tutLastFeed >= TUT_FEED_GAP Then
            TUT_Place tutOutFeed, 0
            tutLastFeed = gameFrame
        End If
    End If

    If tutStreamOn Then
        tgNeed = tutStreamKills - stageKills
        If TUT_ActiveShips% < 2 And TUT_ActiveShips% < tgNeed And gameFrame - tutLastShip >= TUT_SHIP_GAP Then
            TUT_Place "ship", tutStreamFire
            tutLastShip = gameFrame
        End If
        If tutStreamFire And tutFireWas = 0 Then
            For tgI = 1 To MAX_ENEMIES
                If enemies(tgI).active Then enemyFireTimer(tgI) = (1.5 + RNG!(RNG_GAME) * 1.5) * dlvFEnemyFire
            Next tgI
        End If
        tutFireWas = tutStreamFire
    ElseIf tutStreamWas Then
        tutFireWas = 0
        If stageKills >= tutStreamKills Then
            For tgI = 1 To MAX_ENEMIES
                If enemies(tgI).active Then
                    FX_SpawnBurst enemies(tgI).px, enemies(tgI).py, enemies(tgI).pz, 12, 0.28, 20, 10, _RGB(160, 230, 255)
                    enemies(tgI).active = 0
                End If
            Next tgI
        End If
    End If
    tutStreamWas = tutStreamOn

    If tutPc <> tutLoggedPc Then
        tutLoggedPc = tutPc
        If tutPc < tutCount Then DBG_MilestoneWrite LTrim$(Str$(gameFrame)) + " STEP line " + LTrim$(Str$(tutLineNo(tutPc))) + " " + tutKey(tutPc) + " " + tutWaitKind
    End If
    If tutLesson <> tutLoggedLesson Then
        tutLoggedLesson = tutLesson
        DBG_MilestoneWrite LTrim$(Str$(gameFrame)) + " TUT lesson " + LTrim$(Str$(tutLesson)) + " " + tutLessonKey
    End If

    If tutDone Then
        DBG_MilestoneWrite LTrim$(Str$(gameFrame)) + " TUT done"
        TUT_Finish
    End If
End Sub

' The tutorial ends: tutorial_done is saved. Gated, the player goes straight on to a New Game;
' otherwise back to the title. SEQ_RewindToTitle first, so the New Game starts from the title
' waypoint (stage 1) and not from the top of the sequence.
Sub TUT_Finish
    Dim tgGated As Integer
    tgGated = tutGated
    settingTutorialDone = -1 : SETTINGS_Save
    tutGated = 0 : tutActive = 0 : tutLeaving = 0
    SPK_Say ""
    TUT_Flush
    SEQ_RewindToTitle
    If tgGated Then
        GAME_NewGame
    Else
        gameState = GS_TITLE
        MUS_SetCue "title"
    End If
End Sub

Sub TUT_Abandon
    settingTutorialDone = -1 : SETTINGS_Save
    tutGated = 0 : tutActive = 0 : tutLeaving = 0
End Sub

' The title's start (LAUNCH NOW? confirmed): the tutorial first on a fresh install, else a New Game.
Sub TUT_StartFromTitle
    If TUT_GateDue%(settingTutorialDone, iscActive, cliScene, ioReadOnly) Then
        tutGated = -1
        If GAME_StartTutorial% Then Exit Sub
        tutGated = 0
    End If
    GAME_NewGame
End Sub

' --- drawing ---

Sub TUT_Outline (toX1 As Integer, toY1 As Integer, toX2 As Integer, toY2 As Integer)
    Dim toA As Integer
    toA = 150 + INT(105 * SIN(tt * 12))
    LINE (toX1 - 1, toY1 - 1)-(toX2 + 1, toY2 + 1), _RGBA(0, 0, 0, 200), B
    LINE (toX1, toY1)-(toX2, toY2), _RGBA(255, 230, 60, toA), B
    LINE (toX1 - 2, toY1 - 2)-(toX2 + 2, toY2 + 2), _RGBA(255, 230, 60, toA \ 2), B
End Sub

Sub TUT_DrawHighlight
    Dim tgBX As Integer, tgY As Integer, tgLen As Integer, tgStr As String
    If Len(tutHL) = 0 Then Exit Sub
    tgBX = scrW - 6 - UPG_BAR_MAX
    Select Case tutHL
        Case "sh", "la", "fu"
            Select Case tutHL
                Case "sh" : tgY = 4 : tgLen = UPG_BarLen%((shieldMax))
                Case "la" : tgY = 15 : tgLen = UPG_BarLen%((laserMax))
                Case Else : tgY = 26 : tgLen = UPG_BarLen%((fuelMax))
            End Select
            TUT_Outline tgBX - 21, tgY - 1, tgBX + tgLen + 5, tgY + 11
        Case "score"
            tgStr = "SCORE: " + LTRIM$(STR$(score)) + " $" + LTRIM$(STR$(credits))
            TUT_Outline 2, 2, 6 + LEN(tgStr) * FONT_CHAR_W, 4 + FONT_CHAR_H
        Case "hi"
            tgStr = "HI: " + LTRIM$(STR$(highScore))
            TUT_Outline scrW - LEN(tgStr) * FONT_CHAR_W - 4, scrH - FONT_CHAR_H - 1, scrW - 1, scrH - 1
        Case "lives"
            TUT_Outline 1, scrH - 14, 31, scrH - 2
        Case "reticle"
            CIRCLE (hudRetX, hudRetY), 13, _RGBA(0, 0, 0, 200)
            CIRCLE (hudRetX, hudRetY), 12, _RGBA(255, 230, 60, 150 + INT(105 * SIN(tt * 12)))
            CIRCLE (hudRetX, hudRetY), 14, _RGBA(255, 230, 60, 90)
    End Select
End Sub

' The prompt for the thing the player is being asked to do, "" when none.
Function TUT_Prompt$
    Select Case tutWaitCond
        Case TUT_C_MOVE   : TUT_Prompt$ = "FLY: ARROWS, WASD OR STICK"
        Case TUT_C_CAMERA : TUT_Prompt$ = UI_Tok$("TAB", E3D_ACT_CAMERA) + " CAMERA MODE, AGAIN TO LOCK"
        Case TUT_C_SHOOT, TUT_C_HIT, TUT_C_KILLS : TUT_Prompt$ = UI_Tok$("SPACE", E3D_ACT_FIRE) + " HOLD TO FIRE"
        Case TUT_C_DODGE  : TUT_Prompt$ = "DODGE: CHANGE DIRECTION"
        Case TUT_C_PICKUP : TUT_Prompt$ = "FLY INTO THE " + UCase$(tutWaitKind) + " CANISTER"
        Case TUT_C_CLEAR  : TUT_Prompt$ = "STEER CLEAR OF THE ASTEROID"
        Case Else         : TUT_Prompt$ = ""
    End Select
End Function

Sub TUT_Draw
    Dim tgI As Integer, tgHdr As String, tgP As String, tgHint As String, tgW As Integer, tgFill As Integer, tgDev As Integer
    If tutorialRun = 0 Or gameState <> GS_PLAYING Then Exit Sub
    If tutActive = 0 And tutLeaving = 0 Then Exit Sub
    _DEST backBuffer
    TUT_DrawHighlight

    tgDev = INP_LastDevice%
    If tutLeaving = 0 Then
        tgP = TUT_Prompt$
        If Len(tgP) > 0 Then
            tgW = UI_PromptsW%(tgP, tgDev)
            UI_PromptsAt tgP, tgDev, (scrW - tgW) \ 2, 136, 14, 255, 1
        END IF
    END IF

    If Len(tutSayKey) > 0 Then
        UI_Panel 6, 154, scrW - 7, 206
        tgHdr = "ORIENTATION UNIT"
        If tutLesson > 0 And tutLeaving = 0 Then tgHdr = "LESSON " + LTrim$(Str$(tutLesson)) + "/" + LTrim$(Str$(tutLessonCount)) + "  " + TUT_Text$(tutLessonKey)
        If Len(tgHdr) > 36 Then tgHdr = Left$(tgHdr, 36)
        FONT_PrintAlpha fontPalette(11), backBuffer, tgHdr, 14, 156, 255
        For tgI = 0 To tutShownN - 1
            If tgI < 2 Then UI_Text 15, tutShown(tgI), 14, 172 + tgI * 16, 255
        Next tgI
    End If

    If tutLeaving = 0 Then
        tgHint = UI_Tok$("ENTER", E3D_ACT_NOVA) + " SKIP LINE  " + UI_Tok$("N", E3D_ACT_ROLL) + " LESSON"
        tgW = UI_PromptsW%(tgHint, tgDev)
        UI_PromptsAt tgHint, tgDev, (scrW - tgW) \ 2, 208, 8, 255, 0
        tgHint = "HOLD " + UI_Tok$("ENTER", E3D_ACT_NOVA) + " 2S: LEAVE"
        tgW = UI_PromptsW%(tgHint, tgDev)
        UI_PromptsAt tgHint, tgDev, (scrW - tgW) \ 2, 223, 8, 255, 0
        If tutSkHeld >= TUT_SHOW_HOLD Then
            tgFill = tutSkHeld * 100 \ TUT_HOLD_FRAMES
            UI_Panel scrW \ 2 - 60, 100, scrW \ 2 + 60, 124
            UI_TextCentered 14, "FILING WAIVER", 102, 255
            LINE (scrW \ 2 - 50, 118)-(scrW \ 2 + 50, 122), _RGB(15, 20, 30), BF
            LINE (scrW \ 2 - 50, 118)-(scrW \ 2 - 50 + tgFill, 122), _RGB(255, 200, 40), BF
            LINE (scrW \ 2 - 50, 118)-(scrW \ 2 + 50, 122), _RGB(70, 90, 100), B
        End If
    End If
End Sub
