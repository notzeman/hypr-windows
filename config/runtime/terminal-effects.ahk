; Classic conhost only: no shell injection, console creation, or focus changes.
; Acrylic is an undocumented Windows compositor feature; it has no radius knob.
; Modern Windows Terminal supplies its own acrylic and is intentionally excluded.
global TerminalEffects := Map()
global TerminalStateFile := EnvGet('LOCALAPPDATA') '\OmarchyWindows\terminal-effects.ini'

LoadTerminalEffects() {
    global TerminalEffects, TerminalStateFile
    if !FileExist(TerminalStateFile)
        return
    for line in StrSplit(FileRead(TerminalStateFile), "`n", "`r") {
        if !RegExMatch(line, '^(\d+)=([\d,]+)$', &match)
            continue
        values := StrSplit(match[2], ',')
        if values.Length != 9 && values.Length != 11 && values.Length != 12
            continue
        hwnd := Integer(match[1])
        try {
            if WinGetPID(hwnd) = Integer(values[1])
                TerminalEffects[hwnd] := values
        }
    }
}

StartTerminalEffects() {
    LoadTerminalEffects()
    OnExit(StopTerminalEffects)
    UpdateTerminalEffects()
    SetTimer(UpdateTerminalEffects, 1000)
}

TerminalAccent(hwnd, state, flags := 2, tint := 0, animation := 0) {
    accent := Buffer(16, 0)
    NumPut('UInt', state, 'UInt', flags, 'UInt', tint, 'UInt', animation, accent)
    data := Buffer(A_PtrSize * 3, 0)
    NumPut('Int', 19, data)
    NumPut('Ptr', accent.Ptr, 'UPtr', accent.Size, data, A_PtrSize)
    return DllCall('user32\SetWindowCompositionAttribute', 'Ptr', hwnd, 'Ptr', data, 'Int')
}

TerminalCaption(hwnd, bits) {
    ; Change only WS_CAPTION; retain WS_VSCROLL/WS_HSCROLL and resize behavior.
    style := WinGetStyle(hwnd)
    replacement := (style & ~0xC00000) | bits
    if style = replacement
        return
    WinSetStyle(replacement, hwnd)
    DllCall('SetWindowPos', 'Ptr', hwnd, 'Ptr', 0, 'Int', 0, 'Int', 0,
        'Int', 0, 'Int', 0, 'UInt', 0x4037) ; Async FRAMECHANGED, no move/focus
}

TerminalPalette(pid, index := -1, color := 0, write := false) {
    if !DllCall('AttachConsole', 'UInt', pid)
        return false
    output := 0
    try {
        DllCall('SetConsoleCtrlHandler', 'Ptr', 0, 'Int', 1)
        ; A redirected service stdout is a file/pipe even after AttachConsole.
        ; Open the attached console's actual screen buffer explicitly instead.
        output := DllCall('CreateFileW', 'Str', 'CONOUT$', 'UInt', 0xC0000000,
            'UInt', 3, 'Ptr', 0, 'UInt', 3, 'UInt', 0, 'Ptr', 0, 'Ptr')
        if output = -1 || !output
            return false
        info := Buffer(96, 0) ; CONSOLE_SCREEN_BUFFER_INFOEX
        NumPut('UInt', info.Size, info)
        if !DllCall('GetConsoleScreenBufferInfoEx', 'Ptr', output, 'Ptr', info)
            return false
        if index < 0
            index := (NumGet(info, 12, 'UShort') >> 4) & 15
        previous := NumGet(info, 32 + index * 4, 'UInt')
        if write {
            NumPut('UInt', color, info, 32 + index * 4)
            ; The getter returns inclusive window edges; the setter expects
            ; exclusive edges. Preserve console geometry when updating colors.
            NumPut('Short', NumGet(info, 18, 'Short') + 1, info, 18)
            NumPut('Short', NumGet(info, 20, 'Short') + 1, info, 20)
            if !DllCall('SetConsoleScreenBufferInfoEx', 'Ptr', output, 'Ptr', info)
                return false
        }
        return [index, previous]
    } finally {
        if output && output != -1
            DllCall('CloseHandle', 'Ptr', output)
        DllCall('FreeConsole')
    }
}

UpdateTerminalEffects() {
    global TerminalEffects, TerminalStateFile
    stale := []
    for hwnd, saved in TerminalEffects {
        try {
            if WinGetPID(hwnd) != Integer(saved[1])
                stale.Push(hwnd)
        } catch {
            stale.Push(hwnd)
        }
    }
    for hwnd in stale {
        TerminalEffects.Delete(hwnd)
        try IniDelete(TerminalStateFile, 'Windows', String(hwnd))
    }
    for hwnd in WinGetList('ahk_class ConsoleWindowClass') {
        try {
            name := StrLower(WinGetProcessName(hwnd))
            if name != 'cmd.exe' && name != 'powershell.exe' && name != 'pwsh.exe'
                continue
            pid := WinGetPID(hwnd)
            if TerminalEffects.Has(hwnd) {
                if Integer(TerminalEffects[hwnd][1]) = pid {
                    if TerminalEffects[hwnd].Length = 12
                        TerminalCaption(hwnd, 0)
                    continue
                }
                TerminalEffects.Delete(hwnd)
            }
            ; Save original layered attributes, including an existing color key.
            layered := !!(WinGetExStyle(hwnd) & 0x80000)
            colorKey := 0, alpha := 255, layerFlags := 2
            if layered
                DllCall('GetLayeredWindowAttributes', 'Ptr', hwnd, 'UInt*', &colorKey,
                    'UChar*', &alpha, 'UInt*', &layerFlags)
            original := Buffer(16, 0)
            data := Buffer(A_PtrSize * 3, 0)
            NumPut('Int', 19, data)
            NumPut('Ptr', original.Ptr, 'UPtr', original.Size, data, A_PtrSize)
            ; On Windows builds without the getter, restore the default accent.
            try DllCall('user32\GetWindowCompositionAttribute', 'Ptr', hwnd, 'Ptr', data)
            saved := [pid, Integer(layered), colorKey, alpha, layerFlags,
                NumGet(original, 0, 'UInt'), NumGet(original, 4, 'UInt'),
                NumGet(original, 8, 'UInt'), NumGet(original, 12, 'UInt')]
            palette := TerminalPalette(pid)
            if palette
                saved.Push(palette[1], palette[2])
            else
                saved.Push(16, 0) ; No palette was changed; index 16 is a sentinel.
            saved.Push(WinGetStyle(hwnd) & 0xC00000)
            serialized := ''
            for value in saved
                serialized .= (serialized = '' ? '' : ',') value
            IniWrite(serialized, TerminalStateFile, 'Windows', String(hwnd))
            TerminalEffects[hwnd] := saved
            ; Black is conhost's neutral/transparent backdrop. Replace only its
            ; current background palette slot, not the shell profile or registry.
            ; This removes PowerShell's blue paint; remember its exact RGB value.
            if palette
                TerminalPalette(pid, palette[1], 0, true)
            ; Keep glyphs opaque; let the compositor blur the background instead
            ; of fading the whole window. Unsupported builds get alpha only.
            WinSetTransparent(255, hwnd)
            ; Alpha zero disables acrylic on Windows 10. 1/255 black is the
            ; minimum activation alpha, not a visible colored background tint.
            if !TerminalAccent(hwnd, 4, 2, 0x01000000) {
                if !TerminalAccent(hwnd, 3, 2, 0)
                    WinSetTransparent(220, hwnd)
            }
            TerminalCaption(hwnd, 0)
        } catch {
            ; Protected/elevated/closing consoles may reject cross-process changes.
        }
    }
}

StopTerminalEffects(*) {
    global TerminalEffects, TerminalStateFile
    SetTimer(UpdateTerminalEffects, 0)
    for hwnd, saved in TerminalEffects {
        try {
            if WinGetPID(hwnd) != Integer(saved[1])
                continue
            TerminalAccent(hwnd, Integer(saved[6]), Integer(saved[7]),
                Integer(saved[8]), Integer(saved[9]))
            if saved.Length >= 11 && Integer(saved[10]) < 16
                TerminalPalette(Integer(saved[1]), Integer(saved[10]), Integer(saved[11]), true)
            if saved.Length = 12
                TerminalCaption(hwnd, Integer(saved[12]))
            if Integer(saved[2])
                DllCall('SetLayeredWindowAttributes', 'Ptr', hwnd,
                    'UInt', Integer(saved[3]), 'UChar', Integer(saved[4]), 'UInt', Integer(saved[5]))
            else
                WinSetTransparent('Off', hwnd)
        } catch {
        }
    }
    TerminalEffects.Clear()
    try FileDelete(TerminalStateFile)
}
