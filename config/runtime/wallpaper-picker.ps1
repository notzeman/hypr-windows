param([string]$Directory = "$env:USERPROFILE\Pictures\Wallpapers")
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class OmarchyWallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern bool SystemParametersInfo(uint action, uint param, string path, uint flags);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)]
    public static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
}
'@
$mutex = New-Object Threading.Mutex($false, 'Local\OmarchyWallpaperPicker')
$ownsMutex = $mutex.WaitOne(0)
if (-not $ownsMutex) {
    $hwnd = [OmarchyWallpaper]::FindWindow($null, 'Wallpaper Picker')
    if ($hwnd -ne [IntPtr]::Zero) {
        [OmarchyWallpaper]::ShowWindow($hwnd, 9) | Out-Null
        [OmarchyWallpaper]::SetForegroundWindow($hwnd) | Out-Null
    }
    $mutex.Dispose()
    exit
}
try {
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wallpaper Picker" Width="1020" Height="740"
        WindowStartupLocation="CenterScreen" Background="#1e1e2e"
        Foreground="#cdd6f4" FontFamily="Segoe UI" FontSize="14"
        MinWidth="520" MinHeight="360">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="Foreground" Value="#cdd6f4"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Surface" CornerRadius="7" Background="{TemplateBinding Background}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Surface" Property="Background" Value="#45475a"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Surface" Property="Background" Value="#585b70"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Margin="0,0,0,16">
      <TextBlock Text="Wallpapers" FontSize="26" FontWeight="SemiBold"/>
      <TextBlock x:Name="FolderPath" Foreground="#a6adc8" FontSize="12" Margin="0,4,0,0" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    <DockPanel Grid.Row="1" Margin="0,0,0,16">
      <Button x:Name="OpenFolder" DockPanel.Dock="Right" Content="Open folder" Margin="12,0,0,0"/>
      <TextBlock DockPanel.Dock="Left" Text="Search" VerticalAlignment="Center" Margin="0,0,12,0"/>
      <TextBox x:Name="Search" Background="#313244" Foreground="#cdd6f4" CaretBrush="White"
               BorderThickness="0" Padding="10,7"/>
    </DockPanel>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <WrapPanel x:Name="Tiles"/>
    </ScrollViewer>
    <TextBlock x:Name="Status" Grid.Row="3" Margin="0,14,0,0" Foreground="#a6adc8"
               Text="Loading thumbnails...  |  Click to apply  |  Esc to close" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.MaxWidth = [Windows.SystemParameters]::WorkArea.Width
    $window.MaxHeight = [Windows.SystemParameters]::WorkArea.Height
    $window.Width = [Math]::Min($window.Width, $window.MaxWidth - 40)
    $window.Height = [Math]::Min($window.Height, $window.MaxHeight - 40)
    $tiles = $window.FindName('Tiles')
    $search = $window.FindName('Search')
    $status = $window.FindName('Status')
    $window.FindName('FolderPath').Text = $Directory
    $window.FindName('OpenFolder').Add_Click({ Start-Process explorer.exe -ArgumentList ('"' + $Directory + '"') })
    $window.Add_PreviewKeyDown({
        if ($_.Key -eq [Windows.Input.Key]::Escape) { $window.Close(); $_.Handled = $true }
    })
    $script:items = New-Object 'System.Collections.Generic.List[object]'
    $script:loaded = 0
    $script:failed = 0
    $script:files = @()
    if (Test-Path -LiteralPath $Directory -PathType Container) {
        $script:files = @(Get-ChildItem -LiteralPath $Directory -File |
            Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|bmp|gif|tif|tiff)$' } |
            Sort-Object Name)
    }

    function Read-WallpaperBitmap($path, $width) {
        $bitmap = New-Object Windows.Media.Imaging.BitmapImage
        $stream = [IO.File]::OpenRead($path)
        try {
            $bitmap.BeginInit()
            $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            if ($width -gt 0) { $bitmap.DecodePixelWidth = $width }
            $bitmap.StreamSource = $stream
            $bitmap.EndInit()
            $bitmap.Freeze()
        } finally { $stream.Dispose() }
        return $bitmap
    }

    function Update-WallpaperFilter {
        $query = $search.Text.Trim()
        $visible = 0
        foreach ($item in $script:items) {
            $matches = $item.Tag.Name.IndexOf($query, [StringComparison]::OrdinalIgnoreCase) -ge 0
            $item.Visibility = if ($matches) { [Windows.Visibility]::Visible } else { [Windows.Visibility]::Collapsed }
            if ($matches) { $visible++ }
        }
        $suffix = if ($script:loaded -lt $script:files.Count) { 'Loading...' } else { 'Click to apply  |  Esc to close' }
        $status.Text = "$visible wallpapers  |  $suffix"
        if ($script:failed) { $status.Text += "  |  $($script:failed) unreadable images skipped" }
        if (-not $script:files.Count) { $status.Text = 'No supported images in this folder. Add JPG, PNG, BMP, GIF or TIFF files, then reopen.' }
    }

    function Set-ChosenWallpaper($file) {
        try {
            $path = $file.FullName
            if ($file.Extension -match '^\.(gif|tif|tiff)$') {
                # Windows does not animate GIF wallpaper; apply its first frame.
                $cache = Join-Path $env:LOCALAPPDATA 'OmarchyWindows\wallpapers'
                New-Item -ItemType Directory -Path $cache -Force | Out-Null
                $hash = [Security.Cryptography.SHA256]::Create()
                try {
                    $key = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($file.FullName + $file.LastWriteTimeUtc.Ticks))).Replace('-', '')
                } finally { $hash.Dispose() }
                $path = Join-Path $cache ($key + '.png')
                if (-not (Test-Path -LiteralPath $path)) {
                    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create((Read-WallpaperBitmap $file.FullName 0)))
                    $output = [IO.File]::Create($path)
                    try { $encoder.Save($output) } finally { $output.Dispose() }
                }
            }
            if (-not [OmarchyWallpaper]::SystemParametersInfo(0x14, 0, $path, 3)) {
                throw "Windows rejected the wallpaper (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
            }
            $window.Close()
        } catch {
            $status.Text = "Could not apply wallpaper: $($_.Exception.Message)"
        }
    }

    $search.Add_TextChanged({ Update-WallpaperFilter })
    # Load one thumbnail per dispatcher tick so opening/search/Escape stay responsive.
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(15)
    $timer.Add_Tick({
        if ($script:loaded -ge $script:files.Count) { $timer.Stop(); Update-WallpaperFilter; return }
        $file = $script:files[$script:loaded]
        $script:loaded++
        try {
            $image = New-Object Windows.Controls.Image
            $image.Source = Read-WallpaperBitmap $file.FullName 420
            $image.Width = 204; $image.Height = 112
            $image.Stretch = [Windows.Media.Stretch]::UniformToFill
            $label = New-Object Windows.Controls.TextBlock
            $label.Text = $file.BaseName; $label.Width = 204; $label.Margin = '0,7,0,0'
            $label.TextTrimming = [Windows.TextTrimming]::CharacterEllipsis
            $panel = New-Object Windows.Controls.StackPanel
            $panel.Children.Add($image) | Out-Null
            $panel.Children.Add($label) | Out-Null
            $button = New-Object Windows.Controls.Button
            $button.Content = $panel; $button.Margin = '0,0,12,12'; $button.Padding = '7'
            $button.Tag = $file; $button.ToolTip = $file.Name
            $button.Add_Click({ param($sender, $eventArgs) Set-ChosenWallpaper $sender.Tag })
            $tiles.Children.Add($button) | Out-Null
            $script:items.Add($button)
        } catch { $script:failed++ }
        Update-WallpaperFilter
    })
    $window.Add_ContentRendered({ $search.Focus() | Out-Null; $timer.Start() })
    $window.Add_Closed({ $timer.Stop() })
    $window.ShowDialog() | Out-Null
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
