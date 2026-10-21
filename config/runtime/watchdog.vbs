' Launches the Omarchy Windows watchdog with no console window at all.
' wscript.exe is a GUI-subsystem host, so no console is ever created, and the
' PowerShell child is started with window style 0 (hidden). This replaces running
' powershell.exe directly from Task Scheduler, which could briefly flash a console
' and pull focus away from a fullscreen game.
Option Explicit
Dim shell, command
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & _
          shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\.config\omarchy-windows\start.ps1"" -Watchdog"
' 0 = hidden window, False = do not wait for completion.
shell.Run command, 0, False
