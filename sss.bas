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

DIM SHARED player   AS GameObj
DIM SHARED enemies(1 TO MAX_ENEMIES) AS GameObj
DIM SHARED boss     AS GameObj

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

' --- display, font, planet images ---
CONST PLANET_COUNT      = 6
DIM SHARED scrW AS SINGLE, scrH AS SINGLE
DIM SHARED backBuffer AS LONG
DIM SHARED fontPalette(0 TO 15) AS LONG
DIM SHARED planetImages(1 TO PLANET_COUNT) AS LONG
DIM SHARED planetNames(1 TO PLANET_COUNT) AS STRING
DIM SHARED planetCurrent AS INTEGER : planetCurrent = PLANET_COUNT
DIM SHARED planetNameIdx AS INTEGER : planetNameIdx = PLANET_COUNT

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

' --- game object pools ---
DIM SHARED bullets(1 TO MAX_BULLETS)     AS GameObj
DIM SHARED asteroids(1 TO MAX_ASTEROIDS) AS GameObj
DIM SHARED powerups(1 TO MAX_POWERUPS)   AS GameObj
DIM SHARED ebullets(1 TO MAX_EBULLETS)   AS GameObj
DIM SHARED enemyFireTimer(1 TO MAX_ENEMIES) AS SINGLE

' --- game state ---
DIM SHARED score AS LONG
DIM SHARED highScore AS LONG
DIM SHARED stageScore AS LONG  : stageScore = BOSS_TRIGGER
DIM SHARED lives AS INTEGER : lives = 100
DIM SHARED shipLives AS INTEGER : shipLives = 3
DIM SHARED tt AS SINGLE
DIM SHARED spawnTimer AS SINGLE
DIM SHARED camLagY AS SINGLE, camLagZ AS SINGLE
DIM SHARED camFwdY AS SINGLE, camFwdZ AS SINGLE
DIM SHARED camOrbitMode   AS INTEGER
DIM SHARED camAngleLocked AS INTEGER
DIM SHARED camOrbitTheta  AS SINGLE
DIM SHARED camOrbitPhi    AS SINGLE
DIM SHARED camOrbitR      AS SINGLE
DIM SHARED playerVY AS SINGLE, playerVZ AS SINGLE
DIM SHARED isManeuver AS INTEGER
DIM SHARED laserEnergy AS SINGLE : laserEnergy = 100.0
DIM SHARED fuelLevel AS SINGLE : fuelLevel = 100.0
DIM SHARED fuelStranded AS INTEGER
DIM SHARED scorePopTimer AS INTEGER, scorePopY AS SINGLE, scorePopVal AS LONG
DIM SHARED spawnFlashTimer AS INTEGER
DIM SHARED spawnFlashPX AS SINGLE, spawnFlashPY AS SINGLE, spawnFlashPZ AS SINGLE
DIM SHARED bossHP AS INTEGER
DIM SHARED bossPhase AS INTEGER
DIM SHARED bossMoveTimer AS SINGLE
DIM SHARED bossTargetY AS SINGLE, bossTargetZ AS SINGLE
DIM SHARED bossState AS INTEGER
DIM SHARED bossWarnTimer AS INTEGER
DIM SHARED planetTimer AS INTEGER
DIM SHARED planetSeq AS INTEGER
DIM SHARED planetTick AS INTEGER
DIM SHARED planetR AS SINGLE
DIM SHARED planetDefDone AS INTEGER
DIM SHARED cinematicCamX AS SINGLE
DIM SHARED shipCinVX AS SINGLE
DIM SHARED cinematicFade AS INTEGER
DIM SHARED cinPhase AS SINGLE
DIM SHARED gameState AS INTEGER
DIM SHARED prevGameState AS INTEGER : prevGameState = -1
DIM SHARED volMusic  AS SINGLE : volMusic  = 0.3
DIM SHARED volSfx    AS SINGLE : volSfx    = 0.9
DIM SHARED volSpeech AS SINGLE : volSpeech = 0.4
DIM SHARED settingNarration  AS INTEGER : settingNarration  = 1  ' 1=full crawl narration, 0=title/event speech only
DIM SHARED settingFullscreen AS INTEGER : settingFullscreen = 1
DIM SHARED optSel    AS INTEGER
DIM SHARED optUpWas  AS INTEGER
DIM SHARED optDnWas  AS INTEGER
DIM SHARED optLfWas  AS INTEGER
DIM SHARED optRtWas  AS INTEGER
DIM SHARED optLfRpt  AS INTEGER
DIM SHARED optRtRpt  AS INTEGER
DIM SHARED optEscWas   AS INTEGER
DIM SHARED optAboutWas AS INTEGER
DIM SHARED invTimer AS INTEGER
DIM SHARED diffTime AS SINGLE
DIM SHARED diffScale AS SINGLE
DIM SHARED fTypeToMesh(0 TO 5) AS INTEGER
DIM SHARED waveType AS INTEGER, waveCount AS INTEGER, wavePrev AS INTEGER
DIM SHARED godMode    AS INTEGER
DIM SHARED settingNerf AS INTEGER
DIM SHARED debugMode  AS INTEGER
DIM SHARED held(0 TO 32767) AS INTEGER
DIM SHARED fireTimer      AS SINGLE
DIM SHARED bossFireTimer  AS SINGLE
DIM SHARED dbgTtyOK          AS INTEGER
DIM SHARED telemOn           AS INTEGER : telemOn = 0
DIM SHARED telemKills        AS LONG
DIM SHARED telemBossReached  AS INTEGER
DIM SHARED telemBossPhaseLog AS INTEGER
DIM SHARED telemDeathCause$
DIM SHARED telemSession$
DIM SHARED telemShotsFired   AS LONG
DIM SHARED telemShotsHit     AS LONG
DIM SHARED telemEscapes      AS LONG
' --- state sub shared vars (must precede $INCLUDE of state files) ---
DIM SHARED titleImg        AS LONG
DIM SHARED emperorImg      AS LONG
DIM SHARED introTimer      AS INTEGER
DIM SHARED emperorName     AS STRING
DIM SHARED empireName      AS STRING
DIM SHARED gameOverDelay   AS INTEGER
DIM SHARED escWas          AS INTEGER
DIM SHARED spaceWas        AS INTEGER
DIM SHARED crawlFFVolSave  AS SINGLE
DIM SHARED titleEscConfirm AS INTEGER
DIM SHARED escConfirm  AS INTEGER
DIM SHARED escYWas     AS INTEGER
DIM SHARED escNWas     AS INTEGER
DIM SHARED tabWas      AS INTEGER
DIM SHARED rWas        AS INTEGER
DIM SHARED camUpWas    AS INTEGER
DIM SHARED camDnWas    AS INTEGER
'$INCLUDE:'src/version.bas'
'$INCLUDE:'src/engine3d.bi'
'$INCLUDE:'src/obj.bas'
DIM SHARED vpMat AS E3D_Matrix4
DIM SHARED boxLib(1 TO MESH_COUNT) AS E3D_AABB
'$INCLUDE:'src/game.bi'

' --- CLI arg handling (all before screen opens so output goes to terminal) ---
DIM ssCmdLine AS STRING : ssCmdLine = COMMAND$

IF INSTR(ssCmdLine, "--version") > 0 OR ssCmdLine = "-v" OR LEFT$(ssCmdLine, 3) = "-v " THEN
    DIM ssVFH AS INTEGER : ssVFH = FREEFILE
    IF INSTR(_OS$, "WIN") THEN
        OPEN "CON:" FOR OUTPUT AS #ssVFH
    ELSE
        OPEN "/dev/stdout" FOR OUTPUT AS #ssVFH
    END IF
    PRINT #ssVFH, "Super Spaceguy Shooter " + VERSION$
    CLOSE #ssVFH
    SYSTEM
END IF

IF INSTR(ssCmdLine, "--help") > 0 OR ssCmdLine = "-h" OR LEFT$(ssCmdLine, 3) = "-h " THEN
    GAME_Usage("")
END IF

godMode    = (INSTR(ssCmdLine, "--god")   > 0)
settingNerf = (INSTR(ssCmdLine, "--nerf") > 0)
debugMode   = (INSTR(ssCmdLine, "--debug") > 0)
telemOn     = (INSTR(ssCmdLine, "--telem") > 0)

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

DIM ssCmdScene AS STRING
DIM ssCmdScnPos AS INTEGER : ssCmdScnPos = INSTR(ssCmdLine, "--scene ")
IF ssCmdScnPos > 0 THEN
    ssCmdScene = MID$(ssCmdLine, ssCmdScnPos + 8)
    ssCmdScnPos = INSTR(ssCmdScene, " ")
    IF ssCmdScnPos > 0 THEN ssCmdScene = LEFT$(ssCmdScene, ssCmdScnPos - 1)
    ssCmdScene = LTRIM$(RTRIM$(ssCmdScene))
END IF

' validate --scene type prefix before opening the game window
DIM ssSCnI AS INTEGER, ssSCnType AS STRING
IF ssCmdScene <> "" THEN
    ssSCnI = LEN(ssCmdScene)
    DO WHILE ssSCnI > 0
        IF MID$(ssCmdScene, ssSCnI, 1) >= "0" AND MID$(ssCmdScene, ssSCnI, 1) <= "9" THEN ssSCnI = ssSCnI - 1 ELSE EXIT DO
    LOOP
    ssSCnType = LCASE$(LEFT$(ssCmdScene, ssSCnI))
    IF ssSCnType <> "title" AND ssSCnType <> "crawl" AND ssSCnType <> "playing" AND ssSCnType <> "boss" THEN
        GAME_Usage("unknown scene type '" + ssSCnType + "'")
    END IF
END IF

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
DIM sSpkTitle    AS STRING : sSpkTitle    = GTEXT_Get$("speech_title")
DIM sSpkBossWarn AS STRING : sSpkBossWarn = GTEXT_Get$("speech_boss_warning")
DIM sSpkGameOver AS STRING : sSpkGameOver = GTEXT_Get$("speech_game_over")
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
DIM SHARED cam AS E3D_Camera
E3D_MakeCamera cam, 0, 1.5, 0, 0, 0, 0, GAME_FOV

DIM SHARED projMat AS E3D_Matrix4, viewMat AS E3D_Matrix4
DIM SHARED objMat AS E3D_Matrix4
DIM SHARED pPos AS E3D_Coord, pRot AS E3D_Coord
DIM SHARED thrusterLight AS E3D_Coord
DIM SHARED eLitDir AS E3D_Coord
DIM SHARED lightDir AS E3D_Coord
DIM SHARED meshLib(1 TO MESH_COUNT) AS E3D_Mesh
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
DIM SHARED gameOver AS INTEGER
DIM hit        AS INTEGER
DIM i AS INTEGER, j AS INTEGER
DIM noLight AS E3D_Coord : noLight.x = 0 : noLight.y = 0 : noLight.z = -1
DIM thrusterScale AS SINGLE
DIM eDimF AS SINGLE, eDist AS SINGLE
DIM ebClr AS LONG
DIM partR AS INTEGER
DIM pjX AS SINGLE, pjY AS SINGLE, pjW AS SINGLE
DIM pjX2 AS SINGLE, pjY2 AS SINGLE, pjW2 AS SINGLE
DIM pjBX AS SINGLE, pjBY AS SINGLE, pjBZ AS SINGLE
DIM pjFade AS SINGLE
' isManeuver declared DIM SHARED above (read by fuel/thruster logic; written by PLAYER_Update)
DIM dbgOverlay AS INTEGER : IF debugMode THEN dbgOverlay = 1
DIM dbgGraveWas AS INTEGER
DIM dbgT0 AS DOUBLE
DIM dbgFrameMs AS SINGLE

' --- formation → mesh lookup ---
wavePrev = -1 : thrusterScale = 0.30
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
IF ssCmdScene <> "" THEN
    IF SEQ_JumpToScene(ssCmdScene) < 0 THEN GAME_Usage("scene '" + ssCmdScene + "' not found")
    IF ssSCnType = "playing" OR ssSCnType = "boss" THEN GAME_ResetState
    IF ssSCnType = "boss" THEN score = stageScore  ' re-apply after GAME_ResetState zeroed it
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
        IF debugMode AND gameState <> prevGameState THEN
            DIM dbgStateName AS STRING
            SELECT CASE gameState
                CASE GS_TITLE    : dbgStateName = "GS_TITLE"
                CASE GS_PLAYING  : dbgStateName = "GS_PLAYING"
                CASE GS_GAMEOVER : dbgStateName = "GS_GAMEOVER"
                CASE GS_PLANET   : dbgStateName = "GS_PLANET"
                CASE GS_CINEMATIC: dbgStateName = "GS_CINEMATIC"
                CASE GS_INTRO    : dbgStateName = "GS_INTRO"
                CASE GS_CRAWL    : dbgStateName = "GS_CRAWL"
                CASE GS_OPTIONS  : dbgStateName = "GS_OPTIONS"
                CASE GS_ABOUT    : dbgStateName = "GS_ABOUT"
                CASE GS_LEADIN   : dbgStateName = "GS_LEADIN"
                CASE ELSE        : dbgStateName = "GS_?" + LTRIM$(STR$(gameState))
            END SELECT
            DBG_Print "[state] " + dbgStateName
        END IF
        prevGameState = gameState

        SELECT CASE gameState

            ' ============================================================
            ' PLAYING / PLANET / CINEMATIC
            ' ============================================================
        CASE GS_PLAYING, GS_PLANET, GS_CINEMATIC
            GS_PLAYING_Update

            ' ============================================================
            ' TITLE SCREEN
            ' ============================================================
        CASE GS_TITLE
            GS_TITLE_Update

    ' ============================================================
    ' INTRO SCREEN — emperor reveal
    ' ============================================================
CASE GS_INTRO
    GS_INTRO_Update

    ' ============================================================
    ' TEXT CRAWL — stage narrative scroll
    ' ============================================================
CASE GS_CRAWL
    GS_CRAWL_Update

    ' ============================================================
    ' GAME OVER SCREEN
    ' ============================================================
CASE GS_GAMEOVER
    GS_GAMEOVER_Update

    ' ============================================================
    ' SETTINGS / VOLUME CONFIG
    ' ============================================================
CASE GS_OPTIONS
    OPTS_Update
    MUS_Fill 0

    ' ============================================================
    ' ABOUT / CREDITS SCROLL
    ' ============================================================
CASE GS_ABOUT
    ABOUT_Update
    MUS_Fill 0

    ' ============================================================
    ' STUDIO / PRODUCER LEAD-IN CARDS
    ' ============================================================
CASE GS_LEADIN
    LEADIN_Update

END SELECT

' --- debug overlay toggle: ` (backtick) ---
IF _KEYDOWN(96) AND NOT dbgGraveWas THEN dbgOverlay = 1 - dbgOverlay
dbgGraveWas = _KEYDOWN(96)

dbgFrameMs = (TIMER - dbgT0) * 1000

IF dbgOverlay THEN
    DIM dbgPolyClr AS LONG, dbgFpsClr AS LONG, dbgFps AS SINGLE
    IF E3D_scnCount > 350 THEN
        dbgPolyClr = _RGB(255, 80, 60)
    ELSEIF E3D_scnCount > 200 THEN
        dbgPolyClr = _RGB(255, 210, 50)
    ELSE
        dbgPolyClr = _RGB(80, 210, 80)
    END IF
    IF dbgFrameMs > 0.0001 THEN dbgFps = 1000 / dbgFrameMs ELSE dbgFps = 999
    IF dbgFps < 30 THEN
        dbgFpsClr = _RGB(255, 80, 60)
    ELSEIF dbgFps < 50 THEN
        dbgFpsClr = _RGB(255, 210, 50)
    ELSE
        dbgFpsClr = _RGB(80, 210, 80)
    END IF
    _DEST 0
    LINE (0, 0)-(105, 76), _RGBA(0, 0, 0, 190), BF
    COLOR dbgPolyClr
    _PRINTSTRING (2,  2),  "POLY " + LTRIM$(STR$(E3D_scnCount)) + "/450"
    COLOR dbgFpsClr
    _PRINTSTRING (2, 12), "FPS  " + LTRIM$(STR$(CINT(dbgFps)))
    COLOR _RGB(140, 140, 160)
    _PRINTSTRING (2, 22), "ms   " + LEFT$(STR$(dbgFrameMs + 1000), 6)
    COLOR _RGB(120, 200, 255)
    _PRINTSTRING (2, 34), "RY   " + LEFT$(STR$(player.ry + 1000), 7)
    _PRINTSTRING (2, 44), "RZ   " + LEFT$(STR$(player.rz + 1000), 7)
    COLOR _RGB(180, 255, 180)
    _PRINTSTRING (2, 54), "VY   " + LEFT$(STR$(playerVY + 1000), 7)
    _PRINTSTRING (2, 64), "VZ   " + LEFT$(STR$(playerVZ + 1000), 7)

    ' enemy AABB wireframes
    IF gameState = GS_PLAYING THEN
        DIM dbgBi  AS INTEGER
        DIM dbgBwx AS SINGLE, dbgBwy AS SINGLE, dbgBwz AS SINGLE
        DIM dbgBhx AS SINGLE, dbgBhy AS SINGLE, dbgBhz AS SINGLE
        DIM dbgBtx AS SINGLE, dbgBty AS SINGLE, dbgBtz AS SINGLE
        DIM dbgBpx AS SINGLE, dbgBpy AS SINGLE, dbgBpw AS SINGLE
        DIM dbgBsx(0 TO 7) AS SINGLE, dbgBsy(0 TO 7) AS SINGLE, dbgBsw(0 TO 7) AS SINGLE
        DIM dbgBci AS INTEGER, dbgBa AS INTEGER, dbgBb AS INTEGER, dbgBdiff AS INTEGER
        DIM dbgBclr AS LONG : dbgBclr = _RGB(0, 255, 120)
        FOR dbgBi = 1 TO MAX_ENEMIES
            IF enemies(dbgBi).active THEN
                dbgBwx = enemies(dbgBi).px
                dbgBwy = enemies(dbgBi).py
                dbgBwz = enemies(dbgBi).pz
                dbgBhx = boxLib(enemies(dbgBi).meshIdx).hx
                dbgBhy = boxLib(enemies(dbgBi).meshIdx).hy
                dbgBhz = boxLib(enemies(dbgBi).meshIdx).hz
                FOR dbgBci = 0 TO 7
                    IF (dbgBci AND 4) THEN dbgBtx = dbgBwx + dbgBhx ELSE dbgBtx = dbgBwx - dbgBhx
                    IF (dbgBci AND 2) THEN dbgBty = dbgBwy + dbgBhy ELSE dbgBty = dbgBwy - dbgBhy
                    IF (dbgBci AND 1) THEN dbgBtz = dbgBwz + dbgBhz ELSE dbgBtz = dbgBwz - dbgBhz
                    dbgBpx  = dbgBtx * vpMat.m(0,0) + dbgBty * vpMat.m(0,1) + dbgBtz * vpMat.m(0,2) + vpMat.m(0,3)
                    dbgBpy  = dbgBtx * vpMat.m(1,0) + dbgBty * vpMat.m(1,1) + dbgBtz * vpMat.m(1,2) + vpMat.m(1,3)
                    dbgBpw  = dbgBtx * vpMat.m(3,0) + dbgBty * vpMat.m(3,1) + dbgBtz * vpMat.m(3,2) + vpMat.m(3,3)
                    dbgBsw(dbgBci) = dbgBpw
                    IF dbgBpw > 0 THEN
                        dbgBsx(dbgBci) = (dbgBpx / dbgBpw + 1.0) * scrW * 0.5
                        dbgBsy(dbgBci) = (1.0 - dbgBpy / dbgBpw) * scrH * 0.5
                    END IF
                NEXT dbgBci
                FOR dbgBa = 0 TO 6
                    FOR dbgBb = dbgBa + 1 TO 7
                        dbgBdiff = dbgBa XOR dbgBb
                        IF dbgBdiff = 1 OR dbgBdiff = 2 OR dbgBdiff = 4 THEN
                            IF dbgBsw(dbgBa) > 0 THEN
                                IF dbgBsw(dbgBb) > 0 THEN
                                    LINE (dbgBsx(dbgBa), dbgBsy(dbgBa))-(dbgBsx(dbgBb), dbgBsy(dbgBb)), dbgBclr
                                END IF
                            END IF
                        END IF
                    NEXT dbgBb
                NEXT dbgBa
            END IF
        NEXT dbgBi
    END IF
END IF

_LIMIT 60
_DISPLAY
LOOP

SUB StarfieldReset(srX AS SINGLE, srY AS SINGLE, srZ AS SINGLE)
    E3D_StarfieldInit srY, srZ
    E3D_StarfieldAddLayer srX, srY, srZ, 200, 50, 50, 40, 0.010, 0.020, 0
    E3D_StarfieldAddLayer srX, srY, srZ,  60, 40, 30, 25, 0.035, 0.070, 1
    E3D_StarfieldAddLayer srX, srY, srZ,  15, 25, 15, 12, 0.100, 0.180, 2
END SUB


SUB DBG_Print(dbgMsg AS STRING)
    IF dbgTtyOK = 0 THEN EXIT SUB
    DIM dbgF AS INTEGER
    dbgF = FreeFile
    OPEN "/dev/tty" FOR APPEND AS #dbgF
    PRINT #dbgF, dbgMsg
    CLOSE #dbgF
END SUB

SUB GAME_Usage(guErr AS STRING)
    DIM guFH AS INTEGER : guFH = FREEFILE
    IF INSTR(_OS$, "WIN") THEN
        OPEN "CON:" FOR OUTPUT AS #guFH
    ELSE
        OPEN "/dev/stdout" FOR OUTPUT AS #guFH
    END IF
    IF guErr <> "" THEN
        PRINT #guFH, "Error: " + guErr
        PRINT #guFH, ""
    END IF
    PRINT #guFH, "Super Spaceguy Shooter " + VERSION$
    PRINT #guFH, ""
    PRINT #guFH, "Usage: sss [options]"
    PRINT #guFH, ""
    PRINT #guFH, "Options:"
    PRINT #guFH, "  -v, --version          Print version and exit"
    PRINT #guFH, "  -h, --help             Show this help and exit"
    PRINT #guFH, "  --scene <name>         Jump to a named scene (skips normal startup)"
    PRINT #guFH, "  --god                  God mode: shields, health, and laser never deplete"
    PRINT #guFH, "  --nerf                 Nerf mode: 1 kill triggers boss (was 10), boss has 10 HP (was 30)"
    PRINT #guFH, "  --debug                Enable debug overlay and stdout event logging"
    PRINT #guFH, "  --telem                Enable gameplay telemetry logging to sss_telemetry.csv"
    PRINT #guFH, ""
    PRINT #guFH, "Scene names:"
    PRINT #guFH, "  title                  Title screen (default)"
    PRINT #guFH, "  crawl0                 Intro crawl"
    PRINT #guFH, "  crawl1..6              Chapter crawls"
    PRINT #guFH, "  playing1..6            Gameplay stages"
    PRINT #guFH, "  boss1..6               Stage with boss pre-triggered on frame 1"
    CLOSE #guFH
    SYSTEM
END SUB
