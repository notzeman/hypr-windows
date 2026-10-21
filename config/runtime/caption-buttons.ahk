; Hide native caption controls, not the caption/title bar itself. Never inject
; into apps or patch custom title bars. Original button bits are restored on exit.
global CaptionButtonsHidden := true
global CaptionOriginalBits := Map()
global CaptionEventHook := 0
global CaptionEventCallback := 0
global CaptionStateFile := EnvGet('LOCALAPPDATA') '\OmarchyWindows\caption-buttons-state.ini'

StartCaptionButtonHiding() {
    global CaptionEventHook, CaptionEventCallback, CaptionStateFile, CaptionOriginalBits
    ; Survive a hard-killed/restarted service without forgetting original styles.
    if FileExist(CaptionStateFile) {
        for line in StrSplit(FileRead(CaptionStateFile), "`n", "`r") {
            if RegExMatch(line, '^(\d+)=(\d+),(\d+)$', &saved) {
                hwnd := Integer(saved[1])
                owner := 0
                DllCall('GetWindowThreadProcessId', 'Ptr', hwnd, 'UInt*', &owner)
                if DllCall('IsWindow', 'Ptr', hwnd) && owner = Integer(saved[2])
                    CaptionOriginalBits[hwnd] := {pid: owner, bits: Integer(saved[3])}
            }
        }
    }
    CaptionEventCallback := CallbackCreate(CaptionWindowShown, '', 7)
    CaptionEventHook := DllCall('SetWinEventHook', 'UInt', 0x8002, 'UInt', 0x8002,
        'Ptr', 0, 'Ptr', CaptionEventCallback, 'UInt', 0, 'UInt', 0, 'UInt', 0, 'Ptr')
    OnExit(StopCaptionButtonHiding)
    HideCaptionButtons()
    SetTimer(HideCaptionButtons, 1000)
}

CaptionWindowShown(hook, event, hwnd, objectId, childId, eventThread, eventTime) {
    global CaptionButtonsHidden
    if CaptionButtonsHidden && hwnd && objectId = 0 && childId = 0 {
        style := DllCall('GetWindowLongW', 'Ptr', hwnd, 'Int', -16, 'UInt')
        if (style & 0xC00000) = 0xC00000 && (style & 0xB0000)
            SetTimer(RefreshCaptionButtons, -75)
    }
}

RefreshCaptionButtons() => HideCaptionButtons()

HideCaptionButtons() {
    global CaptionButtonsHidden, CaptionOriginalBits, CaptionStateFile
    if !CaptionButtonsHidden
        return
    stale := []
    for hwnd, saved in CaptionOriginalBits {
        owner := 0
        DllCall('GetWindowThreadProcessId', 'Ptr', hwnd, 'UInt*', &owner)
        if !DllCall('IsWindow', 'Ptr', hwnd) || owner != saved.pid
            stale.Push(hwnd)
    }
    for hwnd in stale
        CaptionOriginalBits.Delete(hwnd)
    for hwnd in WinGetList() {
        try {
            if DllCall('IsHungAppWindow', 'Ptr', hwnd)
                continue
            style := WinGetStyle(hwnd)
            ; Require a normal caption and at least one native control bit.
            if (style & 0xC00000) != 0xC00000 || !(style & 0xB0000)
                continue
            if WinGetExStyle(hwnd) & (0x80 | 0x08000000)
                continue
            cls := WinGetClass(hwnd)
            ; Keep dialog recovery controls and all shell panels untouched.
            if cls = '#32770' || cls = 'AutoHotkey' || cls = 'Shell_TrayWnd'
                || cls = 'Shell_SecondaryTrayWnd' || cls = 'WorkerW' || cls = 'Progman'
                continue
            owner := WinGetPID(hwnd)
            if !CaptionOriginalBits.Has(hwnd) {
                CaptionOriginalBits[hwnd] := {pid: owner, bits: style & 0xB0000}
                IniWrite(owner ',' (style & 0xB0000), CaptionStateFile, 'Windows', String(hwnd))
            }
            ; WS_SYSMENU, WS_MINIMIZEBOX, WS_MAXIMIZEBOX. The caption stays.
            WinSetStyle('-0xB0000', hwnd)
            DllCall('SetWindowPos', 'Ptr', hwnd, 'Ptr', 0, 'Int', 0, 'Int', 0,
                'Int', 0, 'Int', 0, 'UInt', 0x4037) ; FRAMECHANGED + async, no move/activate
        } catch {
            ; Elevated/protected/closing windows cannot always be styled.
        }
    }
}

RestoreCaptionButtons() {
    global CaptionButtonsHidden, CaptionOriginalBits, CaptionStateFile
    CaptionButtonsHidden := false
    SetTimer(HideCaptionButtons, 0)
    SetTimer(RefreshCaptionButtons, 0)
    for hwnd, saved in CaptionOriginalBits {
        try {
            owner := 0
            DllCall('GetWindowThreadProcessId', 'Ptr', hwnd, 'UInt*', &owner)
            if !DllCall('IsWindow', 'Ptr', hwnd) || owner != saved.pid
                continue
            bits := DllCall('GetWindowLongW', 'Ptr', hwnd, 'Int', -16, 'UInt')
            ; Change only the control bits we touched; preserve tiling/style edits.
            bits := (bits & ~0xB0000) | saved.bits
            DllCall('SetWindowLongW', 'Ptr', hwnd, 'Int', -16, 'UInt', bits)
            DllCall('SetWindowPos', 'Ptr', hwnd, 'Ptr', 0, 'Int', 0, 'Int', 0,
                'Int', 0, 'Int', 0, 'UInt', 0x4037)
        } catch {
        }
    }
    CaptionOriginalBits.Clear()
    try FileDelete(CaptionStateFile)
}

ToggleCaptionButtons() {
    global CaptionButtonsHidden
    if CaptionButtonsHidden
        RestoreCaptionButtons()
    else {
        CaptionButtonsHidden := true
        HideCaptionButtons()
        SetTimer(HideCaptionButtons, 1000)
    }
}

StopCaptionButtonHiding(*) {
    global CaptionEventHook, CaptionEventCallback
    if CaptionEventHook {
        DllCall('UnhookWinEvent', 'Ptr', CaptionEventHook)
        CaptionEventHook := 0
    }
    if CaptionEventCallback {
        CallbackFree(CaptionEventCallback)
        CaptionEventCallback := 0
    }
    RestoreCaptionButtons()
}
