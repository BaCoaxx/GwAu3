#include-once

;~ Description: Log out of the game to the character select screen, as the in-game menu does.
;~ Only valid in game: on the select screen the same message logs out of the account.
Func PreGame_LogoutToCharSelect()
	If PreGame_Ptr() <> 0 Then Return SetError(1, 0, False)
	DllStructSetData($g_d_Logout, 2, $GC_I_UIMSG_LOGOUT)
	DllStructSetData($g_d_Logout, 3, 1)
	DllStructSetData($g_d_Logout, 4, 1)
	Core_Enqueue($g_p_Logout, 16)
	Return True
EndFunc   ;==>PreGame_LogoutToCharSelect

;~ Description: Select the named character on the character select screen and press Play.
;~ The name must be in the login character array: Play on an unknown name is not guarded by the client.
Func PreGame_PlayCharacter($a_s_Name)
	If PreGame_Ptr() = 0 Then Return SetError(1, 0, False)
	If $a_s_Name = "" Or StringLen($a_s_Name) > 19 Then Return SetError(2, 0, False)
	Local $l_i_Index = PreGame_FindCharacter($a_s_Name)
	If $l_i_Index = -1 Then Return SetError(3, 0, False)
	; The client's own spelling: the match above ignores case, the select frame may not.
	DllStructSetData($g_d_PlayCharacter, 2, StringStripWS(PreGame_CharName($l_i_Index), 3))
	Core_Enqueue($g_p_PlayCharacter, 44)
	Return True
EndFunc   ;==>PreGame_PlayCharacter
