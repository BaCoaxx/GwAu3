#CS ===========================================================================
; Test: the command queue under an Adlib - needs no Guild Wars client.
;
; Every command GwAu3 sends goes through Core_Enqueue into a ring of 256 slots of
; 256 bytes. Code injected into Guild Wars (MainProc in GwAu3_Core_Assembler.au3)
; reads that ring once per game frame, strictly in order, and waits on an empty
; slot. A bot that sends commands from an Adlib (for example a skill upkeep tick)
; while its main loop also sends commands can interrupt Core_Enqueue between its
; statements.
;
; Before the fix, Core_Enqueue wrote the slot at the global counter and then
; incremented the global counter. An Adlib enqueuing in between incremented it
; too, so the counter moved twice and one slot stayed empty. The injected reader
; then waited on that slot while every later command queued up behind it, until
; the writer went round all 256 slots and filled it - the character stops acting
; for minutes, then runs the whole backlog as a burst.
;
; The fix: read the slot once, write it, and set the counter from that slot. An
; interleaved enqueue then reuses the slot instead of skipping one - at worst one
; of the two commands is overwritten or runs late, the queue never stalls.
;
; This test runs both versions against a queue in its own memory: the main loop
; and an Adlib enqueue, and after every main-loop command one frame of a model of
; the injected reader runs. The model follows MainProc's queue handling step by
; step, with the assembly quoted above each step. Simplifications: the reader
; runs between main-loop commands instead of on the game thread, and MainProc's
; HandleCase branch (a game state in which queued commands are dropped unread) is
; left out - neither changes whether a slot can be skipped.
;
; Run with the 32-bit AutoIt interpreter. Prints one PASS/FAIL line per check,
; exits 1 if any check failed.
#CE ===========================================================================

#NoTrayIcon
Opt('MustDeclareVars', True)

#include "../../API/_GwAu3.au3"

Global Const $GC_I_TEST_MAIN_COMMANDS = 20000
Global Const $GC_I_TEST_SLOT_DWORDS = 64
Global Const $GC_I_TEST_QUEUE_SLOTS = 256

Global $g_i_TestFailures = 0
; The queue: 256 slots of 256 bytes, like QueueBase in the injected memory
Global $g_d_TestQueue = DllStructCreate('dword[' & $GC_I_TEST_SLOT_DWORDS * $GC_I_TEST_QUEUE_SLOTS & ']')
; A command: its first dword is the address of the command's code, never 0
Global $g_d_TestCommand = DllStructCreate('dword;dword')
; The enqueue function under test, called by the main loop and the Adlib alike
Global $g_f_TestEnqueue = Null
; The injected reader's own counter - QueueCounter in the injected memory
Global $g_i_TestReaderCounter = 0
Global $g_i_TestEnqueued = 0
Global $g_i_TestExecuted = 0
Global $g_i_TestAdlibEnqueues = 0

Test_CommandQueue()
Exit ($g_i_TestFailures > 0 ? 1 : 0)


Func Test_CommandQueue()
	$g_h_Kernel32 = DllOpen('kernel32.dll')
	; Pseudo handle of this process - WriteProcessMemory then writes into the test's own queue
	$g_h_GWProcess = -1
	$g_p_QueueBase = DllStructGetPtr($g_d_TestQueue)
	$g_i_QueueSize = $GC_I_TEST_QUEUE_SLOTS - 1
	DllStructSetData($g_d_TestCommand, 1, 1)

	Local $l_a_Before = Test_RunQueue(Core_Enqueue_BeforeFix)
	ConsoleWrite('Before the fix: ' & Test_Describe($l_a_Before) & @CRLF)
	Local $l_a_After = Test_RunQueue(Core_Enqueue)
	ConsoleWrite('After the fix:  ' & Test_Describe($l_a_After) & @CRLF)

	Test_Check('the Adlib enqueued during both runs', $l_a_Before[0] > 100 And $l_a_After[0] > 100)
	Test_Check('before the fix, the reader stalls on an empty slot (the test reproduces the bug)', $l_a_Before[1] > 0)
	Test_Check('after the fix, the reader never stalls on an empty slot', $l_a_After[1] == 0)
	Test_Check('after the fix, the reader catches up with the writer', $l_a_After[3] == 0)
	If $g_i_TestFailures == 0 Then ConsoleWrite('ALL PASSED' & @CRLF)
EndFunc


;~ Run the main loop and the Adlib against an empty queue with one enqueue function.
;~ Returns [Adlib enqueues, reader frames stalled on an empty slot, longest stall in commands, commands left unread at the end,
;~ commands enqueued, commands run]
Func Test_RunQueue($a_f_Enqueue)
	DllCall($g_h_Kernel32, 'none', 'RtlZeroMemory', 'ptr', $g_p_QueueBase, 'ulong_ptr', 4 * $GC_I_TEST_SLOT_DWORDS * $GC_I_TEST_QUEUE_SLOTS)
	$g_f_TestEnqueue = $a_f_Enqueue
	$g_i_QueueCounter = 0
	$g_i_TestReaderCounter = 0
	$g_i_TestEnqueued = 0
	$g_i_TestExecuted = 0
	$g_i_TestAdlibEnqueues = 0

	Local $l_i_StalledFrames = 0, $l_i_LongestStall = 0
	AdlibRegister('Test_AdlibEnqueue', 1)
	For $l_i_Command = 1 To $GC_I_TEST_MAIN_COMMANDS
		$g_f_TestEnqueue(DllStructGetPtr($g_d_TestCommand), 8)
		$g_i_TestEnqueued += 1
		If Not Test_ReaderFrame() And $g_i_TestReaderCounter <> $g_i_QueueCounter Then
			$l_i_StalledFrames += 1
			$l_i_LongestStall = _Max($l_i_LongestStall, Mod($g_i_QueueCounter - $g_i_TestReaderCounter + $GC_I_TEST_QUEUE_SLOTS, $GC_I_TEST_QUEUE_SLOTS))
		EndIf
	Next
	AdlibUnRegister('Test_AdlibEnqueue')

	; Writers stopped: let the reader run until it waits
	While Test_ReaderFrame()
	WEnd
	Local $l_i_Unread = Mod($g_i_QueueCounter - $g_i_TestReaderCounter + $GC_I_TEST_QUEUE_SLOTS, $GC_I_TEST_QUEUE_SLOTS)

	Local $l_a_Result[6] = [$g_i_TestAdlibEnqueues, $l_i_StalledFrames, $l_i_LongestStall, $l_i_Unread, $g_i_TestEnqueued, $g_i_TestExecuted]
	Return $l_a_Result
EndFunc


;~ The Adlib: a bot's upkeep tick, reduced to its enqueue
Func Test_AdlibEnqueue()
	$g_f_TestEnqueue(DllStructGetPtr($g_d_TestCommand), 8)
	$g_i_TestEnqueued += 1
	$g_i_TestAdlibEnqueues += 1
EndFunc


;~ One game frame of the injected reader - MainProc's RegularFlow and CommandReturn (GwAu3_Core_Assembler.au3).
;~ Returns True when it ran a command, False when it waited on an empty slot.
Func Test_ReaderFrame()
	; mov eax,dword[QueueCounter] / mov ecx,eax / shl eax,8 / add eax,QueueBase / mov ebx,dword[eax]
	Local $l_i_SlotDword = $GC_I_TEST_SLOT_DWORDS * $g_i_TestReaderCounter + 1
	Local $l_i_CommandPtr = DllStructGetData($g_d_TestQueue, 1, $l_i_SlotDword)
	; test ebx,ebx / jz MainExit - an empty slot: the reader leaves and reads the same slot next frame
	If $l_i_CommandPtr == 0 Then Return False
	; mov dword[SavedIndex],ecx / mov dword[eax],0 / jmp ebx - clear the slot and run the command
	DllStructSetData($g_d_TestQueue, 1, 0, $l_i_SlotDword)
	$g_i_TestExecuted += 1
	; CommandReturn: inc eax / cmp eax,QueueSize / jnz MainSkipReset / xor eax,eax / mov dword[QueueCounter],eax
	$g_i_TestReaderCounter = Mod($g_i_TestReaderCounter + 1, $GC_I_TEST_QUEUE_SLOTS)
	Return True
EndFunc


;~ Core_Enqueue as it was before the fix, for comparison - the counter is incremented from its global value after the write
Func Core_Enqueue_BeforeFix($a_p_Ptr, $a_i_Size)
	DllCall($g_h_Kernel32, 'int', 'WriteProcessMemory', 'int', $g_h_GWProcess, 'int', 256 * $g_i_QueueCounter + $g_p_QueueBase, 'ptr', $a_p_Ptr, 'int', $a_i_Size, 'int', '')
	If $g_i_QueueCounter = $g_i_QueueSize Then
		$g_i_QueueCounter = 0
	Else
		$g_i_QueueCounter = $g_i_QueueCounter + 1
	EndIf
EndFunc


Func Test_Describe($a_a_Result)
	Return $a_a_Result[4] & ' commands enqueued (' & $a_a_Result[0] & ' by the Adlib), ' & $a_a_Result[5] & ' run, reader stalled on an empty slot in ' _
		& $a_a_Result[1] & ' frames (longest: ' & $a_a_Result[2] & ' commands queued behind it), ' & $a_a_Result[3] & ' left unread at the end'
EndFunc


; Functions GwAu3 expects the script to provide - the test attaches to no game, so they do nothing
Func StartBot()
EndFunc

Func _Exit()
EndFunc

Func Extend_Write()
EndFunc

Func Extend_AssemblerWriteDetour()
EndFunc

Func Out($a_s_Text)
	ConsoleWrite($a_s_Text & @CRLF)
EndFunc


Func Test_Check($a_s_Name, $a_b_Condition)
	If $a_b_Condition Then
		ConsoleWrite('PASS ' & $a_s_Name & @CRLF)
	Else
		ConsoleWrite('FAIL ' & $a_s_Name & @CRLF)
		$g_i_TestFailures += 1
	EndIf
EndFunc
