[CmdletBinding()]
param(
    # Watchdog mode runs on a short repeating schedule. It only repairs what is
    # missing, stays quiet unless it acts, and never force-restarts Flow Launcher.
    [switch]$Watchdog
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path "$env:LOCALAPPDATA\HyprWindows\enabled")) { exit 0 }
$root = Join-Path $env:LOCALAPPDATA 'OmarchyWindows'
New-Item -ItemType Directory $root -Force | Out-Null
$log = "$root\startup.log"
$mutex = New-Object Threading.Mutex($false, 'Local\OmarchyWindowsStartup')
if (-not $mutex.WaitOne(0)) { exit 0 }
function Write-Log([string]$message) {
    Add-Content $log "$(Get-Date -Format o) $message"
}
try {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $started = [System.Collections.Generic.List[string]]::new()
    if (-not $Watchdog) { Write-Log 'Startup entered.' }

    $env:Path = 'C:\Program Files\komorebi\bin;C:\Program Files\YASB;' + $env:Path

    if (-not (Get-Process komorebi -ErrorAction SilentlyContinue)) {
        # Launch the daemon directly: do not wait for komorebic start's wrapper.
        Start-Process 'C:\Program Files\komorebi\bin\komorebi.exe' -ArgumentList ('--config "' + "$env:USERPROFILE\komorebi.json" + '"') -WindowStyle Hidden
        $started.Add('komorebi')
    }

    $ahkExe = "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
    $hotkeys = "$PSScriptRoot\hotkeys.ahk"
    $pidFile = "$root\hotkeys.pid"
    # Prefer the service's own PID marker: Get-Process by id is far cheaper than a
    # WMI Win32_Process query, which matters while a game is running.
    $ahkAlive = $false
    if (Test-Path -LiteralPath $pidFile) {
        $markedPid = 0
        $raw = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue)
        if ($raw -and [int]::TryParse($raw.Trim(), [ref]$markedPid) -and $markedPid -gt 0) {
            $proc = Get-Process -Id $markedPid -ErrorAction SilentlyContinue
            if ($proc -and $proc.ProcessName -eq 'AutoHotkey64') { $ahkAlive = $true }
        }
    }
    if (-not $ahkAlive) {
        $ahk = Start-Process $ahkExe -ArgumentList ('"' + $hotkeys + '"') -PassThru
        $started.Add("hotkeys.ahk(pid $($ahk.Id))")
    }

    if (-not (Get-Process yasb -ErrorAction SilentlyContinue)) {
        # Check immediately, then at 100 ms intervals. Avoid YASB's longer
        # reconnect backoff when the daemon is still creating its socket.
        $ready = $false
        for ($i = 0; $i -lt 20; $i++) {
            # Native stderr during cold start is expected, not a fatal error.
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $probe = Start-Process 'C:\Program Files\komorebi\bin\komorebic.exe' -ArgumentList 'state' -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput "$root\probe.txt" -RedirectStandardError "$root\probe-error.txt"
                $responding = $probe.ExitCode -eq 0
            } finally { $ErrorActionPreference = $savedPreference }
            if ($responding) { $ready = $true; break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $ready) {
            Write-Log 'WARNING: Komorebi not yet responsive; launching bar with automatic reconnect.'
        }
        Start-Process 'C:\Program Files\YASB\yasb.exe'
        $started.Add('yasb')
    }

    # The launcher stays resident; on a doing-nothing watchdog pass leave it alone.
    if (-not $Watchdog -and -not (Get-Process Flow.Launcher -ErrorAction SilentlyContinue)) {
        Start-Process "$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe"
        $started.Add('Flow.Launcher')
    }

    if ($started.Count -gt 0) {
        Write-Log "Started $($started -join ', ') in $($timer.ElapsedMilliseconds) ms."
    } elseif (-not $Watchdog) {
        Write-Log "All components already running; nothing to start ($($timer.ElapsedMilliseconds) ms)."
    }
    if (-not $Watchdog) { Write-Log 'Startup dispatched successfully.' }
} catch {
    Write-Log "ERROR: $_"
    if (-not $Watchdog) { throw }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
