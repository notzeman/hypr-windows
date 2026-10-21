; Enable/disable ordinary registered hotkeys outside the keyboard hook. A
; #HotIf expression must wait for the main thread and can time out if it is
; busy launching/closing a console, causing Windows to drop the keyboard hook.
global KomorebiRunning := -1
global KomorebiHotkeys := ['^!F9', '^!F10', '#w', '#Tab', '#+Tab', '#f', '#!f',
    '#t', '#g', '#+g', '#!Tab', '#!p']
global HotkeyForegroundHook := 0
global HotkeyForegroundCallback := 0

StartHotkeyReliability() {
    global HotkeyForegroundHook, HotkeyForegroundCallback, KomorebiHotkeys
    Loop 10 {
        number := Mod(A_Index, 10)
        KomorebiHotkeys.Push('#' number, '#+' number)
    }
    for direction in ['Left', 'Down', 'Up', 'Right']
        KomorebiHotkeys.Push('#' direction, '#+' direction, '#^' direction)
    UpdateKomorebiRunning()
    SetTimer(UpdateKomorebiRunning, 1000)
    InstallKeybdHook(true)
    HotkeyForegroundCallback := CallbackCreate(HotkeyForegroundChanged, '', 7)
    HotkeyForegroundHook := DllCall('SetWinEventHook', 'UInt', 3, 'UInt', 3,
        'Ptr', 0, 'Ptr', HotkeyForegroundCallback, 'UInt', 0, 'UInt', 0, 'UInt', 0, 'Ptr')
    OnError(LogHotkeyError)
    OnExit(StopHotkeyReliability)
}

UpdateKomorebiRunning() {
    global KomorebiRunning, KomorebiHotkeys
    running := !!ProcessExist('komorebi.exe')
    if running != KomorebiRunning {
        for key in KomorebiHotkeys
            Hotkey(key, running ? 'On' : 'Off')
        KomorebiRunning := running
    }
}

HotkeyForegroundChanged(hook, event, hwnd, objectId, childId, eventThread, eventTime) {
    ; Closing the last tile returns focus to Explorer's empty desktop. Re-arm
    ; the keyboard hook there, independent of keyboard input reaching that hook.
    name := Buffer(512, 0)
    if hwnd && DllCall('GetClassNameW', 'Ptr', hwnd, 'Ptr', name, 'Int', 256) {
        cls := StrGet(name)
        if cls != 'Progman' && cls != 'WorkerW' && cls != 'Shell_TrayWnd'
            return
    }
    SetTimer(RecoverKeyboardHook, -150)
}

RecoverKeyboardHook(*) {
    ; Do not reinstall halfway through a physically held shortcut.
    for key in ['LWin', 'RWin', 'LCtrl', 'RCtrl', 'LAlt', 'RAlt', 'LShift', 'RShift'] {
        ; Query Windows directly: AHK's cached physical state may be stale
        ; precisely when a hook has stopped receiving key-up events.
        if DllCall('GetAsyncKeyState', 'Int', GetKeyVK(key), 'Short') & 0x8000 {
            SetTimer(RecoverKeyboardHook, -150)
            return
        }
    }
    InstallKeybdHook(true, true)
    UpdateKomorebiRunning()
}

LogHotkeyError(err, mode) {
    try {
        path := EnvGet('LOCALAPPDATA') '\OmarchyWindows\hotkey-errors.log'
        FileAppend(FormatTime(, 'yyyy-MM-dd HH:mm:ss') ' [' mode '] '
            err.Message ' | ' err.File ':' err.Line "`n", path, 'UTF-8')
    }
    return false  ; Preserve normal error reporting; never silently swallow it.
}

StopHotkeyReliability(*) {
    global HotkeyForegroundHook, HotkeyForegroundCallback
    SetTimer(UpdateKomorebiRunning, 0)
    SetTimer(RecoverKeyboardHook, 0)
    if HotkeyForegroundHook {
        DllCall('UnhookWinEvent', 'Ptr', HotkeyForegroundHook)
        HotkeyForegroundHook := 0
    }
    if HotkeyForegroundCallback {
        CallbackFree(HotkeyForegroundCallback)
        HotkeyForegroundCallback := 0
    }
}
