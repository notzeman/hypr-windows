#requires -version 5.1
<#
Applies or restores the Bibata-Modern-Classic cursor set for the current user.

- No administrator rights: the cursor files live under %LOCALAPPDATA% and only
  HKCU\Control Panel\Cursors is changed (the normal per-user cursor scheme).
- A timestamped registry backup is written before any change.
- -Restore puts back the most recent backup and reloads the cursors.

Usage:
  & "$env:USERPROFILE\.config\omarchy-windows\bibata-cursor.ps1" -Source "<extracted Regular folder>"
  & "$env:USERPROFILE\.config\omarchy-windows\bibata-cursor.ps1" -Restore
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [string]$Source,
    [Parameter(ParameterSetName = 'Apply')]
    [string]$Destination = "$env:LOCALAPPDATA\Programs\Bibata-Modern-Classic",
    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$backupRoot = Join-Path $env:LOCALAPPDATA 'OmarchyWindows\backups'
$schemeName = 'Bibata-Modern-Classic-Regular Cursors'

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class OmarchyCursors {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo(uint action, uint param, IntPtr vparam, uint winini);
}
'@

function Invoke-ReloadCursors {
    # SPI_SETCURSORS = 0x0057; SPIF_UPDATEINIFILE|SPIF_SENDCHANGE = 0x03
    [void][OmarchyCursors]::SystemParametersInfo(0x0057, 0, [IntPtr]::Zero, 0x03)
}

if ($Restore) {
    # Prefer the canonical pre-change backup so repeated applies still restore Windows defaults.
    $original = Join-Path $backupRoot 'bibata-cursor-original'
    $target = if (Test-Path (Join-Path $original 'Cursors.reg')) {
        $original
    } else {
        Get-ChildItem $backupRoot -Directory -Filter 'bibata-cursor-*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
    }
    if (-not $target) { throw 'No bibata-cursor backup found; nothing to restore.' }
    reg.exe import "$target\Cursors.reg" | Out-Null
    reg.exe import "$target\Cursors-Schemes.reg" | Out-Null
    Invoke-ReloadCursors
    Write-Output "Restored cursor settings from $target"
    return
}

if (-not $Source) {
    if (Test-Path (Join-Path $Destination 'install.inf')) {
        $Source = $Destination
    } else {
        throw 'Provide -Source pointing at the extracted "Bibata-Modern-Classic-Regular-Windows" folder.'
    }
}

$map = [ordered]@{
    Arrow       = 'Pointer.cur'
    Help        = 'Help.cur'
    AppStarting = 'Work.ani'
    Wait        = 'Busy.ani'
    Crosshair   = 'Cross.cur'
    IBeam       = 'Text.cur'
    NWPen       = 'Handwriting.cur'
    No          = 'Unavailable.cur'
    SizeNS      = 'Vert.cur'
    SizeWE      = 'Horz.cur'
    SizeNWSE    = 'Dgn1.cur'
    SizeNESW    = 'Dgn2.cur'
    Grab        = 'Move.cur'
    SizeAll     = 'Move.cur'
    UpArrow     = 'Alternate.cur'
    Hand        = 'Link.cur'
    Pin         = 'Pin.cur'
    Person      = 'Person.cur'
    Pan         = 'Pan.cur'
    Grabbing    = 'Grabbing.cur'
    'Zoom-in'   = 'Zoom-in.cur'
    'Zoom-out'  = 'Zoom-out.cur'
}
# Windows' scheme ordering: Arrow,Help,AppStarting,Wait,Crosshair,IBeam,NWPen,No,
# SizeNS,SizeWE,SizeNWSE,SizeNESW,SizeAll,UpArrow,Hand,Pin,Person,Pan,Grabbing,Zoom-in,Zoom-out
$schemeOrder = 'Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No','SizeNS','SizeWE',
    'SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person','Pan','Grabbing','Zoom-in','Zoom-out'

if ($Source -ne $Destination) {
    New-Item -ItemType Directory -Force $Destination | Out-Null
    Copy-Item (Join-Path $Source '*') $Destination -Force
}

$missing = $map.Values | Where-Object { -not (Test-Path (Join-Path $Destination $_)) }
if ($missing) { throw "Missing cursor files in ${Destination}: $($missing -join ', ')" }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $backupRoot "bibata-cursor-$stamp"
New-Item -ItemType Directory -Force $backup | Out-Null
reg.exe export 'HKCU\Control Panel\Cursors' "$backup\Cursors.reg" /y | Out-Null
reg.exe export 'HKCU\Control Panel\Cursors\Schemes' "$backup\Cursors-Schemes.reg" /y | Out-Null

# Canonical pre-change snapshot for -Restore; created once.
$original = Join-Path $backupRoot 'bibata-cursor-original'
if (-not (Test-Path (Join-Path $original 'Cursors.reg'))) {
    New-Item -ItemType Directory -Force $original | Out-Null
    Copy-Item "$backup\Cursors.reg" $original -Force
    Copy-Item "$backup\Cursors-Schemes.reg" $original -Force
}

$key = 'HKCU:\Control Panel\Cursors'
foreach ($role in $map.Keys) {
    Set-ItemProperty -Path $key -Name $role -Value (Join-Path $Destination $map[$role]) -Type String
}
Set-ItemProperty -Path $key -Name 'crosshair' -Value (Join-Path $Destination 'Cross.cur') -Type String
Set-ItemProperty -Path $key -Name 'precisionhair' -Value (Join-Path $Destination 'Cross.cur') -Type String

$schemeValue = ($schemeOrder | ForEach-Object { Join-Path $Destination $map[$_] }) -join ','
if (-not (Test-Path "$key\Schemes")) { New-Item -Path "$key\Schemes" -Force | Out-Null }
Set-ItemProperty -Path "$key\Schemes" -Name $schemeName -Value $schemeValue -Type String
Set-ItemProperty -Path $key -Name '(Default)' -Value $schemeName -Type String

Invoke-ReloadCursors
Write-Output "Applied '$schemeName' from $Destination"
Write-Output "Backup: $backup"
