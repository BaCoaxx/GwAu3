#include-once

Global Const $GC_F_PATHFINDER_COVERAGE_MIN_PROBE_DISTANCE = 75.0
Global Const $GC_I_PATHFINDER_COVERAGE_CANDIDATES_PER_PATH_POINT = 5
Global Const $GC_F_PATHFINDER_COVERAGE_WORST_SCORE = -1e30
Global Const $GC_F_PATHFINDER_COVERAGE_MAX_DISTANCE = 1e30

Func _Pathfinder_GenerateCoverageWaypoints($aStartX, $aStartY, $aStartLayer, $aDestX, $aDestY, $aDestLayer, $aObstacles)
    Local $lMapID = Map_GetMapID()
    Local $lPath = Pathfinder_FindPath($lMapID, $aStartX, $aStartY, $aStartLayer, $aDestX, $aDestY, $aDestLayer, $aObstacles, $g_iPathfinder_SimplifyRange)

    Local $lWaypoints[0][4]
    If Not IsArray($lPath) Or UBound($lPath) = 0 Then
        _Pathfinder_Log("Coverage planner fallback: base path generation failed")
        _Pathfinder_CoveragePushWaypoint($lWaypoints, $aDestX, $aDestY, $aDestLayer, 0)
        Return $lWaypoints
    EndIf

    Local $lProbeDistance = Max($g_iPathfinder_CoverageMinSeparation * 2, $GC_F_PATHFINDER_COVERAGE_MIN_PROBE_DISTANCE)
    Local $lCandidateCount = 0
    Local $lCandidates[UBound($lPath) * $GC_I_PATHFINDER_COVERAGE_CANDIDATES_PER_PATH_POINT][5] ; x, y, layer, tp_type, corner_flag

    ; Start/end waypoints are intentionally excluded because destination is explicitly appended later.
    For $i = 1 To UBound($lPath) - 2
        $lCandidates[$lCandidateCount][0] = $lPath[$i][0]
        $lCandidates[$lCandidateCount][1] = $lPath[$i][1]
        $lCandidates[$lCandidateCount][2] = $lPath[$i][2]
        $lCandidates[$lCandidateCount][3] = 0
        $lCandidates[$lCandidateCount][4] = 0
        $lCandidateCount += 1

        Local $lX = $lPath[$i][0]
        Local $lY = $lPath[$i][1]
        Local $lLayer = $lPath[$i][2]
        Local $lOffsets[4][2] = [[-$lProbeDistance, 0], [$lProbeDistance, 0], [0, -$lProbeDistance], [0, $lProbeDistance]]
        For $j = 0 To 3
            $lCandidates[$lCandidateCount][0] = $lX + $lOffsets[$j][0]
            $lCandidates[$lCandidateCount][1] = $lY + $lOffsets[$j][1]
            $lCandidates[$lCandidateCount][2] = $lLayer
            $lCandidates[$lCandidateCount][3] = 0
            $lCandidates[$lCandidateCount][4] = 1
            $lCandidateCount += 1
        Next
    Next

    If $lCandidateCount = 0 Then
        _Pathfinder_CoveragePushWaypoint($lWaypoints, $aDestX, $aDestY, $aDestLayer, 0)
        Return $lWaypoints
    EndIf

    ReDim $lCandidates[$lCandidateCount][5]
    Local $lCandidateUsed[$lCandidateCount]
    Local $lCurrentX = $aStartX, $lCurrentY = $aStartY, $lCurrentLayer = $aStartLayer
    Local $lMaxSelectable = Max($g_iPathfinder_CoverageMaxWaypoints - 1, 0)

    For $k = 0 To $lMaxSelectable - 1
        Local $lBestIndex = -1
        Local $lBestScore = $GC_F_PATHFINDER_COVERAGE_WORST_SCORE

        For $i = 0 To $lCandidateCount - 1
            If $lCandidateUsed[$i] Then ContinueLoop

            Local $lCandX = $lCandidates[$i][0]
            Local $lCandY = $lCandidates[$i][1]
            Local $lCandLayer = $lCandidates[$i][2]

            If Not _Pathfinder_CoverageHasValidPath($lCurrentX, $lCurrentY, $lCurrentLayer, $lCandX, $lCandY, $lCandLayer, $aObstacles) Then ContinueLoop

            Local $lNovelty = _Pathfinder_CoverageDistanceToNearest($lCandX, $lCandY, $lWaypoints, $aStartX, $aStartY)
            Local $lDistanceToDest = _Pathfinder_Distance($lCandX, $lCandY, $aDestX, $aDestY)
            Local $lCornerBias = $lCandidates[$i][4] * $g_fPathfinder_CornerBiasWeight
            Local $lRevisitPenalty = 0.0

            If $lNovelty < ($g_iPathfinder_CoverageMinSeparation * 2) Then
                $lRevisitPenalty = $g_fPathfinder_RevisitPenalty
                If Not $g_bPathfinder_AllowRevisitAfterExhaustion Then ContinueLoop
            EndIf

            Local $lScore = $lNovelty + $lCornerBias - ($g_fPathfinder_CoverageDistanceWeight * $lDistanceToDest) - $lRevisitPenalty
            If $lScore > $lBestScore Then
                $lBestScore = $lScore
                $lBestIndex = $i
            EndIf
        Next

        If $lBestIndex = -1 Then ExitLoop
        $lCandidateUsed[$lBestIndex] = True

        Local $lBestX = $lCandidates[$lBestIndex][0]
        Local $lBestY = $lCandidates[$lBestIndex][1]
        Local $lBestLayer = $lCandidates[$lBestIndex][2]
        _Pathfinder_CoveragePushWaypoint($lWaypoints, $lBestX, $lBestY, $lBestLayer, 0)
        $lCurrentX = $lBestX
        $lCurrentY = $lBestY
        $lCurrentLayer = $lBestLayer
    Next

    _Pathfinder_CoveragePushWaypoint($lWaypoints, $aDestX, $aDestY, $aDestLayer, 0)
    $lWaypoints = _Pathfinder_EnforceWaypointConstraints($lWaypoints, $g_iPathfinder_CoverageMinSeparation, True, $aDestX, $aDestY, $aDestLayer)

    _Pathfinder_Log("Coverage planner generated " & UBound($lWaypoints) & " constrained waypoint(s)")
    Return $lWaypoints
EndFunc

Func _Pathfinder_EnforceWaypointConstraints($aWaypoints, $aMinSeparation = 25, $aEnsureDestination = True, $aDestX = 0, $aDestY = 0, $aDestLayer = -1)
    Local $lResult[0][4]
    If Not IsArray($aWaypoints) Then Return $lResult
    If UBound($aWaypoints) = 0 Then Return $lResult

    Local $lUniqueRejectCount = 0
    Local $lSeparationRejectCount = 0
    Local $lMinDistance = Max($aMinSeparation, 0)

    For $i = 0 To UBound($aWaypoints) - 1
        Local $lX = $aWaypoints[$i][0]
        Local $lY = $aWaypoints[$i][1]
        Local $lLayer = $aWaypoints[$i][2]
        Local $lTpType = $aWaypoints[$i][3]
        Local $lIsDestination = _Pathfinder_CoverageIsDestination($lX, $lY, $lLayer, $aDestX, $aDestY, $aDestLayer)

        If Not $lIsDestination Then
            If _Pathfinder_CoverageContainsPoint($lResult, $lX, $lY, $lLayer, 1.0) Then
                $lUniqueRejectCount += 1
                ContinueLoop
            EndIf

            If _Pathfinder_CoverageTooCloseToAny($lResult, $lX, $lY, $lMinDistance) Then
                $lSeparationRejectCount += 1
                ContinueLoop
            EndIf
        Else
            For $j = UBound($lResult) - 1 To 0 Step -1
                If _Pathfinder_Distance($lResult[$j][0], $lResult[$j][1], $lX, $lY) < $lMinDistance Then
                    _Pathfinder_CoverageRemoveAt($lResult, $j)
                    $lSeparationRejectCount += 1
                EndIf
            Next

            For $j = UBound($lResult) - 1 To 0 Step -1
                If _Pathfinder_CoverageIsSamePoint($lResult[$j][0], $lResult[$j][1], $lResult[$j][2], $lX, $lY, $lLayer, 1.0) Then
                    _Pathfinder_CoverageRemoveAt($lResult, $j)
                    $lUniqueRejectCount += 1
                EndIf
            Next
        EndIf

        _Pathfinder_CoveragePushWaypoint($lResult, $lX, $lY, $lLayer, $lTpType)
    Next

    If $aEnsureDestination Then
        If Not _Pathfinder_CoverageContainsPoint($lResult, $aDestX, $aDestY, $aDestLayer, 1.0) Then
            For $j = UBound($lResult) - 1 To 0 Step -1
                If _Pathfinder_Distance($lResult[$j][0], $lResult[$j][1], $aDestX, $aDestY) < $lMinDistance Then
                    _Pathfinder_CoverageRemoveAt($lResult, $j)
                    $lSeparationRejectCount += 1
                EndIf
            Next
            _Pathfinder_CoveragePushWaypoint($lResult, $aDestX, $aDestY, $aDestLayer, 0)
        EndIf
    EndIf

    If $lUniqueRejectCount > 0 Or $lSeparationRejectCount > 0 Then
        _Pathfinder_Log("Coverage constraints: rejected unique=" & $lUniqueRejectCount & " separation=" & $lSeparationRejectCount)
    EndIf

    Return $lResult
EndFunc

Func _Pathfinder_CoveragePushWaypoint(ByRef $aArray, $aX, $aY, $aLayer, $aTpType = 0)
    Local $lSize = UBound($aArray)
    ReDim $aArray[$lSize + 1][4]
    $aArray[$lSize][0] = $aX
    $aArray[$lSize][1] = $aY
    $aArray[$lSize][2] = $aLayer
    $aArray[$lSize][3] = $aTpType
EndFunc

Func _Pathfinder_CoverageRemoveAt(ByRef $aArray, $aIndex)
    Local $lSize = UBound($aArray)
    If $aIndex < 0 Or $aIndex >= $lSize Then Return
    If $lSize = 1 Then
        ReDim $aArray[0][4]
        Return
    EndIf

    For $i = $aIndex To $lSize - 2
        $aArray[$i][0] = $aArray[$i + 1][0]
        $aArray[$i][1] = $aArray[$i + 1][1]
        $aArray[$i][2] = $aArray[$i + 1][2]
        $aArray[$i][3] = $aArray[$i + 1][3]
    Next
    ReDim $aArray[$lSize - 1][4]
EndFunc

Func _Pathfinder_CoverageContainsPoint($aWaypoints, $aX, $aY, $aLayer, $aEpsilon = 1.0)
    If Not IsArray($aWaypoints) Then Return False
    For $i = 0 To UBound($aWaypoints) - 1
        If _Pathfinder_CoverageIsSamePoint($aWaypoints[$i][0], $aWaypoints[$i][1], $aWaypoints[$i][2], $aX, $aY, $aLayer, $aEpsilon) Then Return True
    Next
    Return False
EndFunc

Func _Pathfinder_CoverageIsSamePoint($aX1, $aY1, $aLayer1, $aX2, $aY2, $aLayer2, $aEpsilon = 1.0)
    If Abs($aLayer1 - $aLayer2) > 0 Then Return False
    Return _Pathfinder_Distance($aX1, $aY1, $aX2, $aY2) <= $aEpsilon
EndFunc

Func _Pathfinder_CoverageTooCloseToAny($aWaypoints, $aX, $aY, $aMinDistance)
    If $aMinDistance <= 0 Then Return False
    If Not IsArray($aWaypoints) Then Return False
    For $i = 0 To UBound($aWaypoints) - 1
        If _Pathfinder_Distance($aWaypoints[$i][0], $aWaypoints[$i][1], $aX, $aY) < $aMinDistance Then Return True
    Next
    Return False
EndFunc

Func _Pathfinder_CoverageDistanceToNearest($aX, $aY, $aWaypoints, $aFallbackX, $aFallbackY)
    Local $lNearest = _Pathfinder_Distance($aX, $aY, $aFallbackX, $aFallbackY)
    If IsArray($aWaypoints) And UBound($aWaypoints) > 0 Then
        $lNearest = $GC_F_PATHFINDER_COVERAGE_MAX_DISTANCE
        For $i = 0 To UBound($aWaypoints) - 1
            Local $lDist = _Pathfinder_Distance($aX, $aY, $aWaypoints[$i][0], $aWaypoints[$i][1])
            If $lDist < $lNearest Then $lNearest = $lDist
        Next
    EndIf
    Return $lNearest
EndFunc

Func _Pathfinder_CoverageHasValidPath($aStartX, $aStartY, $aStartLayer, $aDestX, $aDestY, $aDestLayer, $aObstacles)
    Local $lMapID = Map_GetMapID()
    Local $lPath = Pathfinder_FindPath($lMapID, $aStartX, $aStartY, $aStartLayer, $aDestX, $aDestY, $aDestLayer, $aObstacles, $g_iPathfinder_SimplifyRange)
    Return IsArray($lPath) And UBound($lPath) > 0
EndFunc

Func _Pathfinder_CoverageIsDestination($aX, $aY, $aLayer, $aDestX, $aDestY, $aDestLayer)
    If _Pathfinder_Distance($aX, $aY, $aDestX, $aDestY) > 1.0 Then Return False
    If $aDestLayer <> -1 And $aLayer <> $aDestLayer Then Return False
    Return True
EndFunc
