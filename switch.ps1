[CmdletBinding()]
param([Parameter(Position=0)][ValidateSet('apply','remove','status','resume')][string]$Mode = 'status')
$ErrorActionPreference = 'Stop'
$store = "$env:LOCALAPPDATA\HyprWindows"
$runtime = "$env:USERPROFILE\.config\omarchy-windows"
$ahk = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
$manifest = "$store\baseline.json"
$enabled = "$store\enabled"
$utf8 = New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory $store -Force | Out-Null
$lock = New-Object Threading.Mutex($false, 'Local\HyprWindowsSwitch')
if (!$lock.WaitOne(0)) { throw 'Another mode switch is running.' }

function Write-Utf8($path, $text) { [IO.File]::WriteAllText($path, $text, $utf8) }
function Stop-OwnedAhk($script) {
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($script) } |
        ForEach-Object {
            # WM_CLOSE on AHK's hidden main window runs OnExit restoration.
            [SwitchNative]::CloseProcessWindows([uint32]$_.ProcessId)
            $p = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
            if ($p -and !$p.WaitForExit(5000)) { throw "Service $script did not exit; refusing unsafe removal." }
        }
}
function Run-Ahk($script) {
    $p = Start-Process $ahk -ArgumentList ('/ErrorStdOut "' + $script + '"') -PassThru -Wait -RedirectStandardOutput "$store\restore-output.log"
    if ($p.ExitCode -ne 0) { throw "Restoration failed. See $store\restore-output.log" }
}
function Register-SwitchTasks {
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\wscript.exe" -Argument ('"' + "$store\launch.vbs" + '"')
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
    # One repeating trigger, rather than two overlapping repeating schedules.
    Register-ScheduledTask -TaskName 'Hypr Windows Switch' -Action $action -Trigger $logon,$repeat -Settings $settings -Principal $principal -Force | Out-Null
}
function Remove-OldTasks {
    foreach ($name in 'Omarchy Windows Watchdog','Omarchy Windows Immediate Logon') {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
        }
    }
}
function Restore-Registry($entries) {
    foreach ($entry in $entries) {
        if ($entry.Exists) {
            if (!(Test-Path $entry.Path)) { New-Item $entry.Path -Force | Out-Null }
            New-ItemProperty $entry.Path -Name $entry.Name -Value $entry.Value -PropertyType $entry.Kind -Force | Out-Null
        } else {
            Remove-ItemProperty $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
        }
    }
}
function Save-Baseline($legacy) {
    $backup = "$store\backups\$(Get-Date -Format yyyyMMdd-HHmmss-fff)"
    New-Item -ItemType Directory "$backup\files" -Force | Out-Null
    # Full diagnostic exports stay local; restoration below touches named values only.
    & reg.exe export 'HKCU\Console' "$backup\console.reg" /y | Out-Null
    if (Test-Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad') { & reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad' "$backup\touchpad.reg" /y | Out-Null }
    $paths = @("$env:USERPROFILE\komorebi.json", "$env:USERPROFILE\applications.json", "$env:USERPROFILE\.config\yasb", $runtime)
    $files = @()
    for ($i=0; $i -lt $paths.Count; $i++) {
        $path = $paths[$i]
        $exists = Test-Path $path
        if ($exists) { Copy-Item -LiteralPath $path -Destination "$backup\files\$i" -Recurse }
        # This machine's original inventory proved these setup configs absent.
        $files += @{ Path=$path; Backup="$backup\files\$i"; Exists=($exists -and !$legacy) }
    }
    $spec = @{
        'HKCU:\Console' = @('FaceName','FontFamily','FontSize','FontWeight','CodePage','WindowAlpha')
        'HKCU:\Console\%SystemRoot%_system32_cmd.exe' = @('FaceName','FontFamily','FontSize','FontWeight','CodePage','WindowAlpha')
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad' = @('ThreeFingerSlideEnabled','ThreeFingerLeft','ThreeFingerLeftKeyParams','ThreeFingerRight','ThreeFingerRightKeyParams')
        'HKCU:\Software\clink' = @('InstalledScripts')
    }
    $registry = @()
    foreach ($path in $spec.Keys) {
        foreach ($name in $spec[$path]) {
            $key = Get-Item $path -ErrorAction SilentlyContinue
            $exists = $key -and ($key.GetValueNames() -contains $name)
            $entry = @{ Path=$path; Name=$name; Exists=[bool]$exists; Value=$null; Kind='String' }
            if ($exists) { $entry.Value=$key.GetValue($name); $entry.Kind=$key.GetValueKind($name).ToString() }
            if ($legacy -and $path -like '*PrecisionTouchPad') {
                $entry.Exists=$true; $entry.Kind='DWord'
                $entry.Value= if ($name -like '*KeyParams') { 0 } else { 1 }
            }
            if ($legacy -and $name -eq 'InstalledScripts') {
                $entry.Value=(($entry.Value -split ';') | Where-Object { $_ -and $_ -ne "$runtime\clink" }) -join ';'
                $entry.Exists=![string]::IsNullOrWhiteSpace($entry.Value)
            }
            if ($legacy -and $path -like 'HKCU:\Console*') {
                # Recover recorded pre-customization values, not guessed theme defaults.
                $regFile= if ($path -eq 'HKCU:\Console') { "$env:LOCALAPPDATA\OmarchyWindows\backups\revision-20261016-195243\console.reg" } else { "$env:LOCALAPPDATA\OmarchyWindows\backups\detailed-list-icons-20261017-053350\cmd-console-original.reg" }
                if (!(Test-Path $regFile)) { throw "Missing original console backup: $regFile" }
                $lines=Get-Content $regFile
                if ($path -eq 'HKCU:\Console') { $lines=(($lines -join "`n") -split '\n\[')[1] }
                $match=[regex]::Match(($lines -join "`n"), '(?m)^"'+[regex]::Escape($name)+'"=(.+)$')
                $entry.Exists=$match.Success
                if ($match.Success) {
                    $v=$match.Groups[1].Value.Trim()
                    if ($v.StartsWith('dword:')) { $entry.Kind='DWord'; $entry.Value=[Convert]::ToInt32($v.Substring(6),16) }
                    else { $entry.Kind='String'; $entry.Value=$v.Trim('"') }
                }
            }
            $registry += $entry
        }
    }
    $clink="$env:LOCALAPPDATA\clink\clink_settings"
    $clinkExisted=Test-Path $clink
    if ($clinkExisted) {
        Copy-Item $clink "$backup\clink_settings"
        if ($legacy) {
            Write-Utf8 "$backup\clink_settings" ((Get-Content $clink | Where-Object { $_ -notmatch '^clink\.logo\s*=' }) -join "`r`n")
        }
    }
    # SPI_GETACTIVEWINDOWTRACKING gives effective state, not a stale registry copy.
    $tracking=[SwitchNative]::Tracking()
    if ($legacy) { $tracking=$false }
    $state=@{ Files=$files; Registry=$registry; Backup=$backup; Tracking=$tracking; ClinkExisted=$clinkExisted; Legacy=$legacy }
    Write-Utf8 $manifest ($state | ConvertTo-Json -Depth 12)
}

Add-Type @'
using System; using System.Runtime.InteropServices;
public class SwitchNative {
 public delegate bool EnumProc(IntPtr h,IntPtr p);
 [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb,IntPtr p);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll", EntryPoint="SystemParametersInfoW")] static extern bool GetSpi(uint a,uint b,out int c,uint d);
 [DllImport("user32.dll", EntryPoint="SystemParametersInfoW")] static extern bool SetSpi(uint a,uint b,IntPtr c,uint d);
 public static void CloseProcessWindows(uint pid) { EnumWindows((h,p)=>{uint owner; GetWindowThreadProcessId(h,out owner); if(owner==pid) PostMessage(h,0x111,new IntPtr(65307),IntPtr.Zero); return true;},IntPtr.Zero); }
 public static bool Tracking() { int v; GetSpi(0x1000,0,out v,0); return v!=0; }
 public static void Tracking(bool v) { SetSpi(0x1001,0,v?new IntPtr(1):IntPtr.Zero,3); }
}
'@
try {
    if ($Mode -eq 'status') {
        [pscustomobject]@{ Mode=if(Test-Path $enabled){'hypr'}else{'windows'}; HotkeyPID=if(Test-Path "$env:LOCALAPPDATA\OmarchyWindows\hotkeys.pid"){Get-Content "$env:LOCALAPPDATA\OmarchyWindows\hotkeys.pid"}else{$null}; State=$store; BaselineSaved=(Test-Path $manifest) }
        return
    }
    if (!(Test-Path $ahk)) { throw "Install AutoHotkey v2 at $ahk first." }
    if ($Mode -eq 'resume') {
        if (Test-Path $enabled) { & "$runtime\start.ps1" -Watchdog }
        else {
            $retained=Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains("$store\retained.ahk") }
            if (!$retained) { Start-Process $ahk -ArgumentList ('"'+"$store\retained.ahk"+'"') }
        }
        return
    }
    if ($Mode -eq 'remove' -and (Test-Path "$store\windows-mode") -and !(Test-Path $enabled)) {
        Write-Output 'Already in Windows mode. No desktop or baseline files changed.'
        return
    }
    $source=$PSScriptRoot
    if ($source -eq $store) { $source=Get-Content "$store\repository.txt" -Raw }
    if (!(Test-Path "$source\config\runtime\hotkeys.ahk")) { throw 'Repository missing. Run switch.ps1 from your clone.' }
    # Validate dependencies before touching the current desktop.
    if ($Mode -eq 'apply') {
        foreach ($exe in 'C:\Program Files\komorebi\bin\komorebi.exe','C:\Program Files\YASB\yasb.exe',"$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe") {
            if (!(Test-Path $exe)) { throw "Missing required software: $exe. See README.md." }
        }
    }
    $legacy= !(Test-Path $manifest) -and [bool](Get-ScheduledTask -TaskName 'Omarchy Windows Immediate Logon' -ErrorAction SilentlyContinue)
    if (!(Test-Path $manifest) -or ($Mode -eq 'apply' -and (Test-Path "$store\windows-mode"))) { Save-Baseline $legacy }
    Remove-Item "$store\windows-mode" -ErrorAction SilentlyContinue
    # Archive the old task definitions for diagnosis; never export them to Git.
    foreach ($name in 'Omarchy Windows Watchdog','Omarchy Windows Immediate Logon') {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) { Write-Utf8 "$store\$name.xml" (Export-ScheduledTask -TaskName $name) }
    }
    Remove-OldTasks
    # OFF first: no watchdog can resurrect a half-removed desktop.
    Remove-Item $enabled -ErrorAction SilentlyContinue
    Stop-OwnedAhk "$runtime\hotkeys.ahk"
    Stop-OwnedAhk "$store\retained.ahk"
    foreach ($exe in 'C:\Program Files\komorebi\bin\komorebic.exe','C:\Program Files\YASB\yasbc.exe') {
        if (Test-Path $exe) { $p=Start-Process $exe -ArgumentList 'stop' -WindowStyle Hidden -PassThru -Wait; if($p.ExitCode -ne 0 -and $exe -like '*komorebic*' -and (Get-Process komorebi -ErrorAction SilentlyContinue)){ throw 'Komorebi did not stop safely.' } }
    }
    # Portable control files are independent of the removable desktop config.
    if ($PSScriptRoot -ne $store) { Copy-Item "$PSScriptRoot\switch.ps1" "$store\switch.ps1" -Force }
    Write-Utf8 "$store\repository.txt" $source
    Copy-Item "$source\scripts\*" $store -Force
    foreach ($name in 'mouse-drag.ahk','caption-buttons.ahk','taskbar.ahk','cursor.ahk','terminal-effects.ahk') { Copy-Item "$source\config\runtime\$name" $store -Force }
    Run-Ahk "$store\restore-windows.ahk"
    $state=Get-Content $manifest -Raw | ConvertFrom-Json
    if ($Mode -eq 'remove') {
        $archive="$store\removed\$(Get-Date -Format yyyyMMdd-HHmmss-fff)"
        New-Item -ItemType Directory $archive -Force | Out-Null
        for ($i=0; $i -lt $state.Files.Count; $i++) {
            $f=$state.Files[$i]
            if (Test-Path -LiteralPath $f.Path) { Move-Item -LiteralPath $f.Path -Destination "$archive\$i" }
            if ($f.Exists) { Copy-Item -LiteralPath $f.Backup -Destination $f.Path -Recurse }
        }
        Restore-Registry $state.Registry
        [SwitchNative]::Tracking([bool]$state.Tracking)
        $clink="$env:LOCALAPPDATA\clink\clink_settings"
        if ($state.ClinkExisted) { Copy-Item "$($state.Backup)\clink_settings" $clink -Force }
        elseif (Test-Path $clink) { Move-Item $clink "$archive\clink_settings" }
        Register-SwitchTasks
        Start-Process $ahk -ArgumentList ('"'+"$store\retained.ahk"+'"')
        Write-Utf8 "$store\windows-mode" 'restored'
        Write-Output 'Windows mode enabled. Desktop configs archived; Flow Win+Space and mouse customization retained. Open a NEW CMD to drop existing aliases.'
    } else {
        # Applying over an enabled mode reuses its original baseline.
        foreach ($pair in @(@('config\komorebi.json',"$env:USERPROFILE\komorebi.json"),@('config\applications.json',"$env:USERPROFILE\applications.json"))) { Copy-Item "$source\$($pair[0])" $pair[1] -Force }
        New-Item -ItemType Directory $runtime,"$env:USERPROFILE\.config\yasb" -Force | Out-Null
        Copy-Item "$source\config\runtime\*" $runtime -Recurse -Force
        foreach ($file in Get-ChildItem "$source\config\yasb" -File) {
            $text=[IO.File]::ReadAllText($file.FullName).Replace('@@LOCALAPPDATA@@',$env:LOCALAPPDATA).Replace('@@USERPROFILE@@',$env:USERPROFILE)
            Write-Utf8 "$env:USERPROFILE\.config\yasb\$($file.Name)" $text
        }
        $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
        if (!(Test-Path $key)) { New-Item $key -Force | Out-Null }
        foreach ($p in @{ ThreeFingerSlideEnabled=65535; ThreeFingerLeft=65535; ThreeFingerLeftKeyParams=7864337; ThreeFingerRight=65535; ThreeFingerRightKeyParams=7929873 }.GetEnumerator()) { New-ItemProperty $key -Name $p.Key -Value $p.Value -PropertyType DWord -Force | Out-Null }
        $key='HKCU:\Software\clink'; if (!(Test-Path $key)) { New-Item $key -Force | Out-Null }
        $paths=(Get-ItemProperty $key -ErrorAction SilentlyContinue).InstalledScripts
        $paths=@(($paths -split ';') | Where-Object { $_ -and $_ -ne "$runtime\clink" }) + "$runtime\clink"
        New-ItemProperty $key -Name InstalledScripts -Value ($paths -join ';') -PropertyType String -Force | Out-Null
        if (Test-Path 'C:\Program Files (x86)\clink\clink_x64.exe') { & 'C:\Program Files (x86)\clink\clink_x64.exe' set clink.logo none | Out-Null }
        $key='HKCU:\Console\%SystemRoot%_system32_cmd.exe'
        if (!(Test-Path $key)) { New-Item $key -Force | Out-Null }
        New-ItemProperty $key -Name FaceName -Value 'JetBrainsMono NF' -PropertyType String -Force | Out-Null
        foreach ($p in @{FontFamily=54; FontWeight=400; FontSize=0x00100000; CodePage=65001}.GetEnumerator()) { New-ItemProperty $key -Name $p.Key -Value $p.Value -PropertyType DWord -Force | Out-Null }
        [SwitchNative]::Tracking($true)
        Write-Utf8 $enabled 'enabled'
        Register-SwitchTasks
        & "$runtime\start.ps1"
        Start-Sleep -Seconds 2
        if (!(Get-Process komorebi -ErrorAction SilentlyContinue) -or !(Test-Path "$env:LOCALAPPDATA\OmarchyWindows\hotkeys.pid")) { throw 'Startup incomplete; use remove to recover and inspect startup.log.' }
        Write-Output 'Hypr Windows mode enabled. Use switch.ps1 remove to restore Windows.'
    }
} finally { $lock.ReleaseMutex(); $lock.Dispose() }
