[CmdletBinding()]
param([switch]$RoundTrip)
$ErrorActionPreference='Stop'
function Assert($condition,$message) { if (!$condition) { throw "FAIL: $message" }; Write-Output "PASS: $message" }
$ahk="$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
foreach ($file in Get-ChildItem $PSScriptRoot -Filter '*.ps1' -Recurse) {
    $tokens=$null; $errors=$null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
    Assert (!$errors) "PowerShell syntax: $($file.Name)"
}
Get-Content "$PSScriptRoot\config\komorebi.json" -Raw | ConvertFrom-Json | Out-Null
Get-Content "$PSScriptRoot\config\applications.json" -Raw | ConvertFrom-Json | Out-Null
Assert $true 'JSON configs parse'
$temp=Join-Path $env:LOCALAPPDATA ('Temp\opencode\hypr-windows-tests-'+[guid]::NewGuid())
New-Item -ItemType Directory $temp -Force | Out-Null
Copy-Item "$PSScriptRoot\config\runtime\*.ahk","$PSScriptRoot\scripts\*.ahk" $temp
foreach ($entry in 'hotkeys.ahk','retained.ahk','restore-windows.ahk','cmd.ahk','actions.ahk') {
    $p=Start-Process $ahk -ArgumentList ('/ErrorStdOut /validate "'+"$temp\$entry"+'"') -Wait -PassThru
    Assert ($p.ExitCode -eq 0) "AHK validation: $entry"
}
Assert (!(Select-String "$PSScriptRoot\config\runtime\*.ahk","$PSScriptRoot\config\yasb\config.yaml" -Pattern 'C:\\Users\\Zaman' -Quiet)) 'Executable configs contain no hardcoded user path'
if (!$RoundTrip) { Write-Output 'Syntax checks complete; desktop unchanged.'; return }
Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class SwitchTest {
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] static extern int GetClassName(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 public static bool TaskbarVisible() { bool visible=false; EnumWindows((h,p)=>{var s=new StringBuilder(256);GetClassName(h,s,256);if(s.ToString()=="Shell_TrayWnd"){uint pid;GetWindowThreadProcessId(h,out pid);try{if(System.Diagnostics.Process.GetProcessById((int)pid).ProcessName=="explorer") visible=IsWindowVisible(h);}catch{}}return true;},IntPtr.Zero);return visible; }
}
'@
$touchpad='HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
$unrelated=(Get-ItemProperty $touchpad).TapAndDrag
& "$PSScriptRoot\switch.ps1" remove
Start-Sleep -Seconds 2
Assert (!(Get-Process komorebi,yasb -ErrorAction SilentlyContinue)) 'Tiling and bar stopped'
Assert ([SwitchTest]::TaskbarVisible()) 'Explorer taskbar visible'
Assert (!(Test-Path "$env:LOCALAPPDATA\HyprWindows\enabled")) 'Persistent mode OFF'
$savedState=Get-Content "$env:LOCALAPPDATA\HyprWindows\baseline.json" -Raw | ConvertFrom-Json
Assert ([SwitchNative]::Tracking() -eq [bool]$savedState.Tracking) 'Prior hover-focus setting restored'
Assert ((Get-ItemProperty $touchpad).TapAndDrag -eq $unrelated) 'Unrelated touchpad property preserved'
$baseline=Get-Content "$env:LOCALAPPDATA\HyprWindows\baseline.json" -Raw | ConvertFrom-Json
foreach ($v in $baseline.Registry) {
    $key=Get-Item $v.Path -ErrorAction SilentlyContinue
    $exists=$key -and ($key.GetValueNames() -contains $v.Name)
    Assert ([bool]$exists -eq [bool]$v.Exists) "Restored registry existence: $($v.Name)"
    if($v.Exists){Assert ($key.GetValue($v.Name) -eq $v.Value) "Restored registry value: $($v.Name)"}
}
$hash=(Get-FileHash "$env:LOCALAPPDATA\HyprWindows\baseline.json").Hash
& "$PSScriptRoot\switch.ps1" remove
Assert ((Get-FileHash "$env:LOCALAPPDATA\HyprWindows\baseline.json").Hash -eq $hash) 'Repeated Remove preserves baseline'
& "$PSScriptRoot\switch.ps1" resume
Assert (!(Get-Process komorebi,yasb -ErrorAction SilentlyContinue)) 'OFF-mode watchdog does not resurrect tiling/bar'
& "$PSScriptRoot\switch.ps1" apply
Start-Sleep -Seconds 2
Assert ([bool](Get-Process komorebi -ErrorAction SilentlyContinue)) 'Komorebi running'
Assert ([bool](Get-Process yasb -ErrorAction SilentlyContinue)) 'YASB running'
Assert ([SwitchNative]::Tracking()) 'Hover focus enabled'
Assert (![SwitchTest]::TaskbarVisible()) 'Explorer taskbar hidden'
Assert ((Get-ItemProperty $touchpad).TapAndDrag -eq $unrelated) 'Apply preserves unrelated touchpad property'
$marker=[int](Get-Content "$env:LOCALAPPDATA\OmarchyWindows\hotkeys.pid")
Assert ((Get-Process -Id $marker).ProcessName -eq 'AutoHotkey64') 'Desktop keybinding service alive'
Assert ([bool](Test-Path "$env:USERPROFILE\.config\omarchy-windows\clink\omarchy_eza.lua")) 'CMD aliases deployed'
Assert ((Get-ItemProperty 'HKCU:\Console\%SystemRoot%_system32_cmd.exe').FaceName -eq 'JetBrainsMono NF') 'CMD font applied'
Assert ((Get-ScheduledTask 'Hypr Windows Switch').Actions.Execute -like '*wscript.exe') 'Windowless scheduler launcher'
$hash=(Get-FileHash "$env:LOCALAPPDATA\HyprWindows\baseline.json").Hash
& "$PSScriptRoot\switch.ps1" apply
Assert ((Get-FileHash "$env:LOCALAPPDATA\HyprWindows\baseline.json").Hash -eq $hash) 'Repeated Apply preserves original baseline'
Write-Output 'Round trip passed; final mode is Hypr Windows.'
