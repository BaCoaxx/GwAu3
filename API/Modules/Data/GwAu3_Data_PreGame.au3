#include-once

Func PreGame_Ptr()
	Return Memory_Read($g_p_PreGame, 'ptr')
EndFunc

Func PreGame_FrameID()
	Return Memory_Read(PreGame_Ptr(), 'dword')
EndFunc

Func PreGame_ChosenCharacter()
	Return Memory_Read(PreGame_Ptr() + 0xD8, 'dword')
EndFunc

Func PreGame_LoginCharacterArray()
	Return Memory_Read(PreGame_Ptr() + 0xE0, 'ptr')
EndFunc

Func PreGame_CharName($a_i_Index) ;from 0 to max character
	Return Memory_Read(PreGame_LoginCharacterArray() + 0x50 + (0x78 * $a_i_Index), 'WCHAR[20]')
EndFunc

;~ Description: Number of characters in the login character array, scrolled into view or not.
Func PreGame_CharacterCount()
	If PreGame_Ptr() = 0 Then Return 0
	Return Memory_Read(PreGame_Ptr() + 0xE8, 'dword')
EndFunc

;~ Description: Index of the named character in the login character array, -1 when absent.
Func PreGame_FindCharacter($a_s_Name)
	For $l_i_Index = 0 To PreGame_CharacterCount() - 1
		If StringCompare(StringStripWS(PreGame_CharName($l_i_Index), 3), $a_s_Name, 0) = 0 Then Return $l_i_Index
	Next
	Return -1
EndFunc