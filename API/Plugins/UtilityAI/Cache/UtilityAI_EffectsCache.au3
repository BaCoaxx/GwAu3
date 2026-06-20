#include-once

; ========== Effect Structure Properties ==========
Global Enum $GC_UAI_EFFECT_SkillID, _
	$GC_UAI_EFFECT_AttributeLevel, _
	$GC_UAI_EFFECT_EffectID, _
	$GC_UAI_EFFECT_CasterID, _
	$GC_UAI_EFFECT_Duration, _
	$GC_UAI_EFFECT_Timestamp, _
	$GC_UAI_EFFECT_TimeElapsed, _
	$GC_UAI_EFFECT_TimeRemaining, _
	$GC_UAI_EFFECT_Scale, _
	$GC_UAI_EFFECT_BonusScale, _
	$GC_UAI_EFFECT_COUNT

; ========== Bond Structure Properties ==========
Global Enum $GC_UAI_BOND_SkillID, _
	$GC_UAI_BOND_Unknown, _
	$GC_UAI_BOND_BONDID, _
	$GC_UAI_BOND_TargetAgentID, _
	$GC_UAI_BOND_COUNT

; ========== Visible Effect Structure Properties ==========
Global Enum $GC_UAI_VISEFFECT_EffectType, _
	$GC_UAI_VISEFFECT_EffectID, _
	$GC_UAI_VISEFFECT_HasEnded, _
	$GC_UAI_VISEFFECT_COUNT

; ========== Global Cache ==========
; Effects cache: $g_amx3_EffectsCache[AgentIndex][EffectIndex][Property]
; Bonds cache: $g_amx3_BondsCache[AgentIndex][BondIndex][Property]
; VisibleEffects cache: $g_amx3_VisEffectsCache[AgentIndex][VisEffectIndex][Property]
Global $g_amx3_EffectsCache[1][1][1]
Global $g_amx3_BondsCache[1][1][1]
Global $g_amx3_VisEffectsCache[1][1][1]

; Count arrays: stores count of effects/bonds/viseffects per agent
Global $g_ai_EffectsCount[1]
Global $g_ai_BondsCount[1]
Global $g_ai_VisEffectsCount[1]

; ========== Internal: Cache Effects for all cached agents ==========
Func UAI_CacheAgentEffects()
	Static $s_d_EffectsStruct = Memory_CreateArrayStructure( _
		"long SkillID[0x0];" & _
		"dword AttributeLevel[0x4];" & _
		"long EffectID[0x8];" & _
		"dword CasterID[0xC];" & _
		"float Duration[0x10];" & _
		"dword Timestamp[0x14]", _
		0x18)

	; AgentEffect entry: AgentID + the Effect TArray (ptr @0x14, count @0x1C), stride 0x24
	Static $s_d_AgentEffectStruct = Memory_CreateArrayStructure( _
		"dword AgentID[0x0];" & _
		"ptr EffectArray[0x14];" & _
		"long EffectCount[0x1C]", _
		0x24)

	Local $l_i_AgentCount = $g_i_AgentCacheCount
	If $l_i_AgentCount = 0 Then Return SetError(1, 0, False)

	; Full reset: fresh zero-filled arrays each frame (no carryover -> no stale rows)
	Global $g_amx3_EffectsCache[$l_i_AgentCount + 1][32][$GC_UAI_EFFECT_COUNT]
	Global $g_ai_EffectsCount[$l_i_AgentCount + 1]

	Local $l_p_AgentEffectsBase = World_GetWorldInfo("AgentEffectsArray")
	Local $l_i_AgentEffectsSize = World_GetWorldInfo("AgentEffectsArraySize")
	If $l_p_AgentEffectsBase = 0 Or $l_i_AgentEffectsSize = 0 Then Return SetError(2, 0, False)

	; Single bulk read of the whole AgentEffects array
	Local $l_amx2_AgentEffects = Memory_ReadArrayStruct($l_p_AgentEffectsBase, $l_i_AgentEffectsSize, $s_d_AgentEffectStruct)
	If @error Then Return SetError(3, 0, False)

	For $j = 0 To $l_i_AgentEffectsSize - 1
		Local $l_i_AgentID = $l_amx2_AgentEffects[$j][0]
		If $l_i_AgentID = 0 Then ContinueLoop

		Local $l_i_Index = UAI_GetIndexByID($l_i_AgentID)
		If $l_i_Index = 0 Then ContinueLoop      ; agent not cached / out of range

		Local $l_p_EffectArray = $l_amx2_AgentEffects[$j][1]
		Local $l_i_EffectCount = $l_amx2_AgentEffects[$j][2]
		If $l_p_EffectArray = 0 Or $l_i_EffectCount <= 0 Then ContinueLoop
		If $l_i_EffectCount > 31 Then $l_i_EffectCount = 31

		Local $l_amx2_AllEffects = Memory_ReadArrayStruct($l_p_EffectArray, $l_i_EffectCount, $s_d_EffectsStruct)
		If @error Then ContinueLoop

		For $k = 0 To $l_i_EffectCount - 1
			$g_amx3_EffectsCache[$l_i_Index][$k][$GC_UAI_EFFECT_SkillID] = $l_amx2_AllEffects[$k][0]
			$g_amx3_EffectsCache[$l_i_Index][$k][$GC_UAI_EFFECT_AttributeLevel] = $l_amx2_AllEffects[$k][1]
			$g_amx3_EffectsCache[$l_i_Index][$k][$GC_UAI_EFFECT_EffectID] = $l_amx2_AllEffects[$k][2]
			$g_amx3_EffectsCache[$l_i_Index][$k][$GC_UAI_EFFECT_CasterID] = $l_amx2_AllEffects[$k][3]
			$g_amx3_EffectsCache[$l_i_Index][$k][$GC_UAI_EFFECT_Duration] = $l_amx2_AllEffects[$k][4]
			$g_amx3_EffectsCache[$l_i_Index][$k][$GC_UAI_EFFECT_Timestamp] = $l_amx2_AllEffects[$k][5]
		Next

		$g_ai_EffectsCount[$l_i_Index] = $l_i_EffectCount
	Next

	Return True
EndFunc

; ========== Internal: Cache Bonds for all cached agents ==========
Func UAI_CacheAgentBonds()
	Static $s_d_BondsStruct = Memory_CreateArrayStructure( _
		"long SkillID[0x0];" & _
		"dword Unknown[0x4];" & _
		"long BondID[0x8];" & _
		"dword TargetAgentID[0xC]", _
		0x10)

	; AgentEffects entry: AgentID + the Bond TArray (ptr @0x4, count @0xC), stride 0x24
	Static $s_d_AgentBondsStruct = Memory_CreateArrayStructure( _
		"dword AgentID[0x0];" & _
		"ptr BondArray[0x4];" & _
		"long BondCount[0xC]", _
		0x24)

	Local $l_i_AgentCount = $g_i_AgentCacheCount
	If $l_i_AgentCount = 0 Then Return SetError(1, 0, False)

	; Full reset: fresh zero-filled arrays each frame
	Global $g_amx3_BondsCache[$l_i_AgentCount + 1][32][$GC_UAI_BOND_COUNT]
	Global $g_ai_BondsCount[$l_i_AgentCount + 1]

	Local $l_p_AgentEffectsBase = World_GetWorldInfo("AgentEffectsArray")
	Local $l_i_AgentEffectsSize = World_GetWorldInfo("AgentEffectsArraySize")
	If $l_p_AgentEffectsBase = 0 Or $l_i_AgentEffectsSize = 0 Then Return SetError(2, 0, False)

	; Single bulk read of the whole AgentEffects array
	Local $l_amx2_AgentEffects = Memory_ReadArrayStruct($l_p_AgentEffectsBase, $l_i_AgentEffectsSize, $s_d_AgentBondsStruct)
	If @error Then Return SetError(3, 0, False)

	For $j = 0 To $l_i_AgentEffectsSize - 1
		Local $l_i_AgentID = $l_amx2_AgentEffects[$j][0]
		If $l_i_AgentID = 0 Then ContinueLoop

		Local $l_i_Index = UAI_GetIndexByID($l_i_AgentID)
		If $l_i_Index = 0 Then ContinueLoop      ; agent not cached / out of range

		Local $l_p_BondArray = $l_amx2_AgentEffects[$j][1]
		Local $l_i_BondCount = $l_amx2_AgentEffects[$j][2]
		If $l_p_BondArray = 0 Or $l_i_BondCount <= 0 Then ContinueLoop
		If $l_i_BondCount > 31 Then $l_i_BondCount = 31

		Local $l_amx2_AllBonds = Memory_ReadArrayStruct($l_p_BondArray, $l_i_BondCount, $s_d_BondsStruct)
		If @error Then ContinueLoop

		For $k = 0 To $l_i_BondCount - 1
			$g_amx3_BondsCache[$l_i_Index][$k][$GC_UAI_BOND_SkillID] = $l_amx2_AllBonds[$k][0]
			$g_amx3_BondsCache[$l_i_Index][$k][$GC_UAI_BOND_Unknown] = $l_amx2_AllBonds[$k][1]
			$g_amx3_BondsCache[$l_i_Index][$k][$GC_UAI_BOND_BONDID] = $l_amx2_AllBonds[$k][2]
			$g_amx3_BondsCache[$l_i_Index][$k][$GC_UAI_BOND_TargetAgentID] = $l_amx2_AllBonds[$k][3]
		Next

		$g_ai_BondsCount[$l_i_Index] = $l_i_BondCount
	Next

	Return True
EndFunc

; ========== Internal: Cache Visible Effects for all cached agents ==========
Func UAI_CacheAgentVisibleEffects()
	Static $s_d_VisibleEffectsStruct = Memory_CreateStructure( _
		"dword EffectType[0x0];" & _
		"dword EffectID[0x4];" & _
		"dword HasEnded[0x8]")

	Local $l_i_AgentCount = $g_i_AgentCacheCount
	If $l_i_AgentCount = 0 Then Return SetError(1, 0, False)

	; Full reset: fresh zero-filled arrays each frame
	Global $g_amx3_VisEffectsCache[$l_i_AgentCount + 1][32][$GC_UAI_VISEFFECT_COUNT]
	Global $g_ai_VisEffectsCount[$l_i_AgentCount + 1]

	For $i = 1 To $l_i_AgentCount
		; Only living agents have visible effects
		If $g_amx2_AgentCache[$i][$GC_UAI_AGENT_IsLivingType] = False Then ContinueLoop

		Local $l_p_AgentPtr = $g_amx2_AgentCache[$i][$GC_UAI_AGENT_Ptr]
		Local $l_p_TList = $l_p_AgentPtr + 0x174
		Local $l_av_Iterator = Utils_TList_CreateIterator($l_p_TList)

		Local $l_i_Count = 0
		Local $l_p_Current = Utils_TList_Iterator_Current($l_av_Iterator)

		While $l_p_Current <> 0 And $l_i_Count < 31
			Local $l_av_Node = Memory_ReadStruct($l_p_Current, $s_d_VisibleEffectsStruct)
			If @error Then ExitLoop

			$g_amx3_VisEffectsCache[$i][$l_i_Count][$GC_UAI_VISEFFECT_EffectType] = $l_av_Node[0]
			$g_amx3_VisEffectsCache[$i][$l_i_Count][$GC_UAI_VISEFFECT_EffectID] = $l_av_Node[1]
			$g_amx3_VisEffectsCache[$i][$l_i_Count][$GC_UAI_VISEFFECT_HasEnded] = $l_av_Node[2]

			$l_i_Count += 1

			If Not Utils_TList_Iterator_Next($l_av_Iterator) Then ExitLoop
			$l_p_Current = Utils_TList_Iterator_Current($l_av_Iterator)
		WEnd

		$g_ai_VisEffectsCount[$i] = $l_i_Count
	Next

	Return True
EndFunc

; ========== Public: Check if agent has effect ==========
Func UAI_AgentHasEffect($a_i_AgentID, $a_i_SkillID)
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return False

	Local $l_i_Count = $g_ai_EffectsCount[$l_i_Index]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_SkillID] = $a_i_SkillID Then Return True
	Next

	Return False
EndFunc

; ========== Public: Check if player has effect ==========
Func UAI_PlayerHasEffect($a_i_SkillID)
	If $g_i_PlayerCacheIndex < 1 Then Return False

	Local $l_i_Count = $g_ai_EffectsCount[$g_i_PlayerCacheIndex]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_SkillID] = $a_i_SkillID Then Return True
	Next

	Return False
EndFunc

; ========== Public: Get effect info ==========
Func UAI_GetAgentEffectInfo($a_i_AgentID, $a_i_SkillID, $a_i_Property)
	If $a_i_Property < 0 Or $a_i_Property >= $GC_UAI_EFFECT_COUNT Then Return 0

	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return 0

	Local $l_i_Count = $g_ai_EffectsCount[$l_i_Index]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_SkillID] = $a_i_SkillID Then
			; Handle dynamic properties (calculated, not cached)
			Switch $a_i_Property
				Case $GC_UAI_EFFECT_TimeElapsed
					Local $l_i_Timestamp = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_Timestamp]
					Return BitAND(Skill_GetSkillTimer() - $l_i_Timestamp, 0xFFFFFFFF)
				Case $GC_UAI_EFFECT_TimeRemaining
					Local $l_i_Timestamp = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_Timestamp]
					Local $l_f_Duration = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_Duration]
					Return $l_f_Duration * 1000 - BitAND(Skill_GetSkillTimer() - $l_i_Timestamp, 0xFFFFFFFF)
				Case $GC_UAI_EFFECT_Scale
					Local $l_i_Scale0 = Skill_GetSkillInfo($a_i_SkillID, "Scale0")
					Local $l_i_Scale15 = Skill_GetSkillInfo($a_i_SkillID, "Scale15")
					Local $l_i_AttrLevel = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_AttributeLevel]
					Return Floor($l_i_Scale0 + (($l_i_Scale15 - $l_i_Scale0) / 15) * $l_i_AttrLevel)
				Case $GC_UAI_EFFECT_BonusScale
					Local $l_i_BonusScale0 = Skill_GetSkillInfo($a_i_SkillID, "BonusScale0")
					Local $l_i_BonusScale15 = Skill_GetSkillInfo($a_i_SkillID, "BonusScale15")
					Local $l_i_AttrLevel = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_AttributeLevel]
					Return Floor($l_i_BonusScale0 + (($l_i_BonusScale15 - $l_i_BonusScale0) / 15) * $l_i_AttrLevel)
				Case Else
					Return $g_amx3_EffectsCache[$l_i_Index][$i][$a_i_Property]
			EndSwitch
		EndIf
	Next

	Return 0
EndFunc

; ========== Public: Get player effect info ==========
Func UAI_GetPlayerEffectInfo($a_i_SkillID, $a_i_Property)
	If $a_i_Property < 0 Or $a_i_Property >= $GC_UAI_EFFECT_COUNT Then Return 0
	If $g_i_PlayerCacheIndex < 1 Then Return 0

	Local $l_i_Count = $g_ai_EffectsCount[$g_i_PlayerCacheIndex]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_SkillID] = $a_i_SkillID Then
			; Handle dynamic properties (calculated, not cached)
			Switch $a_i_Property
				Case $GC_UAI_EFFECT_TimeElapsed
					Local $l_i_Timestamp = $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_Timestamp]
					Return BitAND(Skill_GetSkillTimer() - $l_i_Timestamp, 0xFFFFFFFF)
				Case $GC_UAI_EFFECT_TimeRemaining
					Local $l_i_Timestamp = $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_Timestamp]
					Local $l_f_Duration = $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_Duration]
					Return $l_f_Duration * 1000 - BitAND(Skill_GetSkillTimer() - $l_i_Timestamp, 0xFFFFFFFF)
				Case $GC_UAI_EFFECT_Scale
					Local $l_i_Scale0 = Skill_GetSkillInfo($a_i_SkillID, "Scale0")
					Local $l_i_Scale15 = Skill_GetSkillInfo($a_i_SkillID, "Scale15")
					Local $l_i_AttrLevel = $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_AttributeLevel]
					Return Floor($l_i_Scale0 + (($l_i_Scale15 - $l_i_Scale0) / 15) * $l_i_AttrLevel)
				Case $GC_UAI_EFFECT_BonusScale
					Local $l_i_BonusScale0 = Skill_GetSkillInfo($a_i_SkillID, "BonusScale0")
					Local $l_i_BonusScale15 = Skill_GetSkillInfo($a_i_SkillID, "BonusScale15")
					Local $l_i_AttrLevel = $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_EFFECT_AttributeLevel]
					Return Floor($l_i_BonusScale0 + (($l_i_BonusScale15 - $l_i_BonusScale0) / 15) * $l_i_AttrLevel)
				Case Else
					Return $g_amx3_EffectsCache[$g_i_PlayerCacheIndex][$i][$a_i_Property]
			EndSwitch
		EndIf
	Next

	Return 0
EndFunc

; ========== Public: Get agent effect count ==========
Func UAI_GetAgentEffectCount($a_i_AgentID)
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return 0
	Return $g_ai_EffectsCount[$l_i_Index]
EndFunc

; ========== Public: Get player effect count ==========
Func UAI_GetPlayerEffectCount()
	If $g_i_PlayerCacheIndex < 1 Then Return 0
	Return $g_ai_EffectsCount[$g_i_PlayerCacheIndex]
EndFunc

; ========== Public: Check if agent upkeeps bonds ==========
Func UAI_AgentUpkeepsBond($a_i_AgentID, $a_i_SkillID)
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return False

	Local $l_i_Count = $g_ai_BondsCount[$l_i_Index]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_BondsCache[$l_i_Index][$i][$GC_UAI_BOND_SkillID] = $a_i_SkillID Then Return True
	Next

	Return False
EndFunc

; ========== Public: Check if player upkeeps bonds ==========
Func UAI_PlayerUpkeepsBond($a_i_SkillID)
	If $g_i_PlayerCacheIndex < 1 Then Return False

	Local $l_i_Count = $g_ai_BondsCount[$g_i_PlayerCacheIndex]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_BondsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_BOND_SkillID] = $a_i_SkillID Then Return True
	Next

	Return False
EndFunc

; ========== Public: Get bond info ==========
Func UAI_GetAgentBondInfo($a_i_AgentID, $a_i_SkillID, $a_i_Property)
	If $a_i_Property < 0 Or $a_i_Property >= $GC_UAI_BOND_COUNT Then Return 0

	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return 0

	Local $l_i_Count = $g_ai_BondsCount[$l_i_Index]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_BondsCache[$l_i_Index][$i][$GC_UAI_BOND_SkillID] = $a_i_SkillID Then
			Return $g_amx3_BondsCache[$l_i_Index][$i][$a_i_Property]
		EndIf
	Next

	Return 0
EndFunc

; ========== Public: Get player bond info ==========
Func UAI_GetPlayerBondInfo($a_i_SkillID, $a_i_Property)
	If $a_i_Property < 0 Or $a_i_Property >= $GC_UAI_BOND_COUNT Then Return 0
	If $g_i_PlayerCacheIndex < 1 Then Return 0

	Local $l_i_Count = $g_ai_BondsCount[$g_i_PlayerCacheIndex]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_BondsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_BOND_SkillID] = $a_i_SkillID Then
			Return $g_amx3_BondsCache[$g_i_PlayerCacheIndex][$i][$a_i_Property]
		EndIf
	Next

	Return 0
EndFunc

; ========== Public: Get agent bond count ==========
Func UAI_GetAgentBondCount($a_i_AgentID)
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return 0
	Return $g_ai_BondsCount[$l_i_Index]
EndFunc

; ========== Public: Get player bond count ==========
Func UAI_GetPlayerBondCount()
	If $g_i_PlayerCacheIndex < 1 Then Return 0
	Return $g_ai_BondsCount[$g_i_PlayerCacheIndex]
EndFunc

; ========== Public: Check if agent has visible effect ==========
Func UAI_AgentHasVisibleEffect($a_i_AgentID, $a_i_EffectType, $a_i_EffectID)
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return False

	Local $l_i_Count = $g_ai_VisEffectsCount[$l_i_Index]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_VisEffectsCache[$l_i_Index][$i][$GC_UAI_VISEFFECT_EffectType] <> $a_i_EffectType Then ContinueLoop
		If $g_amx3_VisEffectsCache[$l_i_Index][$i][$GC_UAI_VISEFFECT_EffectID] = $a_i_EffectID Then Return True
	Next

	Return False
EndFunc

; ========== Public: Check if player has visible effect ==========
Func UAI_PlayerHasVisibleEffect($a_i_EffectType, $a_i_EffectID)
	If $g_i_PlayerCacheIndex < 1 Then Return False

	Local $l_i_Count = $g_ai_VisEffectsCount[$g_i_PlayerCacheIndex]
	For $i = 0 To $l_i_Count - 1
		If $g_amx3_VisEffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_VISEFFECT_EffectType] <> $a_i_EffectType Then ContinueLoop
		If $g_amx3_VisEffectsCache[$g_i_PlayerCacheIndex][$i][$GC_UAI_VISEFFECT_EffectID] = $a_i_EffectID Then Return True
	Next

	Return False
EndFunc

; ========== Public: Get visible effect info ==========
Func UAI_GetAgentVisibleEffectInfo($a_i_AgentID)
	Local $l_ai2_VisEffects[1][1] = [[0]]
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return $l_ai2_VisEffects

	Local $l_i_Count = $g_ai_VisEffectsCount[$l_i_Index]
	ReDim $l_ai2_VisEffects[1 + $l_i_Count][3]
	$l_ai2_VisEffects[0][0] = $l_i_Count

	For $i = 1 To $l_i_Count
		$l_ai2_VisEffects[$i][0] = $g_amx3_VisEffectsCache[$l_i_Index][$i - 1][$GC_UAI_VISEFFECT_EffectType]
		$l_ai2_VisEffects[$i][1] = $g_amx3_VisEffectsCache[$l_i_Index][$i - 1][$GC_UAI_VISEFFECT_EffectID]
		$l_ai2_VisEffects[$i][2] = $g_amx3_VisEffectsCache[$l_i_Index][$i - 1][$GC_UAI_VISEFFECT_HasEnded]
	Next

	Return $l_ai2_VisEffects
EndFunc

; ========== Public: Get player visible effect info ==========
Func UAI_GetPlayerVisibleEffectInfo()
	Local $l_ai2_VisEffects[1][1] = [[0]]
	If $g_i_PlayerCacheIndex < 1 Then Return $l_ai2_VisEffects

	Local $l_i_Count = $g_ai_VisEffectsCount[$g_i_PlayerCacheIndex]
	ReDim $l_ai2_VisEffects[1 + $l_i_Count][3]
	$l_ai2_VisEffects[0][0] = $l_i_Count

	For $i = 1 To $l_i_Count
		$l_ai2_VisEffects[$i][0] = $g_amx3_VisEffectsCache[$g_i_PlayerCacheIndex][$i - 1][$GC_UAI_VISEFFECT_EffectType]
		$l_ai2_VisEffects[$i][1] = $g_amx3_VisEffectsCache[$g_i_PlayerCacheIndex][$i - 1][$GC_UAI_VISEFFECT_EffectID]
		$l_ai2_VisEffects[$i][2] = $g_amx3_VisEffectsCache[$g_i_PlayerCacheIndex][$i - 1][$GC_UAI_VISEFFECT_HasEnded]
	Next

	Return $l_ai2_VisEffects
EndFunc

; ========== Public: Get agent visible effect count ==========
Func UAI_GetAgentVisibleEffectCount($a_i_AgentID)
	Local $l_i_Index = UAI_GetIndexByID($a_i_AgentID)
	If $l_i_Index = 0 Then Return 0
	Return $g_ai_VisEffectsCount[$l_i_Index]
EndFunc

; ========== Public: Get player visible effect count ==========
Func UAI_GetPlayerVisibleEffectCount()
	If $g_i_PlayerCacheIndex < 1 Then Return 0
	Return $g_ai_VisEffectsCount[$g_i_PlayerCacheIndex]
EndFunc

Func UAI_GetFeederEnchOnTop()
	Local $l_i_MyID = UAI_GetPlayerInfo($GC_UAI_AGENT_ID)
    If $l_i_MyID = 0 Then Return SetError(1, 0, False)

    Local $l_i_EffectCount = UAI_GetPlayerEffectCount()
    If $l_i_EffectCount = 0 Then Return False

	Local $l_i_Index = UAI_GetPlayerIndex()

    Local $l_i_Timestamp = 0
    Local $l_i_SkillID = 0

    For $i = 0 To $l_i_EffectCount - 1
        Local $l_i_CurrentSkillID = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_SkillID]
		If $GC_AMX2_SKILL_DATA[$l_i_CurrentSkillID][$GC_I_SKILL_PROFESSION] <> $GC_I_PROFESSION_DERVISH Then ContinueLoop
        If $GC_AMX2_SKILL_DATA[$l_i_CurrentSkillID][$GC_I_SKILL_TYPE] <> $GC_I_SKILL_TYPE_ENCHANTMENT Then ContinueLoop
		Local $l_i_CurrentTimeStamp = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_Timestamp]
        If $l_i_CurrentTimeStamp > $l_i_Timestamp Then
            $l_i_Timestamp = $l_i_CurrentTimeStamp
            $l_i_SkillID = $l_i_CurrentSkillID
        EndIf
    Next

    Local $l_ai_FeederEnchantmens[8] = [$GC_I_SKILL_ID_GRENTHS_FINGERS, $GC_I_SKILL_ID_AURA_OF_THORNS, _
        $GC_I_SKILL_ID_BALTHAZARS_RAGE, $GC_I_SKILL_ID_DUST_CLOAK, $GC_I_SKILL_ID_STAGGERING_FORCE, _
        $GC_I_SKILL_ID_PIOUS_RENEWAL, $GC_I_SKILL_ID_EREMITES_ZEAL, $GC_I_SKILL_ID_ZEALOUS_RENEWAL]

    If $l_i_SkillID <> 0 And (_ArrayBinarySearch($l_ai_FeederEnchantmens, $l_i_SkillID)) >= 0 Then Return True
    Return False
EndFunc

Func UAI_PlayerHasEffectType($a_s_EffectType = "")
	Local $l_i_MyID = UAI_GetPlayerInfo($GC_UAI_AGENT_ID)
    If $l_i_MyID = 0 Then Return SetError(1, 0, False)

    Local $l_i_EffectCount = UAI_GetPlayerEffectCount()
    If $l_i_EffectCount = 0 Then Return False

	Local $l_i_Index = UAI_GetPlayerIndex()

	Local $l_i_EffectType = ""
	Switch $a_s_EffectType
		Case "HasStance"
			$l_i_EffectType = $GC_I_SKILL_TYPE_STANCE
		Case "HasGlyph"
			$l_i_EffectType = $GC_I_SKILL_TYPE_GLYPH
		Case "HasPreparation"
			$l_i_EffectType = $GC_I_SKILL_TYPE_PREPARATION
		Case Else
			Return SetError(2, 0, False)
	EndSwitch

    For $i = ($l_i_EffectCount - 1) To 0 Step -1
		Local $l_i_CurrentSkillID = $g_amx3_EffectsCache[$l_i_Index][$i][$GC_UAI_EFFECT_SkillID]
		Local $l_i_SkillType = $GC_AMX2_SKILL_DATA[$l_i_CurrentSkillID][$GC_I_SKILL_TYPE]
		If $l_i_SkillType = $l_i_EffectType Then Return SetExtended($l_i_CurrentSkillID, True)
    Next
    Return False
EndFunc