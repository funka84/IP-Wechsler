# ============================================================
#  KONFIGURATION
# ============================================================
$script:DefaultPresets = @(
    @{ Name="Buero";    IP="192.168.0.250";   Mask="255.255.255.0"; GW="192.168.0.1";   DNS="192.168.0.1"   },
    @{ Name="Heimnetz"; IP="192.168.178.250"; Mask="255.255.255.0"; GW="192.168.178.1"; DNS="192.168.178.1" },
    @{ Name="Labor";    IP="10.0.0.250";      Mask="255.255.255.0"; GW="10.0.0.1";      DNS="10.0.0.1"      }
)

$script:ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath "presets.json"

function ConvertTo-PresetArray {
    param([object[]]$Items)
    $clean = @()
    foreach ($item in $Items) {
        if (-not $item) { continue }
        if (-not $item.Name -or -not $item.IP -or -not $item.Mask) { continue }
        $clean += @{
            Name = [string]$item.Name
            IP   = [string]$item.IP
            Mask = [string]$item.Mask
            GW   = [string]$item.GW
            DNS  = [string]$item.DNS
        }
    }
    return $clean
}

function Save-Presets {
    param([object[]]$Presets)
    $json = $Presets | ConvertTo-Json -Depth 3
    Set-Content -Path $script:ConfigPath -Value $json -Encoding UTF8
}

function Load-Presets {
    if (-not (Test-Path $script:ConfigPath)) {
        Save-Presets $script:DefaultPresets
        return $script:DefaultPresets
    }

    try {
        $raw = Get-Content -Path $script:ConfigPath -Raw -Encoding UTF8
        $fromFile = ConvertFrom-Json -InputObject $raw
        $list = @($fromFile)
        $presets = ConvertTo-PresetArray $list
        if ($presets.Count -eq 0) {
            Save-Presets $script:DefaultPresets
            return $script:DefaultPresets
        }
        return $presets
    } catch {
        Save-Presets $script:DefaultPresets
        return $script:DefaultPresets
    }
}

$script:Presets = Load-Presets
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:SelectedAdapter = $null

function New-Color { param($hex) [Windows.Media.SolidColorBrush][Windows.Media.ColorConverter]::ConvertFromString($hex) }

function Get-AdapterStatus {
    param($name)
    if (-not $name) { return @{ IP = "-"; DHCP = $false } }
    $cfg   = Get-NetIPConfiguration -InterfaceAlias $name -EA SilentlyContinue
    $iface = Get-NetIPInterface -InterfaceAlias $name -AddressFamily IPv4 -EA SilentlyContinue
    $ip    = if ($cfg -and $cfg.IPv4Address) { $cfg.IPv4Address.IPAddress } else { "nicht verbunden" }
    $dhcp  = ($iface -and $iface.Dhcp -eq "Enabled")
    return @{ IP = $ip; DHCP = $dhcp }
}

function Set-IP {
    param($adapter, $mode, $ip="", $mask="", $gw="", $dns="")
    if (-not $adapter) { return "ERR:Kein Adapter ausgewaehlt" }
    try {
        if ($mode -eq "dhcp") {
            netsh interface ip set address name="$adapter" source=dhcp 2>&1 | Out-Null
            netsh interface ip set dns    name="$adapter" source=dhcp 2>&1 | Out-Null
            return "OK:DHCP aktiviert auf '$adapter'"
        } else {
            if ($gw) {
                netsh interface ip set address name="$adapter" static "$ip" "$mask" "$gw" 1 2>&1 | Out-Null
            } else {
                netsh interface ip set address name="$adapter" static "$ip" "$mask" 2>&1 | Out-Null
            }
            if ($dns) { netsh interface ip set dns name="$adapter" static "$dns" 2>&1 | Out-Null }
            return "OK:IP $ip gesetzt auf '$adapter'"
        }
    } catch { return "ERR:$_" }
}

# ============================================================
# XAML - sorgfaeltig balanciert
# ============================================================
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="IP-Adresse Wechsler"
    Width="580" Height="870"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E2E"
    FontFamily="Segoe UI"
    ResizeMode="CanMinimize">

  <Window.Resources>

    <Style x:Key="SBtn" TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,10"/>
      <Setter Property="Margin" Value="0,3"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter
                  HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                  VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#313244"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#89B4FA"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#45475A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SBtnAdapter" TargetType="Button" BasedOn="{StaticResource SBtn}">
      <Setter Property="Background" Value="#2A2A3E"/>
      <Setter Property="BorderBrush" Value="#45475A"/>
      <Setter Property="Foreground" Value="#CDD6F4"/>
    </Style>

    <Style x:Key="SBtnPreset" TargetType="Button" BasedOn="{StaticResource SBtn}">
      <Setter Property="Background" Value="#2A2A3E"/>
      <Setter Property="BorderBrush" Value="#45475A"/>
      <Setter Property="Foreground" Value="#CDD6F4"/>
    </Style>

    <Style x:Key="SBtnPresetActive" TargetType="Button" BasedOn="{StaticResource SBtn}">
      <Setter Property="Background" Value="#1E3A2F"/>
      <Setter Property="BorderBrush" Value="#A6E3A1"/>
      <Setter Property="BorderThickness" Value="2"/>
      <Setter Property="Foreground" Value="#CDD6F4"/>
    </Style>

    <Style x:Key="SBtnAction" TargetType="Button" BasedOn="{StaticResource SBtn}">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="BorderBrush" Value="#585B70"/>
      <Setter Property="Foreground" Value="#CDD6F4"/>
    </Style>

    <Style x:Key="SBtnApply" TargetType="Button" BasedOn="{StaticResource SBtn}">
      <Setter Property="Background" Value="#1E3A5F"/>
      <Setter Property="BorderBrush" Value="#89B4FA"/>
      <Setter Property="Foreground" Value="#89B4FA"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="Padding" Value="20,10"/>
    </Style>

    <Style x:Key="STxBox" TargetType="TextBox">
      <Setter Property="Background" Value="#313244"/>
      <Setter Property="Foreground" Value="#CDD6F4"/>
      <Setter Property="BorderBrush" Value="#585B70"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="CaretBrush" Value="#CDD6F4"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border
                Background="{TemplateBinding Background}"
                BorderBrush="{TemplateBinding BorderBrush}"
                BorderThickness="{TemplateBinding BorderThickness}"
                CornerRadius="6">
              <ScrollViewer x:Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsFocused" Value="True">
                <Setter Property="BorderBrush" Value="#89B4FA"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>

  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,14">
      <TextBlock
          Text="IP-Adresse Wechsler"
          FontSize="22" FontWeight="Bold"
          Foreground="#89B4FA"
          HorizontalAlignment="Center"/>
      <TextBlock
          Text="Netzwerkkonfiguration schnell wechseln"
          FontSize="11" Foreground="#6C7086"
          HorizontalAlignment="Center" Margin="0,2,0,0"/>
    </StackPanel>

    <!-- Statusleiste -->
    <Border Grid.Row="1"
            Background="#2A2A3E" BorderBrush="#45475A"
            BorderThickness="1" CornerRadius="10"
            Padding="16,12" Margin="0,0,0,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock Text="ADAPTER" FontSize="9" Foreground="#6C7086" FontWeight="Bold"/>
          <TextBlock x:Name="TxAdapter" Text="-" FontSize="12" Foreground="#CDD6F4" Margin="0,2,0,0" TextWrapping="Wrap"/>
        </StackPanel>
        <StackPanel Grid.Column="1" HorizontalAlignment="Center">
          <TextBlock Text="IP-ADRESSE" FontSize="9" Foreground="#6C7086" FontWeight="Bold"/>
          <TextBlock x:Name="TxIP" Text="-" FontSize="13" Foreground="#A6E3A1" Margin="0,2,0,0" FontWeight="SemiBold"/>
        </StackPanel>
        <StackPanel Grid.Column="2" HorizontalAlignment="Right">
          <TextBlock Text="MODUS" FontSize="9" Foreground="#6C7086" FontWeight="Bold"/>
          <TextBlock x:Name="TxModus" Text="-" FontSize="13" Foreground="#FAB387" Margin="0,2,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Content -->
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
      <StackPanel>

        <!-- Panel: Adapter-Auswahl -->
        <StackPanel x:Name="PanelAdapter">
          <TextBlock
              Text="Netzwerkadapter wählen"
              FontSize="11" Foreground="#6C7086"
              FontWeight="SemiBold" Margin="2,0,0,8"/>
          <StackPanel x:Name="ListAdapter"/>
          <Button x:Name="BtnNetzwerk" Style="{StaticResource SBtnAction}" Margin="0,8,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock
                  Text="&#xE968;" FontFamily="Segoe MDL2 Assets"
                  FontSize="14" Foreground="#CBA6F7"
                  VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock Text="Netzwerkverbindungen öffnen" FontSize="13" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>
        </StackPanel>

        <!-- Panel: IP-Auswahl -->
        <StackPanel x:Name="PanelIP" Visibility="Collapsed">

          <!-- Titelzeile mit Zurück-Button -->
          <Grid Margin="0,0,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock
                Grid.Column="0"
                Text="Konfiguration wählen"
                FontSize="11" Foreground="#6C7086"
                FontWeight="SemiBold" VerticalAlignment="Center"/>
            <Button x:Name="BtnZurueck" Grid.Column="1"
                    Style="{StaticResource SBtnAction}" Padding="10,6" Margin="0">
              <StackPanel Orientation="Horizontal">
                <TextBlock
                    Text="&#xE72B;" FontFamily="Segoe MDL2 Assets"
                    FontSize="11" Foreground="#6C7086"
                    VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBlock Text="Zurück" FontSize="11" Foreground="#6C7086" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </Grid>

          <!-- DHCP Button -->
          <Button x:Name="BtnDHCP" Style="{StaticResource SBtnPreset}">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <Border Grid.Column="0"
                      Background="#1E3A5F" CornerRadius="6"
                      Width="36" Height="36" Margin="0,0,12,0">
                <TextBlock
                    Text="&#xEE77;" FontFamily="Segoe MDL2 Assets"
                    FontSize="16" Foreground="#89B4FA"
                    HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel Grid.Column="1" VerticalAlignment="Center">
                <TextBlock Text="DHCP" FontSize="14" FontWeight="SemiBold" Foreground="#CDD6F4"/>
                <TextBlock Text="Automatisch vom Router" FontSize="11" Foreground="#6C7086"/>
              </StackPanel>
              <Border x:Name="BadgeDHCP" Grid.Column="2"
                      Background="#1E3A2F" CornerRadius="4"
                      Padding="8,3" VerticalAlignment="Center"
                      Visibility="Collapsed">
                <TextBlock Text="AKTIV" FontSize="10" FontWeight="Bold" Foreground="#A6E3A1"/>
              </Border>
            </Grid>
          </Button>

          <!-- Preset-Liste (per Code befüllt) -->
          <StackPanel x:Name="ListPresets"/>

          <Grid Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="8"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="BtnPresetsBearbeiten" Grid.Column="0" Style="{StaticResource SBtnAction}" Margin="0">
              <StackPanel Orientation="Horizontal">
                <TextBlock
                    Text="&#xE8A5;" FontFamily="Segoe MDL2 Assets"
                    FontSize="14" Foreground="#CBA6F7"
                    VerticalAlignment="Center" Margin="0,0,10,0"/>
                <TextBlock Text="Presets bearbeiten" FontSize="13" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>

            <Button x:Name="BtnPresetsNeuLaden" Grid.Column="2" Style="{StaticResource SBtnAction}" Margin="0">
              <StackPanel Orientation="Horizontal">
                <TextBlock
                    Text="&#xE72C;" FontFamily="Segoe MDL2 Assets"
                    FontSize="14" Foreground="#CBA6F7"
                    VerticalAlignment="Center" Margin="0,0,10,0"/>
                <TextBlock Text="Presets neu laden" FontSize="13" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </Grid>

          <!-- Manuelle Eingabe Toggle -->
          <Button x:Name="BtnManuell" Style="{StaticResource SBtnAction}" Margin="0,8,0,0">
            <StackPanel Orientation="Horizontal">
              <TextBlock
                  Text="&#xE70F;" FontFamily="Segoe MDL2 Assets"
                  FontSize="14" Foreground="#CBA6F7"
                  VerticalAlignment="Center" Margin="0,0,10,0"/>
              <TextBlock Text="Manuelle Eingabe" FontSize="13" VerticalAlignment="Center"/>
            </StackPanel>
          </Button>

          <!-- Manuelle Eingabe Panel -->
          <Border x:Name="PanelManuell"
                  Visibility="Collapsed"
                  Background="#2A2A3E" BorderBrush="#45475A"
                  BorderThickness="1" CornerRadius="10"
                  Padding="16" Margin="0,6,0,0">
            <StackPanel>
              <TextBlock
                  Text="Manuelle Konfiguration"
                  FontSize="13" Foreground="#CDD6F4"
                  FontWeight="SemiBold" Margin="0,0,0,12"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="12"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="10"/>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Grid.Row="0" Grid.Column="0"
                           Text="IP-Adresse" FontSize="11"
                           Foreground="#6C7086" Margin="0,0,0,4"/>
                <TextBox x:Name="InIP" Grid.Row="1" Grid.Column="0"
                         Style="{StaticResource STxBox}"/>
                <TextBlock Grid.Row="0" Grid.Column="2"
                           Text="Subnetzmaske" FontSize="11"
                           Foreground="#6C7086" Margin="0,0,0,4"/>
                <TextBox x:Name="InMask" Grid.Row="1" Grid.Column="2"
                         Style="{StaticResource STxBox}" Text="255.255.255.0"/>
                <TextBlock Grid.Row="3" Grid.Column="0"
                           Text="Gateway  (optional)" FontSize="11"
                           Foreground="#6C7086" Margin="0,0,0,4"/>
                <TextBox x:Name="InGW" Grid.Row="4" Grid.Column="0"
                         Style="{StaticResource STxBox}"/>
                <TextBlock Grid.Row="3" Grid.Column="2"
                           Text="DNS-Server  (optional)" FontSize="11"
                           Foreground="#6C7086" Margin="0,0,0,4"/>
                <TextBox x:Name="InDNS" Grid.Row="4" Grid.Column="2"
                         Style="{StaticResource STxBox}"/>
              </Grid>
              <Button x:Name="BtnApply"
                      Style="{StaticResource SBtnApply}"
                      Content="Einstellungen übernehmen"
                      Margin="0,14,0,0"
                      HorizontalAlignment="Stretch"/>
            </StackPanel>
          </Border>

        </StackPanel>

      </StackPanel>
    </ScrollViewer>

    <!-- Meldungsleiste -->
    <Border x:Name="MsgBar" Grid.Row="3"
            CornerRadius="8" Padding="12,8"
            Margin="0,10,0,0" Visibility="Collapsed">
      <TextBlock x:Name="MsgTx" FontSize="12" HorizontalAlignment="Center"/>
    </Border>

  </Grid>
</Window>
"@

# ============================================================
# Fenster laden
# ============================================================
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$win    = [Windows.Markup.XamlReader]::Load($reader)

$TxAdapter    = $win.FindName("TxAdapter")
$TxIP         = $win.FindName("TxIP")
$TxModus      = $win.FindName("TxModus")
$ListAdapter  = $win.FindName("ListAdapter")
$ListPresets  = $win.FindName("ListPresets")
$PanelAdapter = $win.FindName("PanelAdapter")
$PanelIP      = $win.FindName("PanelIP")
$PanelManuell = $win.FindName("PanelManuell")
$BtnDHCP      = $win.FindName("BtnDHCP")
$BadgeDHCP    = $win.FindName("BadgeDHCP")
$BtnManuell   = $win.FindName("BtnManuell")
$BtnPresetsBearbeiten = $win.FindName("BtnPresetsBearbeiten")
$BtnPresetsNeuLaden   = $win.FindName("BtnPresetsNeuLaden")
$BtnZurueck   = $win.FindName("BtnZurueck")
$BtnNetzwerk  = $win.FindName("BtnNetzwerk")
$BtnApply     = $win.FindName("BtnApply")
$InIP         = $win.FindName("InIP")
$InMask       = $win.FindName("InMask")
$InGW         = $win.FindName("InGW")
$InDNS        = $win.FindName("InDNS")
$MsgBar       = $win.FindName("MsgBar")
$MsgTx        = $win.FindName("MsgTx")

# ============================================================
# UI-Funktionen
# ============================================================
function Show-Msg {
    param($text, $type = "ok")
    $MsgTx.Text = $text
    switch ($type) {
        "ok"  { $MsgBar.Background = New-Color "#1E3A2F"; $MsgBar.BorderBrush = New-Color "#A6E3A1"; $MsgTx.Foreground = New-Color "#A6E3A1" }
        "err" { $MsgBar.Background = New-Color "#3A1E1E"; $MsgBar.BorderBrush = New-Color "#F38BA8"; $MsgTx.Foreground = New-Color "#F38BA8" }
        "inf" { $MsgBar.Background = New-Color "#2A2A3E"; $MsgBar.BorderBrush = New-Color "#45475A"; $MsgTx.Foreground = New-Color "#FAB387" }
    }
    $MsgBar.BorderThickness = "1"
    $MsgBar.Visibility = "Visible"
}

function Refresh-StatusBar {
    if (-not $script:SelectedAdapter) { return }
    $s = Get-AdapterStatus $script:SelectedAdapter
    $TxAdapter.Text = $script:SelectedAdapter
    $TxIP.Text      = $s.IP
    $TxModus.Text   = if ($s.DHCP) { "DHCP" } else { "Statisch" }
}

function Build-AdapterButtons {
    $ListAdapter.Children.Clear()
    $adapters = Get-NetAdapter | Where-Object { $_.Status -ne "Not Present" } | Sort-Object Name

    foreach ($a in $adapters) {
        $s      = Get-AdapterStatus $a.Name
        $dot    = if ($a.Status -eq "Up") { "*" } else { "o" }
        $dotClr = if ($a.Status -eq "Up") { "#A6E3A1" } else { "#6C7086" }

        $btn = New-Object Windows.Controls.Button
        $btn.Style = $win.Resources["SBtnAdapter"]
        $btn.Tag   = $a.Name

        $sp = New-Object Windows.Controls.StackPanel
        $sp.Orientation = "Horizontal"

        $dotTx = New-Object Windows.Controls.TextBlock
        $dotTx.Text = $dot
        $dotTx.Foreground = New-Color $dotClr
        $dotTx.FontSize = 10
        $dotTx.VerticalAlignment = "Center"
        $dotTx.Margin = "0,0,10,0"

        $info = New-Object Windows.Controls.StackPanel

        $nTx = New-Object Windows.Controls.TextBlock
        $nTx.Text = $a.Name; $nTx.FontSize = 13; $nTx.FontWeight = "SemiBold"
        $nTx.Foreground = New-Color "#CDD6F4"

        $iTx = New-Object Windows.Controls.TextBlock
        $iTx.Text = $s.IP; $iTx.FontSize = 11
        $iTx.Foreground = New-Color "#6C7086"

        $info.Children.Add($nTx) | Out-Null
        $info.Children.Add($iTx) | Out-Null
        $sp.Children.Add($dotTx) | Out-Null
        $sp.Children.Add($info)  | Out-Null
        $btn.Content = $sp

        # Tag enthaelt den Adapter-Namen - kein Closure noetig
        $btn.Add_Click({
            param($sender, $e)
            $script:SelectedAdapter = $sender.Tag
            Refresh-StatusBar
            Build-PresetButtons
            $PanelAdapter.Visibility = "Collapsed"
            $PanelIP.Visibility      = "Visible"
            $MsgBar.Visibility       = "Collapsed"
        })

        $ListAdapter.Children.Add($btn) | Out-Null
    }
}

function Build-PresetButtons {
    $ListPresets.Children.Clear()
    if (-not $script:SelectedAdapter) { return }
    $s = Get-AdapterStatus $script:SelectedAdapter

    # DHCP-Badge aktualisieren
    if ($s.DHCP) {
        $BadgeDHCP.Visibility = "Visible"
        $BtnDHCP.Style = $win.Resources["SBtnPresetActive"]
    } else {
        $BadgeDHCP.Visibility = "Collapsed"
        $BtnDHCP.Style = $win.Resources["SBtnPreset"]
    }

    for ($i = 0; $i -lt $script:Presets.Count; $i++) {
        $p        = $script:Presets[$i]
        $isActive = ($s.IP -eq $p.IP -and -not $s.DHCP)
        $style    = if ($isActive) { "SBtnPresetActive" } else { "SBtnPreset" }

        $btn = New-Object Windows.Controls.Button
        $btn.Style = $win.Resources[$style]
        # Alle noetigen Daten direkt im Tag - kein Closure
        $btn.Tag = [PSCustomObject]@{ IP=$p.IP; Mask=$p.Mask; GW=$p.GW; DNS=$p.DNS; Name=$p.Name }

        $grid = New-Object Windows.Controls.Grid
        $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = "Auto"
        $c1 = New-Object Windows.Controls.ColumnDefinition; $c1.Width = "*"
        $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = "Auto"
        $grid.ColumnDefinitions.Add($c0) | Out-Null
        $grid.ColumnDefinitions.Add($c1) | Out-Null
        $grid.ColumnDefinitions.Add($c2) | Out-Null

        # Icon
        $iconBg = New-Object Windows.Controls.Border
        $iconBg.Background = New-Color "#1E2A1E"; $iconBg.CornerRadius = "6"
        $iconBg.Width = 36; $iconBg.Height = 36; $iconBg.Margin = "0,0,12,0"
        [Windows.Controls.Grid]::SetColumn($iconBg, 0)
        $ico = New-Object Windows.Controls.TextBlock
        $ico.Text = [char]0xE968; $ico.FontFamily = "Segoe MDL2 Assets"; $ico.FontSize = 16
        $ico.Foreground = New-Color "#A6E3A1"
        $ico.HorizontalAlignment = "Center"; $ico.VerticalAlignment = "Center"
        $iconBg.Child = $ico

        # Name + IP
        $info = New-Object Windows.Controls.StackPanel
        $info.VerticalAlignment = "Center"
        [Windows.Controls.Grid]::SetColumn($info, 1)
        $nTx = New-Object Windows.Controls.TextBlock
        $nTx.Text = $p.Name; $nTx.FontSize = 14; $nTx.FontWeight = "SemiBold"
        $nTx.Foreground = New-Color "#CDD6F4"
        $iTx = New-Object Windows.Controls.TextBlock
        $iTx.Text = $p.IP; $iTx.FontSize = 11; $iTx.Foreground = New-Color "#6C7086"
        $info.Children.Add($nTx) | Out-Null
        $info.Children.Add($iTx) | Out-Null

        # Aktiv-Badge
        $badge = New-Object Windows.Controls.Border
        $badge.Background = New-Color "#1E3A2F"; $badge.CornerRadius = "4"
        $badge.Padding = "8,3"; $badge.VerticalAlignment = "Center"
        $badge.Visibility = if ($isActive) { "Visible" } else { "Collapsed" }
        [Windows.Controls.Grid]::SetColumn($badge, 2)
        $badgeTx = New-Object Windows.Controls.TextBlock
        $badgeTx.Text = "AKTIV"; $badgeTx.FontSize = 10; $badgeTx.FontWeight = "Bold"
        $badgeTx.Foreground = New-Color "#A6E3A1"
        $badge.Child = $badgeTx

        $grid.Children.Add($iconBg) | Out-Null
        $grid.Children.Add($info)   | Out-Null
        $grid.Children.Add($badge)  | Out-Null
        $btn.Content = $grid

        # Click: Tag lesen - kein Closure, kein Scope-Problem
        $btn.Add_Click({
            param($sender, $e)
            $d = $sender.Tag
            $result = Set-IP $script:SelectedAdapter "static" $d.IP $d.Mask $d.GW $d.DNS
            if ($result.StartsWith("OK:")) { Show-Msg "[OK]  $($result.Substring(3))" "ok" }
            else                           { Show-Msg "[FEHLER]  $($result.Substring(4))" "err" }
            Refresh-StatusBar
            Build-PresetButtons
        })

        $ListPresets.Children.Add($btn) | Out-Null
    }
}

# ============================================================
# Event-Handler
# ============================================================
$BtnZurueck.Add_Click({
    $PanelIP.Visibility       = "Collapsed"
    $PanelAdapter.Visibility  = "Visible"
    $PanelManuell.Visibility  = "Collapsed"
    $MsgBar.Visibility        = "Collapsed"
    $script:SelectedAdapter   = $null
    Build-AdapterButtons
})

$BtnDHCP.Add_Click({
    if (-not $script:SelectedAdapter) { Show-Msg "[FEHLER]  Kein Adapter ausgewaehlt!" "err"; return }
    $result = Set-IP $script:SelectedAdapter "dhcp"
    if ($result.StartsWith("OK:")) { Show-Msg "[OK]  $($result.Substring(3))" "ok" }
    else                           { Show-Msg "[FEHLER]  $($result.Substring(4))" "err" }
    Refresh-StatusBar
    Build-PresetButtons
})

$BtnManuell.Add_Click({
    $PanelManuell.Visibility = if ($PanelManuell.Visibility -eq "Visible") { "Collapsed" } else { "Visible" }
})

$BtnApply.Add_Click({
    if (-not $script:SelectedAdapter) { Show-Msg "[FEHLER]  Kein Adapter ausgewaehlt!" "err"; return }
    $ip   = $InIP.Text.Trim()
    $mask = $InMask.Text.Trim()
    $gw   = $InGW.Text.Trim()
    $dns  = $InDNS.Text.Trim()
    if (-not $ip -or -not $mask) { Show-Msg "[FEHLER]  IP und Maske sind Pflichtfelder!" "err"; return }
    $result = Set-IP $script:SelectedAdapter "static" $ip $mask $gw $dns
    if ($result.StartsWith("OK:")) { Show-Msg "[OK]  $($result.Substring(3))" "ok" }
    else                           { Show-Msg "[FEHLER]  $($result.Substring(4))" "err" }
    Refresh-StatusBar
    Build-PresetButtons
})

$BtnPresetsBearbeiten.Add_Click({
    if (-not (Test-Path $script:ConfigPath)) { Save-Presets $script:Presets }
    Start-Process notepad.exe $script:ConfigPath
    Show-Msg "[INFO]  Presets in Notepad geoeffnet: $script:ConfigPath" "inf"
})

$BtnPresetsNeuLaden.Add_Click({
    $script:Presets = Load-Presets
    Build-PresetButtons
    Show-Msg "[OK]  Presets neu geladen" "ok"
})

$BtnNetzwerk.Add_Click({
    Start-Process explorer.exe "shell:::{7007ACC7-3202-11D1-AAD2-00805FC1270E}"
})

# ============================================================
# Start
# ============================================================
Build-AdapterButtons
$win.ShowDialog() | Out-Null
