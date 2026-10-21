# Hypr Windows

A reversible, per-user switch between an Omarchy/Hyprland-inspired Windows
desktop and normal Windows. **This is not Hyprland running on Windows.**
Komorebi handles tiling, YASB draws the bar, and AutoHotkey supplies shortcuts.
No Explorer patch, injected shell DLL, replacement shell, or Explorer transparency.

## Requirements

Windows 10/11 x64, Windows PowerShell 5.1, Task Scheduler and Windows Script Host
enabled. Tested on Windows 10 build 19044, one 1920×1080 display at 100% scaling.
Run the switch as your normal interactive user, **not Administrator**.

Install software from its official releases first; the switch does not download
or silently install software, request elevation, or bypass antivirus.

| Software | Tested version / expected location |
| --- | --- |
| [Komorebi](https://github.com/LGUG2Z/komorebi/releases) | 0.1.41; `C:\Program Files\komorebi\bin` |
| [YASB Reborn](https://github.com/amnweb/yasb/releases) | 2.0.7; `C:\Program Files\YASB` |
| [AutoHotkey v2](https://www.autohotkey.com/) | 2.0.30; `%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe` |
| [Flow Launcher](https://github.com/Flow-Launcher/Flow.Launcher/releases) | 2.1.4; `%LOCALAPPDATA%\FlowLauncher\Flow.Launcher.exe` |
| [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts/releases) | family **JetBrainsMono NF**; install per user for bar/terminal icons |
| [Clink](https://github.com/chrisant996/clink/releases) | existing 1.9.34; required for interactive CMD aliases; enable its normal CMD injection |
| [eza](https://github.com/eza-community/eza/releases) | 0.23.5; `%LOCALAPPDATA%\Programs\eza\eza.exe` |

Optional shortcut targets: Notepad++, Chromium and OBS Studio. Edit
`config/runtime/hotkeys.ahk` and `actions.ahk` to use your installed apps.
Review Komorebi's current license before use: personal use and commercial use have
different requirements. Each dependency retains its own license.

## Fresh Windows PC: install and set up

These instructions are for **Windows 10/11 x64 PC**.
Use **Windows PowerShell 5.1**, opened as your normal user. Installers for
machine-wide applications will request UAC approval; do not run the desktop
switch itself elevated. The scripts expect the standard locations in the table
above (`C:\Program Files` and your own `%LOCALAPPDATA%`), not arbitrary portable
or Scoop layouts. Usernames and repository locations can be different.

The commands below intentionally use the tested application versions. Newer
releases may change config schemas; review/test before upgrading them. If a
pinned version is no longer in WinGet, use its linked official GitHub release
installer, keeping the same installation location. **Do not downgrade an existing
newer install automatically.** Check it first and decide whether to use a separate
test PC. Installing dependencies does not automatically activate this desktop.

### 1. Get WinGet, Git and the repository

WinGet is supplied by Microsoft's [App Installer](https://aka.ms/getwinget).
Install/update App Installer if `winget --version` is not recognized. Then:

```powershell
winget --version
winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements
```

Open a **new** PowerShell window so Git's PATH change is picked up:

```powershell
git clone https://github.com/notzeman/hypr-windows.git
cd hypr-windows
```

### 2. Install the main programs

Run these one at a time. Keep the default installation locations. Review any
license prompts (especially Komorebi's personal/commercial-use terms).

```powershell
# Tiling manager: machine-wide MSI; approve its UAC prompt.
winget install --id LGUG2Z.komorebi --exact --version 0.1.41 --source winget --accept-source-agreements --accept-package-agreements

# Hotkey service: v2, x64, PER USER, at the location required by these scripts.
winget install --id AutoHotkey.AutoHotkey --exact --version 2.0.30 --architecture x64 --scope user --location "$env:LOCALAPPDATA\Programs\AutoHotkey" --source winget --accept-source-agreements --accept-package-agreements

# Launcher: per-user default location, not the portable build.
winget install --id Flow-Launcher.Flow-Launcher --exact --version 2.1.4 --scope user --source winget --accept-source-agreements --accept-package-agreements

# CMD line editor: default installer location is Program Files (x86)\clink.
winget install --id chrisant996.Clink --exact --version 1.9.34 --source winget --accept-source-agreements --accept-package-agreements
```

Install YASB from its official x64 MSI. This block verifies the release asset's
SHA-256 before asking Windows Installer to install it:

```powershell
$downloads = Join-Path $env:TEMP 'hypr-windows-setup'
New-Item -ItemType Directory $downloads -Force | Out-Null
$msi = Join-Path $downloads 'yasb-2.0.7-x64.msi'
Invoke-WebRequest -UseBasicParsing 'https://github.com/amnweb/yasb/releases/download/v2.0.7/yasb-2.0.7-x64.msi' -OutFile $msi
if ((Get-FileHash $msi -Algorithm SHA256).Hash -ne 'C93B3EB24FCEB64B8BAEFE694A947FECD31A7E58F0939BA61296048124EDBE8B') { throw 'YASB download hash mismatch; do not install.' }
$installer = Start-Process msiexec.exe -ArgumentList ('/i "' + $msi + '"') -Verb RunAs -PassThru -Wait
if ($installer.ExitCode -notin 0,3010) { throw "YASB installer failed: $($installer.ExitCode)" }
```

Keep YASB at `C:\Program Files\YASB`. Do **not** enable separate Komorebi,
YASB, whkd or Flow login entries: this repository manages startup. **whkd is not
required**; AutoHotkey is the only desktop hotkey daemon used here. If an installer
offers to launch the bar/manager immediately, leave that unchecked until Apply.

### 3. Install eza for CMD's `l` command

Run this per-user PowerShell block; it verifies the official release archive and
puts the executable exactly where the Clink alias expects it:

```powershell
$downloads = Join-Path $env:TEMP 'hypr-windows-setup'
New-Item -ItemType Directory $downloads -Force | Out-Null
$zip = Join-Path $downloads 'eza-0.23.5.zip'
Invoke-WebRequest -UseBasicParsing 'https://github.com/eza-community/eza/releases/download/v0.23.5/eza.exe_x86_64-pc-windows-gnu.zip' -OutFile $zip
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne 'C830638C844A5B89D39BA662B5549903A71FA539018E813880F5B8AFA77BAC2E') { throw 'eza download hash mismatch.' }
$destination = Join-Path $env:LOCALAPPDATA 'Programs\eza'
New-Item -ItemType Directory $destination -Force | Out-Null
Expand-Archive $zip -DestinationPath $destination -Force
& "$destination\eza.exe" --version
```

The archive is extracted only inside the dedicated eza directory. No global PATH
edit is needed: the alias uses the executable's full path.

### 4. Install JetBrainsMono Nerd Font (icons)

This installs only the regular face **per user**, without admin rights. It uses
Nerd Fonts v3.5.1, with its official release asset digest checked before extraction.
If you already have **JetBrainsMono NF** installed, skip this block.

```powershell
$downloads = Join-Path $env:TEMP 'hypr-windows-setup'
New-Item -ItemType Directory $downloads -Force | Out-Null
$zip = Join-Path $downloads 'JetBrainsMono-3.5.1.zip'
Invoke-WebRequest -UseBasicParsing 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip' -OutFile $zip
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne 'FAB782A66F7D3019DA64F6572DB9FC5D3A4BCB19F9FA13E2D8A62E3693D6396E') { throw 'Font download hash mismatch.' }
Expand-Archive $zip -DestinationPath "$downloads\JetBrainsMono" -Force
$font = Get-ChildItem "$downloads\JetBrainsMono" -Filter 'JetBrainsMonoNerdFont-Regular.ttf' -Recurse | Select-Object -First 1
if (!$font) { throw 'Regular Nerd Font face not found in archive.' }
$fontDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
New-Item -ItemType Directory $fontDirectory -Force | Out-Null
$fontPath = Join-Path $fontDirectory $font.Name
Copy-Item $font.FullName $fontPath -Force
$fontKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
if (!(Test-Path $fontKey)) { New-Item $fontKey -Force | Out-Null }
New-ItemProperty $fontKey -Name 'JetBrainsMono NF (TrueType)' -Value $fontPath -PropertyType String -Force | Out-Null
Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class HyprFontSetup { [DllImport("gdi32.dll", CharSet=CharSet.Unicode)] public static extern int AddFontResourceEx(string path, uint flags, System.IntPtr reserved); }'
if ([HyprFontSetup]::AddFontResourceEx($fontPath, 0, [IntPtr]::Zero) -eq 0) { Write-Warning 'Font registered; sign out/in yourself if it is not available yet.' }
```

Restart applications that were open during font installation. If glyphs still
appear as boxes, sign out/in yourself, then Apply. The classic Windows 10 console
still cannot render every supplementary-plane icon; this does not install or
switch you to Windows Terminal.

### 5. One-time application setup

Enable Clink in **your user's** CMD startup (omit `--allusers`). On a fresh PC:

```powershell
& 'C:\Program Files (x86)\clink\clink_x64.exe' autorun show
& 'C:\Program Files (x86)\clink\clink_x64.exe' autorun install
New-Item -ItemType Directory "$env:USERPROFILE\Pictures\Wallpapers" -Force | Out-Null
& "$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe"
```

If CMD already has a custom AutoRun command, review the displayed value first;
do not replace someone else's startup logic blindly. Clink is a separately
installed application: Remove restores this project's aliases/settings, not the
Clink installation/AutoRun you explicitly enabled here.

In Flow's Settings:

- Set its own activation hotkey to **Alt+Space** (the AHK mapping exposes Win+Space).
- Disable **Start Flow Launcher on system startup**; the mode service handles it.
- Disable launch/notification sound effects if you want the same silent setup.
- Leave your existing plugins, search data and other preferences unchanged.

Copy your own wallpapers into `Pictures\Wallpapers`. Wallpapers are not bundled.
Bibata is optional; see [Flow and mouse exceptions](#flow-and-mouse-exceptions).

Optional shortcuts can use these installations:

```powershell
winget install --id Notepad++.Notepad++ --exact --source winget
winget install --id OBSProject.OBSStudio --exact --source winget
```

Win+Shift+B/L currently targets Chromium's per-user installation. Install your
preferred browser separately and update those two bindings in
`config/runtime/hotkeys.ahk`; no particular Chromium distribution is required.
Without Notepad++, change the help/editor commands in `actions.ahk` and
`hotkeys.ahk` to `notepad.exe` or another editor before using those shortcuts.

### 6. Verify, Apply and switch back

Check the paths before changing your desktop:

```powershell
$required = @(
  'C:\Program Files\komorebi\bin\komorebi.exe',
  'C:\Program Files\komorebi\bin\komorebic-no-console.exe',
  'C:\Program Files\YASB\yasb.exe',
  "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
  "$env:LOCALAPPDATA\FlowLauncher\Flow.Launcher.exe",
  'C:\Program Files (x86)\clink\clink_x64.exe',
  "$env:LOCALAPPDATA\Programs\eza\eza.exe"
)
$missing = @($required | Where-Object { !(Test-Path -LiteralPath $_) })
if ($missing.Count) { throw ('Missing required files: ' + ($missing -join ', ')) }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests.ps1
.\switch.cmd apply
.\switch.cmd status
```

Try Win+Space, Win+Enter, workspace switching, and the Wi-Fi/tray menus. When you
want normal Windows again:

```powershell
.\switch.cmd remove
```

From **CMD**, run `switch apply`, `switch remove`, and `switch status` inside the
clone. Do **not** launch `switch.ps1` directly from CMD (it may open an Open With
dialog). No permanent execution-policy change or reboot is required. A full
`tests.ps1 -RoundTrip` test intentionally changes the desktop and ends in Hypr mode;
run it only when you're ready, not in the middle of a game or presentation.

### Flow and mouse exceptions

Set Flow's activation hotkey to **Alt+Space**; the retained AHK service maps
**Win+Space** to it and Escape dismisses it. Keep Flow's own automatic startup
disabled to avoid duplicate launchers. Existing Flow settings, plugins and data
are never copied into this repository or reset.

The existing Bibata-Modern-Classic cursor scheme is left alone in both modes.
For a new machine, optionally download [Bibata for Windows](https://github.com/ful1e5/Bibata_Cursor/releases)
and use `config/runtime/bibata-cursor.ps1 -Source <extracted-cursor-folder>`.
Cursor auto-hide is disabled. **Win+left-drag** is retained in normal mode too.
If you only want the cursor theme retained, remove that binding from
`scripts/retained.ahk` before the next switch.

## Commands

**From CMD**, inside this repository, use the included wrapper:

```bat
switch apply
switch remove
switch status
```

From PowerShell use `.\switch.cmd apply`, `.\switch.cmd remove`, or
`.\switch.cmd status`.
Do not execute `.ps1` directly in CMD: Windows may display an "Open with" dialog.

Clone and run from PowerShell:

```powershell
git clone https://github.com/notzeman/hypr-windows.git
cd hypr-windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\switch.ps1 apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\switch.ps1 remove
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\switch.ps1 status
```

`-ExecutionPolicy Bypass` applies to that process only; no permanent policy change.
From CMD, the same `powershell.exe ...` commands work. No reboot required.

After the first switch, these also work from **any directory**, even when the
desktop configs have been removed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\HyprWindows\switch.ps1" apply
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\HyprWindows\switch.ps1" remove
```

CMD uses `%LOCALAPPDATA%` in place of `$env:LOCALAPPDATA`.
Keep this clone available: Apply redeploys its tracked configs, not archived copies.
Edit the repository files, then run Apply to deploy changes.

## What each mode does

| Feature | Apply | Remove |
| --- | --- | --- |
| Komorebi tiling/borders | BSP, 10 workspaces, 8/4 px gaps, 2 px border | daemon stopped gracefully; hidden windows restored |
| YASB | 24-DIP Catppuccin acrylic bar, white text | stopped; desktop config archived |
| Native taskbar | hidden, event-driven re-hide | shown, original appbar flags restored |
| Caption buttons | native minimize/maximize/close hidden | original tracked style bits restored |
| Hover focus | Windows focus-follows-mouse enabled | prior Windows setting restored |
| Workspace/terminal/app shortcuts | active | removed; native Win+Tab/Win+numbers/etc. work again |
| Three-finger swipe | left=next, right=previous workspace | original five modified registry values restored |
| CMD | translucent launched consoles, Nerd Font/UTF-8, `l`, `clear`, `pwd` | registry defaults and Clink settings restored; setup script path removed |
| Flow and mouse | Win+Space, Escape, cursor theme, Win+drag | **retained intentionally** |

Some touchpad drivers cache settings until the next login; sign out yourself if
needed. Open a **new CMD** after Remove: an already-open shell keeps its aliases
in memory. Fonts and installed applications stay installed; Remove is a desktop
configuration switch, **not an application uninstaller**. Your wallpaper and
personal files are not deleted or changed by mode switching.

## Shortcuts in Hypr mode

| Shortcut | Action |
| --- | --- |
| Win+Space / Win+Enter | Flow / translucent CMD |
| Win+1…0 | workspace 1…10 |
| Win+Shift+1…0 | move window **and follow** |
| Win+arrows / Win+Shift+arrows | focus / move window |
| Win+Ctrl+arrows | resize |
| Win+Tab / Win+Shift+Tab | next / previous workspace |
| Win+W / Win+T / Win+F | close / float / monocle |
| Win+left-drag | native drag from content area |
| Win+Shift+F / Win+Shift+B | Explorer / Chromium |
| Win+Shift+R | YASB tray popup (Win+R remains native Run) |
| Ctrl+Win+Space | wallpaper picker, `Pictures\Wallpapers` |
| Win+K | complete shortcut reference |
| Ctrl+Alt+F6 | temporarily restore/hide native caption buttons |
| Ctrl+Alt+F7 | recover shortcut registration |
| Ctrl+Alt+F8 | temporarily restore taskbar |
| Ctrl+Alt+F11 | temporarily suspend shortcuts |
| Ctrl+Alt+F12 | **Remove mode**, including its persistent OFF flag |

The bar always shows 1–5; 6–10 appear while active or occupied. Caption changes
cannot hide every app's custom-drawn buttons; protected windows may reject style
changes. Classic Windows 10 CMD cannot render every newer Nerd Font glyph.

## Startup, backups and safe removal

`%LOCALAPPDATA%\HyprWindows` stores the mode flag, baseline manifest, control
scripts, archives and backups **outside the clone**. Do not delete this directory
while the mode is active: it contains restoration state.

One limited, interactive task, **Hypr Windows Switch**, runs at login and once a
minute. A `wscript.exe` GUI launcher starts PowerShell hidden; it does not launch a
visible terminal. The task reads the persistent mode flag before doing anything:

- ON: repair missing Komorebi, YASB and the desktop hotkey service.
- OFF: only ensure the small Flow/mouse-exception service is running.

Remove clears ON **before** stopping services, so the watchdog cannot undo it.
The two older Omarchy tasks are unregistered during migration. Normal-Windows mode
still needs this small task and AHK service for the exceptions you requested.

Before deploying, the switch copies existing config paths and saves the registry
values it will change. Remove archives deployed configs, restores pre-Apply files
if they existed, and restores only named registry values rather than overwriting
unrelated Windows settings. Repeated Remove is a no-op; repeated Apply preserves
the baseline. After switching back from Windows mode, a new baseline captures any
normal-Windows changes you made. Full diagnostic registry exports remain local.

For the original installed setup on this PC, migration uses its recorded
pre-customization console backups and known-original touchpad values, rather than
mistaking the already-customized desktop for normal Windows. No original config
existed at the migrated desktop paths. These private backups are **not** in Git.

If Apply fails, run Remove from this clone. Inspect
`%LOCALAPPDATA%\OmarchyWindows\startup.log` and
`%LOCALAPPDATA%\HyprWindows\restore-output.log`. Do not kill Explorer or reset your
whole registry. The existing emergency taskbar script is also shipped under
`config/runtime/restore-taskbar.ps1`.

To stop even the retained Flow/mouse service, first Remove, then disable
**Hypr Windows Switch** in Task Scheduler and exit `retained.ahk` via its tray
icon. That intentionally also disables Win+Space and Win+drag.

## Repository layout and tests

- `switch.ps1`: Apply / Remove / Status and scheduled-task resume.
- `config/komorebi.json`, `config/applications.json`: tiling and application rules.
- `config/yasb/`: bar YAML/CSS; user-path tokens rendered during deployment.
- `config/runtime/`: active AHK modules, menus, picker, CMD aliases and startup.
- `scripts/`: retained-mode service, restoration helper and invisible launcher.
- `tests.ps1`: syntax/deployment checks; optional round trip changes the desktop.

```powershell
.\tests.ps1                 # syntax and repository validation only
.\tests.ps1 -RoundTrip      # Remove -> check Windows -> Apply -> check Hypr
```

No logs, registry exports, histories, Wi-Fi credentials, Flow data, binary installers
or wallpapers are tracked. Additional monitors/scaling, physical touchpad refresh,
and exclusive-fullscreen games need your own interactive acceptance testing.
