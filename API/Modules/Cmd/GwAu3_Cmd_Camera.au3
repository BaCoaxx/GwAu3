#include-once

Global $g_i_CameraUnlockPID = 0
Global $g_p_CameraUnlockPatch = 0
Global $g_b_CameraUnlockOwned = False
Global $g_b_CameraUnlockExitRegistered = False
Global $g_p_CameraNative = 0

;~ Description: Detach or reattach the camera from the player.
Func Camera_Unlock($a_b_Unlock = True)
    If $g_h_GWProcess = 0 Or $g_i_GWProcessId = 0 Then Return SetError(1, 0, False)

    If $g_i_CameraUnlockPID <> $g_i_GWProcessId Then
        $g_i_CameraUnlockPID = $g_i_GWProcessId
        $g_p_CameraUnlockPatch = 0
        $g_p_CameraNative = 0
        $g_b_CameraUnlockOwned = False
    EndIf

    If $g_p_CameraUnlockPatch = 0 Then
        $g_p_CameraUnlockPatch = _Camera_FindCodePattern("E88B4DEC8B55F08906894E048956085E8BE55DC21400", -2)
        If $g_p_CameraUnlockPatch = 0 Then Return SetError(2, 0, False)
    EndIf

    Local $l_d_Current = DllStructCreate("byte[2]")
    Local $l_av_Read = DllCall($g_h_Kernel32, "bool", "ReadProcessMemory", _
        "handle", $g_h_GWProcess, "ptr", $g_p_CameraUnlockPatch, _
        "struct*", $l_d_Current, "ulong_ptr", 2, "ulong_ptr*", 0)
    If @error Or Not $l_av_Read[0] Or $l_av_Read[5] <> 2 Then Return SetError(3, 0, False)

    Local $l_b_Patched = DllStructGetData($l_d_Current, 1) = Binary("0xEB0F")
    If Not $l_b_Patched And DllStructGetData($l_d_Current, 1) <> Binary("0x8B45") Then Return SetError(4, 0, False)

    If $a_b_Unlock Then
        If $l_b_Patched Then Return SetError($g_b_CameraUnlockOwned ? 0 : 5, 0, $g_b_CameraUnlockOwned)
        If Not _Camera_WriteUnlockPatch(Binary("0xEB0F")) Then Return SetError(6, 0, False)
        $g_b_CameraUnlockOwned = True
        If Not $g_b_CameraUnlockExitRegistered Then
            OnAutoItExitRegister("_Camera_RestoreOnExit")
            $g_b_CameraUnlockExitRegistered = True
        EndIf
    Else
        If Not $l_b_Patched Then
            $g_b_CameraUnlockOwned = False
            Return True
        EndIf
        If Not $g_b_CameraUnlockOwned Then Return SetError(5, 0, False)
        If Not _Camera_WriteUnlockPatch(Binary("0x8B45")) Then Return SetError(6, 0, False)
        $g_b_CameraUnlockOwned = False
    EndIf

    Return True
EndFunc

Func _Camera_RestoreOnExit()
    If $g_b_CameraUnlockOwned Then Camera_Unlock(False)
EndFunc

;~ Description: Move an unlocked camera in its facing direction; distances are game units, yaw is radians.
Func Camera_FreeMove($a_f_Forward, $a_f_Side, $a_f_Vertical, $a_f_Yaw = 0)
    If Not $g_b_CameraUnlockOwned Then Return SetError(1, 0, False)
    Local $l_p_Camera = _Camera_GetNativePtr()
    If $l_p_Camera = 0 Then Return SetError(2, 0, False)

    Local $l_d_Camera = DllStructCreate("byte[24];float yaw;float pitch;float distance;" & _
        "byte[84];float posX;float posY;float posZ;byte[36];float lookX;float lookY;float lookZ")
    Local $l_av_Read = DllCall($g_h_Kernel32, "bool", "ReadProcessMemory", _
        "handle", $g_h_GWProcess, "ptr", $l_p_Camera, "struct*", $l_d_Camera, _
        "ulong_ptr", DllStructGetSize($l_d_Camera), "ulong_ptr*", 0)
    If @error Or Not $l_av_Read[0] Or $l_av_Read[5] <> DllStructGetSize($l_d_Camera) Then Return SetError(3, 0, False)

    Local $l_f_Yaw = DllStructGetData($l_d_Camera, "yaw") + $a_f_Yaw
    Local $l_f_Pitch = DllStructGetData($l_d_Camera, "pitch")
    Local $l_f_Distance = DllStructGetData($l_d_Camera, "distance")
    If Abs($l_f_Pitch) > 1 Or $l_f_Distance < 0 Or $l_f_Distance > 5000 Then Return SetError(4, 0, False)

    Local $l_f_LookX = DllStructGetData($l_d_Camera, "lookX") + _
        $a_f_Forward * Cos($l_f_Yaw) - $a_f_Side * Sin($l_f_Yaw)
    Local $l_f_LookY = DllStructGetData($l_d_Camera, "lookY") + _
        $a_f_Forward * Sin($l_f_Yaw) + $a_f_Side * Cos($l_f_Yaw)
    Local $l_f_LookZ = DllStructGetData($l_d_Camera, "lookZ") + $a_f_Vertical
    Local $l_f_Horizontal = $l_f_Distance * Sqrt(1 - $l_f_Pitch * $l_f_Pitch)

    If Not _Camera_WriteVec3($l_p_Camera + 0xA8, $l_f_LookX, $l_f_LookY, $l_f_LookZ) Then Return SetError(5, 0, False)
    If $a_f_Yaw <> 0 Then
        If Not _Camera_WriteFloat($l_p_Camera + 0x18, $l_f_Yaw) Or _
            Not _Camera_WriteFloat($l_p_Camera + 0x60, $l_f_Yaw) Then Return SetError(5, 0, False)
    EndIf
    If Not _Camera_WriteVec3($l_p_Camera + 0x78, _
        $l_f_LookX - $l_f_Horizontal * Cos($l_f_Yaw), _
        $l_f_LookY - $l_f_Horizontal * Sin($l_f_Yaw), _
        $l_f_LookZ - 0.95 * $l_f_Distance * $l_f_Pitch) Then Return SetError(5, 0, False)
    Return True
EndFunc

Func _Camera_GetNativePtr()
    If $g_i_CameraUnlockPID <> $g_i_GWProcessId Then Return 0
    If $g_p_CameraNative Then Return $g_p_CameraNative

    ; Camera global referenced by the GmCam.cpp fov path in GWCA.
    Local $l_p_Immediate = _Camera_FindCodePattern("D916D95604D9560853D91757D95704", -4)
    If $l_p_Immediate = 0 Then Return 0
    Local $l_p_Camera = Memory_Read($l_p_Immediate, "ptr")
    Local $l_p_DataStart, $l_p_DataEnd
    If Not Scanner_GetSection($GC_I_SECTION_DATA, $l_p_DataStart, $l_p_DataEnd) Then Return 0
    If $l_p_Camera < $l_p_DataStart Or $l_p_Camera + 0xB4 > $l_p_DataEnd Then Return 0
    $g_p_CameraNative = $l_p_Camera
    Return $g_p_CameraNative
EndFunc

Func _Camera_FindCodePattern($a_s_Pattern, $a_i_Offset)
    Local $l_p_Start, $l_p_End
    If Not Scanner_GetSection($GC_I_SECTION_TEXT, $l_p_Start, $l_p_End) Then Return 0

    Local Const $l_i_ChunkSize = 0x40000
    Local $l_i_Overlap = Int(StringLen($a_s_Pattern) / 2) - 1
    Local $l_p_Found = 0

    For $l_p_Chunk = $l_p_Start To $l_p_End - 1 Step $l_i_ChunkSize
        Local $l_i_Size = $l_i_ChunkSize + $l_i_Overlap
        If $l_i_Size > $l_p_End - $l_p_Chunk Then $l_i_Size = Number($l_p_End - $l_p_Chunk)
        Local $l_d_Buffer = DllStructCreate("byte[" & $l_i_Size & "]")
        Local $l_av_Read = DllCall($g_h_Kernel32, "bool", "ReadProcessMemory", _
            "handle", $g_h_GWProcess, "ptr", $l_p_Chunk, _
            "struct*", $l_d_Buffer, "ulong_ptr", $l_i_Size, "ulong_ptr*", 0)
        If @error Or Not $l_av_Read[0] Or $l_av_Read[5] <> $l_i_Size Then Return 0

        Local $l_s_Bytes = String(DllStructGetData($l_d_Buffer, 1))
        Local $l_i_From = 1
        While True
            Local $l_i_Pos = StringInStr($l_s_Bytes, $a_s_Pattern, 1, 1, $l_i_From)
            If $l_i_Pos = 0 Then ExitLoop
            Local $l_p_Match = $l_p_Chunk + Int(($l_i_Pos - 3) / 2) + $a_i_Offset
            If $l_p_Found <> 0 And $l_p_Found <> $l_p_Match Then Return 0
            $l_p_Found = $l_p_Match
            $l_i_From = $l_i_Pos + StringLen($a_s_Pattern)
        WEnd
    Next

    Return $l_p_Found
EndFunc

Func _Camera_WriteFloat($a_p_Address, $a_f_Value)
    Local $l_d_Value = DllStructCreate("float")
    DllStructSetData($l_d_Value, 1, $a_f_Value)
    Local $l_av_Write = DllCall($g_h_Kernel32, "bool", "WriteProcessMemory", _
        "handle", $g_h_GWProcess, "ptr", $a_p_Address, "struct*", $l_d_Value, _
        "ulong_ptr", 4, "ulong_ptr*", 0)
    Return Not @error And $l_av_Write[0] And $l_av_Write[5] = 4
EndFunc

Func _Camera_WriteVec3($a_p_Address, $a_f_X, $a_f_Y, $a_f_Z)
    Local $l_d_Value = DllStructCreate("float x;float y;float z")
    DllStructSetData($l_d_Value, "x", $a_f_X)
    DllStructSetData($l_d_Value, "y", $a_f_Y)
    DllStructSetData($l_d_Value, "z", $a_f_Z)
    Local $l_av_Write = DllCall($g_h_Kernel32, "bool", "WriteProcessMemory", _
        "handle", $g_h_GWProcess, "ptr", $a_p_Address, "struct*", $l_d_Value, _
        "ulong_ptr", 12, "ulong_ptr*", 0)
    Return Not @error And $l_av_Write[0] And $l_av_Write[5] = 12
EndFunc

Func _Camera_WriteUnlockPatch($a_b_Bytes)
    Local $l_d_Bytes = DllStructCreate("byte[2]")
    DllStructSetData($l_d_Bytes, 1, $a_b_Bytes)

    Local $l_av_Protect = DllCall($g_h_Kernel32, "bool", "VirtualProtectEx", _
        "handle", $g_h_GWProcess, "ptr", $g_p_CameraUnlockPatch, _
        "ulong_ptr", 2, "dword", 0x40, "dword*", 0)
    If @error Or Not $l_av_Protect[0] Then Return False

    Local $l_av_Write = DllCall($g_h_Kernel32, "bool", "WriteProcessMemory", _
        "handle", $g_h_GWProcess, "ptr", $g_p_CameraUnlockPatch, _
        "struct*", $l_d_Bytes, "ulong_ptr", 2, "ulong_ptr*", 0)
    Local $l_b_Written = Not @error And $l_av_Write[0] And $l_av_Write[5] = 2

    DllCall($g_h_Kernel32, "bool", "VirtualProtectEx", _
        "handle", $g_h_GWProcess, "ptr", $g_p_CameraUnlockPatch, _
        "ulong_ptr", 2, "dword", $l_av_Protect[5], "dword*", 0)
    If Not $l_b_Written Then Return False

    Local $l_av_Flush = DllCall($g_h_Kernel32, "bool", "FlushInstructionCache", _
        "handle", $g_h_GWProcess, "ptr", $g_p_CameraUnlockPatch, "ulong_ptr", 2)
    Return Not @error And $l_av_Flush[0]
EndFunc
