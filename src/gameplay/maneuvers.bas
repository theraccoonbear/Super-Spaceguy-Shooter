' maneuvers.bas -- boss flight-path data loader
'
' The 3 boss flight-path maneuvers are each their own independent $EMBED'd
' .mvr file (assets/maneuvers/*.mvr, listed in sss.bas) -- no concatenation,
' no bake step. $EMBED requires a literal string id (QB64-PE rejects a
' computed one), so MNV_Load dispatches by name straight to each literal
' _EMBEDDED$() call, handing the raw content to MNV_ParseBlock -- the actual
' line-by-line parser, kept separate so it's testable with fixture strings.

Sub MNV_ListBlocks(mnvlbNames() As String, mnvlbCount As Integer)
    mnvlbCount = 0
    mnvlbNames(mnvlbCount) = "boss-x-flight"  : mnvlbCount = mnvlbCount + 1
    mnvlbNames(mnvlbCount) = "boss-v-flight"  : mnvlbCount = mnvlbCount + 1
    mnvlbNames(mnvlbCount) = "attack-pass"    : mnvlbCount = mnvlbCount + 1
End Sub

Sub MNV_Load(mnvlName As String)
    Dim mnvlKey As String
    mnvlKey = LCase$(mnvlName)
    If mnvlKey = "boss-x-flight" Then
        MNV_ParseBlock _EMBEDDED$("MNVBOSSXFLIGHT")
    ElseIf mnvlKey = "boss-v-flight" Then
        MNV_ParseBlock _EMBEDDED$("MNVBOSSVFLIGHT")
    ElseIf mnvlKey = "attack-pass" Then
        MNV_ParseBlock _EMBEDDED$("MNVATTACKPASS")
    Else
        MNV_ParseBlock ""   ' unknown name -- 0 waypoints, same as before
    End If
End Sub

' Parses one maneuver's raw .mvr content into the bsmWp* arrays (behavior.bas).
' Exactly one block per call -- no [name] matching needed, unlike the old
' single-blob format. Sets bsmFlySpd; Z values are unsigned, caller applies
' bsmTurnDir sign.
Sub MNV_ParseBlock(mnvpbRaw As String)
    Dim mnvpbI As Integer, mnvpbNL As Integer
    Dim mnvpbRawLine As String, mnvpbLine As String
    Dim mnvpbRest As String
    Dim mnvpbSp As Integer
    Dim mnvpbOrV As String   ' value side of orient= key
    Dim mnvpbJ As Integer    ' roll-array clear loop counter
    Dim mnvpbScale As Single ' scale= multiplier applied to all waypoint coords

    bsmWpCount   = 0
    bsmFlySpd    = 0.025     ' fallback if speed= line is missing
    bsmClosed    = 0
    bsmStandoff  = 0
    mnvpbScale   = 1.0
    bsmOrientMode = 0
    bsmTargetX   = 0 : bsmTargetY = 0 : bsmTargetZ = 0
    bsmPhaseTrigCount = 0
    For mnvpbJ = 0 To BSM_WP_MAX - 1
        bsmPathRoll(mnvpbJ) = 0 : bsmCraftRoll(mnvpbJ) = 0
    Next mnvpbJ
    mnvpbI = 1

    Do While mnvpbI <= Len(mnvpbRaw)
        mnvpbNL  = InStr(mnvpbI, mnvpbRaw, Chr$(10))
        If mnvpbNL = 0 Then mnvpbNL = Len(mnvpbRaw) + 1
        mnvpbRawLine = Mid$(mnvpbRaw, mnvpbI, mnvpbNL - mnvpbI)
        mnvpbI       = mnvpbNL + 1
        If Right$(mnvpbRawLine, 1) = Chr$(13) Then mnvpbRawLine = Left$(mnvpbRawLine, Len(mnvpbRawLine) - 1)
        mnvpbLine = LTrim$(RTrim$(mnvpbRawLine))
        If Len(mnvpbLine) = 0 Or Left$(mnvpbLine, 1) = "#" Then GoTo mnvpbNext

        If Left$(mnvpbLine, 1) = "[" Then GoTo mnvpbNext   ' [name] header -- informational only now

        ' ── Key=value lines ──────────────────────────────────────────────
        If LCase$(Left$(mnvpbLine, 6)) = "speed=" Then
            bsmFlySpd = Val(Mid$(mnvpbLine, 7))
            GoTo mnvpbNext
        End If

        If LCase$(Left$(mnvpbLine, 9)) = "standoff=" Then
            bsmStandoff = Val(Mid$(mnvpbLine, 10))
            GoTo mnvpbNext
        End If

        If LCase$(Left$(mnvpbLine, 6)) = "scale=" Then
            mnvpbScale = Val(Mid$(mnvpbLine, 7))
            If mnvpbScale < 0.001 Then mnvpbScale = 1.0
            GoTo mnvpbNext
        End If

        If LCase$(Left$(mnvpbLine, 7)) = "closed=" Then
            bsmClosed = Val(Mid$(mnvpbLine, 8))
            GoTo mnvpbNext
        End If

        If LCase$(Left$(mnvpbLine, 7)) = "orient=" Then
            mnvpbOrV = Mid$(mnvpbLine, 8)
            If LCase$(Left$(mnvpbOrV, 7)) = "target:" Then
                bsmOrientMode = 1
                mnvpbRest = Mid$(mnvpbOrV, 8)          ' "x,y,z"
                mnvpbSp   = InStr(mnvpbRest, ",")
                If mnvpbSp > 0 Then
                    bsmTargetX = Val(Left$(mnvpbRest, mnvpbSp))
                    mnvpbRest  = Mid$(mnvpbRest, mnvpbSp + 1)
                    mnvpbSp    = InStr(mnvpbRest, ",")
                    If mnvpbSp > 0 Then
                        bsmTargetY = Val(Left$(mnvpbRest, mnvpbSp))
                        bsmTargetZ = Val(Mid$(mnvpbRest, mnvpbSp + 1))
                    End If
                End If
            Else
                bsmOrientMode = 0
            End If
            GoTo mnvpbNext
        End If

        If LCase$(Left$(mnvpbLine, 5)) = "type=" Then GoTo mnvpbNext   ' craft|camera -- only craft used today

        ' ── Behavioral lines (Phase 2, mostly not yet consumed) -- must be
        ' skipped here, not fall through to waypoint parsing below, or they
        ' corrupt bsmWpCount with bogus entries (the exact bug this replaces).
        If LCase$(Left$(mnvpbLine, 8))  = "segment:" Then GoTo mnvpbNext
        If LCase$(Left$(mnvpbLine, 8))  = "segseam:" Then GoTo mnvpbNext
        If LCase$(Left$(mnvpbLine, 10)) = "craftroll:" Then GoTo mnvpbNext
        If LCase$(Left$(mnvpbLine, 9))  = "loopseam:" Then GoTo mnvpbNext

        ' ── trigger: <t>, <type>, <args...> -- only "phase" is consumed today ──
        If LCase$(Left$(mnvpbLine, 8)) = "trigger:" Then
            Dim mnvpbTrigRest As String : mnvpbTrigRest = LTrim$(Mid$(mnvpbLine, 9))
            Dim mnvpbTrigT As Single
            Dim mnvpbTrigType As String
            mnvpbSp = InStr(mnvpbTrigRest, ",")
            If mnvpbSp > 0 Then
                mnvpbTrigT    = Val(Left$(mnvpbTrigRest, mnvpbSp))
                mnvpbTrigRest = LTrim$(Mid$(mnvpbTrigRest, mnvpbSp + 1))
                mnvpbSp       = InStr(mnvpbTrigRest, ",")
                If mnvpbSp > 0 Then
                    mnvpbTrigType = LCase$(RTrim$(Left$(mnvpbTrigRest, mnvpbSp - 1)))
                Else
                    mnvpbTrigType = LCase$(RTrim$(mnvpbTrigRest))
                End If
                If mnvpbTrigType = "phase" And mnvpbSp > 0 And bsmPhaseTrigCount < BSM_TRIG_MAX Then
                    mnvpbTrigRest = LTrim$(Mid$(mnvpbTrigRest, mnvpbSp + 1))
                    bsmPhaseTrigT(bsmPhaseTrigCount)   = mnvpbTrigT
                    bsmPhaseTrigVal(bsmPhaseTrigCount) = Val(mnvpbTrigRest)
                    bsmPhaseTrigCount = bsmPhaseTrigCount + 1
                End If
            End If
            GoTo mnvpbNext
        End If

        ' ── Waypoint line: X Y Z [pathRoll [craftRoll]] ─────────────────
        If bsmWpCount < BSM_WP_MAX Then
            mnvpbSp = InStr(mnvpbLine, " ")
            If mnvpbSp > 0 Then
                bsmWp(bsmWpCount).x = Val(Left$(mnvpbLine, mnvpbSp)) * mnvpbScale
                mnvpbRest = LTrim$(Mid$(mnvpbLine, mnvpbSp))  ' "Y Z [pR [cR]]"
                mnvpbSp   = InStr(mnvpbRest, " ")
                If mnvpbSp > 0 Then
                    bsmWp(bsmWpCount).y = Val(Left$(mnvpbRest, mnvpbSp)) * mnvpbScale
                    mnvpbRest = LTrim$(Mid$(mnvpbRest, mnvpbSp)) ' "Z [pR [cR]]"
                    mnvpbSp   = InStr(mnvpbRest, " ")
                    If mnvpbSp > 0 Then
                        bsmWp(bsmWpCount).z = Val(Left$(mnvpbRest, mnvpbSp)) * mnvpbScale
                        mnvpbRest = LTrim$(Mid$(mnvpbRest, mnvpbSp)) ' "[pR [cR]]"
                        mnvpbSp   = InStr(mnvpbRest, " ")
                        If mnvpbSp > 0 Then
                            bsmPathRoll(bsmWpCount)  = Val(Left$(mnvpbRest, mnvpbSp))
                            bsmCraftRoll(bsmWpCount) = Val(LTrim$(Mid$(mnvpbRest, mnvpbSp)))
                        ElseIf Len(mnvpbRest) > 0 Then
                            bsmPathRoll(bsmWpCount) = Val(mnvpbRest)
                        End If
                    Else
                        bsmWp(bsmWpCount).z = Val(mnvpbRest) * mnvpbScale  ' Z is last token
                    End If
                    bsmWpCount = bsmWpCount + 1
                End If
            End If
        End If

        mnvpbNext:
    Loop
End Sub
