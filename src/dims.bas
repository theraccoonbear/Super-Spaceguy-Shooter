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
DIM SHARED stageScore AS LONG  : stageScore = BOSS_TRIGGER
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
DIM SHARED invTimer AS INTEGER
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
