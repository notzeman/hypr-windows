#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook False
A_MenuMaskKey := 'vkE8'
Persistent
SetWorkingDir(A_ScriptDir)
global KExe := 'C:\Program Files\komorebi\bin\komorebic-no-console.exe'
global FlowExe := EnvGet('LOCALAPPDATA') '\FlowLauncher\Flow.Launcher.exe'
; Liveness marker so start.ps1 can detect this service cheaply (no WMI query
; every minute). Removed on graceful exit so a dead service is obvious.
global HotkeyPidFile := EnvGet('LOCALAPPDATA') '\OmarchyWindows\hotkeys.pid'
DirCreate(EnvGet('LOCALAPPDATA') '\OmarchyWindows')
try {
    pidFile := FileOpen(HotkeyPidFile, 'w')
    pidFile.Write(String(DllCall('GetCurrentProcessId')))
    pidFile.Close()
} catch {
}
OnExit(ClearHotkeyPid)
ClearHotkeyPid(*) {
    try FileDelete(HotkeyPidFile)
}
#Include taskbar.ahk
StartTaskbarHiding()
#Include cursor.ahk
; Cursor auto-hide disabled: it relied on idle time (no keyboard reset), which
; left the pointer blank while typing. Ensure the real scheme is loaded once.
ShowCursorNow()
#Include hotkey-reliability.ahk
StartHotkeyReliability()
#Include mouse-drag.ahk
#Include caption-buttons.ahk
StartCaptionButtonHiding()
#Include terminal-effects.ahk
StartTerminalEffects()

K(args) {
    global KExe
    Run('"' KExe '" ' args, , 'Hide')
}
Action(name) {
    Run('"' A_AhkPath '" "' A_ScriptDir '\actions.ahk" ' name)
}
FlowVisible() {
    return WinExist('ahk_exe Flow.Launcher.exe')   ; visible windows only
}
ShowFlow() {
    global FlowExe
    if ProcessExist('Flow.Launcher.exe')
        Run('"' FlowExe '"')            ; wake the existing instance
    else {
        Run('"' FlowExe '"')            ; cold start opens hidden (HideOnStartup)
        SetTimer(EnsureFlowShown, -3000)
    }
}
EnsureFlowShown() {
    if ProcessExist('Flow.Launcher.exe') && !FlowVisible()
        Send('!{Space}')                ; Flow's own activation hotkey
}
DismissFlow() {
    ; Escape always dismisses, even when the query box has text
    ; (Flow alone would only clear the query on the first Escape).
    if FlowVisible()
        Send('!{Space}')
}
OpenSystray() {
    ; "Tray of running services": open the YASB systray popup (all background
    ; app icons). The Win+Shift+R hotkey drives the bar's expand/collapse
    ; button. Win+R is left untouched for the native Windows Run dialog.
    ; The systray widget is the last widget in the bar, so its toggle sits ~14px
    ; inside the bar's right edge. Qt routes a click by cursor position and needs
    ; a fresh mouse-move onto the button first, so approach it along the bar.
    if !(hwnd := WinExist('YasbBar'))
        return
    WinGetPos(&bx, &by, &bw, &bh, hwnd)
    tx := bx + bw - 14
    ty := by + bh // 2
    MouseMove(tx - 90, ty, 0)
    Sleep(120)
    MouseMove(tx, ty, 0)
    Sleep(120)
    Click()
}

; Safety controls remain available even when tiling is stopped.
#UseHook False
#SuspendExempt True
^!F6::ToggleCaptionButtons()
^!F7::RecoverKeyboardHook()
^!F8::RestoreTaskbar()
^!F12::{
    Run('powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' EnvGet('LOCALAPPDATA') '\HyprWindows\switch.ps1" remove', , 'Hide')
}
^!F11::{
    ShowCursorNow()
    Suspend(-1)
}
#SuspendExempt False
#UseHook False
#Space::ShowFlow()
#HotIf WinActive('ahk_exe Flow.Launcher.exe')
Escape::DismissFlow()
#HotIf
#!Space::Action('root')
#Enter::Run('"' A_AhkPath '" "' A_ScriptDir '\cmd.ahk"')
#k::Action('help')
#Escape::Action('power')
#+^Space::Action('theme')
#^Space::Action('wallpaper')
#+a::Run('"C:\Program Files\Notepad++\notepad++.exe"')
#+l::Run('"' EnvGet('LOCALAPPDATA') '\Chromium\Application\chrome.exe"')
#+b::Run('"' EnvGet('LOCALAPPDATA') '\Chromium\Application\chrome.exe"')
#+f::Run('explorer.exe')
; Win+Ctrl+L is not remapped: Windows can reserve Win+L even with modifiers.
#^v::Send('#v')
#^e::Send('#.')
; Leave Win+R native; Super+Shift+R opens the background-app tray.
#+r::OpenSystray()
~#LButton::DragWindowFromAnywhere()
PrintScreen::Send('#+s')
!PrintScreen::Run('"C:\Program Files\obs-studio\bin\64bit\obs64.exe"', 'C:\Program Files\obs-studio\bin\64bit')

; Enabled/disabled by UpdateKomorebiRunning, without synchronous #HotIf checks.
; Windows Precision Touchpad custom three-finger swipe shortcuts.
^!F9::K('cycle-workspace next')
^!F10::K('cycle-workspace previous')
#w::K('close')
#Tab::K('cycle-workspace next')
#+Tab::K('cycle-workspace previous')
#1::K('focus-workspace 0')
#2::K('focus-workspace 1')
#3::K('focus-workspace 2')
#4::K('focus-workspace 3')
#5::K('focus-workspace 4')
#6::K('focus-workspace 5')
#7::K('focus-workspace 6')
#8::K('focus-workspace 7')
#9::K('focus-workspace 8')
#0::K('focus-workspace 9')
#+1::K('move-to-workspace 0')
#+2::K('move-to-workspace 1')
#+3::K('move-to-workspace 2')
#+4::K('move-to-workspace 3')
#+5::K('move-to-workspace 4')
#+6::K('move-to-workspace 5')
#+7::K('move-to-workspace 6')
#+8::K('move-to-workspace 7')
#+9::K('move-to-workspace 8')
#+0::K('move-to-workspace 9')
#f::K('toggle-monocle')
#!f::K('toggle-maximize')
#t::K('toggle-float')
#g::K('stack-all')
#+g::K('unstack-all')
#Left::K('focus left')
#Down::K('focus down')
#Up::K('focus up')
#Right::K('focus right')
#+Left::K('move left')
#+Down::K('move down')
#+Up::K('move up')
#+Right::K('move right')
#^Left::K('resize-axis horizontal decrease')
#^Right::K('resize-axis horizontal increase')
#^Up::K('resize-axis vertical increase')
#^Down::K('resize-axis vertical decrease')
#!Tab::K('cycle-stack next')
#!p::K('toggle-pause')
