#Requires AutoHotkey v2.0
#SingleInstance Force
; Only these requested exceptions survive normal-Windows mode.
Persistent
global FlowExe := EnvGet('LOCALAPPDATA') '\FlowLauncher\Flow.Launcher.exe'
#Include mouse-drag.ahk
if !ProcessExist('Flow.Launcher.exe')
    Run('"' FlowExe '"')
#Space::{
    Run('"' FlowExe '"')
    if !WinExist('ahk_exe Flow.Launcher.exe')
        SetTimer(() => Send('!{Space}'), -1500)
}
#HotIf WinActive('ahk_exe Flow.Launcher.exe')
Escape::Send('!{Space}')
#HotIf
~#LButton::DragWindowFromAnywhere()
