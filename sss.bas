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
' --- constants needed by included files ---
CONST SAMPLE_RATE = 44100  ' audio sample rate; used by snd.bas and speech.bas
CONST GS_TITLE     = 0
CONST GS_PLAYING   = 1
CONST GS_GAMEOVER  = 2
CONST GS_PLANET    = 3
CONST GS_CINEMATIC = 4
CONST GS_INTRO     = 5
CONST GS_CRAWL     = 6
CONST GS_OPTIONS   = 7
CONST GS_ABOUT     = 8
CONST GS_LEADIN    = 9
CONST MAX_ENEMIES   = 35
CONST MAX_BULLETS   = 30
CONST MAX_ASTEROIDS = 15
CONST MAX_POWERUPS  = 5
CONST MAX_EBULLETS  = 24
CONST BOSS_MAX_HP      = 30
CONST BOSS_MAX_HP_NERF = 10

TYPE GameObj
    active  AS INTEGER
    meshIdx AS INTEGER
    px AS SINGLE : py AS SINGLE : pz AS SINGLE
    vx AS SINGLE : vy AS SINGLE : vz AS SINGLE
    rx AS SINGLE : ry AS SINGLE : rz AS SINGLE
    drx AS SINGLE : dry AS SINGLE : drz AS SINGLE
    scl AS SINGLE
    life AS SINGLE
END TYPE

TYPE BossObj
    active  AS INTEGER
    meshIdx AS INTEGER
    px AS SINGLE : py AS SINGLE : pz AS SINGLE
    vx AS SINGLE : vy AS SINGLE : vz AS SINGLE
    rx AS SINGLE : ry AS SINGLE : rz AS SINGLE
    drx AS SINGLE : dry AS SINGLE : drz AS SINGLE
    scl AS SINGLE
    life AS SINGLE
    hp        AS INTEGER
    phase     AS INTEGER
    fireTimer AS SINGLE
    moveTimer AS SINGLE
    targetY   AS SINGLE
    targetZ   AS SINGLE
    state     AS INTEGER
    warnTimer AS INTEGER
END TYPE

TYPE CamFollow
    lagY        AS SINGLE
    lagZ        AS SINGLE
    fwdY        AS SINGLE
    fwdZ        AS SINGLE
    orbitMode   AS INTEGER
    angleLocked AS INTEGER
    orbitTheta  AS SINGLE
    orbitPhi    AS SINGLE
    orbitR      AS SINGLE
END TYPE

' --- tuning constants ---
CONST PLAYER_ACCEL        = 0.14    ' velocity lerp rate (controls both accel and drag)
CONST PLAYER_MAX_VEL      = 0.12    ' max lateral velocity per frame
CONST ATTITUDE_LERP       = 0.09    ' ship tilt/roll settle rate

CONST BULLET_SPEED        = 0.35    ' player bullet X velocity
CONST FIRE_COOLDOWN       = 0.18    ' seconds between shots
CONST LASER_COST          = 5.0     ' laser energy drained per shot (%)
CONST AIM_ASSIST          = 0.30    ' fraction of aim error corrected toward nearest enemy in cone
CONST HIT_SCALE           = 1.5     ' enemy AABB scale factor for hit detection (visual stays unchanged)
CONST LASER_REGEN         = 0.167   ' laser energy per frame (~10%/sec at 60fps)

CONST FUEL_DRAIN          = 0.0185  ' base drain per frame (~90 sec at 60fps)
CONST FUEL_DRAIN_BOOST    = 0.006   ' extra drain per frame when thrusting
CONST BULLET_RANGE        = 110     ' cull player bullet beyond player.px + this
CONST BULLET_TRAIL_LEN    = 2.0     ' world-unit length of bolt body (rear to tip along nose)

CONST EBULLET_SPEED       = 0.16    ' regular enemy bullet speed
CONST EBULLET_CULL        = 8       ' cull when px < player.px - this
CONST EFIRE_INIT_MIN      = 2.5     ' enemy initial fire timer min (seconds)
CONST EFIRE_INIT_VAR      = 2.0     ' enemy initial fire timer variance
CONST EFIRE_COOL_MIN      = 3.5     ' post-shot cooldown min
CONST EFIRE_COOL_VAR      = 2.2     ' post-shot cooldown variance
CONST EFIRE_RANGE         = 40      ' X-range at which enemies fire
CONST EFIRE_LEAD          = 0.65    ' fraction of perfect lead applied to enemy shots (0=dumb, 1=perfect)

CONST DMG_COLLISION       = 17      ' shield damage from collision
CONST DMG_LASER           = 5       ' shield damage from enemy bullet
CONST SHAKE_COLLISION     = 7       ' shakeTimer on collision
CONST FLASH_COLLISION     = 4       ' flashTimer on collision
CONST SHAKE_LASER         = 2       ' shakeTimer on laser hit
CONST FLASH_LASER         = 1       ' flashTimer on laser hit

CONST SPAWN_INTERVAL_BASE = 7.0     ' base spawn interval (seconds)
CONST SPAWN_INTERVAL_MIN  = 2.0     ' difficulty reduces interval by up to this
CONST SPAWN_DIST_MIN      = 70      ' spawn ahead of player: min distance
CONST SPAWN_DIST_VAR      = 30      ' spawn ahead of player: variance
CONST SPAWN_SPREAD_Y      = 18      ' ±Y spawn spread
CONST SPAWN_SPREAD_Z      = 22      ' ±Z spawn spread
CONST DIFF_RAMP_DURATION  = 600.0   ' play-seconds to reach max difficulty
CONST DIFF_SPEED_SCALE    = 0.6     ' how much difficulty boosts enemy speed

CONST SCORE_ENEMY         = 100     ' points per enemy kill
CONST SCORE_ASTEROID      = 50      ' points per asteroid kill
CONST SCORE_POWERUP       = 500     ' points for powerup collect
CONST SHIELD_RESTORE      = 30      ' shield added by powerup

CONST BOSS_SCALE          = 3.5     ' boss mesh scale
CONST BOSS_SPAWN_DIST     = 55      ' boss spawns this far ahead of player
CONST BOSS_COMBAT_DIST    = 45      ' boss holds at this X distance
CONST BOSS_WARN_FRAMES    = 120     ' warning frames before boss spawns
CONST BOSS_FIRE_INIT      = 2.5     ' fire interval at boss spawn (before phase lock-in)
CONST BOSS_FIRE1          = 2.2     ' phase 1 fire interval
CONST BOSS_FIRE2          = 1.5     ' phase 2 fire interval
CONST BOSS_FIRE3          = 0.9     ' phase 3 fire interval
CONST BOSS_DIM_FLOOR      = 0.35    ' minimum lighting factor for boss (keeps it visible at range)
CONST BOSS_DEATH_PARTS    = 35      ' particle count on boss death

CONST CAM_OFFSET_X        = 6.5    ' camera behind player
CONST CAM_OFFSET_Y        = 2.0    ' camera above player
CONST CAM_LEAD_X          = 8      ' look-at point ahead of player
CONST CAM_LAG_RATE        = 0.08   ' camera positional lag lerp rate
CONST CAM_FWD_RATE        = 0.04   ' camera orientation lag lerp rate (slower = weightier feel)
CONST CAM_FWD_SCALE       = 1.0    ' world units of camera tilt per unit of normalized velocity
CONST GAME_FOV            = 72     ' field of view

CONST DIM_FAR             = 55      ' distance dimming far threshold
CONST DIM_NEAR            = 28      ' distance dimming near threshold
CONST DIM_AMBIENT         = 0.22    ' minimum brightness at far distance

CONST PLANET_COUNT      = 6

' --- mesh constants ---
CONST MESH_PLAYER       = 1
CONST MESH_ENEMY        = 2   ' red  — solo
CONST MESH_ASTEROID     = 3
CONST MESH_BULLET       = 4
CONST MESH_POWERUP      = 5
CONST MESH_ENEMY_ARROW  = 6   ' orange — arrow
CONST MESH_ENEMY_HLINE  = 7   ' green  — horizontal line
CONST MESH_ENEMY_VCOL   = 8   ' cyan   — vertical column
CONST MESH_ENEMY_PINCER = 9   ' yellow — pincer
CONST MESH_ENEMY_VWEDGE = 10  ' purple — V-wedge
CONST MESH_THRUSTER     = 11
CONST MESH_EBULLET      = 12
CONST MESH_BOSS         = 13
CONST MESH_COUNT        = 13
CONST BOSS_TRIGGER      = 1000
CONST BOSS_TRIGGER_NERF = 100

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

