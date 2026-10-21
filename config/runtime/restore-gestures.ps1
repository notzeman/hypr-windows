$ErrorActionPreference = 'Stop'
# Restore only the five values changed by this setup, not unrelated touchpad options.
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad'
$original = @{
    ThreeFingerSlideEnabled = 1
    ThreeFingerLeft = 1
    ThreeFingerLeftKeyParams = 0
    ThreeFingerRight = 1
    ThreeFingerRightKeyParams = 0
}
foreach ($name in $original.Keys) {
    New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value $original[$name] -Force | Out-Null
}
Write-Output 'Original three-finger app-switching settings restored. Sign out/in yourself if Windows has not refreshed the gestures.'
