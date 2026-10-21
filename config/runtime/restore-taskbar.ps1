$ErrorActionPreference = 'Stop'
# Run after stopping hotkeys; otherwise its timer will hide the taskbar again.
if (-not ('OmarchyTaskbarRestore' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class OmarchyTaskbarRestore {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int L,T,R,B; }
    [StructLayout(LayoutKind.Sequential)] public struct Data {
        public uint Size; public IntPtr Hwnd; public uint Callback; public uint Edge;
        public Rect Rect; public IntPtr Param;
    }
    [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref Data data);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr param);
    public delegate bool EnumProc(IntPtr hwnd, IntPtr param);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, System.Text.StringBuilder text, int size);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
}
'@
}
$path = Join-Path $env:LOCALAPPDATA 'OmarchyWindows\taskbar-original-state.txt'
$state = if (Test-Path -LiteralPath $path) { [int](Get-Content $path -Raw).Trim() } else { 0 }
$data = New-Object OmarchyTaskbarRestore+Data
$data.Size = [Runtime.InteropServices.Marshal]::SizeOf($data)
$explorerBars = [System.Collections.Generic.List[IntPtr]]::new()
$null = [OmarchyTaskbarRestore]::EnumWindows({
    param($hwnd, $unused)
    $text = New-Object Text.StringBuilder 256
    $null = [OmarchyTaskbarRestore]::GetClassName($hwnd, $text, 256)
    if ($text.ToString() -in @('Shell_TrayWnd', 'Shell_SecondaryTrayWnd')) {
        [uint32]$ownerId = 0
        $null = [OmarchyTaskbarRestore]::GetWindowThreadProcessId($hwnd, [ref]$ownerId)
        $owner = Get-Process -Id $ownerId -ErrorAction SilentlyContinue
        if ($owner.ProcessName -eq 'explorer') { $explorerBars.Add($hwnd) }
    }
    return $true
}, [IntPtr]::Zero)
$data.Hwnd = [IntPtr]::Zero
foreach ($hwnd in $explorerBars) {
    $text = New-Object Text.StringBuilder 256
    $null = [OmarchyTaskbarRestore]::GetClassName($hwnd, $text, 256)
    if ($text.ToString() -eq 'Shell_TrayWnd') { $data.Hwnd = $hwnd; break }
}
$data.Param = [IntPtr]$state
if ($data.Hwnd -ne [IntPtr]::Zero) {
    $null = [OmarchyTaskbarRestore]::SHAppBarMessage(10, [ref]$data)
}
foreach ($hwnd in $explorerBars) {
    $null = [OmarchyTaskbarRestore]::ShowWindow($hwnd, 5)
}
