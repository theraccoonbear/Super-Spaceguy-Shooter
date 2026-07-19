CONST SAMPLE_RATE = 44100  ' audio sample rate; used by speech.bas and snd.bas

' --- game state constants ---
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

' --- object pool limits ---
CONST MAX_ENEMIES   = 35
CONST MAX_BULLETS   = 30
CONST MAX_ASTEROIDS = 25
CONST MAX_POWERUPS  = 5
CONST MAX_EBULLETS  = 24

' --- mesh indices and pool limits ---
CONST MESH_PLAYER       = 1
CONST MESH_ENEMY        = 2
CONST MESH_ASTEROID     = 3
CONST MESH_BULLET       = 4
CONST MESH_POWERUP      = 5
CONST MESH_ENEMY_ARROW  = 6
CONST MESH_ENEMY_HLINE  = 7
CONST MESH_ENEMY_VCOL   = 8
CONST MESH_ENEMY_PINCER = 9
CONST MESH_ENEMY_VWEDGE = 10
CONST MESH_THRUSTER     = 11
CONST MESH_EBULLET      = 12
CONST MESH_BOSS         = 13
CONST MESH_COUNT        = 13

' --- boss / stage globals ---
CONST NERF_FACTOR       = 0.1                        ' all nerf-mode quantities are this fraction of normal
CONST BOSS_MAX_HP       = 30
CONST BOSS_MAX_HP_NERF  = BOSS_MAX_HP * NERF_FACTOR  ' 3
CONST BOSS_TRIGGER      = 1000
CONST BOSS_TRIGGER_NERF = BOSS_TRIGGER * NERF_FACTOR ' 100
CONST BOSS_WARN_FRAMES  = 120   ' frames of warning before boss spawns
CONST PLANET_COUNT     = 6
CONST HIT_SCALE        = 1.5    ' enemy AABB scale factor for hit detection (visual stays unchanged)

' --- level types ---
CONST LEVEL_COMBAT   = 0
CONST LEVEL_ASTEROID = 1
CONST LEVEL_BOSS     = 2

' --- camera ---
CONST CAM_OFFSET_X  = 6.5
CONST CAM_OFFSET_Y  = 2.0
CONST CAM_LEAD_X    = 8
CONST CAM_LAG_RATE  = 0.08
CONST CAM_FWD_RATE  = 0.04
CONST CAM_FWD_SCALE = 1.0
CONST GAME_FOV      = 72

' --- difficulty ramp (used by sequence.bas before wave.bas is included) ---
CONST DIFF_RAMP_DURATION = 600.0   ' play-seconds to reach max difficulty
CONST DIFF_STAGE_COUNT   = 6.0     ' number of SEQ_PLAY stages; each opens at its floor

' --- enemy behavior (ENEMY_STRAFE_COOL used by wave.bas before enemy.bas is included) ---
CONST ENEMY_HOMING_SCALE  = 0.016  ' homing lerp rate at diffScale = 1.0
CONST ENEMY_HOMING_REXT   = 20     ' extra homing range at diffScale = 1.0
CONST ENEMY_STRAFE_MAG    = 0.018  ' lateral strafe impulse per unit of diffScale
CONST ENEMY_STRAFE_COOL   = 60     ' base frames between strafe bursts
CONST ENEMY_NEAR_MISS_RAD = 3.5    ' Y/Z radius for near-miss break detection
CONST ENEMY_BREAK_VEL     = 0.032  ' lateral velocity kick magnitude on break

' --- game object types ---
TYPE GameObj
    active  AS INTEGER
    meshIdx AS INTEGER
    px AS SINGLE : py AS SINGLE : pz AS SINGLE
    vx AS SINGLE : vy AS SINGLE : vz AS SINGLE
    rx AS SINGLE : ry AS SINGLE : rz AS SINGLE
    drx AS SINGLE : dry AS SINGLE : drz AS SINGLE
    scl AS SINGLE
    life AS SINGLE
    strafeCool AS INTEGER
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

' --- game objects ---
DIM SHARED player   AS GameObj
DIM SHARED enemies(1 TO MAX_ENEMIES) AS GameObj
DIM SHARED boss     AS BossObj

' --- display ---
DIM SHARED scrW AS SINGLE, scrH AS SINGLE
DIM SHARED backBuffer AS LONG
DIM SHARED fontPalette(0 TO 15) AS LONG
DIM SHARED planetImages(1 TO PLANET_COUNT) AS LONG
DIM SHARED planetNames(1 TO PLANET_COUNT) AS STRING
DIM SHARED planetCurrent AS INTEGER : planetCurrent = PLANET_COUNT
DIM SHARED planetNameIdx AS INTEGER : planetNameIdx = PLANET_COUNT

' --- game object pools ---
DIM SHARED bullets(1 TO MAX_BULLETS)     AS GameObj
DIM SHARED asteroids(1 TO MAX_ASTEROIDS) AS GameObj
DIM SHARED powerups(1 TO MAX_POWERUPS)   AS GameObj
DIM SHARED ebullets(1 TO MAX_EBULLETS)   AS GameObj
DIM SHARED enemyFireTimer(1 TO MAX_ENEMIES) AS SINGLE

' --- game state ---
DIM SHARED score AS LONG
DIM SHARED highScore AS LONG
DIM SHARED stageScore AS LONG     : stageScore = BOSS_TRIGGER
DIM SHARED stageScoreBase AS LONG : stageScoreBase = 0
DIM SHARED lives AS INTEGER : lives = 100
DIM SHARED shipLives AS INTEGER : shipLives = 3
DIM SHARED tt AS SINGLE
DIM SHARED spawnTimer AS SINGLE
DIM SHARED camF AS CamFollow
DIM SHARED playerVY AS SINGLE, playerVZ AS SINGLE
DIM SHARED isManeuver AS INTEGER
DIM SHARED laserEnergy AS SINGLE : laserEnergy = 100.0
DIM SHARED fuelLevel AS SINGLE : fuelLevel = 100.0
DIM SHARED fuelStranded AS INTEGER
DIM SHARED scorePopTimer AS INTEGER, scorePopY AS SINGLE, scorePopVal AS LONG
DIM SHARED spawnFlashTimer AS INTEGER
DIM SHARED spawnFlashPX AS SINGLE, spawnFlashPY AS SINGLE, spawnFlashPZ AS SINGLE
DIM SHARED planetTimer AS INTEGER
DIM SHARED planetSeq AS INTEGER
DIM SHARED planetTick AS INTEGER
DIM SHARED planetR AS SINGLE
DIM SHARED planetDefDone AS INTEGER
DIM SHARED planetBgR AS SINGLE     : planetBgR = 3.0
DIM SHARED planetBgAlpha AS SINGLE : planetBgAlpha = 245.0
DIM SHARED cinematicCamX AS SINGLE
DIM SHARED shipCinVX AS SINGLE
DIM SHARED cinematicFade AS INTEGER
DIM SHARED cinPhase AS SINGLE
DIM SHARED gameState AS INTEGER
DIM SHARED prevGameState AS INTEGER : prevGameState = -1
DIM SHARED gameOver AS INTEGER

' --- settings ---
DIM SHARED volMusic  AS SINGLE : volMusic  = 0.3
DIM SHARED volSfx    AS SINGLE : volSfx    = 0.9
DIM SHARED volSpeech AS SINGLE : volSpeech = 0.4
DIM SHARED settingNarration  AS INTEGER : settingNarration  = 1
DIM SHARED settingFullscreen AS INTEGER : settingFullscreen = 1
DIM SHARED settingNerf AS INTEGER
DIM SHARED godMode    AS INTEGER
DIM SHARED debugMode  AS INTEGER

' --- options UI ---
DIM SHARED optSel      AS INTEGER
DIM SHARED optUpWas    AS INTEGER
DIM SHARED optDnWas    AS INTEGER
DIM SHARED optLfWas    AS INTEGER
DIM SHARED optRtWas    AS INTEGER
DIM SHARED optLfRpt    AS INTEGER
DIM SHARED optRtRpt    AS INTEGER
DIM SHARED optEscWas   AS INTEGER
DIM SHARED optAboutWas AS INTEGER

DIM SHARED thrusterScale AS SINGLE

' --- gameplay timers / misc ---
DIM SHARED levelNum      AS INTEGER
DIM SHARED levelType     AS INTEGER
DIM SHARED astParsecs        AS INTEGER                          ' parsec display total for the asteroid stage HUD gauge
Const ASTFIELD_DURATION      = 120.0  ' tt-ticks to survive the asteroid stage (≈80s at 60fps)
Const ASTFIELD_FUEL_DRAIN_PT = 0.74   ' fuel units per tt-tick (FUEL_DRAIN 0.0185/frame * 40 frames/tick)
Const ASTFIELD_FUEL_FRAC     = 0.50   ' fraction of field's base-drain cost on arrival — tune for evasive margin
DIM SHARED astFieldStart AS SINGLE
DIM SHARED astDestName   AS STRING
DIM SHARED astNmSndCool   AS INTEGER
DIM SHARED astIdleTimer   AS INTEGER
DIM SHARED astForceTarget AS INTEGER
DIM SHARED astSpawnXBias  AS SINGLE
DIM SHARED invTimer   AS INTEGER
DIM SHARED deathTimer AS INTEGER
DIM SHARED diffTime AS SINGLE
DIM SHARED diffScale AS SINGLE
DIM SHARED fTypeToMesh(0 TO 5) AS INTEGER
DIM SHARED waveType AS INTEGER, waveCount AS INTEGER, wavePrev AS INTEGER
DIM SHARED held(0 TO 32767) AS INTEGER
DIM SHARED fireTimer AS SINGLE

' --- telemetry ---
DIM SHARED dbgTtyOK          AS INTEGER
DIM SHARED telemOn           AS INTEGER
DIM SHARED telemKills        AS LONG
DIM SHARED telemBossReached  AS INTEGER
DIM SHARED telemBossPhaseLog AS INTEGER
DIM SHARED telemDeathCause   AS STRING
DIM SHARED telemSession      AS STRING
DIM SHARED telemShotsFired   AS LONG
DIM SHARED telemShotsHit     AS LONG
DIM SHARED telemEscapes      AS LONG

' --- speech cues ---
DIM SHARED sSpkTitle    AS STRING
DIM SHARED sSpkGameOver AS STRING

' --- state-sub vars ---
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
DIM SHARED escConfirm      AS INTEGER
DIM SHARED escYWas         AS INTEGER
DIM SHARED escNWas         AS INTEGER
DIM SHARED tabWas          AS INTEGER
DIM SHARED rWas            AS INTEGER
DIM SHARED camUpWas        AS INTEGER
DIM SHARED camDnWas        AS INTEGER
DIM SHARED cliScene        AS STRING
DIM SHARED cliSceneType    AS STRING

' --- debug ---
DIM SHARED dbgOverlay  AS INTEGER
DIM SHARED dbgGraveWas AS INTEGER
DIM SHARED dbgT0       AS DOUBLE

' --- engine / render ---
DIM SHARED vpMat AS E3D_Matrix4
DIM SHARED boxLib(1 TO MESH_COUNT) AS E3D_AABB
DIM SHARED cam          AS E3D_Camera
DIM SHARED projMat      AS E3D_Matrix4
DIM SHARED viewMat      AS E3D_Matrix4
DIM SHARED objMat       AS E3D_Matrix4
DIM SHARED pPos         AS E3D_Coord
DIM SHARED pRot         AS E3D_Coord
DIM SHARED thrusterLight AS E3D_Coord
DIM SHARED eLitDir      AS E3D_Coord
DIM SHARED lightDir     AS E3D_Coord
DIM SHARED meshLib(1 TO MESH_COUNT) AS E3D_Mesh
