' settingsprobe.bas -- picks where sss_settings.ini and the telemetry CSV live (#284, #283)
'
' Module-level code, run with GOSUB ioProbeRun (it stays a block here, not a SUB, because
' QB64-PE rejects the ON ERROR GOTO / label pattern inside a SUB; tests include this file
' and GOSUB it too).
'   in:  ioDirs(1) = the preferred settings folder ("" if none), ioDirs(2) = the launch folder,
'        ioMigrateWanted = copy a launch-folder sss_settings.ini into a new settings folder
'   out: settingsDir (first of the two that is writable, "" = read-only session, ioReadOnly set),
'        telemCsvDir (the launch folder if writable), ioMigrated
' A folder that is missing is created, parents included. An error here never reaches the player.
DIM SHARED ioDirs(1 TO 2) AS STRING, ioOk(1 TO 2) AS INTEGER, ioI AS INTEGER, ioFail AS INTEGER
DIM SHARED ioMissing(1 TO 16) AS STRING, ioMissN AS INTEGER, ioPath AS STRING, ioProbe AS INTEGER
DIM SHARED ioMigrated AS INTEGER, ioMigrateWanted AS INTEGER

GOTO ioProbeEnd

ioProbeRun:
settingsDir = "" : ioReadOnly = 0 : telemCsvDir = "" : ioMigrated = 0
ON ERROR GOTO ioProbeFail
FOR ioI = 1 TO 2
    ioFail = 0
    IF ioDirs(ioI) = "" THEN ioFail = -1
    ioMissN = 0
    ioPath = ioDirs(ioI)
    DO WHILE ioFail = 0 AND ioPath <> "" AND ioMissN < 16
        IF _DIREXISTS(ioPath) THEN EXIT DO
        ioMissN = ioMissN + 1
        ioMissing(ioMissN) = ioPath
        ioPath = SETTINGS_Parent$(ioPath)
    LOOP
    DO WHILE ioFail = 0 AND ioMissN > 0
        MKDIR ioMissing(ioMissN)
        ioMissN = ioMissN - 1
    LOOP
    IF ioFail = 0 THEN
        ioProbe = FREEFILE
        OPEN ioDirs(ioI) + "/sss_write_probe.tmp" FOR OUTPUT AS #ioProbe
        IF ioFail = 0 THEN CLOSE #ioProbe
        IF ioFail = 0 THEN KILL ioDirs(ioI) + "/sss_write_probe.tmp"
    END IF
    ioOk(ioI) = (ioFail = 0)
NEXT ioI
ON ERROR GOTO 0
IF ioOk(1) THEN
    settingsDir = ioDirs(1)
ELSEIF ioOk(2) THEN
    settingsDir = ioDirs(2)
ELSE
    ioReadOnly = -1
END IF
IF ioOk(2) THEN telemCsvDir = ioDirs(2)
IF ioMigrateWanted AND settingsDir <> "" AND settingsDir <> ioDirs(2) THEN
    ioMigrated = SETTINGS_Migrate%(ioDirs(2) + "/" + SETTINGS_FILE, settingsDir + "/" + SETTINGS_FILE)
END IF
RETURN

ioProbeFail:
ioFail = -1
RESUME NEXT

ioProbeEnd:
