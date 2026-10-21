Option Explicit
Dim shell, root, script
Set shell = CreateObject("WScript.Shell")
root = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\HyprWindows"
script = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & root & "\switch.ps1"" resume"
shell.Run script, 0, True
