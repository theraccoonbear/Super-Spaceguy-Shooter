' ============================================================
' Super Spaceguy Shooter  —  sss.bas
' 3rd person pseudo-rail 3D space shooter
' Player moves freely in Y/Z (up/down, left/right)
' Enemies and asteroids spawn around the player's current Y/Z and fly toward the player in X.
' ============================================================
$Resize:stretch
$EMBED:'code/3d/assets/sss-title-final.png':'TITLEIMG'
$EMBED:'code/3d/assets/planet-01-clean.png':'PLANET01'
$EMBED:'code/3d/assets/planet-02-clean.png':'PLANET02'
$EMBED:'code/3d/assets/planet-03-clean.png':'PLANET03'
$EMBED:'code/3d/assets/planet-04-clean.png':'PLANET04'
$EMBED:'code/3d/assets/planet-05-clean.png':'PLANET05'
$EMBED:'code/3d/assets/planet-06-clean.png':'PLANET06'
$EMBED:'code/3d/assets/grotuk2.png':'EMPERORIMG'
$EMBED:'code/3d/assets/models.e3d':'MODELS'
$EMBED:'code/3d/assets/gametext.txt':'GAMETEXT'
$EMBED:'code/3d/assets/gamevalues.ini':'GAMEVALUES'
$EMBED:'code/3d/assets/speech_dict.txt':'SPEECHDICT'
$EMBED:'code/3d/assets/music.mus':'MUSICDATA'
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
CONST BOSS_FIRE1          = 2.2     ' phase 1 fire interval
CONST BOSS_FIRE2          = 1.5     ' phase 2 fire interval
CONST BOSS_FIRE3          = 0.9     ' phase 3 fire interval
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
DIM SHARED stageScore AS LONG  : stageScore = BOSS_TRIGGER
DIM SHARED lives AS INTEGER : lives = 100
DIM SHARED shipLives AS INTEGER : shipLives = 3
DIM SHARED tt AS SINGLE
DIM SHARED spawnTimer AS SINGLE
DIM SHARED camLagY AS SINGLE, camLagZ AS SINGLE
DIM SHARED camFwdY AS SINGLE, camFwdZ AS SINGLE
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
DIM SHARED crawlNextState AS INTEGER
DIM SHARED pauseFlag AS INTEGER
DIM SHARED invTimer AS INTEGER
DIM SHARED diffTime AS SINGLE
DIM SHARED diffScale AS SINGLE
DIM SHARED fTypeToMesh(0 TO 5) AS INTEGER
DIM SHARED waveType AS INTEGER, waveCount AS INTEGER, wavePrev AS INTEGER

'$INCLUDE:'version.bas'
'$INCLUDE:'engine3d.bi'
'$INCLUDE:'obj.bas'
DIM SHARED vpMat AS E3D_Matrix4
'$INCLUDE:'speech.bas'
'$INCLUDE:'effects.bas'
'$INCLUDE:'snd.bas'
'$INCLUDE:'music.bas'
'$INCLUDE:'behavior.bas'
'$INCLUDE:'font.bas'
'$INCLUDE:'gametext.bas'
'$INCLUDE:'crawl.bas'
'$INCLUDE:'about.bas'
'$INCLUDE:'sequence.bas'
'$INCLUDE:'hud.bas'
'$INCLUDE:'wave.bas'
'$INCLUDE:'stage.bas'
'$INCLUDE:'game.bas'
'$INCLUDE:'settings.bas'
'$INCLUDE:'ui.bas'
'$INCLUDE:'player.bas'

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

DIM SHARED godMode    AS INTEGER : godMode    = (INSTR(ssCmdLine, "--god")  > 0)
DIM SHARED settingNerf AS INTEGER : settingNerf = (INSTR(ssCmdLine, "--nerf") > 0)

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
DIM titleImg AS LONG
DIM emperorImg AS LONG
DIM introTimer AS INTEGER
DIM emperorName AS STRING, empireName AS STRING
titleImg        = _LOADIMAGE(_EMBEDDED$("TITLEIMG"),   32, "memory")
emperorImg      = _LOADIMAGE(_EMBEDDED$("EMPERORIMG"), 32, "memory")
FONT_BuildPalette fontPalette()
GTEXT_LoadVars _EMBEDDED$("GAMEVALUES")
GTEXT_Load _EMBEDDED$("GAMETEXT")
GTEXT_Diag
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

' --- input ---
DIM SHARED held(0 TO 32767) AS INTEGER

' --- camera ---
DIM SHARED cam AS E3D_Camera
E3D_MakeCamera cam, 0, 1.5, 0, 0, 0, 0, GAME_FOV

DIM SHARED projMat AS E3D_Matrix4, viewMat AS E3D_Matrix4
E3D_MatPerspective cam, scrW / scrH, projMat

' --- light (coming from upper-left-front) ---
DIM lightDir AS E3D_Coord
lightDir.x = -0.4 : lightDir.y = 0.7 : lightDir.z = -0.5

' --- mesh library ---
DIM meshLib(1 TO MESH_COUNT) AS E3D_Mesh
DIM boxLib(1 TO MESH_COUNT) AS E3D_AABB
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
DIM fireTimer  AS SINGLE
DIM hit        AS INTEGER
DIM i AS INTEGER, j AS INTEGER
DIM objMat AS E3D_Matrix4
' tgtRx/Ry/Rz moved into PLAYER_Update in player.bas
DIM pPos AS E3D_Coord, pRot AS E3D_Coord
DIM noLight AS E3D_Coord : noLight.x = 0 : noLight.y = 0 : noLight.z = -1
DIM thrusterLight AS E3D_Coord
DIM thrusterScale AS SINGLE
DIM eLitDir AS E3D_Coord
DIM eDimF AS SINGLE, eDist AS SINGLE
DIM p AS INTEGER, pk AS INTEGER  ' used for boss death particle loop
DIM ej AS INTEGER
DIM eDX AS SINGLE, eDY AS SINGLE, eDZ AS SINGLE, eMag AS SINGLE
DIM ebClr AS LONG
DIM partR AS INTEGER, partG AS INTEGER, partB AS INTEGER
DIM pjX AS SINGLE, pjY AS SINGLE, pjW AS SINGLE
DIM pjX2 AS SINGLE, pjY2 AS SINGLE, pjW2 AS SINGLE
DIM pjBX AS SINGLE, pjBY AS SINGLE, pjBZ AS SINGLE
DIM pjFade AS SINGLE
DIM bossFireTimer AS SINGLE
DIM bossShots AS INTEGER
DIM bossAngle AS SINGLE
DIM highScore AS LONG
DIM gameOverDelay AS INTEGER
DIM pKeyWas AS INTEGER
DIM escConfirm AS INTEGER
DIM escWas AS INTEGER
DIM spaceWas       AS INTEGER
DIM crawlFFVolSave AS SINGLE
DIM titleEscConfirm AS INTEGER
DIM throbBright AS INTEGER
' isManeuver declared DIM SHARED above (read by fuel/thruster logic; written by PLAYER_Update)
DIM dbgOverlay AS INTEGER
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
IF settingFullscreen THEN _FULLSCREEN _SQUAREPIXELS ELSE _FULLSCREEN OFF
SEQ_Init
IF ssCmdScene <> "" THEN
    IF SEQ_JumpToScene(ssCmdScene) < 0 THEN GAME_Usage("scene '" + ssCmdScene + "' not found")
    IF ssSCnType = "playing" OR ssSCnType = "boss" THEN GAME_ResetState
    SEQ_Advance
ELSE
    SEQ_Advance
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
        SPK_Say "SUPER SPACE GUY SHOOTER"
    END IF
    prevGameState = gameState

    SELECT CASE gameState

        ' ============================================================
        ' PLAYING / PLANET / CINEMATIC
        ' ============================================================
    CASE GS_PLAYING, GS_PLANET, GS_CINEMATIC
        ' ESC during planet/cinematic: skip straight to title (no confirm needed)
        IF gameState = GS_PLANET OR gameState = GS_CINEMATIC THEN
            IF held(E3D_KEY_ESCAPE) AND NOT escWas THEN
                gameState = GS_TITLE
                planetTimer = 0 : cinematicFade = 0 : shipCinVX = 0 : cinematicCamX = 0
                MUS_SetCue "title"
                escWas = held(E3D_KEY_ESCAPE)
                EXIT SELECT
            END IF
            escWas = held(E3D_KEY_ESCAPE)
        END IF

        ' ESC: rising edge toggles confirm dialog (game only); Y returns to title, Esc/N cancels
        IF gameState = GS_PLAYING THEN
            IF held(E3D_KEY_ESCAPE) AND NOT escWas THEN escConfirm = 1 - escConfirm
            escWas = held(E3D_KEY_ESCAPE)
            IF escConfirm THEN
                IF _KEYDOWN(89) OR _KEYDOWN(121) THEN
                    escConfirm = 0 : gameState = GS_TITLE
                    SEQ_RewindToTitle
                    MUS_SetCue "title"
                END IF
                IF _KEYDOWN(78) OR _KEYDOWN(110) THEN escConfirm = 0
                _DEST backBuffer
                UI_DrawPanel scrW\2 - 76, scrH\2 - 28, scrW\2 + 76, scrH\2 + 28, "ABORT MISSION"
                FONT_PrintCentered fontPalette(14), backBuffer, "Y   CONFIRM RETREAT", scrH\2 - 9, scrW
                FONT_PrintCentered fontPalette(8),  backBuffer, "ESC CANCEL",          scrH\2 + 5, scrW
                _DEST 0
                _PUTIMAGE , backBuffer, 0
                EXIT SELECT
            END IF
        END IF

        ' --- pause toggle (P key, debounced) ---
        IF _KEYDOWN(112) AND NOT pKeyWas THEN pauseFlag = 1 - pauseFlag
        pKeyWas = _KEYDOWN(112)

        IF NOT pauseFlag THEN
            ' --- timers ---
            tt = tt + 0.025
            spawnTimer = spawnTimer + 0.025
            IF fireTimer > 0 THEN fireTimer = fireTimer - 0.025
            IF invTimer > 0 THEN invTimer = invTimer - 1
            IF laserEnergy < 100.0 THEN
                laserEnergy = laserEnergy + LASER_REGEN
                IF laserEnergy > 100.0 THEN laserEnergy = 100.0
            END IF
            STAGE_Update

            ' --- player movement, velocity physics, attitude ---
            PLAYER_Update held(E3D_KEY_UP) OR held(E3D_KEY_W), held(E3D_KEY_DOWN) OR held(E3D_KEY_S), held(E3D_KEY_LEFT) OR held(E3D_KEY_A), held(E3D_KEY_RIGHT) OR held(E3D_KEY_D)

            IF gameState = GS_PLAYING THEN
                fuelLevel = fuelLevel - FUEL_DRAIN
                IF isManeuver THEN fuelLevel = fuelLevel - FUEL_DRAIN_BOOST
                IF fuelLevel <= 0 THEN fuelLevel = 0 : fuelStranded = -1
            END IF
            IF godMode THEN
                lives = 100 : laserEnergy = 100.0 : fuelLevel = 100.0 : fuelStranded = 0
            END IF

            IF isManeuver THEN
                thrusterScale = thrusterScale + (0.88 - thrusterScale) * 0.14
            ELSEIF fuelStranded THEN
                thrusterScale = thrusterScale * 0.92
            ELSE
                thrusterScale = thrusterScale + (0.28 - thrusterScale) * 0.06
            END IF


            ' --- fire ---
            IF held(E3D_KEY_SPACE) AND invTimer = 0 AND gameState = GS_PLAYING THEN
                IF fireTimer <= 0 AND laserEnergy >= LASER_COST THEN
                    FOR i = 1 TO MAX_BULLETS
                        IF bullets(i).active = 0 THEN
                            bullets(i).active  = -1
                            bullets(i).meshIdx = MESH_BULLET
                            ' compute nose unit vector from full E3D rotation (Rx*Ry*Rz applied to forward)
                            DIM bvRx AS SINGLE, bvRy AS SINGLE, bvRz AS SINGLE
                            DIM bvNx AS SINGLE, bvNy AS SINGLE, bvNz AS SINGLE
                            bvRx = player.rx * _PI / 180.0
                            bvRy = player.ry * _PI / 180.0
                            bvRz = player.rz * _PI / 180.0
                            bvNx = COS(bvRz) * COS(bvRy)
                            bvNy = COS(bvRx)*SIN(bvRz)*COS(bvRy) + SIN(bvRx)*SIN(bvRy)
                            bvNz = SIN(bvRx)*SIN(bvRz)*COS(bvRy) - COS(bvRx)*SIN(bvRy)
                            ' spawn bolt so its rear (trailing point) clears the ship nose by ~1wu
                            bullets(i).px = player.px + bvNx * (BULLET_TRAIL_LEN + 1.0)
                            bullets(i).py = player.py + bvNy * (BULLET_TRAIL_LEN + 1.0)
                            bullets(i).pz = player.pz + bvNz * (BULLET_TRAIL_LEN + 1.0)
                            bullets(i).vx = bvNx * BULLET_SPEED
                            bullets(i).vy = bvNy * BULLET_SPEED
                            bullets(i).vz = bvNz * BULLET_SPEED
                            bullets(i).life = BULLET_RANGE / BULLET_SPEED
                            bullets(i).scl = 1.0
                            fireTimer = FIRE_COOLDOWN
                            laserEnergy = laserEnergy - LASER_COST
                            SND_Shoot
                            EXIT FOR
                        END IF
                    NEXT i
                END IF
            END IF

            ' --- spawning ---
            WAVE_Spawn

            ' --- update bullets ---
            FOR i = 1 TO MAX_BULLETS
                IF bullets(i).active THEN
                    bullets(i).px = bullets(i).px + bullets(i).vx
                    bullets(i).py = bullets(i).py + bullets(i).vy
                    bullets(i).pz = bullets(i).pz + bullets(i).vz
                    bullets(i).life = bullets(i).life - 1
                    IF bullets(i).life <= 0 THEN bullets(i).active = 0
                END IF
            NEXT i

            ' --- update enemies ---
            FOR i = 1 TO MAX_ENEMIES
                IF enemies(i).active THEN
                    enemies(i).px  = enemies(i).px  + enemies(i).vx
                    enemies(i).ry  = enemies(i).ry  + enemies(i).dry
                    IF enemies(i).px < player.px + 30 THEN
                        enemies(i).py = enemies(i).py + (player.py - enemies(i).py) * 0.008
                        enemies(i).pz = enemies(i).pz + (player.pz - enemies(i).pz) * 0.008
                    ELSE
                        enemies(i).py = enemies(i).py + SIN(tt * 1.5 + i * 1.3) * 0.015
                        enemies(i).pz = enemies(i).pz + COS(tt * 1.1 + i * 2.1) * 0.015
                    END IF

                    ' fire at player when cooled down and in range
                    enemyFireTimer(i) = enemyFireTimer(i) - 0.025
                    IF enemyFireTimer(i) <= 0 AND enemies(i).px > player.px AND enemies(i).px < player.px + EFIRE_RANGE THEN
                        eDX = player.px - enemies(i).px
                        eDY = player.py - enemies(i).py
                        eDZ = player.pz - enemies(i).pz
                        eMag = SQR(eDX * eDX + eDY * eDY + eDZ * eDZ)
                        IF eMag > 0.1 THEN
                            eDX = eDX / eMag : eDY = eDY / eMag : eDZ = eDZ / eMag
                            FOR ej = 1 TO MAX_EBULLETS
                                IF ebullets(ej).active = 0 THEN
                                    ebullets(ej).active  = -1
                                    ebullets(ej).meshIdx = enemies(i).meshIdx
                                    ebullets(ej).px = enemies(i).px
                                    ebullets(ej).py = enemies(i).py
                                    ebullets(ej).pz = enemies(i).pz
                                    ebullets(ej).vx = eDX * EBULLET_SPEED
                                    ebullets(ej).vy = eDY * EBULLET_SPEED
                                    ebullets(ej).vz = eDZ * EBULLET_SPEED
                                    ebullets(ej).scl = 1.0
                                    EXIT FOR
                                END IF
                            NEXT ej
                        END IF
                        enemyFireTimer(i) = EFIRE_COOL_MIN + RND * EFIRE_COOL_VAR
                    END IF

                    IF enemies(i).px < -5 THEN enemies(i).active = 0

                    ' bullet vs enemy
                    FOR j = 1 TO MAX_BULLETS
                        IF bullets(j).active THEN
                            E3D_AABBOverlap enemies(i).px, enemies(i).py, enemies(i).pz, boxLib(MESH_ENEMY), _
                            bullets(j).px, bullets(j).py, bullets(j).pz, boxLib(MESH_BULLET), hit
                            IF hit THEN
                                enemies(i).active = 0
                                bullets(j).active = 0
                                score = score + SCORE_ENEMY
                                SND_Boom
                                scorePopTimer = 30 : scorePopY = scrH * 0.45 : scorePopVal = SCORE_ENEMY
                                SELECT CASE enemies(i).meshIdx
                                CASE MESH_ENEMY        : partR = 255 : partG =  80 : partB =  60
                                CASE MESH_ENEMY_ARROW  : partR = 255 : partG = 140 : partB =   0
                                CASE MESH_ENEMY_HLINE  : partR =  60 : partG = 210 : partB =  80
                                CASE MESH_ENEMY_VCOL   : partR =  60 : partG = 220 : partB = 235
                                CASE MESH_ENEMY_PINCER : partR = 235 : partG = 225 : partB =  50
                                CASE ELSE              : partR = 185 : partG =  80 : partB = 255
                                END SELECT
                                FX_SpawnBurst enemies(i).px, enemies(i).py, enemies(i).pz, 10, 0.22, 18, 8, _RGB(partR, partG, partB)
                            END IF
                        END IF
                    NEXT j

                    ' player vs enemy
                    E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                    enemies(i).px, enemies(i).py, enemies(i).pz, boxLib(MESH_ENEMY), hit
                    IF hit AND invTimer = 0 THEN
                        enemies(i).active = 0
                        SELECT CASE enemies(i).meshIdx
                        CASE MESH_ENEMY        : partR = 255 : partG =  80 : partB =  60
                        CASE MESH_ENEMY_ARROW  : partR = 255 : partG = 140 : partB =   0
                        CASE MESH_ENEMY_HLINE  : partR =  60 : partG = 210 : partB =  80
                        CASE MESH_ENEMY_VCOL   : partR =  60 : partG = 220 : partB = 235
                        CASE MESH_ENEMY_PINCER : partR = 235 : partG = 225 : partB =  50
                        CASE ELSE              : partR = 185 : partG =  80 : partB = 255
                        END SELECT
                        SND_Boom
                        FX_SpawnBurst enemies(i).px, enemies(i).py, enemies(i).pz, 10, 0.22, 18, 8, _RGB(partR, partG, partB)
                        PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
                    END IF
                END IF
            NEXT i

            ' --- update asteroids ---
            FOR i = 1 TO MAX_ASTEROIDS
                IF asteroids(i).active THEN
                    asteroids(i).px  = asteroids(i).px  + asteroids(i).vx
                    asteroids(i).rx  = asteroids(i).rx  + asteroids(i).drx
                    asteroids(i).ry  = asteroids(i).ry  + asteroids(i).dry
                    asteroids(i).rz  = asteroids(i).rz  + asteroids(i).drz
                    IF asteroids(i).px < player.px + 25 THEN
                        asteroids(i).py = asteroids(i).py + (player.py - asteroids(i).py) * 0.004
                        asteroids(i).pz = asteroids(i).pz + (player.pz - asteroids(i).pz) * 0.004
                    END IF
                    IF asteroids(i).px < -5 THEN asteroids(i).active = 0

                    ' bullet vs asteroid
                    FOR j = 1 TO MAX_BULLETS
                        IF bullets(j).active THEN
                            E3D_AABBOverlap asteroids(i).px, asteroids(i).py, asteroids(i).pz, boxLib(MESH_ASTEROID), _
                            bullets(j).px, bullets(j).py, bullets(j).pz, boxLib(MESH_BULLET), hit
                            IF hit THEN
                                asteroids(i).active = 0
                                bullets(j).active = 0
                                score = score + SCORE_ASTEROID
                                SND_Boom
                                scorePopTimer = 30 : scorePopY = scrH * 0.45 : scorePopVal = SCORE_ASTEROID
                                FX_SpawnBurst asteroids(i).px, asteroids(i).py, asteroids(i).pz, 8, 0.18, 15, 7, _RGB(120 + INT(RND * 40), 100 + INT(RND * 30), 75 + INT(RND * 20))
                            END IF
                        END IF
                    NEXT j

                    ' player vs asteroid
                    E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                    asteroids(i).px, asteroids(i).py, asteroids(i).pz, boxLib(MESH_ASTEROID), hit
                    IF hit AND invTimer = 0 THEN
                        asteroids(i).active = 0
                        SND_Boom
                        FX_SpawnBurst asteroids(i).px, asteroids(i).py, asteroids(i).pz, 8, 0.18, 15, 7, _RGB(120 + INT(RND * 40), 100 + INT(RND * 30), 75 + INT(RND * 20))
                        PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
                    END IF
                END IF
            NEXT i

            ' --- update powerups ---
            FOR i = 1 TO MAX_POWERUPS
                IF powerups(i).active THEN
                    powerups(i).px  = powerups(i).px  + powerups(i).vx
                    powerups(i).ry  = powerups(i).ry  + powerups(i).dry
                    powerups(i).rz  = powerups(i).rz  + powerups(i).drz
                    IF powerups(i).px < -5 THEN powerups(i).active = 0

                    E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                    powerups(i).px, powerups(i).py, powerups(i).pz, boxLib(MESH_POWERUP), hit
                    IF hit THEN
                        powerups(i).active = 0
                        lives = lives + SHIELD_RESTORE
                        IF lives > 100 THEN lives = 100
                        score = score + SCORE_POWERUP
                        SND_Pup
                    END IF
                END IF
            NEXT i

            ' --- boss ---
            IF gameState = GS_PLAYING AND boss.active = 0 AND bossWarnTimer = 0 AND score >= stageScore THEN
                bossWarnTimer = BOSS_WARN_FRAMES
                SPK_Say "WARNING BOSS INCOMING"
            END IF
            IF bossWarnTimer > 0 THEN
                bossWarnTimer = bossWarnTimer - 1
                IF bossWarnTimer = 0 AND gameState = GS_PLAYING THEN
                    boss.active  = -1
                    boss.meshIdx = MESH_BOSS
                    boss.px = player.px + BOSS_SPAWN_DIST
                    boss.py = player.py
                    boss.pz = player.pz
                    boss.vx = -0.05
                    boss.scl = BOSS_SCALE
                    IF settingNerf THEN bossHP = BOSS_MAX_HP_NERF ELSE bossHP = BOSS_MAX_HP
                    bossPhase = 1
                    bossFireTimer = 2.5
                    bossMoveTimer = 0
                    bossTargetY = player.py
                    bossTargetZ = player.pz
                    bossState = 0
                    MUS_SetCue "boss"
                END IF
            END IF

            IF boss.active THEN
                ' phase thresholds
                IF bossHP > 20 THEN
                    bossPhase = 1
                ELSEIF bossHP > 10 THEN
                    bossPhase = 2
                ELSE
                    bossPhase = 3
                END IF

                ' X approach: hold at combat range
                IF boss.px > player.px + BOSS_COMBAT_DIST THEN
                    boss.px = boss.px + boss.vx * (1.0 + (bossPhase - 1) * 0.4)
                END IF

                ' intent-driven lateral movement (see behavior.bas)
                BOSS_UpdateMovement

                ' fire patterns
                bossFireTimer = bossFireTimer - 0.025
                IF bossFireTimer <= 0 THEN
                    eDX = player.px - boss.px
                    eDY = player.py - boss.py
                    eDZ = player.pz - boss.pz
                    eMag = SQR(eDX * eDX + eDY * eDY + eDZ * eDZ)
                    IF eMag > 0.1 THEN eDX = eDX/eMag : eDY = eDY/eMag : eDZ = eDZ/eMag
                    SELECT CASE bossPhase
                    CASE 1  ' 3-shot Y fan aimed at player
                        bossShots = 0
                        FOR ej = 1 TO MAX_EBULLETS
                            IF ebullets(ej).active = 0 AND bossShots < 3 THEN
                                ebullets(ej).active  = -1
                                ebullets(ej).meshIdx = MESH_BOSS
                                ebullets(ej).px = boss.px : ebullets(ej).py = boss.py : ebullets(ej).pz = boss.pz
                                ebullets(ej).vx = eDX * 0.26
                                ebullets(ej).vy = eDY * 0.26 + (bossShots - 1) * 0.07
                                ebullets(ej).vz = eDZ * 0.26
                                ebullets(ej).scl = 1.0
                                bossShots = bossShots + 1
                            END IF
                        NEXT ej
                        bossFireTimer = BOSS_FIRE1
                        BOSS_SetEvasion bossPhase
                    CASE 2  ' 5-shot aimed cross: center + 4 cardinal offsets
                        bossShots = 0
                        FOR ej = 1 TO MAX_EBULLETS
                            IF ebullets(ej).active = 0 AND bossShots < 5 THEN
                                ebullets(ej).active  = -1
                                ebullets(ej).meshIdx = MESH_BOSS
                                ebullets(ej).px = boss.px : ebullets(ej).py = boss.py : ebullets(ej).pz = boss.pz
                                ebullets(ej).vx = eDX * 0.30
                                SELECT CASE bossShots
                                CASE 0 : ebullets(ej).vy = eDY * 0.30        : ebullets(ej).vz = eDZ * 0.30
                                CASE 1 : ebullets(ej).vy = eDY * 0.30 - 0.11 : ebullets(ej).vz = eDZ * 0.30
                                CASE 2 : ebullets(ej).vy = eDY * 0.30 + 0.11 : ebullets(ej).vz = eDZ * 0.30
                                CASE 3 : ebullets(ej).vy = eDY * 0.30        : ebullets(ej).vz = eDZ * 0.30 - 0.11
                                CASE 4 : ebullets(ej).vy = eDY * 0.30        : ebullets(ej).vz = eDZ * 0.30 + 0.11
                                END SELECT
                                ebullets(ej).scl = 1.0
                                bossShots = bossShots + 1
                            END IF
                        NEXT ej
                        bossFireTimer = BOSS_FIRE2
                        BOSS_SetEvasion bossPhase
                    CASE 3  ' 7-shot diagonal fan aimed at player, fast — requires Y+Z dodge
                        bossShots = 0
                        FOR ej = 1 TO MAX_EBULLETS
                            IF ebullets(ej).active = 0 AND bossShots < 7 THEN
                                ebullets(ej).active  = -1
                                ebullets(ej).meshIdx = MESH_BOSS
                                ebullets(ej).px = boss.px : ebullets(ej).py = boss.py : ebullets(ej).pz = boss.pz
                                ebullets(ej).vx = eDX * 0.35
                                ebullets(ej).vy = eDY * 0.35 + (bossShots - 3) * 0.07
                                ebullets(ej).vz = eDZ * 0.35 + (bossShots - 3) * 0.07
                                ebullets(ej).scl = 1.0
                                bossShots = bossShots + 1
                            END IF
                        NEXT ej
                        bossFireTimer = BOSS_FIRE3
                        BOSS_SetEvasion bossPhase
                    END SELECT
                END IF

                ' player vs boss body
                E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                boss.px,   boss.py,   boss.pz,   boxLib(MESH_BOSS),   hit
                IF hit AND invTimer = 0 THEN
                    PLAYER_TakeDamage DMG_COLLISION, SHAKE_COLLISION, FLASH_COLLISION
                END IF

                ' player bullets vs boss
                FOR j = 1 TO MAX_BULLETS
                    IF bullets(j).active THEN
                        E3D_AABBOverlap boss.px, boss.py, boss.pz, boxLib(MESH_BOSS), _
                        bullets(j).px, bullets(j).py, bullets(j).pz, boxLib(MESH_BULLET), hit
                        IF hit THEN
                            bullets(j).active = 0
                            bossHP = bossHP - 1
                            fxShakeTimer = 2
                            SND_Boom
                            IF bossHP <= 0 THEN
                                boss.active   = 0
                                gameState     = GS_PLANET
                                planetTimer   = 1
                                MUS_SetCue "planet"
                                planetCurrent = (planetCurrent MOD PLANET_COUNT) + 1
                                planetNameIdx = (planetNameIdx MOD PLANET_COUNT) + 1
                                score = score + 2000
                                scorePopTimer = 40 : scorePopY = scrH * 0.38 : scorePopVal = 2000
                                pk = 0
                                FOR p = 1 TO FX_MAX_PARTICLES
                                    IF fxPartActive(p) = 0 AND pk < BOSS_DEATH_PARTS THEN
                                        fxPartActive(p) = -1
                                        fxPartPX(p) = boss.px + (RND - 0.5) * 5
                                        fxPartPY(p) = boss.py + (RND - 0.5) * 5
                                        fxPartPZ(p) = boss.pz + (RND - 0.5) * 5
                                        fxPartVX(p) = (RND - 0.5) * 0.40
                                        fxPartVY(p) = (RND - 0.5) * 0.40
                                        fxPartVZ(p) = (RND - 0.5) * 0.40
                                        fxPartLife(p) = 35 + INT(RND * 25)
                                        fxPartClr(p) = _RGB(255, INT(RND * 140) + 60, 0)
                                        pk = pk + 1
                                    END IF
                                NEXT p
                                MUS_SetCue "game"
                            END IF
                        END IF
                    END IF
                NEXT j
            END IF

            ' --- update enemy bullets ---
            FOR i = 1 TO MAX_EBULLETS
                IF ebullets(i).active THEN
                    ebullets(i).px = ebullets(i).px + ebullets(i).vx
                    ebullets(i).py = ebullets(i).py + ebullets(i).vy
                    ebullets(i).pz = ebullets(i).pz + ebullets(i).vz
                    IF ebullets(i).px < player.px - EBULLET_CULL THEN ebullets(i).active = 0

                    E3D_AABBOverlap player.px, player.py, player.pz, boxLib(MESH_PLAYER), _
                    ebullets(i).px, ebullets(i).py, ebullets(i).pz, boxLib(MESH_EBULLET), hit
                    IF hit AND invTimer = 0 THEN
                        ebullets(i).active = 0
                        PLAYER_TakeDamage DMG_LASER, SHAKE_LASER, FLASH_LASER
                    ELSEIF NOT hit THEN
                        ' near-miss: bullet just passed the player's X plane within a narrow lateral window
                        IF ebullets(i).px < player.px AND ebullets(i).px >= player.px - 0.42 THEN
                            eDY = ABS(ebullets(i).py - player.py)
                            eDZ = ABS(ebullets(i).pz - player.pz)
                            IF eDY < 5.0 AND eDZ < 5.0 THEN SND_Whoosh
                        END IF
                    END IF
                END IF
            NEXT i

            FX_Update

            E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z

            IF gameOver THEN
                IF score > highScore THEN highScore = score
                gameOverDelay = 90
                gameState = GS_GAMEOVER
                StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
                MUS_SetCue "gameover"
                SPK_Say "GAME OVER"
                gameOver = 0
            END IF
        END IF  ' not pauseFlag

        ' --------------------------------------------------------
        ' RENDER
        ' --------------------------------------------------------
        ' camera: nose-following, velocity-oriented (see player.bas)
        ' PLAYER_CamUpdate updates camLagY/Z and camFwdY/Z; cam fields set here
        ' because nested UDT field writes from included Subs don't update globals.
        PLAYER_CamUpdate
        IF gameState = GS_CINEMATIC THEN
            cam.POS.x = cinematicCamX
        ELSE
            cam.POS.x = player.px - CAM_OFFSET_X
        END IF
        cam.POS.y = camLagY + CAM_OFFSET_Y - camFwdY * CAM_FWD_SCALE
        cam.POS.z = camLagZ               - camFwdZ * CAM_FWD_SCALE
        IF gameState = GS_CINEMATIC THEN
            cam.target.x = cinematicCamX + CAM_OFFSET_X + CAM_LEAD_X
            cam.target.y = camLagY
            cam.target.z = camLagZ
        ELSE
            cam.target.x = player.px + CAM_LEAD_X
            cam.target.y = player.py + camFwdY * CAM_LEAD_X
            cam.target.z = player.pz + camFwdZ * CAM_LEAD_X
        END IF
        E3D_MatLookAt cam, viewMat
        E3D_MatMul projMat, viewMat, vpMat

        _DEST backBuffer
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 5, 185), BF

        E3D_StarfieldDraw vpMat, scrW, scrH

        ' planet: fades in and grows after boss defeat
        STAGE_DrawPlanet

        ' --- build and draw scene ---
        E3D_SceneBegin

        pPos.x = player.px : pPos.y = player.py : pPos.z = player.pz
        pRot.x = player.rx : pRot.y = player.ry : pRot.z = player.rz
        E3D_BuildObjectMat pPos, pRot, player.scl, objMat
        ' flash ship during invincibility (skip draw on alternating frames)
        IF invTimer = 0 OR (invTimer MOD 6) < 3 THEN
            E3D_SceneAddMeshLit meshLib(MESH_PLAYER), objMat, cam.POS, tt, lightDir
        END IF

        ' thruster glow at engine nozzle — brightness scales with thrusterScale
        thrusterLight.x = -(0.28 + thrusterScale * 0.85)
        thrusterLight.y = 0.0 : thrusterLight.z = 0.0
        pPos.x = player.px - 0.92 : pPos.y = player.py : pPos.z = player.pz
        E3D_BuildObjectMat pPos, pRot, thrusterScale, objMat
        IF invTimer = 0 OR (invTimer MOD 6) < 3 THEN
            E3D_SceneAddMeshLit meshLib(MESH_THRUSTER), objMat, cam.POS, tt, thrusterLight
        END IF

        FOR j = 1 TO MAX_ENEMIES
            IF enemies(j).active THEN
                IF enemies(j).px > cam.POS.x THEN
                    pPos.x = enemies(j).px : pPos.y = enemies(j).py : pPos.z = enemies(j).pz
                    pRot.x = enemies(j).rx : pRot.y = enemies(j).ry : pRot.z = enemies(j).rz
                    E3D_BuildObjectMat pPos, pRot, enemies(j).scl, objMat
                    ' distance dimming: enemies far ahead appear darker
                    eDist = enemies(j).px - player.px
                    IF eDist > DIM_FAR THEN
                        eDimF = DIM_AMBIENT
                    ELSEIF eDist > DIM_NEAR THEN
                        eDimF = DIM_AMBIENT + (eDist - DIM_NEAR) * ((1.0 - DIM_AMBIENT) / (DIM_FAR - DIM_NEAR))
                    ELSE
                        eDimF = 1.0
                    END IF
                    eLitDir.x = lightDir.x * eDimF
                    eLitDir.y = lightDir.y * eDimF
                    eLitDir.z = lightDir.z * eDimF
                    E3D_SceneAddMeshLit meshLib(enemies(j).meshIdx), objMat, cam.POS, tt, eLitDir
                END IF
            END IF
        NEXT j

        FOR j = 1 TO MAX_ASTEROIDS
            IF asteroids(j).active THEN
                IF asteroids(j).px > cam.POS.x THEN
                    pPos.x = asteroids(j).px : pPos.y = asteroids(j).py : pPos.z = asteroids(j).pz
                    pRot.x = asteroids(j).rx : pRot.y = asteroids(j).ry : pRot.z = asteroids(j).rz
                    E3D_BuildObjectMat pPos, pRot, asteroids(j).scl, objMat
                    E3D_SceneAddMeshLit meshLib(MESH_ASTEROID), objMat, cam.POS, tt, lightDir
                END IF
            END IF
        NEXT j

        IF boss.active THEN
            pPos.x = boss.px : pPos.y = boss.py : pPos.z = boss.pz
            pRot.x = boss.rx : pRot.y = boss.ry : pRot.z = boss.rz
            E3D_BuildObjectMat pPos, pRot, boss.scl, objMat
            eDist = boss.px - player.px
            IF eDist > DIM_FAR THEN
                eDimF = 0.35
            ELSEIF eDist > DIM_NEAR THEN
                eDimF = 0.35 + (eDist - DIM_NEAR) * (0.65 / (DIM_FAR - DIM_NEAR))
            ELSE
                eDimF = 1.0
            END IF
            eLitDir.x = lightDir.x * eDimF
            eLitDir.y = lightDir.y * eDimF
            eLitDir.z = lightDir.z * eDimF
            E3D_SceneAddMeshLit meshLib(MESH_BOSS), objMat, cam.POS, tt, eLitDir
        END IF

        FOR j = 1 TO MAX_POWERUPS
            IF powerups(j).active THEN
                IF powerups(j).px > cam.POS.x THEN
                    pPos.x = powerups(j).px : pPos.y = powerups(j).py : pPos.z = powerups(j).pz
                    pRot.x = powerups(j).rx : pRot.y = powerups(j).ry : pRot.z = powerups(j).rz
                    E3D_BuildObjectMat pPos, pRot, powerups(j).scl, objMat
                    E3D_SceneAddMeshLit meshLib(MESH_POWERUP), objMat, cam.POS, tt, lightDir
                END IF
            END IF
        NEXT j

        E3D_SceneFlush vpMat, scrW, scrH

        ' --- player bullets: depth-perspective laser lines ---
        _DEST backBuffer
        FOR j = 1 TO MAX_BULLETS
            IF bullets(j).active THEN
                ' project bolt tip (current pos)
                pjX  = bullets(j).px * vpMat.m(0,0) + bullets(j).py * vpMat.m(0,1) + bullets(j).pz * vpMat.m(0,2) + vpMat.m(0,3)
                pjY  = bullets(j).px * vpMat.m(1,0) + bullets(j).py * vpMat.m(1,1) + bullets(j).pz * vpMat.m(1,2) + vpMat.m(1,3)
                pjW  = bullets(j).px * vpMat.m(3,0) + bullets(j).py * vpMat.m(3,1) + bullets(j).pz * vpMat.m(3,2) + vpMat.m(3,3)
                ' project bolt rear (BULLET_TRAIL_LEN world-units behind tip along velocity axis)
                pjBX = bullets(j).px - bullets(j).vx * (BULLET_TRAIL_LEN / BULLET_SPEED)
                pjBY = bullets(j).py - bullets(j).vy * (BULLET_TRAIL_LEN / BULLET_SPEED)
                pjBZ = bullets(j).pz - bullets(j).vz * (BULLET_TRAIL_LEN / BULLET_SPEED)
                pjX2 = pjBX * vpMat.m(0,0) + pjBY * vpMat.m(0,1) + pjBZ * vpMat.m(0,2) + vpMat.m(0,3)
                pjY2 = pjBX * vpMat.m(1,0) + pjBY * vpMat.m(1,1) + pjBZ * vpMat.m(1,2) + vpMat.m(1,3)
                pjW2 = pjBX * vpMat.m(3,0) + pjBY * vpMat.m(3,1) + pjBZ * vpMat.m(3,2) + vpMat.m(3,3)
                IF pjW > 0.0001 AND pjW2 > 0.0001 THEN
                    pjX  = (pjX  / pjW  + 1.0) * scrW * 0.5
                    pjY  = (1.0 - pjY  / pjW)  * scrH * 0.5
                    pjX2 = (pjX2 / pjW2 + 1.0) * scrW * 0.5
                    pjY2 = (1.0 - pjY2 / pjW2) * scrH * 0.5
                    IF pjX >= 0 AND pjX < scrW AND pjY >= 0 AND pjY < scrH THEN
                        pjFade = bullets(j).life / (BULLET_RANGE / BULLET_SPEED)
                        IF pjFade > 1.0 THEN pjFade = 1.0
                        LINE (INT(pjX2), INT(pjY2))-(INT(pjX), INT(pjY)), _RGB(INT(210*pjFade), INT(215*pjFade), INT(60*pjFade))
                        PSET (INT(pjX), INT(pjY)), _RGB(INT(240*pjFade), INT(245*pjFade), INT(140*pjFade))
                    END IF
                END IF
            END IF
        NEXT j

        ' --- enemy bullets: cross in ship-type color ---
        FOR j = 1 TO MAX_EBULLETS
            IF ebullets(j).active THEN
                pjX = ebullets(j).px * vpMat.m(0,0) + ebullets(j).py * vpMat.m(0,1) + ebullets(j).pz * vpMat.m(0,2) + vpMat.m(0,3)
                pjY = ebullets(j).px * vpMat.m(1,0) + ebullets(j).py * vpMat.m(1,1) + ebullets(j).pz * vpMat.m(1,2) + vpMat.m(1,3)
                pjW = ebullets(j).px * vpMat.m(3,0) + ebullets(j).py * vpMat.m(3,1) + ebullets(j).pz * vpMat.m(3,2) + vpMat.m(3,3)
                IF pjW > 0.0001 THEN
                    pjX = (pjX / pjW + 1.0) * scrW * 0.5
                    pjY = (1.0 - pjY / pjW) * scrH * 0.5
                    IF pjX >= 4 AND pjX < scrW - 4 AND pjY >= 3 AND pjY < scrH - 3 THEN
                        SELECT CASE ebullets(j).meshIdx
                        CASE MESH_BOSS         : ebClr = _RGB(255, 200,   0)
                        CASE MESH_ENEMY        : ebClr = _RGB(255,  80,  60)
                        CASE MESH_ENEMY_ARROW  : ebClr = _RGB(220,  35,  65)
                        CASE MESH_ENEMY_HLINE  : ebClr = _RGB( 80, 140, 255)
                        CASE MESH_ENEMY_VCOL   : ebClr = _RGB(180,  65, 255)
                        CASE MESH_ENEMY_PINCER : ebClr = _RGB(255,  45, 190)
                        CASE ELSE              : ebClr = _RGB(185,  80, 255)
                        END SELECT
                        LINE (pjX - 4, pjY)-(pjX + 4, pjY), ebClr
                        LINE (pjX, pjY - 2)-(pjX, pjY + 2), ebClr
                        PSET (pjX, pjY), _RGB(255, 255, 255)
                    END IF
                END IF
            END IF
        NEXT j

        ' --- spawn entry flash ---
        _DEST backBuffer
        IF spawnFlashTimer > 0 THEN
            pjX = spawnFlashPX * vpMat.m(0,0) + spawnFlashPY * vpMat.m(0,1) + spawnFlashPZ * vpMat.m(0,2) + vpMat.m(0,3)
            pjY = spawnFlashPX * vpMat.m(1,0) + spawnFlashPY * vpMat.m(1,1) + spawnFlashPZ * vpMat.m(1,2) + vpMat.m(1,3)
            pjW = spawnFlashPX * vpMat.m(3,0) + spawnFlashPY * vpMat.m(3,1) + spawnFlashPZ * vpMat.m(3,2) + vpMat.m(3,3)
            IF pjW > 0.0001 THEN
                pjX = (pjX / pjW + 1.0) * scrW * 0.5
                pjY = (1.0 - pjY / pjW) * scrH * 0.5
                IF pjX >= 3 AND pjX < scrW - 3 AND pjY >= 3 AND pjY < scrH - 3 THEN
                    partR = spawnFlashTimer * 26
                    LINE (pjX - 4, pjY)-(pjX + 4, pjY), _RGB(partR, partR, partR)
                    LINE (pjX, pjY - 4)-(pjX, pjY + 4), _RGB(partR, partR, partR)
                END IF
            END IF
            spawnFlashTimer = spawnFlashTimer - 1
        END IF

        FX_Draw vpMat, scrW, scrH

        ' --- HUD ---
        HUD_Draw

        FX_Flash scrW, scrH

        ' cinematic fade-to-black — must be before FX_Shake which presents backBuffer
        IF cinematicFade > 0 THEN
            _DEST backBuffer
            LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, cinematicFade), BF
        END IF

        FX_Shake backBuffer, scrW, scrH

        IF gameState = GS_PLAYING THEN
            SND_GameFill isManeuver
        ELSE
            MUS_Fill 0
        END IF

        ' ============================================================
        ' TITLE SCREEN
        ' ============================================================
    CASE GS_TITLE
        tt = tt + 0.025
        _DEST backBuffer
        _PUTIMAGE (0, 0)-(scrW - 1, scrH - 1), titleImg, backBuffer
        ' translucent footer so text reads over the image art
        LINE (0, 196)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 175), BF
        throbBright = INT(170 + 85 * SIN(tt * 5))
        COLOR _RGB(throbBright, throbBright, throbBright)
        _PRINTSTRING (scrW / 2 - 80, 200), "PRESS SPACE TO START"
        IF highScore > 0 THEN
            FONT_PrintCentered fontPalette(14), backBuffer, "BEST: " + LTRIM$(STR$(highScore)), 218, scrW
        END IF
        FONT_Print fontPalette(8), backBuffer, "ESC  OPTIONS", 2, scrH - FONT_CHAR_H
        FONT_Print fontPalette(8), backBuffer, "v" + VERSION$, scrW - LEN("v" + VERSION$) * FONT_CHAR_W - 2, scrH - FONT_CHAR_H
        IF titleEscConfirm THEN
            UI_DrawPanel scrW\2 - 76, scrH\2 - 48, scrW\2 + 76, scrH\2 + 48, "COMMAND CONSOLE"
            FONT_PrintCentered fontPalette(9),  backBuffer, "A   ABOUT",       scrH\2 - 30, scrW
            FONT_PrintCentered fontPalette(9),  backBuffer, "S   SETTINGS",    scrH\2 - 16, scrW
            FONT_PrintCentered fontPalette(14), backBuffer, "Y   QUIT GAME",   scrH\2 -  2, scrW
            FONT_PrintCentered fontPalette(8),  backBuffer, "ESC CANCEL",      scrH\2 + 12, scrW
        END IF
        _DEST 0
        _PUTIMAGE , backBuffer, 0
        ' ESC: rising edge toggles quit-confirm; Y exits, N/ESC cancels
        IF held(E3D_KEY_ESCAPE) AND NOT escWas THEN titleEscConfirm = 1 - titleEscConfirm
        escWas = held(E3D_KEY_ESCAPE)
        IF titleEscConfirm THEN
            IF _KEYDOWN(65) OR _KEYDOWN(97) THEN  ' A — about
            ABOUT_Prep : gameState = GS_ABOUT : titleEscConfirm = 0
        END IF
        IF _KEYDOWN(83) OR _KEYDOWN(115) THEN  ' S — settings
        gameState = GS_OPTIONS : titleEscConfirm = 0
        optUpWas = -1 : optDnWas = 0 : optLfWas = 0 : optRtWas = 0 : optEscWas = -1 : optAboutWas = _KEYDOWN(65) OR _KEYDOWN(97)
    END IF
    IF _KEYDOWN(89) OR _KEYDOWN(121) THEN EXIT DO
    IF _KEYDOWN(78) OR _KEYDOWN(110) THEN titleEscConfirm = 0
    MUS_Fill 0
    EXIT SELECT
END IF
MUS_Fill 0
IF held(E3D_KEY_SPACE) AND NOT spaceWas THEN GAME_NewGame
spaceWas = held(E3D_KEY_SPACE)

' ============================================================
' INTRO SCREEN — emperor reveal
' ============================================================
CASE GS_INTRO
    tt = tt + 0.025
    introTimer = introTimer + 1
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    IF emperorImg <> 0 THEN
        _PUTIMAGE (10, 0)-(309, scrH - 1), emperorImg, backBuffer
    END IF
    ' emperor name + prompt footer bar
    LINE (0, scrH - 38)-(scrW - 1, scrH - 1), _RGBA(0, 0, 8, 210), BF
    FONT_PrintCentered fontPalette(14), backBuffer, emperorName, scrH - 34, scrW
    IF introTimer > 60 THEN
        throbBright = INT(160 + 95 * SIN(tt * 5))
        COLOR _RGB(throbBright, throbBright, throbBright)
        _PRINTSTRING (scrW\2 - 44, scrH - 14), "PRESS SPACE"
    END IF
    ' fade in from black
    IF introTimer < 40 THEN
        LINE (0, 0)-(scrW - 1, scrH - 1), _RGBA(0, 0, 0, 255 - introTimer * 6), BF
    END IF
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    IF held(E3D_KEY_ESCAPE) AND NOT escWas THEN gameState = GS_TITLE : introTimer = 0 : MUS_SetCue "title"
    escWas = held(E3D_KEY_ESCAPE)
    IF held(E3D_KEY_SPACE) AND NOT spaceWas AND introTimer > 45 THEN
        introTimer = 0 : SEQ_Advance
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    MUS_Fill 0

    ' ============================================================
    ' TEXT CRAWL — stage narrative scroll
    ' ============================================================
CASE GS_CRAWL
    IF crawlLineCount = 0 THEN SEQ_Advance : EXIT SELECT
    ' on first frame (crawlTimer=0 set by CRAWL_Prep), reset starfield to crawl camera
    IF crawlTimer = 0 THEN
        StarfieldReset -CAM_OFFSET_X, CAM_OFFSET_Y, 0
        MUS_SetCue "crawl"
    END IF
    tt = tt + 0.025
    crawlTimer = crawlTimer + 1
    IF held(E3D_KEY_SPACE) AND crawlTimer > 60 THEN
        crawlScroll = crawlScroll - CRAWL_SPEED * 5
    ELSE
        crawlScroll = crawlScroll - CRAWL_SPEED
    END IF
    ' Fire each paragraph's speech when its first line scrolls near the bottom.
    ' All paragraphs use the same crawlRateScale (computed in CRAWL_Prep) so the
    ' entire narration fills the crawl window at a consistent pace.
    IF settingNarration AND NOT (held(E3D_KEY_SPACE) AND crawlTimer > 60) THEN
        DO WHILE crawlParaIdx < crawlParaCount
            IF crawlScroll + crawlParaLine(crawlParaIdx) * CRAWL_LINE_H > scrH - CRAWL_LINE_H THEN EXIT DO
            IF crawlParaIdx > 0 AND SPK_IsPlaying% THEN EXIT DO
            SPK_Say crawlParaText$(crawlParaIdx)
            spkRateScale = crawlRateScale
            crawlParaIdx = crawlParaIdx + 1
        LOOP
    ELSE
        crawlParaIdx = crawlParaCount  ' narration off: mark all paragraphs done
    END IF

    cam.POS.x = -CAM_OFFSET_X : cam.POS.y = CAM_OFFSET_Y : cam.POS.z = 0
    cam.target.x = CAM_LEAD_X : cam.target.y = 0 : cam.target.z = 0
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat
    E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z

    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH

    ' Fetch current spoken word once; used in both the line loop and bottom indicator
    DIM crawlSpkW AS STRING
    DIM crawlHiVis AS STRING, crawlHiViU AS STRING, crawlHiPos AS INTEGER, crawlHiX AS INTEGER
    DIM crawlSpkOcc AS INTEGER, crawlHiPara AS INTEGER
    DIM crawlScanI AS INTEGER, crawlScanV AS STRING, crawlScanP AS INTEGER
    DIM crawlPriorOcc AS INTEGER, crawlLineOcc AS INTEGER, crawlHiLB AS INTEGER, crawlHiRB AS INTEGER
    crawlSpkW = SPK_CurWord$
    crawlSpkOcc = SPK_CurWordOcc%
    crawlHiPara = crawlParaIdx - 1 : IF crawlHiPara < 0 THEN crawlHiPara = 0

    FOR crawlIdx = 0 TO crawlLineCount - 1
        crawlLY = INT(crawlScroll + crawlIdx * CRAWL_LINE_H)
        IF crawlLY > -CRAWL_LINE_H AND crawlLY < scrH THEN
            IF LEN(crawlLines$(crawlIdx)) > 0 THEN
                FONT_PrintCenteredRich fontPalette(), backBuffer, crawlLines$(crawlIdx), crawlLY, scrW
                ' Inline highlight: redraw the exact spoken word occurrence in cyan.
                ' Restricted to the active paragraph's lines; uses whole-word matching
                ' and occurrence index so only one instance lights up at a time.
                IF LEN(crawlSpkW) > 0 AND crawlIdx >= crawlParaLine(crawlHiPara) AND crawlIdx <= crawlParaLastLine(crawlHiPara) THEN
                    crawlHiVis = CRAWL_VisText$(crawlLines$(crawlIdx))
                    crawlHiViU = UCASE$(crawlHiVis)
                    ' count whole-word occurrences in earlier lines of this paragraph
                    crawlPriorOcc = 0
                    FOR crawlScanI = crawlParaLine(crawlHiPara) TO crawlIdx - 1
                        crawlScanV = UCASE$(CRAWL_VisText$(crawlLines$(crawlScanI)))
                        crawlScanP = 1
                        DO
                            crawlScanP = INSTR(crawlScanP, crawlScanV, crawlSpkW)
                            IF crawlScanP = 0 THEN EXIT DO
                            crawlHiLB = 0 : IF crawlScanP > 1 THEN crawlHiLB = ASC(MID$(crawlScanV, crawlScanP - 1, 1))
                            crawlHiRB = 0 : IF crawlScanP + LEN(crawlSpkW) <= LEN(crawlScanV) THEN crawlHiRB = ASC(MID$(crawlScanV, crawlScanP + LEN(crawlSpkW), 1))
                            IF (crawlHiLB < 65 OR crawlHiLB > 90) AND (crawlHiRB < 65 OR crawlHiRB > 90) THEN crawlPriorOcc = crawlPriorOcc + 1
                            crawlScanP = crawlScanP + LEN(crawlSpkW)
                        LOOP
                    NEXT crawlScanI
                    ' find the target occurrence on this line
                    crawlHiPos = 1 : crawlLineOcc = 0
                    DO
                        crawlHiPos = INSTR(crawlHiPos, crawlHiViU, crawlSpkW)
                        IF crawlHiPos = 0 THEN EXIT DO
                        crawlHiLB = 0 : IF crawlHiPos > 1 THEN crawlHiLB = ASC(MID$(crawlHiViU, crawlHiPos - 1, 1))
                        crawlHiRB = 0 : IF crawlHiPos + LEN(crawlSpkW) <= LEN(crawlHiViU) THEN crawlHiRB = ASC(MID$(crawlHiViU, crawlHiPos + LEN(crawlSpkW), 1))
                        IF (crawlHiLB < 65 OR crawlHiLB > 90) AND (crawlHiRB < 65 OR crawlHiRB > 90) THEN
                            IF crawlPriorOcc + crawlLineOcc = crawlSpkOcc THEN
                                crawlHiX = (scrW - CRAWL_VisLen%(crawlLines$(crawlIdx)) * FONT_CHAR_W) \ 2
                                crawlHiX = crawlHiX + (crawlHiPos - 1) * FONT_CHAR_W
                                FONT_Print fontPalette(11), backBuffer, MID$(crawlHiVis, crawlHiPos, LEN(crawlSpkW)), crawlHiX, crawlLY
                                EXIT DO
                            END IF
                            crawlLineOcc = crawlLineOcc + 1
                        END IF
                        crawlHiPos = crawlHiPos + LEN(crawlSpkW)
                    LOOP
                END IF
            END IF
        END IF
    NEXT crawlIdx

    ' fade band at top — text fades out as it approaches the vanishing point
    FOR crawlFY = 0 TO 47
        LINE (0, crawlFY)-(scrW - 1, crawlFY), _RGBA(0, 0, 5, 255 - crawlFY * 5), BF
    NEXT crawlFY
    ' fade band at bottom — new text fades in from below
    FOR crawlFY = 0 TO 31
        LINE (0, scrH - 1 - crawlFY)-(scrW - 1, scrH - 1 - crawlFY), _RGBA(0, 0, 5, 200 - crawlFY * 6), BF
    NEXT crawlFY

    ' Bottom-left word chip (` toggles both this and the inline highlight)
    IF crawlSpkOverlay AND LEN(crawlSpkW) > 0 THEN
        LINE (0, scrH - FONT_CHAR_H - 3)-(LEN(crawlSpkW) * FONT_CHAR_W + 7, scrH - 1), _RGB(0, 20, 60), BF
        FONT_Print fontPalette(10), backBuffer, crawlSpkW, 4, scrH - FONT_CHAR_H - 1
    END IF
    ' FFWD lozenge hint — always visible after lock-out period
    IF crawlTimer > 60 AND held(E3D_KEY_SPACE) THEN
        DIM crawlFFHint AS STRING : crawlFFHint = ">> FAST FORWARD <<"
        DIM crawlFFHX AS INTEGER : crawlFFHX = (scrW - LEN(crawlFFHint) * FONT_CHAR_W) \ 2
        LINE (crawlFFHX - 5, scrH - FONT_CHAR_H - 5)-(crawlFFHX + LEN(crawlFFHint) * FONT_CHAR_W + 4, scrH - 1), _RGBA(0, 8, 24, 210), BF
        FONT_Print fontPalette(14), backBuffer, crawlFFHint, crawlFFHX, scrH - FONT_CHAR_H - 2
    END IF

    ' auto-advance when last line has cleared the top fade band
    IF crawlScroll + crawlLineCount * CRAWL_LINE_H < -20 THEN
        crawlParaIdx = crawlParaCount : SPK_Say ""
        fxVCRActive = 0 : IF crawlFFActive THEN volMusic = crawlFFVolSave : crawlFFActive = 0
        SEQ_Advance
        EXIT SELECT
    END IF
    ' SPACE held = fast-forward (locked 1 sec to prevent accidental carry-through from intro)
    IF crawlTimer > 60 THEN
        IF held(E3D_KEY_SPACE) THEN
            IF NOT crawlFFActive THEN
                crawlFFVolSave = volMusic : volMusic = 0 : SPK_Say "" : crawlFFActive = -1
            END IF
            fxVCRActive = -1
            IF settingNarration AND (crawlTimer MOD 4) = 0 THEN SND_Blip 400 + INT(RND * 1200)
        ELSE
            IF crawlFFActive THEN
                volMusic = crawlFFVolSave : crawlFFActive = 0
                IF settingNarration THEN
                    ' Find highest-indexed paragraph whose trigger scroll has been passed
                    DIM crawlResI AS INTEGER : crawlResI = -1
                    DIM crawlResP AS INTEGER
                    FOR crawlResP = crawlParaCount - 1 TO 0 STEP -1
                        IF crawlScroll + crawlParaLine(crawlResP) * CRAWL_LINE_H <= scrH - CRAWL_LINE_H THEN
                            crawlResI = crawlResP : EXIT FOR
                        END IF
                    NEXT crawlResP
                    IF crawlResI < 0 THEN
                        crawlParaIdx = 0  ' nothing triggered yet; let trigger loop handle entry
                    ELSE
                        ' Build phoneme queue then skip past the portion that would already have played
                        SPK_Say crawlParaText$(crawlResI)
                        spkRateScale = crawlRateScale
                        DIM crawlSyncS AS SINGLE
                        crawlSyncS = (scrH - CRAWL_LINE_H) - crawlParaLine(crawlResI) * CRAWL_LINE_H
                        DIM crawlSyncEla AS LONG
                        crawlSyncEla = CLNG((crawlSyncS - crawlScroll) / CRAWL_SPEED / 60.0 * SAMPLE_RATE)
                        DIM crawlSyncJ AS INTEGER : crawlSyncJ = 0
                        DIM crawlSyncDur AS LONG : crawlSyncDur = 0
                        DO WHILE crawlSyncJ < spkPhoneCount
                            DIM crawlSyncPD AS LONG
                            crawlSyncPD = CLNG(spkDur(spkPhones(crawlSyncJ), spkStress(crawlSyncJ)) * crawlRateScale)
                            IF crawlSyncDur + crawlSyncPD > crawlSyncEla THEN EXIT DO
                            crawlSyncDur = crawlSyncDur + crawlSyncPD
                            crawlSyncJ = crawlSyncJ + 1
                        LOOP
                        IF crawlSyncJ >= spkPhoneCount THEN
                            ' Paragraph fully elapsed; silence queue and advance to next
                            spkPhoneCount = 0 : spkPhoneIdx = 0 : spkSamplePos = 0
                        ELSE
                            spkPhoneIdx = crawlSyncJ : spkSamplePos = 0
                        END IF
                        crawlParaIdx = crawlResI + 1
                    END IF
                ELSE
                    crawlParaIdx = crawlParaCount
                END IF
            END IF
            fxVCRActive = 0
        END IF
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    ' ` toggles speech word overlay (inline highlight + bottom chip)
    IF _KEYDOWN(96) THEN
        IF NOT crawlBtWas THEN crawlSpkOverlay = 1 - crawlSpkOverlay
        crawlBtWas = -1
    ELSE
        crawlBtWas = 0
    END IF

    _DEST 0 : _PUTIMAGE , backBuffer, 0
    FX_VCRNoise scrW, scrH
    MUS_Fill 0

    ' ============================================================
    ' GAME OVER SCREEN
    ' ============================================================
CASE GS_GAMEOVER
    tt = tt + 0.025
    cam.POS.x = -CAM_OFFSET_X : cam.POS.y = CAM_OFFSET_Y : cam.POS.z = 0
    cam.target.x = CAM_LEAD_X : cam.target.y = 0 : cam.target.z = 0
    E3D_MatLookAt cam, viewMat
    E3D_MatMul projMat, viewMat, vpMat
    E3D_StarfieldUpdate cam.POS.x, cam.POS.y, cam.POS.z
    _DEST backBuffer
    LINE (0, 0)-(scrW - 1, scrH - 1), _RGB(0, 0, 5), BF
    E3D_StarfieldDraw vpMat, scrW, scrH
    gameOverDelay = gameOverDelay - 1
    FONT_PrintCentered fontPalette(14), backBuffer, "GAME OVER", scrH \ 2 - 28, scrW
    FONT_PrintCentered fontPalette(9), backBuffer, "SCORE:  " + LTRIM$(STR$(score)), scrH \ 2 - 8, scrW
    IF score >= highScore THEN
        COLOR _RGB(255, 220, 60)
    ELSE
        COLOR _RGB(170, 170, 170)
    END IF
    _PRINTSTRING (scrW / 2 - 48, scrH / 2 +  8), "BEST:   " + LTRIM$(STR$(highScore))
    IF gameOverDelay <= 0 THEN
        throbBright = INT(170 + 85 * SIN(tt * 5))
        COLOR _RGB(throbBright, throbBright, throbBright)
        _PRINTSTRING (scrW / 2 - 80, scrH / 2 + 28), "PRESS SPACE TO PLAY"
        IF held(E3D_KEY_SPACE) AND NOT spaceWas THEN gameState = GS_TITLE : SEQ_RewindToTitle : MUS_SetCue "title"
    END IF
    spaceWas = held(E3D_KEY_SPACE)
    _DEST 0
    _PUTIMAGE , backBuffer, 0
    MUS_Fill 0

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
END IF

_LIMIT 60
_DISPLAY
LOOP

SUB StarfieldReset(srX AS SINGLE, srY AS SINGLE, srZ AS SINGLE)
    E3D_StarfieldInit srX, srY, srZ
    E3D_StarfieldAddLayer srX, srY, srZ, 200, 50, 50, 40, 0.010, 0.020, 0
    E3D_StarfieldAddLayer srX, srY, srZ,  60, 40, 30, 25, 0.035, 0.070, 1
    E3D_StarfieldAddLayer srX, srY, srZ,  15, 25, 15, 12, 0.100, 0.180, 2
END SUB

SUB PLAYER_TakeDamage(ptDmg AS INTEGER, ptShake AS INTEGER, ptFlash AS INTEGER)
    lives = lives - ptDmg
    fxShakeTimer = ptShake : fxFlashTimer = ptFlash
    SND_Hit
    IF lives <= 0 THEN
        shipLives = shipLives - 1
        IF shipLives <= 0 THEN
            gameOver = -1
        ELSE
            lives = 100 : invTimer = 240 : fuelLevel = 100.0 : fuelStranded = 0
        END IF
    END IF
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
  PRINT #guFH, "  --nerf                 Nerf mode: 10 kills trigger boss (was 1000), boss has 10 HP (was 30)"
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
