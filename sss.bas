' ============================================================
' Super Spaceguy Shooter  —  sss.bas
' https://github.com/theraccoonbear/Super-Spaceguy-Shooter
' Copyright (C) 2024-2026 theraccoonbear
' SPDX-License-Identifier: GPL-3.0-or-later
' ============================================================
' 3rd person pseudo-rail 3D space shooter
' Player moves freely in Y/Z (up/down, left/right)
' Enemies and asteroids spawn around the player's current Y/Z and fly toward the player in X.
' ============================================================
OPTION _EXPLICIT
$Resize:stretch
$EMBED:'assets/ctut_game_studios.png':'CTUTPNG'
$EMBED:'assets/cogikel_heavy_industries.png':'COGIKELPNG'
$EMBED:'assets/sss-title-final.png':'TITLEIMG'
$EMBED:'assets/just_juliaing.png':'JUSTJULIAING'
$EMBED:'assets/planet-01-clean.png':'PLANET01'
$EMBED:'assets/planet-02-clean.png':'PLANET02'
$EMBED:'assets/planet-03-clean.png':'PLANET03'
$EMBED:'assets/planet-04-clean.png':'PLANET04'
$EMBED:'assets/planet-05-clean.png':'PLANET05'
$EMBED:'assets/planet-06-clean.png':'PLANET06'
$EMBED:'assets/grotuk.png':'EMPERORIMG'
$EMBED:'assets/models.e3d':'MODELS'
$EMBED:'assets/gametext.txt':'GAMETEXT'
$EMBED:'assets/gamevalues.ini':'GAMEVALUES'
$EMBED:'assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'assets/music.mus':'MUSICDATA'
$EMBED:'assets/sequence.txt':'SEQTXT'

'$INCLUDE:'src/version.bas'
'$INCLUDE:'src/engine3d.bi'
'$INCLUDE:'src/obj.bas'
'$INCLUDE:'src/dims.bas'
'$INCLUDE:'src/game.bi'

' --- CLI arg handling (all before screen opens so output goes to terminal) ---
CLI_Parse

' Probe /dev/tty once at startup; DBG_Print and GTEXT_Log check this flag.
' Silently skips terminal output when launched without a controlling terminal
' (e.g. double-click from a GUI file manager) instead of popping error dialogs.
DIM dbgTtyProbe AS INTEGER : dbgTtyProbe = FREEFILE
ON ERROR GOTO dbgTtyFail
OPEN "/dev/tty" FOR APPEND AS #dbgTtyProbe : CLOSE #dbgTtyProbe
ON ERROR GOTO 0
dbgTtyOK = -1
GOTO dbgTtyDone
dbgTtyFail:
ON ERROR GOTO 0
dbgTtyDone:

' --- screen ---
scrW = 320 : scrH = 240
SCREEN _NEWIMAGE(scrW, scrH, 32)
backBuffer = _NEWIMAGE(scrW, scrH, 32)
titleImg        = _LOADIMAGE(_EMBEDDED$("TITLEIMG"),   32, "memory")
emperorImg      = _LOADIMAGE(_EMBEDDED$("EMPERORIMG"), 32, "memory")
FONT_BuildPalette fontPalette()
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
GTEXT_Diag
sSpkTitle    = GTEXT_Get$("speech_title")
sSpkGameOver = GTEXT_Get$("speech_game_over")
planetImages(1) = _LOADIMAGE(_EMBEDDED$("PLANET01"), 32, "memory")
planetImages(2) = _LOADIMAGE(_EMBEDDED$("PLANET02"), 32, "memory")
planetImages(3) = _LOADIMAGE(_EMBEDDED$("PLANET03"), 32, "memory")
planetImages(4) = _LOADIMAGE(_EMBEDDED$("PLANET04"), 32, "memory")
planetImages(5) = _LOADIMAGE(_EMBEDDED$("PLANET05"), 32, "memory")
planetImages(6) = _LOADIMAGE(_EMBEDDED$("PLANET06"), 32, "memory")

emperorName = GTEXT_Var$("emperor")
empireName  = GTEXT_Var$("the_empire")
planetNames(1) = GTEXT_Var$("planet1")
planetNames(2) = GTEXT_Var$("planet2")
planetNames(3) = GTEXT_Var$("planet3")
planetNames(4) = GTEXT_Var$("planet4")
planetNames(5) = GTEXT_Var$("planet5")
planetNames(6) = GTEXT_Var$("planet6")

' --- camera ---
E3D_MakeCamera cam, 0, 1.5, 0, 0, 0, 0, GAME_FOV
'$INCLUDE:'src/state/title.bas'
'$INCLUDE:'src/state/intro.bas'
'$INCLUDE:'src/state/gameover.bas'
'$INCLUDE:'src/state/crawl.bas'
'$INCLUDE:'src/state/playing.bas'
E3D_MatPerspective cam, scrW / scrH, projMat

' --- light (coming from upper-left-front) ---
lightDir.x = -0.4 : lightDir.y = 0.7 : lightDir.z = -0.5

' --- mesh library ---
DIM mdl AS STRING
mdl = _EMBEDDED$("MODELS")
E3D_LoadMesh mdl, "PLAYER",       meshLib(MESH_PLAYER),       boxLib(MESH_PLAYER)
E3D_LoadMesh mdl, "ENEMY",        meshLib(MESH_ENEMY),        boxLib(MESH_ENEMY)
E3D_LoadMesh mdl, "ASTEROID",     meshLib(MESH_ASTEROID),     boxLib(MESH_ASTEROID)
E3D_LoadMesh mdl, "BULLET",       meshLib(MESH_BULLET),       boxLib(MESH_BULLET)
E3D_LoadMesh mdl, "POWERUP",      meshLib(MESH_POWERUP),      boxLib(MESH_POWERUP)
E3D_LoadMesh mdl, "ENEMY_ARROW",  meshLib(MESH_ENEMY_ARROW),  boxLib(MESH_ENEMY_ARROW)
E3D_LoadMesh mdl, "ENEMY_HLINE",  meshLib(MESH_ENEMY_HLINE),  boxLib(MESH_ENEMY_HLINE)
E3D_LoadMesh mdl, "ENEMY_VCOL",   meshLib(MESH_ENEMY_VCOL),   boxLib(MESH_ENEMY_VCOL)
E3D_LoadMesh mdl, "ENEMY_PINCER", meshLib(MESH_ENEMY_PINCER), boxLib(MESH_ENEMY_PINCER)
E3D_LoadMesh mdl, "ENEMY_VWEDGE", meshLib(MESH_ENEMY_VWEDGE), boxLib(MESH_ENEMY_VWEDGE)
E3D_LoadMesh mdl, "THRUSTER",     meshLib(MESH_THRUSTER),     boxLib(MESH_THRUSTER)
E3D_LoadMesh mdl, "EBULLET",      meshLib(MESH_EBULLET),      boxLib(MESH_EBULLET)
E3D_LoadMesh mdl, "BOSS",         meshLib(MESH_BOSS),         boxLib(MESH_BOSS)
DIM mlI AS INTEGER
FOR mlI = 1 TO MESH_COUNT
    E3D_BakeMeshNormals meshLib(mlI)
NEXT mlI
DIM hsI AS INTEGER
FOR hsI = MESH_ENEMY TO MESH_ENEMY_VWEDGE
    boxLib(hsI).hx = boxLib(hsI).hx * HIT_SCALE
    boxLib(hsI).hy = boxLib(hsI).hy * HIT_SCALE
    boxLib(hsI).hz = boxLib(hsI).hz * HIT_SCALE
NEXT hsI

' --- init player ---
player.active  = -1
player.meshIdx = MESH_PLAYER
player.px = 0 : player.py = 0 : player.pz = 0
player.scl = 1.0

' --- starfield ---
RANDOMIZE TIMER
StarfieldReset cam.POS.x, cam.POS.y, cam.POS.z

' scratch vars
DIM hit        AS INTEGER
DIM i AS INTEGER, j AS INTEGER
IF debugMode THEN dbgOverlay = 1

' --- formation → mesh lookup ---
wavePrev = -1
fTypeToMesh(0) = MESH_ENEMY
fTypeToMesh(1) = MESH_ENEMY_ARROW
fTypeToMesh(2) = MESH_ENEMY_HLINE
fTypeToMesh(3) = MESH_ENEMY_VCOL
fTypeToMesh(4) = MESH_ENEMY_PINCER
fTypeToMesh(5) = MESH_ENEMY_VWEDGE

SND_Init
SPK_Init
SETTINGS_Load
TELEM_Init
IF settingFullscreen THEN _FULLSCREEN _SQUAREPIXELS ELSE _FULLSCREEN OFF
SEQ_Load _EMBEDDED$("SEQTXT")
IF cliScene <> "" THEN
    IF SEQ_JumpToScene(cliScene) < 0 THEN GAME_Usage("scene '" + cliScene + "' not found")
    IF cliSceneType = "playing" OR cliSceneType = "boss" THEN GAME_ResetState
    IF cliSceneType = "boss" THEN score = stageScore  ' re-apply after GAME_ResetState zeroed it
    SEQ_Advance
ELSE
    gameState = GS_LEADIN
    LEADIN_Init
END IF

' ============================================================
' MAIN LOOP
' ============================================================
DIM fsKeyWas AS INTEGER
DO
    dbgT0 = TIMER
    ' --- input ---
    E3D_InputUpdate held()
    IF _KEYDOWN(34048) AND NOT fsKeyWas THEN
        settingFullscreen = 1 - settingFullscreen
        IF settingFullscreen THEN _FULLSCREEN _SQUAREPIXELS ELSE _FULLSCREEN OFF
        SETTINGS_Save
    END IF
    fsKeyWas = _KEYDOWN(34048)

    ' Detect state transitions for speech triggers
    IF gameState = GS_TITLE AND prevGameState <> GS_TITLE AND prevGameState <> GS_OPTIONS THEN
        SPK_Say sSpkTitle
    END IF
    DBG_LogStateChange
    prevGameState = gameState

    SELECT CASE gameState

    CASE GS_PLAYING, GS_PLANET, GS_CINEMATIC
        GS_PLAYING_Update

    CASE GS_TITLE
        GS_TITLE_Update

    CASE GS_INTRO
        GS_INTRO_Update

    CASE GS_CRAWL
        GS_CRAWL_Update

    CASE GS_GAMEOVER
        GS_GAMEOVER_Update

    CASE GS_OPTIONS
        OPTS_Update
        MUS_Fill 0

    CASE GS_ABOUT
        ABOUT_Update
        MUS_Fill 0

    CASE GS_LEADIN
        LEADIN_Update

    END SELECT

    DBG_Overlay

    _LIMIT 60
    _DISPLAY
LOOP

