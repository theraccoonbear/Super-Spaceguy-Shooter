' failfast.bi -- an unhandled runtime error ends the program with exit code 1 (#427)
'
' QB64-PE has no switch for this: an unhandled error opens a dialog, or with no display
' a "Continue? y/n" prompt on stdin that loops forever when stdin is at EOF. Include this
' once, at the top of the main module (after Option _Explicit and any $CONSOLE line), in
' every program that runs unattended. The handler prints the error and where it happened
' to stderr (to the console on Windows) and exits 1.
'
' A local "ON ERROR GOTO label ... ON ERROR GOTO 0" probe must end with
' "ON ERROR GOTO SSS_FailFast" instead, or the prompt comes back after the probe.
Dim Shared sssFfFile As Long, sssFfMsg As String

On Error GoTo SSS_FailFast
GoTo SSS_FailFastDone

SSS_FailFast:
sssFfMsg = "Runtime error " + LTrim$(Str$(Err)) + ": " + _ErrorMessage$ + " (line " + LTrim$(Str$(_ErrorLine))
If _InclErrorLine > 0 Then sssFfMsg = sssFfMsg + ", " + _InclErrorFile$ + " line " + LTrim$(Str$(_InclErrorLine))
sssFfMsg = sssFfMsg + ")"
$If WIN Then
    Print sssFfMsg
$Else
    sssFfFile = FreeFile
    Open "/dev/stderr" For Output As #sssFfFile
    Print #sssFfFile, sssFfMsg
    Close #sssFfFile
$End If
System 1

SSS_FailFastDone:
