#Requires AutoHotkey v2.0
#Include caption-buttons.ahk
#Include taskbar.ahk
#Include cursor.ahk
#Include terminal-effects.ahk
LoadTerminalEffects()
StopTerminalEffects()
; Recover saved caption bits, even if the previous service was hard-killed.
StartCaptionButtonHiding()
StopCaptionButtonHiding()
StartTaskbarHiding()
RestoreTaskbar()
ShowCursorNow()
; Turn off Windows focus-follows-mouse using the supported API.
DllCall('SystemParametersInfo', 'UInt', 0x1001, 'UInt', 0, 'Ptr', 0, 'UInt', 3)
ExitApp()
