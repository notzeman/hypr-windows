; Win + left-drag starts a real Windows caption drag. Unlike repeatedly using
; WinMove, this generates the move/size events Komorebi needs for tile drops.
DragWindowFromAnywhere() {
    oldMode := A_CoordModeMouse
    CoordMode('Mouse', 'Screen')
    try MouseGetPos(&x, &y, &underMouse)
    finally CoordMode('Mouse', oldMode)
    if !underMouse
        return
    hwnd := DllCall('GetAncestor', 'Ptr', underMouse, 'UInt', 2, 'Ptr')
    if !hwnd || !DllCall('IsWindowVisible', 'Ptr', hwnd)
        return
    try {
        cls := WinGetClass(hwnd)
        if cls = 'Progman' || cls = 'WorkerW' || cls = 'Shell_TrayWnd'
            || cls = 'Shell_SecondaryTrayWnd' || cls = '#32768'
            || cls = 'tooltips_class32' || WinGetTitle(hwnd) = 'YasbBar'
            return
        ; Don't drag non-activating panels, popups, or tool windows.
        if WinGetExStyle(hwnd) & (0x08000000 | 0x80)
            return
        ; The pass-through physical click activates the target normally.
        DllCall('ReleaseCapture')
        position := (x & 0xFFFF) | ((y & 0xFFFF) << 16)
        ; Asynchronous: a synchronous SendMessage would block our hotkey
        ; service for the entire drag, risking another keyboard-hook timeout.
        PostMessage(0xA1, 2, position, , hwnd) ; WM_NCLBUTTONDOWN / HTCAPTION
    } catch TargetError {
        ; A window may disappear between hit-testing and the posted message.
    }
}
