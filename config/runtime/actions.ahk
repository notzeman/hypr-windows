#Requires AutoHotkey v2.0
#SingleInstance Off
SetWorkingDir(A_ScriptDir)
action := A_Args.Length ? A_Args[1] : 'root'
K(args) => Run('"C:\Program Files\komorebi\bin\komorebic-no-console.exe" ' args, , 'Hide')
PowerAction(action) {
    if MsgBox(action ' this computer?', 'Confirm power action', 'YesNo Icon! Default2') != 'Yes'
        return
    switch action {
        case 'Shut down': Run('shutdown.exe /s /t 0', , 'Hide')
        case 'Restart': Run('shutdown.exe /r /t 0', , 'Hide')
        case 'Sign out': Run('shutdown.exe /l', , 'Hide')
        case 'Sleep':
            if !DllCall('PowrProf\SetSuspendState', 'UChar', 0, 'UChar', 0, 'UChar', 0)
                TrayTip('Windows could not enter sleep.', 'Power menu')
    }
}
switch action {
    case 'help': Run('"C:\Program Files\Notepad++\notepad++.exe" "' A_ScriptDir '\SHORTCUTS.txt"')
    case 'theme': Run('ms-settings:themes')
    case 'wallpaper': Run('powershell.exe -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "' A_ScriptDir '\wallpaper-picker.ps1"', , 'Hide')
    case 'power':
        m := Menu()
        m.Add('Lock (native Win+L)', (*) => DllCall('LockWorkStation'))
        m.Add('Sleep...', (*) => PowerAction('Sleep'))
        m.Add('Restart...', (*) => PowerAction('Restart'))
        m.Add('Shut down...', (*) => PowerAction('Shut down'))
        m.Add('Sign out...', (*) => PowerAction('Sign out'))
        m.Add()
        m.Add('Windows power and sleep settings', (*) => Run('ms-settings:powersleep'))
        m.Add('Cancel', (*) => 0)
        m.Show()
    default:
        m := Menu()
        m.Add('Applications (Flow Launcher)', (*) => Run('"' EnvGet('LOCALAPPDATA') '\FlowLauncher\Flow.Launcher.exe"'))
        m.Add('CMD terminal', (*) => Run('"' A_AhkPath '" "' A_ScriptDir '\cmd.ahk"'))
        m.Add('Keyboard shortcuts', (*) => Run('"C:\Program Files\Notepad++\notepad++.exe" "' A_ScriptDir '\SHORTCUTS.txt"'))
        m.Add('BSP layout', (*) => K('change-layout bsp'))
        m.Add('Columns layout', (*) => K('change-layout columns'))
        m.Add('Retile windows', (*) => K('retile'))
        m.Add('Pause / resume tiling', (*) => K('toggle-pause'))
        m.Add('Windows settings', (*) => Run('ms-settings:'))
        m.Show()
}
ExitApp()
