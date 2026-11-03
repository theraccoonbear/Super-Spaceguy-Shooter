' thruster.bas -- the player's engine sound: thrust demand, config and --thruster-dev (#402)
'
' The voice itself (hum, body timbres, smoothing) lives in snd.bas (SND_ThrusterFrame,
' SND_RumbleNext!) so the mixer tests need nothing from the game. This file feeds it:
'   THR_Load       read assets/config/thruster.ini (cfgThruster) into the thr* values
'   THR_Update     once per frame of play: the thrust demand from the ship's speed and how fast
'                  that speed is changing, handed to SND_ThrusterFrame
'   THR_DevFrame / THR_DevDraw   --thruster-dev: nudge keys, reload from disk, on-screen readout
'
' --thruster-dev keys (in play), each nudge repeats while held:
'   1 / 2  rumble level - / +        3 / 4  rumble cutoff range - / +
'   5 / 6  hum pitch range - / +     7 / 8  attack - / +      9 / 0  release - / +
'   \      re-read assets/config/thruster.ini from disk
'   =      next timbre (BRN brown noise + sub, JET band-passed whoosh, SAW detuned saws)
'   readout: one line per tunable, left edge: RL body level, CO cutoff, HP hum pitch, AT attack, RE release, TB timbre
'
' Local variable prefix: thr*

Const THR_DEV_FILE = "assets/config/thruster.ini"
Const THR_NOTE_FRAMES = 90
Const THR_DEV_TOP = 24
Const THR_REPEAT_DELAY = 20
Const THR_REPEAT_EVERY = 3

Dim Shared cfgThruster As String
Dim Shared thrPrevVY As Single, thrPrevVZ As Single
Dim Shared thrHeld(0 To 11) As Integer
Dim Shared thrMsg As String, thrMsgAt As Long
Dim Shared thrRaw As Single

Sub THR_Num (thnStore As String, thnKey As String, thnV As Single)
    Dim thnS As String
    thnS = CFG_Get$(thnStore, thnKey)
    If thnS <> "" Then thnV = Val(thnS)
End Sub

' Set every thr* value from a parsed thruster.ini; a missing key keeps its current value.
Sub THR_Load (thlStore As String)
    Dim thlT As String
    THR_Num thlStore, "attack_ms", thrAttackMs
    THR_Num thlStore, "release_ms", thrReleaseMs
    THR_Num thlStore, "speed_weight", thrSpeedW
    THR_Num thlStore, "accel_weight", thrAccelW
    THR_Num thlStore, "hum_pitch_min", thrHumPitchMin
    THR_Num thlStore, "hum_pitch_max", thrHumPitchMax
    THR_Num thlStore, "hum_amp_idle", thrHumAmpIdle
    THR_Num thlStore, "hum_amp_max", thrHumAmpMax
    THR_Num thlStore, "rumble_level", thrRumbleLevel
    THR_Num thlStore, "rumble_idle", thrRumbleIdle
    THR_Num thlStore, "cutoff_min", thrCutMin
    THR_Num thlStore, "cutoff_max", thrCutMax
    THR_Num thlStore, "speech_duck", thrDuck
    THR_Num thlStore, "smooth_ms", thrSmoothMs
    thlT = LCase$(CFG_Get$(thlStore, "timbre"))
    If thlT = "brn" Then SND_ThrusterTimbre 0
    If thlT = "jet" Then SND_ThrusterTimbre 1
    If thlT = "saw" Then SND_ThrusterTimbre 2
End Sub

' The frame's raw thrust demand (0..1) for a ship moving at (thdVY, thdVZ) that changed by
' (thdDY, thdDZ) since the last frame, and whether that change is a sudden direction change.
' Speed and change are measured against the top speed and the most one frame can change it
' (PLAYER_ACCEL of a full reversal's 2x), so a start from rest reads 1 and a reversal 2.
Function THR_RawDemand! (thdVY As Single, thdDY As Single, thdVZ As Single, thdDZ As Single, thdMax As Single, thdChange As Single)
    Dim thdSpd As Single, thdAcc As Single, thdRaw As Single
    If thdMax < 0.0001 Then thdMax = 0.0001
    thdSpd = Sqr(thdVY * thdVY + thdVZ * thdVZ) / thdMax
    If thdSpd > 1 Then thdSpd = 1
    thdAcc = Sqr(thdDY * thdDY + thdDZ * thdDZ) / (thdMax * PLAYER_ACCEL)
    thdChange = thdAcc
    If thdAcc > 1 Then thdAcc = 1
    thdRaw = thrSpeedW * thdSpd + thrAccelW * thdAcc
    If thdRaw > 1 Then thdRaw = 1
    If thdRaw < 0 Then thdRaw = 0
    THR_RawDemand! = thdRaw
End Function

' Once per frame of play, after PLAYER_Update, before the audio fill.
Sub THR_Update
    Dim thuChange As Single, thuRaw As Single
    thuRaw = THR_RawDemand!(playerVY, playerVY - thrPrevVY, playerVZ, playerVZ - thrPrevVZ, shipMaxVel, thuChange)
    thrPrevVY = playerVY : thrPrevVZ = playerVZ
    If fuelStranded Then thuRaw = 0 : thuChange = 0
    thrRaw = thuRaw
    SND_ThrusterFrame thuRaw
End Sub

' --- --thruster-dev ---

Function THR_DevPath$ ()
    Dim thpA As String
    thpA = _StartDir$ + "/" + THR_DEV_FILE
    If _FileExists(thpA) Then THR_DevPath$ = thpA : Exit Function
    thpA = _Cwd$ + "/../" + THR_DEV_FILE
    If _FileExists(thpA) Then THR_DevPath$ = thpA : Exit Function
    THR_DevPath$ = ""
End Function

Sub THR_DevReload
    Dim thrPath As String
    thrPath = THR_DevPath$
    If thrPath = "" Then
        thrMsg = "\: " + THR_DEV_FILE + " not found (launch from the repository folder)"
    Else
        THR_Load CFG_Parse$(_ReadFile$(thrPath))
        thrMsg = "reloaded from disk"
    End If
    thrMsgAt = gameFrame
End Sub

Function THR_Clamp! (thcV As Single, thcLo As Single, thcHi As Single)
    If thcV < thcLo Then thcV = thcLo
    If thcV > thcHi Then thcV = thcHi
    THR_Clamp! = thcV
End Function

' Apply one nudge (thnDir -1 or +1) for key group thnGrp.
Sub THR_Nudge (thnGrp As Integer, thnDir As Integer)
    Select Case thnGrp
    Case 0: thrRumbleLevel = THR_Clamp!(thrRumbleLevel + 0.05 * thnDir, 0, 3)
    Case 1
        thrCutMin = THR_Clamp!(thrCutMin * (1 + 0.06 * thnDir), 10, 2000)
        thrCutMax = THR_Clamp!(thrCutMax * (1 + 0.06 * thnDir), 10, 4000)
    Case 2: thrHumPitchMax = THR_Clamp!(thrHumPitchMax + 5 * thnDir, thrHumPitchMin, 600)
    Case 3: thrAttackMs = THR_Clamp!(thrAttackMs + 10 * thnDir, 1, 2000)
    Case 4: thrReleaseMs = THR_Clamp!(thrReleaseMs + 20 * thnDir, 1, 4000)
    End Select
End Sub

' Once per frame of play.
Sub THR_DevFrame
    Dim thfI As Integer, thfDown As Integer, thfGrp As Integer, thfDir As Integer, thfFire As Integer
    Dim thfCode As Integer
    If cliThrusterDev = 0 Then Exit Sub
    For thfI = 0 To 9
        thfGrp = thfI \ 2
        thfDir = -1 + 2 * (thfI Mod 2)
        thfCode = 49 + thfI
        If thfI = 9 Then thfCode = 48
        thfDown = KEY_Down%(thfCode)
        thfFire = 0
        If thfDown Then
            thrHeld(thfI) = thrHeld(thfI) + 1
            If thrHeld(thfI) = 1 Then thfFire = -1
            If thrHeld(thfI) > THR_REPEAT_DELAY And (thrHeld(thfI) - THR_REPEAT_DELAY) Mod THR_REPEAT_EVERY = 0 Then thfFire = -1
        Else
            thrHeld(thfI) = 0
        End If
        If thfFire Then THR_Nudge thfGrp, thfDir
    Next thfI
    thfDown = KEY_Down%(92)
    If thfDown Then thrHeld(10) = thrHeld(10) + 1 Else thrHeld(10) = 0
    If thrHeld(10) = 1 Then THR_DevReload
    If KEY_Down%(61) Then thrHeld(11) = thrHeld(11) + 1 Else thrHeld(11) = 0
    If thrHeld(11) = 1 Then SND_ThrusterTimbre thrTimbre + 1
End Sub

Function THR_F$ (thfV As Single, thfPlaces As Integer)
    Dim thfS As String
    thfS = LTrim$(Str$(Int(thfV * 10 ^ thfPlaces + 0.5) / 10 ^ thfPlaces))
    If Left$(thfS, 1) = "." Then thfS = "0" + thfS
    THR_F$ = thfS
End Function

Sub THR_DevLine (thlRow As Integer, thlTxt As String)
    Dim thlY As Long
    thlY = THR_DEV_TOP + thlRow * FONT_CHAR_H
    Line (0, thlY)-(Len(thlTxt) * FONT_CHAR_W + 1, thlY + FONT_CHAR_H - 1), _RGBA(0, 0, 0, 200), BF
    FONT_PrintAlpha fontPalette(14), backBuffer, thlTxt, 1, thlY, 255
End Sub

Sub THR_DevDraw
    If cliThrusterDev = 0 Then Exit Sub
    _Dest backBuffer
    THR_DevLine 0, "DM " + THR_F$(thrDemand, 2)
    THR_DevLine 1, "RL 1/2 " + THR_F$(thrRumbleLevel, 2)
    THR_DevLine 2, "CO 3/4 " + THR_F$(thrCutMin, 0) + "-" + THR_F$(thrCutMax, 0)
    THR_DevLine 3, "HP 5/6 " + THR_F$(thrHumPitchMin, 0) + "-" + THR_F$(thrHumPitchMax, 0)
    THR_DevLine 4, "AT 7/8 " + THR_F$(thrAttackMs, 0)
    THR_DevLine 5, "RE 9/0 " + THR_F$(thrReleaseMs, 0)
    THR_DevLine 6, "TB = " + Mid$("BRNJETSAW", thrTimbre * 3 + 1, 3)
    THR_DevLine 7, "\ reload"
    If Len(thrMsg) > 0 And gameFrame - thrMsgAt < THR_NOTE_FRAMES Then UI_Text 10, thrMsg, 1, THR_DEV_TOP + 8 * FONT_CHAR_H, 255
End Sub
