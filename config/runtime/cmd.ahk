#Requires AutoHotkey v2.0
#SingleInstance Off
#Include console-style.ahk
; Affect only the console opened here; never alter global console defaults.
; Open in the user profile instead of inheriting this script's folder.
; The main service applies reversible transparency/blur to visible consoles.
Run('"' A_ComSpec '"', EnvGet('USERPROFILE'), , &pid)
hwnd := WinWait('ahk_pid ' pid, , 10)
if hwnd {
    ApplyConsoleStyle(pid)
} else {
    TrayTip('CMD opened, but its console window could not be found for styling.', 'Terminal')
}
ExitApp()
