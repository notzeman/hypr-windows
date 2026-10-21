; Included by hotkeys.ahk. Keep Explorer running; hide only its taskbar windows.
global TaskbarLastHwnd := 0
global TaskbarOriginalState := 0
global TaskbarHidingEnabled := false
global TaskbarShowHook := 0
global TaskbarShowCallback := 0

IsExplorerTaskbar(hwnd, primaryOnly := false) {
    name := Buffer(512, 0)
    if !DllCall('GetClassNameW', 'Ptr', hwnd, 'Ptr', name, 'Int', 256)
        return false
    cls := StrGet(name)
    if primaryOnly && cls != 'Shell_TrayWnd'
        return false
    if cls != 'Shell_TrayWnd' && cls != 'Shell_SecondaryTrayWnd'
        return false
    pid := 0
    DllCall('GetWindowThreadProcessId', 'Ptr', hwnd, 'UInt*', &pid)
    try return StrLower(ProcessGetName(pid)) = 'explorer.exe'
    catch
        return false
}

ExplorerTaskbars() {
    windows := []
    old := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        for cls in ['Shell_TrayWnd', 'Shell_SecondaryTrayWnd'] {
            for hwnd in WinGetList('ahk_class ' cls) {
                if IsExplorerTaskbar(hwnd)
                    windows.Push(hwnd)
            }
        }
    } finally DetectHiddenWindows(old)
    return windows
}

TaskbarMessage(message, state := 0, hwnd := 0) {
    data := Buffer(A_PtrSize = 8 ? 48 : 36, 0)
    NumPut('UInt', data.Size, data, 0)
    if !hwnd {
        for candidate in ExplorerTaskbars() {
            if IsExplorerTaskbar(candidate, true) {
                hwnd := candidate
                break
            }
        }
    }
    if !hwnd
        return 0
    NumPut('Ptr', hwnd, data, A_PtrSize = 8 ? 8 : 4)
    NumPut('Ptr', state, data, A_PtrSize = 8 ? 40 : 32)
    return DllCall('shell32\SHAppBarMessage', 'UInt', message, 'Ptr', data, 'UPtr')
}

StartTaskbarHiding() {
    global TaskbarOriginalState, TaskbarHidingEnabled, TaskbarShowHook, TaskbarShowCallback
    path := EnvGet('LOCALAPPDATA') '\OmarchyWindows\taskbar-original-state.txt'
    if FileExist(path)
        TaskbarOriginalState := Integer(Trim(FileRead(path), " `t`r`n"))
    else {
        TaskbarOriginalState := TaskbarMessage(4)
        DirCreate(EnvGet('LOCALAPPDATA') '\OmarchyWindows')
        FileAppend(String(TaskbarOriginalState), path, 'UTF-8-RAW')
    }
    OnExit(RestoreTaskbar)
    TaskbarHidingEnabled := true
    TaskbarShowCallback := CallbackCreate(TaskbarShown, '', 7)
    ; EVENT_OBJECT_SHOW, out-of-context: react to Explorer revealing its taskbar.
    TaskbarShowHook := DllCall('SetWinEventHook', 'UInt', 0x8002, 'UInt', 0x8002,
        'Ptr', 0, 'Ptr', TaskbarShowCallback, 'UInt', 0, 'UInt', 0, 'UInt', 0, 'Ptr')
    OnMessage(DllCall('RegisterWindowMessage', 'Str', 'TaskbarCreated'), TaskbarRecreated)
    KeepTaskbarHidden()
    SetTimer(KeepTaskbarHidden, 250)
}

TaskbarShown(hook, event, hwnd, objectId, childId, eventThread, eventTime) {
    global TaskbarHidingEnabled
    if TaskbarHidingEnabled && objectId = 0 && childId = 0 && IsExplorerTaskbar(hwnd)
        DllCall('ShowWindowAsync', 'Ptr', hwnd, 'Int', 0)
}

TaskbarRecreated(*) {
    global TaskbarLastHwnd, TaskbarHidingEnabled
    if TaskbarHidingEnabled {
        TaskbarLastHwnd := 0
        KeepTaskbarHidden()
    }
}

KeepTaskbarHidden() {
    global TaskbarLastHwnd, TaskbarOriginalState, TaskbarHidingEnabled
    if !TaskbarHidingEnabled
        return
    for hwnd in ExplorerTaskbars() {
        if IsExplorerTaskbar(hwnd, true) && hwnd != TaskbarLastHwnd {
            ; Only Explorer's real appbar may change work-area reservations.
            TaskbarMessage(10, TaskbarOriginalState | 1, hwnd)
            TaskbarLastHwnd := hwnd
        }
        if DllCall('IsWindowVisible', 'Ptr', hwnd)
            DllCall('ShowWindowAsync', 'Ptr', hwnd, 'Int', 0)
    }
}

RestoreTaskbar(*) {
    global TaskbarOriginalState, TaskbarHidingEnabled, TaskbarShowHook, TaskbarShowCallback
    TaskbarHidingEnabled := false
    SetTimer(KeepTaskbarHidden, 0)
    if TaskbarShowHook {
        DllCall('UnhookWinEvent', 'Ptr', TaskbarShowHook)
        TaskbarShowHook := 0
    }
    if TaskbarShowCallback {
        CallbackFree(TaskbarShowCallback)
        TaskbarShowCallback := 0
    }
    TaskbarMessage(10, TaskbarOriginalState)
    for hwnd in ExplorerTaskbars()
        DllCall('ShowWindow', 'Ptr', hwnd, 'Int', 5)
}
