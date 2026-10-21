; Included by hotkeys.ahk. Cursor auto-hide is disabled: the previous
; implementation keyed off idle *mouse* time only, so the pointer stayed blank
; while typing and needed a mouse move to come back. ShowCursorNow reloads the
; real scheme (Bibata) from the registry and is called once at startup in case a
; previous run left a blank cursor in place.

ShowCursorNow() {
    ; SPI_SETCURSORS reloads every system cursor from the current registry scheme.
    DllCall('user32\SystemParametersInfo', 'UInt', 0x0057, 'UInt', 0, 'Ptr', 0, 'UInt', 0x03)
}
