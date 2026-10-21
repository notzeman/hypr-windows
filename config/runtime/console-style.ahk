; Configure only the console belonging to the launched CMD, not every terminal.
ApplyConsoleStyle(pid) {
    if !DllCall('AttachConsole', 'UInt', pid)
        return false
    try {
        DllCall('SetConsoleCtrlHandler', 'Ptr', 0, 'Int', 1)
        output := DllCall('GetStdHandle', 'Int', -11, 'Ptr')
        info := Buffer(84, 0) ; CONSOLE_FONT_INFOEX, including WCHAR FaceName[32]
        NumPut('UInt', 84, info, 0)
        if !DllCall('GetCurrentConsoleFontEx', 'Ptr', output, 'Int', 0, 'Ptr', info)
            return false
        height := NumGet(info, 10, 'Short')
        NumPut('Short', 0, info, 8) ; Calculate cell width from the chosen font.
        NumPut('Short', Max(height, 16), info, 10)
        NumPut('UInt', 54, info, 12)
        NumPut('UInt', 400, info, 16)
        StrPut('JetBrainsMono NF', info.Ptr + 20, 32, 'UTF-16')
        applied := DllCall('SetCurrentConsoleFontEx', 'Ptr', output, 'Int', 0, 'Ptr', info)
        DllCall('SetConsoleCP', 'UInt', 65001)
        DllCall('SetConsoleOutputCP', 'UInt', 65001)
        return !!applied
    } finally DllCall('FreeConsole')
}
