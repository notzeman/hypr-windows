#Requires AutoHotkey v2.0
#SingleInstance Off
#Include console-style.ahk
; Affect only the console opened here; never alter global console defaults.
; Open in the user profile instead of inheriting this script's folder.
; Match the launched process, not an artificial title, for translucency.
Run('"' A_ComSpec '"', EnvGet('USERPROFILE'), , &pid)
hwnd := WinWait('ahk_pid ' pid, , 10)
if hwnd {
    ApplyConsoleStyle(pid)
    WinSetTransparent(220, 'ahk_id ' hwnd)
} else {
    TrayTip('CMD opened, but its console window could not be found for translucency.', 'Terminal')
}
ExitApp()
