#Requires AutoHotkey v2.0
#Include caption-buttons.ahk
#Include taskbar.ahk
#Include cursor.ahk
; Recover saved caption bits, even if the previous service was hard-killed.
StartCaptionButtonHiding()
StopCaptionButtonHiding()
StartTaskbarHiding()
RestoreTaskbar()
ShowCursorNow()
; Turn off Windows focus-follows-mouse using the supported API.
DllCall('SystemParametersInfo', 'UInt', 0x1001, 'UInt', 0, 'Ptr', 0, 'UInt', 3)
; Restore only console alpha values, not unrelated application windows.
for hwnd in WinGetList('ahk_class ConsoleWindowClass') {
    try WinSetTransparent('Off', hwnd)
}
ExitApp()
