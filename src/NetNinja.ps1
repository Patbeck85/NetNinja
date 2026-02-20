# ═══════════════════════════════════════════════════════════════════════
# NetNinja v4.9.0
# Network Latency Monitor & Optimizer — PowerShell 5.1+
# ═══════════════════════════════════════════════════════════════════════
#
# PROFILE SYSTEM
#   MMO           → Ragnarok, WoW, FFXIV, ESO, BDO, PoE, und mehr
#   Competitive   → CS2, Valorant, Apex, R6 Siege, Overwatch
#   Analysis      → Erweitertes Monitoring, alle Logs
#   Silent        → Hintergrundmodus, keine Benachrichtigungen
#
# AUTO-DETECT GAMES         103 Spiele (MMO, Competitive, Battle Royale, MOBA, Survival)
# NETWORK OPTIMIZATIONS     19 Basis + 10 Competitive-spezifische Tweaks
# OVERLAY MODE              Vollbild-taugliches Click-Through Overlay (Ctrl+Alt+O)
# GLOBAL HOTKEYS            Ctrl+Alt+P/R/M/S/O
# ADAPTIVE PING RATE        1s–5s automatisch je nach Verbindungsstabilität
# MTU OPTIMIZER             Automatische MTU-Ermittlung pro Profil
# A/B BENCHMARK             Vor/Nach-Vergleich mit Statistik
# SESSION HISTORY           Letzte 50 Sessions, Excel-Export
# AUTO-RECONNECT            Automatische Wiederverbindung bei Verbindungsabbruch
# DARK/LIGHT THEME          Systemweites Theme mit zentraler Farbpalette
#
# FUNKTIONEN (39)
#   UI-Helpers       Get-ThemeColors, New-StyledButton/Label/Form, Set-ButtonStyle
#   Helpers          Notify-User, Add-MenuItem, Write-Log
#   Konfiguration    Save-Config, Load-Config, Apply-Theme
#   Netzwerk         Apply-Optimizations, Apply-FPSOptimizations, Switch-Profile
#                    Set-DNS, Reset-NetworkAdapter, Get-GameServerIP
#   Monitoring       Show-StatsDashboard, Show-SessionHistory
#   Tools            Show-MTUOptimizer, Show-BenchmarkABGUI, Show-TracerouteGUI
#   HUD/Overlay      Show-HUD, Hide-HUD, Enable-Overlay, Disable-Overlay, Toggle-Overlay
#   System           Cleanup-AndExit, Backup-*/Restore-*, Optimize-RAM
# ═══════════════════════════════════════════════════════════════════════

#Requires -Version 5.1

# ==========================================
# AUTO-ELEVATE: Restart as Administrator
# ==========================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Get the real script path
    $scriptFile = $MyInvocation.MyCommand.Path
    if (-not $scriptFile) { $scriptFile = $PSCommandPath }
    if (-not $scriptFile) { $scriptFile = $PSScriptRoot + "\monitor.ps1" }

    try {
        # Relaunch as Administrator silently
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName        = "powershell.exe"
        $psi.Arguments       = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptFile`""
        $psi.Verb            = "runas"
        $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {
        # User clicked No on UAC prompt — show message
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            "NetNinja benötigt Administratorrechte!`n`nPlease run the script as administrator.",
            "Admin Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    exit
}

try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
} catch {
    Write-Host "ERROR: Failed to load .NET assemblies" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Win32 API for Global Hotkeys + Click-Through Overlay
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotkeyHelper : Form {
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const int MOD_CTRL  = 0x0002;
    public const int MOD_ALT   = 0x0001;
    public const int MOD_SHIFT = 0x0004;
    public const int VK_P = 0x50;
    public const int VK_R = 0x52;
    public const int VK_M = 0x4D;
    public const int VK_S = 0x53;
    public const int VK_O = 0x4F;  // Ctrl+Alt+O → Toggle Overlay
    public const int WM_HOTKEY = 0x0312;
}
"@ -ErrorAction Stop
} catch {}

# Win32: SetWindowLong für Click-Through Overlay
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class OverlayHelper {
    public const int GWL_EXSTYLE       = -20;
    public const int WS_EX_LAYERED     = 0x00080000;
    public const int WS_EX_TRANSPARENT = 0x00000020;
    public const int WS_EX_TOPMOST     = 0x00000008;
    public const int WS_EX_TOOLWINDOW  = 0x00000080;
    public const int LWA_COLORKEY      = 0x00000001;
    public const int LWA_ALPHA         = 0x00000002;
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint crKey, byte bAlpha, uint dwFlags);
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public const uint SWP_NOMOVE    = 0x0002;
    public const uint SWP_NOSIZE    = 0x0001;
    public const uint SWP_NOACTIVATE = 0x0010;
}
"@ -ErrorAction Stop
} catch {}

$script:scriptPath = $PSScriptRoot
if (!$script:scriptPath) { $script:scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (!$script:scriptPath) { $script:scriptPath = Get-Location }
Set-Location -Path $script:scriptPath

$configFile = Join-Path $script:scriptPath "optimizations.cfg"
$configFile             = Join-Path $script:scriptPath "netninja_config.json"
$mtuConfigFile = Join-Path $script:scriptPath "mtu.cfg"
$logFile = Join-Path $script:scriptPath "netninja.log"
$registryBackupFile = Join-Path $script:scriptPath "registry_backup.reg"
$networkBackupFile = Join-Path $script:scriptPath "network_backup.json"

$CONFIG = @{
    ServerAddress     = "138.201.124.56" 
    ServerPort        = 5121
    ProcessName       = "Ragnarokplus"
    PingIntervalMin   = 1000    # 1s  — fastest (unstable/spike)
    PingIntervalMax   = 5000    # 5s  — slowest (very stable, DDoS-safe)
    PingIntervalAlert = 1200    # ms  — alert threshold
    SpikeThreshold    = 150     # ms  — spike detection
    AlertHighPing     = 200     # ms  — "High Ping" balloon notification
    AlertCriticalPing = 300     # ms  — "Critical" balloon + triple beep
    Version           = "5.0.0"

    # Adaptive Rate Settings
    AdaptiveRate          = $true   # Feature ON/OFF
    AdaptiveStableWindow  = 30      # Pings needed to consider stable
    AdaptiveStableJitter  = 15      # Max jitter (ms) to be "stable"
    AdaptiveStableMaxPing = 100     # Max avg ping (ms) to be "stable"
    AdaptiveStepUp        = 500     # ms to increase interval when stable
    AdaptiveStepDown      = 1000    # ms to decrease interval when unstable
}

$Global:OptimizationConfig = @{
    # ── Immer sicher (Grün) ─────────────────────────
    NetworkThrottling    = $true
    SystemResponsiveness = $true
    NetworkOptimizations = $true
    DisableNagleIface    = $true
    TcpTimedWaitDelay    = $true
    DNSCache             = $true
    NetworkPowerSaving   = $true
    HighPerfPowerPlan    = $true
    DisableNetBIOS       = $true
    DisableIPv6          = $false
    PagingExecutive      = $true
    TimerResolutionMMO   = $true
    GameMode             = $true
    MMCSS                = $true
    CoreParkingFix       = $true
    KeyboardResponse     = $true
    DeliveryOptimization = $true
    WindowsDefenderExcl  = $false
    # ── System-abhängig (Orange) ────────────────────
    SysMainOptimization  = $false
    HAGS                 = $false
    QoSMMO               = $false
    NetworkBuffersMMO    = $false
    FlowControl          = $false
    LargePacketOffload   = $false
    RSSQueuesMMO         = $false
    InterruptAffinityMMO = $false
    AutoTuningMMO        = $false
    DNSOverHTTPS         = $false
    # ── Competitive-spezifisch ──────────────────────
    InterruptModeration  = $false
    AutoTuningLevel      = $false
    NetworkBuffers       = $false
    ReceiveSideScaling   = $false
    CongestionProvider   = $false
    TimerResolution      = $false
    TCPAckFreqComp       = $false    # NEU: ACK Frequency
    NetworkBuffersComp   = $false    # NEU: NIC Buffer 64 (Competitive)
    CPUPriorityBoost     = $false    # NEU: CPU Priority Boost
    PowerSchemeUltimate  = $false    # NEU: Ultimate Performance
}

if (Test-Path $configFile) {
    try { 
        $saved = Get-Content $configFile -Raw | ConvertFrom-Json
        foreach ($prop in $saved.PSObject.Properties) { 
            if ($Global:OptimizationConfig.ContainsKey($prop.Name)) { 
                $Global:OptimizationConfig[$prop.Name] = $prop.Value 
            } 
        }
    } catch { $null = $_ }
}

$script:WinVersion = [System.Environment]::OSVersion.Version
$script:isWin10Plus = $script:WinVersion.Major -ge 10
$script:isWin10Build19041Plus = ($script:WinVersion.Major -eq 10 -and $script:WinVersion.Build -ge 19041)

$sig = '[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);'
if (-not ([System.Management.Automation.PSTypeName]'Win32.IconHelper').Type) {
    Add-Type -MemberDefinition $sig -Name "IconHelper" -Namespace "Win32"
}

$script:DeepGreen  = [System.Drawing.Color]::FromArgb(20, 90, 50)
$script:DeepOrange = [System.Drawing.Color]::FromArgb(120, 50, 0)
$script:DeepRed    = [System.Drawing.Color]::FromArgb(100, 10, 10)
$script:DarkGray   = [System.Drawing.Color]::FromArgb(60, 60, 60)

$script:TargetIP         = $CONFIG.ServerAddress
$script:activeServerPort = $CONFIG.ServerPort   # v5.0: Failover-sicherer aktiver Port
$script:IsIPDetected = $false
$script:AudioAlertEnabled = $false
$script:Last60sSpike = 0
$script:SpikeTimer = [System.Diagnostics.Stopwatch]::StartNew()
$script:totalPings = 0
$script:lostPings = 0
$script:lastLogRotationCheck = 0   # Write-Log Rotation-Throttle
$script:minLat = 999
$script:maxLat = 0
$script:lastIconText = ""
$script:lastColor = $null
$script:iconCache = @{}
$script:currentLatency = 0
$script:lossAlertShown = $false
$script:monitorEnabled = $true

# Extended Statistics
$script:sessionStartTime = Get-Date
$script:totalSpikes = 0
$script:worstSpikeTime = $null
$script:worstSpikeValue = 0
$script:avgLatency = 0
$script:lastNotificationTime = [DateTime]::MinValue
$script:notificationCooldown = 60  # Seconds between notifications

# Session History
$script:sessionHistoryFile = Join-Path $script:scriptPath "session_history.json"
$script:sessionHistory = @()
$script:maxHistorySessions = 50  # Keep last 50 sessions

# Config Profiles System
$script:currentProfile = "MMO"  # Default profile

# ── AUTOMATISCHE PROFIL-ERKENNUNG — Prozess → Profil-Map ────────
$script:gameProfileMap = @{
    # MMO / MMORPG → MMO-Profil
    "Ragnarokplus"      = "MMO"; "Ragnarok"         = "MMO"
    "RagnarokOnline"    = "MMO"; "Wow"              = "MMO"
    "WowClassic"        = "MMO"; "Wow-64"           = "MMO"
    "ffxiv_dx11"        = "MMO"; "ffxiv"            = "MMO"
    "eso64"             = "MMO"; "eso"              = "MMO"
    "GuildWars2"        = "MMO"; "Gw2-64"           = "MMO"
    "LostArk"           = "MMO"; "BlackDesertOnline"= "MMO"
    "rs2client"         = "MMO"; "osclient"         = "MMO"
    "pso2_bin"          = "MMO"; "NewWorld"         = "MMO"
    "THRONE"            = "MMO"; "AlbionOnline"     = "MMO"
    "PathOfExile"       = "MMO"; "PathOfExile_x64"  = "MMO"
    "PathOfExile2"      = "MMO"; "MapleStory"       = "MMO"
    # FPS / Battle Royale / Competitive → FPS-Profil
    "cs2"               = "FPS"; "csgo"             = "FPS"
    "valorant"          = "FPS"; "VALORANT-Win64-Shipping" = "FPS"
    "TslGame"           = "FPS"; "FortniteClient-Win64-Shipping" = "FPS"
    "r5apex"            = "FPS"; "RainbowSix"       = "FPS"
    "RainbowSix_BE"     = "FPS"; "Overwatch"        = "FPS"
    "Overwatch2"        = "FPS"; "destiny2"         = "FPS"
    "dota2"             = "FPS"; "NarakaBladePoint" = "FPS"
    # MOBA → FPS-Profil (niedrige Latenz wichtig)
    "LeagueofLegends"   = "FPS"; "smite"            = "FPS"
    # Survival / Co-op → MMO-Profil
    "RustClient"        = "MMO"; "ShooterGame"      = "MMO"
    "EscapeFromTarkov"  = "MMO"
}
$script:lastAutoProfile = ""   # Verhindert Loop bei manueller Änderung
$script:autoProfileEnabled = $true
$script:profiles = @{
    MMO = @{
        Name          = "MMO Gaming"
        AudioAlerts   = $true
        MonitorVisible = $true
        GraphTimeframe = "60s"
        OptimalMTU    = 1400          # Stable MTU for MMO/MMORPG servers
        AutoMTU       = $false        # MTU scan on profile switch
    }
    FPS = @{
        Name          = "Competitive"
        AudioAlerts   = $false
        MonitorVisible = $true
        GraphTimeframe = "60s"
        OptimalMTU    = 1350          # Lower MTU = less fragmentation in FPS
        AutoMTU       = $true         # Run MTU scan automatically when switching
    }
    Analysis = @{
        Name          = "Analysis Mode"
        AudioAlerts   = $false
        MonitorVisible = $true
        GraphTimeframe = "1h"
        OptimalMTU    = 1480          # Max practical MTU for analysis
        AutoMTU       = $false
    }
    Silent = @{
        Name          = "Silent Background"
        AudioAlerts   = $false
        MonitorVisible = $false
        GraphTimeframe = "5min"
        OptimalMTU    = 1400
        AutoMTU       = $false
    }
}

# ══ v5.0: MULTI-TARGET PING ══════════════════════════════
$script:multiTargets = [System.Collections.Generic.List[hashtable]]::new()
# Jeder Eintrag: @{ Host; Port; Label; Color; Enabled; History(List[int]); LossHistory(List[bool]); LastPing; LastMs }
$script:multiPingEnabled = $false   # false = klassisch, true = Multi-Target
$script:multiPingJobs    = @()      # Runspace-Jobs

function Add-PingTarget {
    # FIX: renamed $Host → $TargetHost (avoids conflict with PS builtin $Host variable)
    param([string]$TargetHost, [int]$Port = 80, [string]$Label = "",
          [System.Drawing.Color]$Color = [System.Drawing.Color]::Cyan)
    if (-not $TargetHost.Trim()) { return }   # Guard: leere Hosts ablehnen
    $script:multiTargets.Add(@{
        Host        = $TargetHost.Trim()
        Port        = $Port
        Label       = if ($Label.Trim()) { $Label.Trim() } else { $TargetHost.Trim() }
        Color       = $Color
        Enabled     = $true
        History     = [System.Collections.Generic.List[int]]::new()
        LossHistory = [System.Collections.Generic.List[bool]]::new()
        AvgMs       = 0       # Laufender Durchschnitt (neu)
        LastMs      = -1
        PenCache    = New-Object System.Drawing.Pen($Color, 1.5)
    })
}

function Invoke-MultiPing {
    # Alle aktivierten Ziele via ThreadPool asynchron pingen (PS 5.1-kompatibel)
    $jobs = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($t in $script:multiTargets) {
        if (-not $t.Enabled) { continue }
        # FIX: Werte in lokale Variablen kopieren BEVOR Closure erstellt wird
        # PowerShell-Closures capture by reference → explizit kopieren
        $capturedHost = $t.Host
        $capturedPort = $t.Port
        $capturedTarget = $t

        # FIX: [System.Threading.Tasks.Task]::Run (ohne Generics) für PS 5.1
        $job = [System.Threading.Tasks.Task]::Run([System.Action]{
            $tcp = $null
            try {
                $sw = [System.Diagnostics.Stopwatch]::StartNew()
                $tcp = New-Object System.Net.Sockets.TcpClient
                $tcp.SendTimeout = 1000; $tcp.ReceiveTimeout = 1000
                $ar = $tcp.BeginConnect($capturedHost, $capturedPort, $null, $null)
                if ($ar.AsyncWaitHandle.WaitOne(1000, $false)) {
                    try { $tcp.EndConnect($ar) } catch { $null = $_ }
                    $sw.Stop()
                    $capturedTarget.LastMs = [int]$sw.ElapsedMilliseconds
                } else {
                    $capturedTarget.LastMs = -1
                }
            } catch {
                $capturedTarget.LastMs = -1
            } finally {
                # FIX: TcpClient immer disposed — auch bei Timeout
                if ($tcp) { try { $tcp.Close(); $tcp.Dispose() } catch { $null = $_ } }
            }
        })
        $jobs.Add(@{ Job = $job; Target = $capturedTarget })
    }

    # Warten mit individuellem 1,5s Timeout pro Job
    foreach ($j in $jobs) {
        try {
            $null = $j.Job.Wait(1500)
        } catch { $null = $_ }

        # History aktualisieren (im Haupt-Thread, thread-safe via List)
        $t   = $j.Target
        $ms  = $t.LastMs
        $hit = $ms -ge 0

        $t.LossHistory.Add(-not $hit)
        if ($t.LossHistory.Count -gt 60) { $t.LossHistory.RemoveAt(0) }

        if ($hit) {
            $t.History.Add($ms)
            if ($t.History.Count -gt 60) { $t.History.RemoveAt(0) }
            # Laufenden Avg aktualisieren
            if ($t.History.Count -gt 0) {
                $t.AvgMs = [int](($t.History | Measure-Object -Sum).Sum / $t.History.Count)
            }
        }
    }
}


# ══ v5.0: REGELN-ENGINE ═══════════════════════════════════
$script:pingRules = [System.Collections.Generic.List[hashtable]]::new()
$script:ruleFireLog = [System.Collections.Generic.List[string]]::new()

function Add-PingRule {
    param($Name, $Condition, $Action, [int]$Cooldown = 60)
    if (-not $Name.Trim()) { return }   # Guard: leere Namen ablehnen
    $script:pingRules.Add(@{
        Name        = $Name.Trim()
        Condition   = $Condition
        Action      = $Action
        CooldownSec = $Cooldown
        LastFired   = 0
        Enabled     = $true
        FireCount   = 0
        Description = ""   # Optionale Beschreibung für UI
    })
}

function Evaluate-PingRules {
    param([int]$lat, [decimal]$lossP, [int]$jitter)
    $now = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    # FIX: Liste kopieren vor Iteration (Regeln könnten sich selbst entfernen)
    $rules = @($script:pingRules)
    foreach ($rule in $rules) {
        if (-not $rule.Enabled) { continue }
        if (($now - $rule.LastFired) -lt $rule.CooldownSec) { continue }
        $triggered = $false
        try { $triggered = [bool](& $rule.Condition $lat $lossP $jitter) } catch { $null = $_ }
        if ($triggered) {
            $rule.LastFired = $now
            $rule.FireCount++
            $ts = Get-Date -Format "HH:mm:ss"
            $script:ruleFireLog.Insert(0, "${ts}  [$($rule.Name)]  ping=${lat}ms loss=${lossP}% jit=${jitter}ms")
            if ($script:ruleFireLog.Count -gt 100) { $script:ruleFireLog.RemoveAt(100) }
            Add-TimelineEvent -Type "warn" -Msg "Rule fired: $($rule.Name)"
            try { & $rule.Action $lat $lossP $jitter } catch {
                Write-Log "Rule '$($rule.Name)' action error: $_" "WARNING"
            }
        }
    }
}

# Standard-Regeln (editierbar)
Add-PingRule -Name "Critical Ping Alert" -Cooldown 60 `
    -Condition { param($lat,$loss,$jit) $lat -gt $CONFIG.AlertCriticalPing } `
    -Action    { param($lat,$loss,$jit)
        Play-AlertSound -Level "critical"
        $trayIcon.ShowBalloonTip(4000,"🔴 Critical Ping!","${lat}ms — Check connection",[System.Windows.Forms.ToolTipIcon]::Error) }

Add-PingRule -Name "High Loss → Switch Profile" -Cooldown 120 `
    -Condition { param($lat,$loss,$jit) $loss -gt 8 } `
    -Action    { param($lat,$loss,$jit) Switch-Profile -ProfileName "FPS" }

Add-PingRule -Name "Stable → Auto-Report" -Cooldown 3600 `
    -Condition { param($lat,$loss,$jit) $lat -lt 50 -and $loss -lt 0.5 -and $script:totalPings -gt 200 } `
    -Action    { param($lat,$loss,$jit) Export-HTMLReport }

function Show-RulesEngine {
    $rF = New-Object System.Windows.Forms.Form
    $rF.Text = "Rules Engine — NetNinja v5.0"
    $rF.Size = New-Object System.Drawing.Size(700, 620)
    $rF.MinimumSize = $rF.MaximumSize = $rF.Size
    $rF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $rF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $rF.MaximizeBox = $false; $rF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
    $rF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)
    $rF.KeyPreview = $true   # FIX: Escape schließt Dialog

    $rHdr = New-Object System.Windows.Forms.Label
    $rHdr.Text = "⚙  Rules Engine"
    $rHdr.Location = New-Object System.Drawing.Point(20,14)
    $rHdr.Size = New-Object System.Drawing.Size(400,28)
    $rHdr.Font = $script:Fonts.Title
    $rHdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220)
    $rF.Controls.Add($rHdr)

    # Counter rechts
    $rCount = New-Object System.Windows.Forms.Label
    $rCount.Location = New-Object System.Drawing.Point(520,18)
    $rCount.Size = New-Object System.Drawing.Size(160,22)
    $rCount.Font = $script:Fonts.Small
    $rCount.ForeColor = [System.Drawing.Color]::FromArgb(70,75,95)
    $rCount.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
    $rF.Controls.Add($rCount)

    $rSub = New-Object System.Windows.Forms.Label
    $rSub.Text = "IF condition is met THEN execute action — evaluated after every ping"
    $rSub.Location = New-Object System.Drawing.Point(20,44)
    $rSub.Size = New-Object System.Drawing.Size(660,18)
    $rSub.Font = $script:Fonts.Small
    $rSub.ForeColor = [System.Drawing.Color]::FromArgb(90,90,115)
    $rF.Controls.Add($rSub)

    # Regelliste
    $lv2 = New-Object System.Windows.Forms.ListView
    $lv2.Location = New-Object System.Drawing.Point(16,68)
    $lv2.Size = New-Object System.Drawing.Size(664,200)
    $lv2.View = [System.Windows.Forms.View]::Details
    $lv2.FullRowSelect = $true; $lv2.GridLines = $true
    $lv2.BackColor = [System.Drawing.Color]::FromArgb(14,14,20)
    $lv2.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $lv2.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $lv2.Font = $script:Fonts.Small
    $null = $lv2.Columns.Add("Rule Name", 180)
    $null = $lv2.Columns.Add("Fires",     50)
    $null = $lv2.Columns.Add("Cooldown",  75)
    $null = $lv2.Columns.Add("Status",    75)
    $null = $lv2.Columns.Add("Last Fire", 155)
    $null = $lv2.Columns.Add("Enabled",   90)
    $rF.Controls.Add($lv2)

    $refreshRules = {
        $lv2.Items.Clear()
        foreach ($r in $script:pingRules) {
            $itm = New-Object System.Windows.Forms.ListViewItem($r.Name)
            $null = $itm.SubItems.Add($r.FireCount.ToString())
            $null = $itm.SubItems.Add("$($r.CooldownSec)s")
            $firesSinceStart = if ($r.FireCount -gt 0) { "$($r.FireCount)×" } else { "—" }
            $null = $itm.SubItems.Add($firesSinceStart)
            $ts2 = if ($r.LastFired -gt 0) {
                [DateTimeOffset]::FromUnixTimeSeconds($r.LastFired).LocalDateTime.ToString("HH:mm:ss")
            } else { "never" }
            $null = $itm.SubItems.Add($ts2)
            $null = $itm.SubItems.Add(if ($r.Enabled) { "● On" } else { "○ Off" })
            $itm.ForeColor = if ($r.Enabled) {
                [System.Drawing.Color]::FromArgb(160,215,160)
            } else {
                [System.Drawing.Color]::FromArgb(90,90,110)
            }
            $lv2.Items.Add($itm) | Out-Null
        }
        $rCount.Text = "$($script:pingRules.Count) rule(s) active"
    }
    & $refreshRules

    # Toggle-Enable per Doppelklick
    $lv2.Add_DoubleClick({
        if ($lv2.SelectedIndices.Count -gt 0) {
            $idx = $lv2.SelectedIndices[0]
            $script:pingRules[$idx].Enabled = -not $script:pingRules[$idx].Enabled
            & $refreshRules
        }
    })

    # Neue Regel erstellen
    $mkL2 = { param($t,$x,$y,$w=180)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $t; $l.Location = New-Object System.Drawing.Point($x,$y)
        $l.Size = New-Object System.Drawing.Size($w,20)
        $l.Font = $script:Fonts.Small
        $l.ForeColor = [System.Drawing.Color]::FromArgb(120,125,155)
        $rF.Controls.Add($l)
    }
    & $mkL2 "Rule Name:"        16  282  90
    & $mkL2 "Condition:"        16  310  90
    & $mkL2 "Value (X):"       420  310  80
    & $mkL2 "Action:"           16  338  90
    & $mkL2 "Cooldown (s):"     16  366  95

    $tbRName = New-Object System.Windows.Forms.TextBox
    $tbRName.Location = New-Object System.Drawing.Point(110,280)
    $tbRName.Size = New-Object System.Drawing.Size(570,24)
    $tbRName.Text = "My Rule"
    $tbRName.BackColor = [System.Drawing.Color]::FromArgb(30,30,42)
    $tbRName.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $tbRName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $rF.Controls.Add($tbRName)

    $condTypes = @("Ping > X ms","Ping < X ms","Loss > X %","Jitter > X ms","Loss = 0 & Ping < X ms","Always fire")
    $cmbCond = New-Object System.Windows.Forms.ComboBox
    $cmbCond.Location = New-Object System.Drawing.Point(110,308)
    $cmbCond.Size = New-Object System.Drawing.Size(300,24)
    $cmbCond.Font = $script:Fonts.Small
    $cmbCond.BackColor = [System.Drawing.Color]::FromArgb(30,30,42)
    $cmbCond.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $cmbCond.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $condTypes | ForEach-Object { $null = $cmbCond.Items.Add($_) }
    $cmbCond.SelectedIndex = 0
    $rF.Controls.Add($cmbCond)

    $numThresh = New-Object System.Windows.Forms.NumericUpDown
    $numThresh.Location = New-Object System.Drawing.Point(500,308)
    $numThresh.Size = New-Object System.Drawing.Size(80,24)
    $numThresh.Minimum = 0; $numThresh.Maximum = 9999; $numThresh.Value = 200
    $numThresh.BackColor = [System.Drawing.Color]::FromArgb(30,30,42)
    $numThresh.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $rF.Controls.Add($numThresh)

    $actionTypes = @(
        "Play alert sound","Show balloon tip","Switch to FPS profile",
        "Switch to MMO profile","Export HTML report","Run Auto-Diagnosis",
        "Pause monitoring","Log to timeline","Send webhook alert"
    )
    $cmbAction = New-Object System.Windows.Forms.ComboBox
    $cmbAction.Location = New-Object System.Drawing.Point(110,336)
    $cmbAction.Size = New-Object System.Drawing.Size(370,24)
    $cmbAction.Font = $script:Fonts.Small
    $cmbAction.BackColor = [System.Drawing.Color]::FromArgb(30,30,42)
    $cmbAction.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $cmbAction.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $actionTypes | ForEach-Object { $null = $cmbAction.Items.Add($_) }
    $cmbAction.SelectedIndex = 0
    $rF.Controls.Add($cmbAction)

    $numCD = New-Object System.Windows.Forms.NumericUpDown
    $numCD.Location = New-Object System.Drawing.Point(110,364)
    $numCD.Size = New-Object System.Drawing.Size(80,24)
    $numCD.Minimum = 5; $numCD.Maximum = 86400; $numCD.Value = 60
    $numCD.BackColor = [System.Drawing.Color]::FromArgb(30,30,42)
    $numCD.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $rF.Controls.Add($numCD)

    $addRuleBtn = New-Object System.Windows.Forms.Button
    $addRuleBtn.Text = "+ Add Rule"
    $addRuleBtn.Location = New-Object System.Drawing.Point(500,362)
    $addRuleBtn.Size = New-Object System.Drawing.Size(100,28)
    $addRuleBtn.BackColor = [System.Drawing.Color]::FromArgb(0,130,210)
    $addRuleBtn.ForeColor = [System.Drawing.Color]::White
    $addRuleBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $addRuleBtn.FlatAppearance.BorderSize = 0
    $addRuleBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $addRuleBtn.Font = $script:Fonts.Small
    $addRuleBtn.Add_Click({
        if (-not $tbRName.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show("Rule name cannot be empty.","Validation","OK","Warning")
            return
        }
        $thresh = [decimal]$numThresh.Value
        $condIdx = $cmbCond.SelectedIndex
        $actIdx  = $cmbAction.SelectedIndex
        $condBlock = switch ($condIdx) {
            0 { [scriptblock]::Create("param(`$lat,`$loss,`$jit) `$lat -gt $thresh") }
            1 { [scriptblock]::Create("param(`$lat,`$loss,`$jit) `$lat -lt $thresh") }
            2 { [scriptblock]::Create("param(`$lat,`$loss,`$jit) `$loss -gt $thresh") }
            3 { [scriptblock]::Create("param(`$lat,`$loss,`$jit) `$jit -gt $thresh") }
            4 { [scriptblock]::Create("param(`$lat,`$loss,`$jit) `$loss -lt 0.1 -and `$lat -lt $thresh") }
            5 { [scriptblock]::Create("param(`$lat,`$loss,`$jit) `$true") }
        }
        $actBlock = switch ($actIdx) {
            0 { { param($l,$p,$j) Play-AlertSound -Level "high" } }
            1 { { param($l,$p,$j) $trayIcon.ShowBalloonTip(3000,"NetNinja Rule","Ping:${l}ms Loss:${p}%",[System.Windows.Forms.ToolTipIcon]::Warning) } }
            2 { { param($l,$p,$j) Switch-Profile -ProfileName "FPS" } }
            3 { { param($l,$p,$j) Switch-Profile -ProfileName "MMO" } }
            4 { { param($l,$p,$j) Export-HTMLReport } }
            5 { { param($l,$p,$j) Show-DiagnosisReport } }
            6 { { param($l,$p,$j) if (-not $script:hudPaused) { $pingTimer.Stop(); $script:hudPaused = $true } } }
            7 { { param($l,$p,$j) Add-TimelineEvent -Type "warn" -Msg "Rule: Ping=${l}ms Loss=${p}%" } }
            8 { { param($l,$p,$j) Send-WebhookAlert -Level "high" -Message "Rule triggered: Ping=${l}ms Loss=${p}%" } }
        }
        Add-PingRule -Name $tbRName.Text -Condition $condBlock -Action $actBlock -Cooldown ([int]$numCD.Value)
        $tbRName.Text = "My Rule"
        & $refreshRules
    })
    $rF.Controls.Add($addRuleBtn)

    # Delete + Toggle Buttons
    $delRuleBtn = New-Object System.Windows.Forms.Button
    $delRuleBtn.Text = "✕ Delete"; $delRuleBtn.Location = New-Object System.Drawing.Point(16,400)
    $delRuleBtn.Size = New-Object System.Drawing.Size(90,28)
    $delRuleBtn.BackColor = [System.Drawing.Color]::FromArgb(150,35,35)
    $delRuleBtn.ForeColor = [System.Drawing.Color]::White
    $delRuleBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $delRuleBtn.FlatAppearance.BorderSize = 0
    $delRuleBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $delRuleBtn.Font = $script:Fonts.Small
    $delRuleBtn.Add_Click({
        if ($lv2.SelectedIndices.Count -gt 0) {
            $idx = $lv2.SelectedIndices[0]
            # FIX: Standard-Regeln (0-2) vor versehentlichem Löschen schützen
            if ($idx -lt 3) {
                $res = [System.Windows.Forms.MessageBox]::Show(
                    "Delete built-in rule '$($script:pingRules[$idx].Name)'?",
                    "Confirm","YesNo","Warning")
                if ($res -ne "Yes") { return }
            }
            $script:pingRules.RemoveAt($idx)
            & $refreshRules
        }
    })
    $rF.Controls.Add($delRuleBtn)

    $togBtn = New-Object System.Windows.Forms.Button
    $togBtn.Text = "⏸ Toggle"; $togBtn.Location = New-Object System.Drawing.Point(114,400)
    $togBtn.Size = New-Object System.Drawing.Size(90,28)
    $togBtn.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $togBtn.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200)
    $togBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $togBtn.FlatAppearance.BorderSize = 0
    $togBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $togBtn.Font = $script:Fonts.Small
    $togBtn.Add_Click({
        if ($lv2.SelectedIndices.Count -gt 0) {
            $idx = $lv2.SelectedIndices[0]
            $script:pingRules[$idx].Enabled = -not $script:pingRules[$idx].Enabled
            & $refreshRules
        }
    })
    $rF.Controls.Add($togBtn)

    # Fire-Log
    $logLbl = New-Object System.Windows.Forms.Label
    $logLbl.Text = "Rule Fire Log (last 100):"
    $logLbl.Location = New-Object System.Drawing.Point(16,434)
    $logLbl.Size = New-Object System.Drawing.Size(200,18)
    $logLbl.Font = $script:Fonts.Small
    $logLbl.ForeColor = [System.Drawing.Color]::FromArgb(90,90,115)
    $rF.Controls.Add($logLbl)

    $clrLogBtn = New-Object System.Windows.Forms.Button
    $clrLogBtn.Text = "Clear Log"; $clrLogBtn.Location = New-Object System.Drawing.Point(570,430)
    $clrLogBtn.Size = New-Object System.Drawing.Size(80,22)
    $clrLogBtn.BackColor = [System.Drawing.Color]::FromArgb(40,42,55)
    $clrLogBtn.ForeColor = [System.Drawing.Color]::FromArgb(120,120,145)
    $clrLogBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $clrLogBtn.FlatAppearance.BorderSize = 0
    $clrLogBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $clrLogBtn.Font = $script:Fonts.Small
    $clrLogBtn.Add_Click({ $script:ruleFireLog.Clear(); $logBox2.Items.Clear() })
    $rF.Controls.Add($clrLogBtn)

    $logBox2 = New-Object System.Windows.Forms.ListBox
    $logBox2.Location = New-Object System.Drawing.Point(16,455)
    $logBox2.Size = New-Object System.Drawing.Size(664,112)
    $logBox2.BackColor = [System.Drawing.Color]::FromArgb(12,12,18)
    $logBox2.ForeColor = [System.Drawing.Color]::FromArgb(130,175,130)
    $logBox2.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $logBox2.Font = New-Object System.Drawing.Font("Consolas",8)
    $script:ruleFireLog | ForEach-Object { $null = $logBox2.Items.Add($_) }
    $rF.Controls.Add($logBox2)

    $rClose = New-Object System.Windows.Forms.Button
    $rClose.Text = "Close"; $rClose.Location = New-Object System.Drawing.Point(564,576)
    $rClose.Size = New-Object System.Drawing.Size(116,36)
    $rClose.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $rClose.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200)
    $rClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $rClose.FlatAppearance.BorderSize = 0
    $rClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $rClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $rF.Controls.Add($rClose)
    $rF.AcceptButton = $rClose
    $rF.CancelButton = $rClose   # FIX: Escape schließt auch

    $rF.ShowDialog() | Out-Null
    $rF.Dispose()
}


# ══ v5.0: WEBSOCKET / HTTP LIVE-DASHBOARD ═════════════════
$script:webDashEnabled  = $false
$script:webDashListener = $null
$script:webDashPort     = 8765

function Start-WebDashboard {
    if ($script:webDashListener) { return }
    try {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$($script:webDashPort)/")
        $listener.Start()
        $script:webDashListener = $listener
        $script:webDashEnabled  = $true
        Write-Log "Web dashboard started at http://localhost:$($script:webDashPort)/" "INFO"
        Add-TimelineEvent -Type "info" -Msg "Web Dashboard started on port $($script:webDashPort)"

        # Async request handler
        $handleRequest = {
            param($ctx)
            $req  = $ctx.Request
            $resp = $ctx.Response
            try {
                $path = $req.Url.AbsolutePath
                if ($path -eq "/data") {
                    # JSON API: aktueller Status
                    $hist = @($script:pingHistory)
                    $lossP2 = if ($script:totalPings -gt 0) { [math]::Round(($script:lostPings/$script:totalPings)*100,1) } else { 0 }
                    $json = '{"ping":' + $script:currentLatency + ',"avg":' + ([math]::Round(($hist|Measure-Object -Average).Average,0)) + ',"min":' + $script:minLat + ',"max":' + $script:maxLat + ',"jitter":' + $script:currentJitter + ',"loss":' + $lossP2 + ',"profile":"' + $script:currentProfile + '","history":[' + ($hist -join ",") + ']}'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                    $resp.ContentType = "application/json"; $resp.AddHeader("Access-Control-Allow-Origin","*")
                    $resp.ContentLength64 = $bytes.Length; $resp.OutputStream.Write($bytes,0,$bytes.Length)
                } else {
                    # Haupt-HTML-Dashboard
                    $html = @'
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>NetNinja Dashboard</title>
<meta http-equiv="refresh" content="2">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{background:#0a0a12;color:#d8d8e4;font-family:"Segoe UI",sans-serif;padding:20px}
h1{color:#0096e0;font-size:22px;margin-bottom:4px}
.meta{color:#555;font-size:12px;margin-bottom:20px}
.cards{display:flex;gap:12px;margin-bottom:20px;flex-wrap:wrap}
.card{background:#14141e;border-radius:8px;padding:14px 20px;flex:1;min-width:110px;border:1px solid #1e1e2a;text-align:center}
.val{font-size:28px;font-weight:bold}.lbl{font-size:10px;color:#555;text-transform:uppercase;margin-top:4px}
canvas{background:#0a0a12;border-radius:8px;border:1px solid #1a1a28;display:block;width:100%}
.status{font-size:11px;color:#444;margin-top:8px}
</style></head><body>
<h1>🥷 NetNinja — Live Dashboard</h1>
<div class="meta" id="ts">Loading...</div>
<div class="cards">
<div class="card"><div class="val" id="ping" style="color:#32dc50">--</div><div class="lbl">Ping ms</div></div>
<div class="card"><div class="val" id="avg" style="color:#32dc50">--</div><div class="lbl">Avg ms</div></div>
<div class="card"><div class="val" id="jitter">--</div><div class="lbl">Jitter ms</div></div>
<div class="card"><div class="val" id="loss" style="color:#ff3232">--%</div><div class="lbl">Loss</div></div>
<div class="card"><div class="val" id="profile" style="color:#0096e0;font-size:16px">--</div><div class="lbl">Profile</div></div>
</div>
<canvas id="g" height="160"></canvas>
<div class="status">Auto-refresh every 2s &nbsp;·&nbsp; NetNinja v5.0</div>
<script>
async function load(){
  try{
    const r=await fetch("/data"),d=await r.json();
    const c=v=>v<75?"#32dc50":v<150?"#ffe040":v<250?"#ff9900":"#ff3232";
    document.getElementById("ping").textContent=d.ping+"ms";
    document.getElementById("ping").style.color=c(d.ping);
    document.getElementById("avg").textContent=d.avg+"ms";
    document.getElementById("avg").style.color=c(d.avg);
    document.getElementById("jitter").textContent=d.jitter+"ms";
    document.getElementById("loss").textContent=d.loss+"%";
    document.getElementById("profile").textContent=d.profile;
    document.getElementById("ts").textContent="Last update: "+new Date().toLocaleTimeString()+" | Pings: "+d.history.length;
    const cv=document.getElementById("g"),ctx=cv.getContext("2d");
    cv.width=cv.parentElement.offsetWidth||800;
    const h=d.history,W=cv.width,H=cv.height,pad=12;
    const mx=Math.max(...h,1),step=(W-2*pad)/Math.max(h.length-1,1);
    ctx.clearRect(0,0,W,H);
    ctx.fillStyle="#0a0a12";ctx.fillRect(0,0,W,H);
    [75,150,250].forEach(v=>{const y=H-pad-(v/mx)*(H-2*pad);ctx.strokeStyle="#1a1a28";ctx.beginPath();ctx.moveTo(pad,y);ctx.lineTo(W-pad,y);ctx.stroke();ctx.fillStyle="#333";ctx.font="9px monospace";ctx.fillText(v+"ms",2,y-2);});
    if(h.length>1){ctx.beginPath();ctx.lineWidth=2;h.forEach((v,i)=>{const x=pad+i*step,y=H-pad-(Math.min(v,mx)/mx)*(H-2*pad);i===0?ctx.moveTo(x,y):ctx.lineTo(x,y);});ctx.strokeStyle="#32dc50";ctx.stroke();}
  }catch(e){document.getElementById("ts").textContent="Connecting...";}
}
load();
</script></body></html>
'@
                    $bytes2 = [System.Text.Encoding]::UTF8.GetBytes($html)
                    $resp.ContentType = "text/html; charset=utf-8"
                    $resp.ContentLength64 = $bytes2.Length; $resp.OutputStream.Write($bytes2,0,$bytes2.Length)
                }
            } catch { $null = $_ } finally { try { $resp.Close() } catch { $null = $_ } }
        }

        # Async Request-Loop im Runspace
        $script:webDashRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs = $script:webDashRunspace
        $rs.Open()
        $rs.SessionStateProxy.SetVariable("listener",  $listener)
        $rs.SessionStateProxy.SetVariable("handleRequest", $handleRequest)
        $rs.SessionStateProxy.SetVariable("script", $script)
        $script:webDashPS = [System.Management.Automation.PowerShell]::Create()
        $ps = $script:webDashPS
        $ps.Runspace = $rs
        $null = $ps.AddScript({
            while ($listener.IsListening) {
                try {
                    $ctx = $listener.GetContext()
                    try { & $handleRequest $ctx } catch { $null = $_ }
                } catch { if (-not $listener.IsListening) { break } }
            }
        })
        $null = $ps.BeginInvoke()
        Write-Log "Web dashboard request handler running" "INFO"
    } catch {
        Write-Log "Web dashboard start failed: $_" "ERROR"
        $script:webDashEnabled = $false
    }
}

function Stop-WebDashboard {
    try {
        if ($script:webDashListener) {
            $script:webDashListener.Stop()
            $script:webDashListener.Close()
            $script:webDashListener = $null
        }
        if ($script:webDashPS) {
            try { $script:webDashPS.Stop() } catch { $null = $_ }
            try { $script:webDashPS.Dispose() } catch { $null = $_ }
            $script:webDashPS = $null
        }
        if ($script:webDashRunspace) {
            try { $script:webDashRunspace.Close() } catch { $null = $_ }
            try { $script:webDashRunspace.Dispose() } catch { $null = $_ }
            $script:webDashRunspace = $null
        }
        $script:webDashEnabled = $false
        Write-Log "Web dashboard stopped and runspace disposed" "INFO"
    } catch { $null = $_ }
}


# ══ v5.0: SERVER FAILOVER ══════════════════════════════════
$script:failoverTargets = [System.Collections.Generic.List[hashtable]]::new()
$script:failoverActive   = $false
$script:failoverIndex    = 0   # 0 = primary, 1+ = failover
$script:failoverLossThreshold = 5   # consecutive losses → switch
$script:failoverConsecLoss    = 0
$script:failoverPrimaryCheckEvery = 30  # Pings zwischen Primary-Check
$script:failoverPrimaryCheckCount = 0

function Add-FailoverTarget {
    param([string]$TargetHost, [int]$Port = 80, [string]$Label = "")
    # FIX: Guard + $Host-Konflikt vermieden
    if (-not $TargetHost.Trim()) { return }
    $h = $TargetHost.Trim()
    $script:failoverTargets.Add(@{ Host=$h; Port=$Port; Label=$(if ($Label.Trim()) { $Label.Trim() } else { $h }) })
}

# Standard-Failover: Primary zuerst, dann Fallbacks
Add-FailoverTarget -TargetHost $CONFIG.ServerAddress -Port $CONFIG.ServerPort -Label "Primary"

function Invoke-FailoverCheck {
    param([bool]$isLoss)
    if ($script:failoverTargets.Count -lt 2) { return }

    if ($isLoss) {
        $script:failoverConsecLoss++
        if ($script:failoverConsecLoss -ge $script:failoverLossThreshold -and -not $script:failoverActive) {
            $nextIdx = 1
            if ($nextIdx -lt $script:failoverTargets.Count) {
                $backup = $script:failoverTargets[$nextIdx]
                $script:failoverIndex      = $nextIdx
                $script:failoverActive     = $true
                $script:TargetIP           = $backup.Host
                $script:activeServerPort   = $backup.Port
                $script:failoverConsecLoss = 0
                $script:failoverPrimaryCheckCount = 0   # FIX: Reset Check-Counter bei Aktivierung
                Add-TimelineEvent -Type "warn" -Msg "Failover → $($backup.Label) ($($backup.Host))"
                Write-Log "Failover activated → $($backup.Host):$($backup.Port)" "WARNING"
                try {
                    $trayIcon.ShowBalloonTip(4000, "⚡ Server Failover",
                        "Primary unreachable`nSwitched to: $($backup.Label) ($($backup.Host))",
                        [System.Windows.Forms.ToolTipIcon]::Warning)
                } catch { $null = $_ }
            }
        }
    } else {
        # Erfolgreicher Ping → Konsekutiv-Zähler zurücksetzen
        if ($script:failoverConsecLoss -gt 0) { $script:failoverConsecLoss = 0 }

        if ($script:failoverActive) {
            $script:failoverPrimaryCheckCount++
            if ($script:failoverPrimaryCheckCount -ge $script:failoverPrimaryCheckEvery) {
                $script:failoverPrimaryCheckCount = 0
                $primary = $script:failoverTargets[0]
                $tcp3 = $null
                try {
                    $tcp3 = New-Object System.Net.Sockets.TcpClient
                    $ar3  = $tcp3.BeginConnect($primary.Host, $primary.Port, $null, $null)
                    if ($ar3.AsyncWaitHandle.WaitOne(800, $false)) {
                        try { $tcp3.EndConnect($ar3) } catch { $null = $_ }
                        # Primary wieder erreichbar → zurückschalten
                        $script:TargetIP         = $primary.Host
                        $script:activeServerPort = $primary.Port
                        $script:failoverActive   = $false
                        $script:failoverIndex    = 0
                        Add-TimelineEvent -Type "restore" -Msg "Primary restored → $($primary.Label)"
                        Write-Log "Failover resolved: back to $($primary.Host):$($primary.Port)" "INFO"
                        try {
                            $trayIcon.ShowBalloonTip(3000, "✅ Primary Restored",
                                "Switched back to $($primary.Label) ($($primary.Host))",
                                [System.Windows.Forms.ToolTipIcon]::Info)
                        } catch { $null = $_ }
                    }
                } catch { $null = $_ } finally {
                    # FIX: TcpClient immer disposed
                    if ($tcp3) { try { $tcp3.Close(); $tcp3.Dispose() } catch { $null = $_ } }
                }
            }
        }
    }
}

function Show-FailoverSettings {
    $ffF = New-Object System.Windows.Forms.Form
    $ffF.Text = "Server Failover Settings — NetNinja v5.0"
    $ffF.Size = New-Object System.Drawing.Size(540, 440)
    $ffF.MinimumSize = $ffF.MaximumSize = $ffF.Size
    $ffF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $ffF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $ffF.MaximizeBox = $false; $ffF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
    $ffF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $fHdr = New-Object System.Windows.Forms.Label; $fHdr.Text = "⚡  Server Failover"
    $fHdr.Location=New-Object System.Drawing.Point(20,14); $fHdr.Size=New-Object System.Drawing.Size(500,28)
    $fHdr.Font=$script:Fonts.Title; $fHdr.ForeColor=[System.Drawing.Color]::FromArgb(255,180,40); $ffF.Controls.Add($fHdr)

    $fSub = New-Object System.Windows.Forms.Label
    $fSub.Text="Auto-switch to backup server when primary is unreachable"
    $fSub.Location=New-Object System.Drawing.Point(20,44); $fSub.Size=New-Object System.Drawing.Size(500,18)
    $fSub.Font=$script:Fonts.Small; $fSub.ForeColor=[System.Drawing.Color]::FromArgb(90,90,115); $ffF.Controls.Add($fSub)

    $fStatus = New-Object System.Windows.Forms.Label
    $active = if ($script:failoverActive) { "● ACTIVE — on backup server" } else { "○ Standby" }
    $fStatus.Text="Status: $active"; $fStatus.Location=New-Object System.Drawing.Point(20,70); $fStatus.Size=New-Object System.Drawing.Size(500,20)
    $fStatus.Font=$script:Fonts.Small; $fStatus.ForeColor=if ($script:failoverActive){[System.Drawing.Color]::FromArgb(255,180,40)} else {[System.Drawing.Color]::FromArgb(60,200,80)}; $ffF.Controls.Add($fStatus)

    # Server-Liste
    $fLv = New-Object System.Windows.Forms.ListView; $fLv.Location=New-Object System.Drawing.Point(16,96); $fLv.Size=New-Object System.Drawing.Size(506,160)
    $fLv.View=[System.Windows.Forms.View]::Details; $fLv.FullRowSelect=$true; $fLv.GridLines=$true
    $fLv.BackColor=[System.Drawing.Color]::FromArgb(14,14,20); $fLv.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215)
    $fLv.BorderStyle=[System.Windows.Forms.BorderStyle]::None; $fLv.Font=$script:Fonts.Small
    $null=$fLv.Columns.Add("#",30); $null=$fLv.Columns.Add("Label",120); $null=$fLv.Columns.Add("Host",200); $null=$fLv.Columns.Add("Port",60); $null=$fLv.Columns.Add("Role",80)
    $ffF.Controls.Add($fLv)

    $refreshF = {
        $fLv.Items.Clear()
        for ($fi=0; $fi -lt $script:failoverTargets.Count; $fi++) {
            $t=$script:failoverTargets[$fi]
            $role = if ($fi -eq 0){"PRIMARY"} elseif($fi-eq$script:failoverIndex-and$script:failoverActive){"ACTIVE"}else{"BACKUP"}
            $itm=New-Object System.Windows.Forms.ListViewItem(($fi+1).ToString())
            $null=$itm.SubItems.Add($t.Label); $null=$itm.SubItems.Add($t.Host)
            $null=$itm.SubItems.Add($t.Port.ToString()); $null=$itm.SubItems.Add($role)
            $itm.ForeColor=if($role-eq"PRIMARY"){[System.Drawing.Color]::FromArgb(0,180,255)}elseif($role-eq"ACTIVE"){[System.Drawing.Color]::FromArgb(255,200,40)}else{[System.Drawing.Color]::FromArgb(150,150,180)}
            $fLv.Items.Add($itm)|Out-Null
        }
    }; & $refreshF

    # Eingabe-Zeile
    $mkL3={ param($t,$x,$y) $l=New-Object System.Windows.Forms.Label; $l.Text=$t; $l.Location=New-Object System.Drawing.Point($x,$y); $l.Size=New-Object System.Drawing.Size(70,20); $l.Font=$script:Fonts.Small; $l.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165); $ffF.Controls.Add($l) }
    & $mkL3 "Label:" 20 265; & $mkL3 "Host/IP:" 110 265; & $mkL3 "Port:" 320 265
    $fTbL=New-Object System.Windows.Forms.TextBox; $fTbL.Location=New-Object System.Drawing.Point(20,285); $fTbL.Size=New-Object System.Drawing.Size(82,24); $fTbL.Text="Backup 1"; $fTbL.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $fTbL.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $fTbL.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $ffF.Controls.Add($fTbL)
    $fTbH=New-Object System.Windows.Forms.TextBox; $fTbH.Location=New-Object System.Drawing.Point(110,285); $fTbH.Size=New-Object System.Drawing.Size(202,24); $fTbH.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $fTbH.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $fTbH.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $ffF.Controls.Add($fTbH)
    $fNPort=New-Object System.Windows.Forms.NumericUpDown; $fNPort.Location=New-Object System.Drawing.Point(320,285); $fNPort.Size=New-Object System.Drawing.Size(70,24); $fNPort.Minimum=1; $fNPort.Maximum=65535; $fNPort.Value=$CONFIG.ServerPort; $fNPort.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $fNPort.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $ffF.Controls.Add($fNPort)
    $fAdd=New-Object System.Windows.Forms.Button; $fAdd.Text="+ Add Backup"; $fAdd.Location=New-Object System.Drawing.Point(20,318); $fAdd.Size=New-Object System.Drawing.Size(120,28); $fAdd.BackColor=[System.Drawing.Color]::FromArgb(0,130,210); $fAdd.ForeColor=[System.Drawing.Color]::White; $fAdd.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $fAdd.FlatAppearance.BorderSize=0; $fAdd.Cursor=[System.Windows.Forms.Cursors]::Hand; $fAdd.Font=$script:Fonts.Small
    $fAdd.Add_Click({ if ($fTbH.Text.Trim()) { Add-FailoverTarget -TargetHost $fTbH.Text.Trim() -Port ([int]$fNPort.Value) -Label $fTbL.Text.Trim(); & $refreshF } }); $ffF.Controls.Add($fAdd)
    $fDel=New-Object System.Windows.Forms.Button; $fDel.Text="✕ Remove"; $fDel.Location=New-Object System.Drawing.Point(152,318); $fDel.Size=New-Object System.Drawing.Size(96,28); $fDel.BackColor=[System.Drawing.Color]::FromArgb(160,40,40); $fDel.ForeColor=[System.Drawing.Color]::White; $fDel.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $fDel.FlatAppearance.BorderSize=0; $fDel.Cursor=[System.Windows.Forms.Cursors]::Hand; $fDel.Font=$script:Fonts.Small
    $fDel.Add_Click({ if ($fLv.SelectedIndices.Count-gt0 -and $fLv.SelectedIndices[0]-gt0) { $script:failoverTargets.RemoveAt($fLv.SelectedIndices[0]); & $refreshF } }); $ffF.Controls.Add($fDel)

    # Schwellwert
    $mkL3 "Loss threshold (consecutive losses to trigger failover):" 20 358
    $fNThr=New-Object System.Windows.Forms.NumericUpDown; $fNThr.Location=New-Object System.Drawing.Point(360,355); $fNThr.Size=New-Object System.Drawing.Size(60,24); $fNThr.Minimum=2; $fNThr.Maximum=30; $fNThr.Value=$script:failoverLossThreshold; $fNThr.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $fNThr.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $ffF.Controls.Add($fNThr)

    $fSave=New-Object System.Windows.Forms.Button; $fSave.Text="Save & Close"; $fSave.Location=New-Object System.Drawing.Point(290,388); $fSave.Size=New-Object System.Drawing.Size(120,34); $fSave.BackColor=[System.Drawing.Color]::FromArgb(45,175,80); $fSave.ForeColor=[System.Drawing.Color]::White; $fSave.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $fSave.FlatAppearance.BorderSize=0; $fSave.Cursor=[System.Windows.Forms.Cursors]::Hand; $fSave.Font=$script:Fonts.Small
    $fSave.Add_Click({ $script:failoverLossThreshold=[int]$fNThr.Value; Write-Log "Failover: $($script:failoverTargets.Count) targets, threshold=$($script:failoverLossThreshold)" "INFO"; $ffF.Close() }); $ffF.Controls.Add($fSave)
    $fCls=New-Object System.Windows.Forms.Button; $fCls.Text="Cancel"; $fCls.Location=New-Object System.Drawing.Point(420,388); $fCls.Size=New-Object System.Drawing.Size(96,34); $fCls.BackColor=[System.Drawing.Color]::FromArgb(55,58,70); $fCls.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200); $fCls.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $fCls.FlatAppearance.BorderSize=0; $fCls.Cursor=[System.Windows.Forms.Cursors]::Hand; $fCls.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $ffF.Controls.Add($fCls); $ffF.CancelButton=$fCls
    $ffF.ShowDialog() | Out-Null
    $ffF.Dispose()
}


# ══════════════════════════════════════════════════════════════
# GEO-IP LOOKUP — Serverstandort per ip-api.com
# ══════════════════════════════════════════════════════════════
$script:geoCache = @{}

function Get-GeoIP {
    param([string]$IP)
    if (-not $IP -or $IP -eq "0.0.0.0" -or $IP -match '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)') {
        return $null   # FIX: Private/lokale IPs ablehnen (ip-api gibt Fehler zurück)
    }
    if ($script:geoCache.ContainsKey($IP)) { return $script:geoCache[$IP] }
    $wc = $null
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent","NetNinja/$($CONFIG.Version)")
        # FIX: HTTPS statt HTTP + Timeout via ServicePoint
        [System.Net.ServicePointManager]::FindServicePoint("https://ip-api.com/").ConnectionLeaseTimeout = 8000
        $json = $wc.DownloadString("https://ip-api.com/json/${IP}?fields=status,country,regionName,city,isp,org,lat,lon,timezone,as")
        $obj  = $json | ConvertFrom-Json
        if ($obj.status -eq "success") {
            $result = @{
                Country = $obj.country;    Region  = $obj.regionName
                City    = $obj.city;       ISP     = $obj.isp
                Org     = $obj.org;        Lat     = $obj.lat
                Lon     = $obj.lon;        TZ      = $obj.timezone
                AS      = $obj.as
            }
            $script:geoCache[$IP] = $result
            Add-TimelineEvent -Type "info" -Msg "GeoIP: $($obj.city), $($obj.country) [$($obj.isp)]"
            return $result
        } else {
            Write-Log "GeoIP: API returned status=$($obj.status) for $IP" "WARNING"
        }
    } catch {
        Write-Log "GeoIP lookup failed for ${IP}: $_" "WARNING"
    } finally {
        # FIX: WebClient immer disposed
        if ($wc) { try { $wc.Dispose() } catch { $null = $_ } }
    }
    return $null
}

function Show-GeoIPInfo {
    param([string]$IP = $script:TargetIP)
    $geo = Get-GeoIP -IP $IP
    $gF = New-Object System.Windows.Forms.Form
    $gF.Text = "Server Location — $IP"; $gF.Size = New-Object System.Drawing.Size(480,360)
    $gF.MinimumSize = $gF.MaximumSize = $gF.Size
    $gF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $gF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $gF.MaximizeBox = $false; $gF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
    $gF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $gHdr = New-Object System.Windows.Forms.Label
    $gHdr.Text = "🌍  Server Geo-IP"; $gHdr.Location = New-Object System.Drawing.Point(20,14)
    $gHdr.Size = New-Object System.Drawing.Size(440,28); $gHdr.Font = $script:Fonts.Title
    $gHdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220); $gF.Controls.Add($gHdr)

    # Map panel — GDI ASCII-style world dot
    $mapPnl = New-Object System.Windows.Forms.Panel
    $mapPnl.Location = New-Object System.Drawing.Point(16,50); $mapPnl.Size = New-Object System.Drawing.Size(446,130)
    $mapPnl.BackColor = [System.Drawing.Color]::FromArgb(10,14,22); $gF.Controls.Add($mapPnl)

    if ($geo) {
        $mapPnl.Add_Paint({
            param($s,$e)
            $g2 = $e.Graphics; $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g2.Clear([System.Drawing.Color]::FromArgb(10,14,22))
            # Einfache Gitterlinien
            $gridPen = $script:gfxCache.PenGrid
            for ($gx=0; $gx -lt 446; $gx+=22) { $g2.DrawLine($gridPen,$gx,0,$gx,130) }
            for ($gy=0; $gy -lt 130; $gy+=13) { $g2.DrawLine($gridPen,0,$gy,446,$gy) }
            # PenGrid gecacht
            # Koordinaten auf Karte projizieren (Mercator)
            $lon = $geo.Lon; $lat2 = $geo.Lat
            $px = [int](($lon + 180) / 360.0 * 446)
            $py = [int]((1 - ($lat2 + 90) / 180.0) * 130)
            # Pulsring
            $ringBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40,0,200,100))
            $g2.FillEllipse($ringBr, $px-18, $py-18, 36, 36); $ringBr.Dispose()
            $ring2Br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80,0,220,100))
            $g2.FillEllipse($ring2Br, $px-10, $py-10, 20, 20); $ring2Br.Dispose()
            # Marker
            $dotBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0,255,100))
            $g2.FillEllipse($dotBr, $px-5, $py-5, 10, 10); $dotBr.Dispose()
            # Label
            $lblBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0,220,90))
            $g2.DrawString("$($geo.City)", $script:Fonts.Tiny, $lblBr, [float]($px+8), [float]($py-6))
            $lblBr.Dispose()
        })

        $y = 190
        $rows = @(
            @("IP",      $IP)
            @("Location","$($geo.City), $($geo.Region), $($geo.Country)")
            @("ISP",     $geo.ISP)
            @("Org",     $geo.Org)
            @("Coords",  "Lat $($geo.Lat)°  Lon $($geo.Lon)°")
            @("Timezone",$geo.TZ)
        )
        foreach ($row in $rows) {
            $kL = New-Object System.Windows.Forms.Label; $kL.Text = $row[0]+":"; $kL.Location = New-Object System.Drawing.Point(20,$y)
            $kL.Size = New-Object System.Drawing.Size(80,20); $kL.Font = $script:Fonts.Small
            $kL.ForeColor = [System.Drawing.Color]::FromArgb(80,80,110); $gF.Controls.Add($kL)
            $vL = New-Object System.Windows.Forms.Label; $vL.Text = $row[1]; $vL.Location = New-Object System.Drawing.Point(105,$y)
            $vL.Size = New-Object System.Drawing.Size(356,20); $vL.Font = $script:Fonts.Small
            $vL.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215); $gF.Controls.Add($vL)
            $y += 22
        }
    } else {
        $eL = New-Object System.Windows.Forms.Label; $eL.Text = "GeoIP lookup failed — check internet connection"
        $eL.Location = New-Object System.Drawing.Point(20,200); $eL.Size = New-Object System.Drawing.Size(440,20)
        $eL.Font = $script:Fonts.Small; $eL.ForeColor = [System.Drawing.Color]::FromArgb(180,80,80); $gF.Controls.Add($eL)
    }

    $cBtn = New-Object System.Windows.Forms.Button; $cBtn.Text = "Close"; $cBtn.Location = New-Object System.Drawing.Point(360,314)
    $cBtn.Size = New-Object System.Drawing.Size(100,30); $cBtn.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $cBtn.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200); $cBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cBtn.FlatAppearance.BorderSize = 0; $cBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $cBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK; $gF.Controls.Add($cBtn); $gF.AcceptButton = $cBtn
    $gF.ShowDialog() | Out-Null
    $gF.Dispose()
}

# ══════════════════════════════════════════════════════════════
# LOG VIEWER GUI — Scrollbarer, filterba Log-Viewer
# ══════════════════════════════════════════════════════════════
function Show-LogViewer {
    $lvF = New-Object System.Windows.Forms.Form
    $lvF.Text = "Log Viewer — NetNinja v5.0"
    $lvF.Size = New-Object System.Drawing.Size(800,520)
    $lvF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $lvF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $lvF.BackColor = [System.Drawing.Color]::FromArgb(12,12,18)
    $lvF.MinimumSize = New-Object System.Drawing.Size(600,360)
    $lvF.KeyPreview = $true
    $lvF.Add_KeyDown({ param($s,$e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $lvF.Close() } })

    $lvHdr = New-Object System.Windows.Forms.Label
    $lvHdr.Text = "📋  Log Viewer"
    $lvHdr.Dock = [System.Windows.Forms.DockStyle]::Top
    $lvHdr.Height = 32
    $lvHdr.Font = $script:Fonts.Title
    $lvHdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220)
    $lvHdr.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lvHdr.Padding = New-Object System.Windows.Forms.Padding(12,0,0,0)
    $lvF.Controls.Add($lvHdr)

    # Filter bar
    $filterPnl = New-Object System.Windows.Forms.Panel
    $filterPnl.Dock = [System.Windows.Forms.DockStyle]::Top
    $filterPnl.Height = 36
    $filterPnl.BackColor = [System.Drawing.Color]::FromArgb(18,18,26)
    $lvF.Controls.Add($filterPnl)

    $lvFilter = New-Object System.Windows.Forms.TextBox
    $lvFilter.Location = New-Object System.Drawing.Point(8,7)
    $lvFilter.Size = New-Object System.Drawing.Size(320,22)
    $lvFilter.BackColor = [System.Drawing.Color]::FromArgb(28,28,38)
    $lvFilter.ForeColor = [System.Drawing.Color]::FromArgb(180,180,200)
    $lvFilter.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $lvFilter.Font = $script:Fonts.Small
    # FIX: Placeholder-Text ohne "Filter..." als Default-Wert — nutze PlaceholderText direkt
    $filterPnl.Controls.Add($lvFilter)

    $levels = @("ALL","INFO","WARNING","ERROR")
    $lvLevel = New-Object System.Windows.Forms.ComboBox
    $lvLevel.Location = New-Object System.Drawing.Point(336,6)
    $lvLevel.Size = New-Object System.Drawing.Size(90,22)
    $lvLevel.Font = $script:Fonts.Small
    $lvLevel.BackColor = [System.Drawing.Color]::FromArgb(28,28,38)
    $lvLevel.ForeColor = [System.Drawing.Color]::FromArgb(180,180,200)
    $lvLevel.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $levels | ForEach-Object { $null = $lvLevel.Items.Add($_) }
    $lvLevel.SelectedIndex = 0
    $filterPnl.Controls.Add($lvLevel)

    $refreshBtn = New-Object System.Windows.Forms.Button
    $refreshBtn.Text = "↻ Refresh"
    $refreshBtn.Location = New-Object System.Drawing.Point(434,5)
    $refreshBtn.Size = New-Object System.Drawing.Size(80,26)
    $refreshBtn.BackColor = [System.Drawing.Color]::FromArgb(0,110,190)
    $refreshBtn.ForeColor = [System.Drawing.Color]::White
    $refreshBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $refreshBtn.FlatAppearance.BorderSize = 0
    $refreshBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $refreshBtn.Font = $script:Fonts.Small
    $filterPnl.Controls.Add($refreshBtn)

    $clearLogBtn = New-Object System.Windows.Forms.Button
    $clearLogBtn.Text = "✕ Clear"
    $clearLogBtn.Location = New-Object System.Drawing.Point(522,5)
    $clearLogBtn.Size = New-Object System.Drawing.Size(70,26)
    $clearLogBtn.BackColor = [System.Drawing.Color]::FromArgb(140,35,35)
    $clearLogBtn.ForeColor = [System.Drawing.Color]::White
    $clearLogBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $clearLogBtn.FlatAppearance.BorderSize = 0
    $clearLogBtn.Cursor = [System.Windows.Forms.Cursors]::Hand
    $clearLogBtn.Font = $script:Fonts.Small
    $clearLogBtn.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show(
            "Clear log file? This cannot be undone.", "Confirm",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning) -eq "Yes") {
            try { Clear-Content $logFile -Force; $rtb.Clear() } catch { $null = $_ }
        }
    })
    $filterPnl.Controls.Add($clearLogBtn)

    # Line count label
    $lineCountLbl = New-Object System.Windows.Forms.Label
    $lineCountLbl.Location = New-Object System.Drawing.Point(600,9)
    $lineCountLbl.Size = New-Object System.Drawing.Size(180,20)
    $lineCountLbl.Font = $script:Fonts.Small
    $lineCountLbl.ForeColor = [System.Drawing.Color]::FromArgb(60,65,85)
    $filterPnl.Controls.Add($lineCountLbl)

    # Log text box — FIX: Font aus globalem Cache statt new
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.Dock = [System.Windows.Forms.DockStyle]::Fill
    $rtb.ReadOnly = $true
    $rtb.BackColor = [System.Drawing.Color]::FromArgb(10,10,16)
    $rtb.ForeColor = [System.Drawing.Color]::FromArgb(160,165,185)
    $rtb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $rtb.Font = $script:gfxCache.FontTimeline   # FIX: gecacht, kein new Font()
    $rtb.WordWrap = $false
    $rtb.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Both
    $lvF.Controls.Add($rtb)

    $loadLog = {
        if (-not (Test-Path $logFile)) { $rtb.Text = "(log file not found)"; return }
        $rtb.SuspendLayout()   # FIX: Rendering während Befüllung pausieren
        $rtb.Clear()
        $filterTxt   = $lvFilter.Text.Trim()
        $levelFilter = $lvLevel.SelectedItem
        $shown = 0
        try {
            $rawLines = Get-Content $logFile -Tail 1000 -ErrorAction Stop
        } catch { $rtb.Text = "(cannot read log: $_)"; $rtb.ResumeLayout(); return }

        # FIX: Regex-Objekte vorab kompilieren (statt inline re-evaluation)
        $reError   = [regex]'\[ERROR\]'
        $reWarn    = [regex]'\[WARNING\]'
        $reInfo    = [regex]'\[INFO\]'
        $reFilter  = if ($filterTxt) { [regex]::new([regex]::Escape($filterTxt), [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) } else { $null }

        foreach ($rl in $rawLines) {
            if ($reFilter -and -not $reFilter.IsMatch($rl)) { continue }
            if ($levelFilter -ne "ALL" -and $rl -notmatch "\[$levelFilter\]") { continue }
            $color = if     ($reError.IsMatch($rl))  { [System.Drawing.Color]::FromArgb(255,90,90)   }
                     elseif ($reWarn.IsMatch($rl))   { [System.Drawing.Color]::FromArgb(255,200,60)  }
                     elseif ($reInfo.IsMatch($rl))   { [System.Drawing.Color]::FromArgb(110,165,220) }
                     else                            { [System.Drawing.Color]::FromArgb(130,130,150) }
            $start = $rtb.TextLength
            $rtb.AppendText($rl + "`n")
            $rtb.Select($start, $rl.Length)
            $rtb.SelectionColor = $color
            $shown++
        }
        $rtb.SelectionStart = $rtb.TextLength
        $rtb.ScrollToCaret()
        $rtb.ResumeLayout()
        $lineCountLbl.Text = "$shown / $($rawLines.Count) lines"
    }
    & $loadLog

    $refreshBtn.Add_Click({ & $loadLog })
    $lvFilter.Add_TextChanged({ & $loadLog })
    $lvLevel.Add_SelectedIndexChanged({ & $loadLog })

    $lvF.ShowDialog() | Out-Null
    $lvF.Dispose()
}

# ══════════════════════════════════════════════════════════════
# CONFIG EDITOR GUI — Alle CONFIG-Werte direkt editierbar
# ══════════════════════════════════════════════════════════════
function Show-ConfigEditor {
    $cF = New-Object System.Windows.Forms.Form
    $cF.Text = "Config Editor — NetNinja v5.0"; $cF.Size = New-Object System.Drawing.Size(520,540)
    $cF.MinimumSize = $cF.MaximumSize = $cF.Size
    $cF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $cF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $cF.MaximizeBox = $false; $cF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
    $cF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $cHdr = New-Object System.Windows.Forms.Label; $cHdr.Text = "⚙  Config Editor"
    $cHdr.Location = New-Object System.Drawing.Point(20,14); $cHdr.Size = New-Object System.Drawing.Size(480,28)
    $cHdr.Font = $script:Fonts.Title; $cHdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220); $cF.Controls.Add($cHdr)

    $cSub = New-Object System.Windows.Forms.Label
    $cSub.Text = "Changes take effect immediately. Restart required for some settings."
    $cSub.Location = New-Object System.Drawing.Point(20,44); $cSub.Size = New-Object System.Drawing.Size(480,18)
    $cSub.Font = $script:Fonts.Small; $cSub.ForeColor = [System.Drawing.Color]::FromArgb(90,90,115); $cF.Controls.Add($cSub)

    $fields = [ordered]@{
        ServerAddress        = @{ Label="Game Server IP/Host"; Tip="Target host for ping measurement" }
        ServerPort           = @{ Label="Server Port";          Tip="TCP port to connect to" }
        PingIntervalMin      = @{ Label="Min Ping Interval (ms)"; Tip="Fastest ping rate (1000=1s)" }
        PingIntervalMax      = @{ Label="Max Ping Interval (ms)"; Tip="Slowest rate when stable" }
        SpikeThreshold       = @{ Label="Spike Threshold (ms)";   Tip="Ping value considered a spike" }
        AlertHighPing        = @{ Label="High Ping Alert (ms)";   Tip="Balloon at this ping value" }
        AlertCriticalPing    = @{ Label="Critical Ping (ms)";     Tip="Triple alert at this value" }
        AdaptiveStableMaxPing= @{ Label="Adaptive Stable Max Ping";Tip="Max avg to call connection stable" }
        AdaptiveStableJitter = @{ Label="Adaptive Stable Jitter";  Tip="Max jitter to call stable" }
        AdaptiveStableWindow = @{ Label="Adaptive Window (pings)"; Tip="Pings needed to evaluate stability" }
    }

    $controls = @{}
    $y = 72
    foreach ($k in $fields.Keys) {
        $meta = $fields[$k]
        $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = $meta.Label + ":"
        $lbl.Location = New-Object System.Drawing.Point(20,$y); $lbl.Size = New-Object System.Drawing.Size(210,22)
        $lbl.Font = $script:Fonts.Small; $lbl.ForeColor = [System.Drawing.Color]::FromArgb(160,160,180)
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $cF.Controls.Add($lbl)

        $tb2 = New-Object System.Windows.Forms.TextBox; $tb2.Text = $CONFIG[$k].ToString()
        $tb2.Location = New-Object System.Drawing.Point(236,$y); $tb2.Size = New-Object System.Drawing.Size(160,24)
        $tb2.BackColor = [System.Drawing.Color]::FromArgb(28,28,40); $tb2.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
        $tb2.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $tb2.Font = $script:Fonts.Small
        $cF.Controls.Add($tb2); $controls[$k] = $tb2

        $tipLbl = New-Object System.Windows.Forms.Label; $tipLbl.Text = $meta.Tip
        $tipLbl.Location = New-Object System.Drawing.Point(404,$y); $tipLbl.Size = New-Object System.Drawing.Size(98,22)
        $tipLbl.Font = $script:Fonts.Micro; $tipLbl.ForeColor = [System.Drawing.Color]::FromArgb(60,65,85)
        $tipLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft; $cF.Controls.Add($tipLbl)
        $y += 34
    }

    $saveC = New-Object System.Windows.Forms.Button; $saveC.Text = "Save & Apply"
    $saveC.Location = New-Object System.Drawing.Point(20,474); $saveC.Size = New-Object System.Drawing.Size(160,38)
    $saveC.BackColor = [System.Drawing.Color]::FromArgb(45,175,80); $saveC.ForeColor = [System.Drawing.Color]::White
    $saveC.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $saveC.FlatAppearance.BorderSize = 0
    $saveC.Cursor = [System.Windows.Forms.Cursors]::Hand; $saveC.Font = $script:Fonts.Header
    $saveC.Add_Click({
        $errs = @()
        foreach ($k in $controls.Keys) {
            $val = $controls[$k].Text.Trim()
            if ($CONFIG[$k] -is [int]) {
                # FIX: Nur int-Felder mit int-Parse validieren (altes OR-Muster war fehlerhaft)
                $intVal = 0
                if ([int]::TryParse($val, [ref]$intVal)) { $CONFIG[$k] = $intVal }
                else { $errs += "$k (must be a number)" }
            } elseif ($CONFIG[$k] -is [string]) {
                # String-Felder: Direkt übernehmen (IP-Validation optional)
                if ($val.Length -gt 0) { $CONFIG[$k] = $val }
                else { $errs += "$k (cannot be empty)" }
            } else {
                try { $CONFIG[$k] = $val } catch { $errs += $k }
            }
        }
        $script:TargetIP         = $CONFIG.ServerAddress
        $script:activeServerPort = $CONFIG.ServerPort   # FIX: Port synchronisieren
        Save-Config
        Write-Log "Config updated via Editor" "INFO"
        if ($errs) { [System.Windows.Forms.MessageBox]::Show("Validation errors:`n• $($errs -join "`n• ")","Validation","OK","Warning") }
        else { $cF.Close() }
    })
    $cF.Controls.Add($saveC)

    $resetC = New-Object System.Windows.Forms.Button; $resetC.Text = "Reset Defaults"
    $resetC.Location = New-Object System.Drawing.Point(190,474); $resetC.Size = New-Object System.Drawing.Size(130,38)
    $resetC.BackColor = [System.Drawing.Color]::FromArgb(55,58,70); $resetC.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200)
    $resetC.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $resetC.FlatAppearance.BorderSize = 0
    $resetC.Cursor = [System.Windows.Forms.Cursors]::Hand; $resetC.Font = $script:Fonts.Small
    $resetC.Add_Click({
        $controls["SpikeThreshold"].Text     = "150"
        $controls["AlertHighPing"].Text      = "200"
        $controls["AlertCriticalPing"].Text  = "300"
        $controls["PingIntervalMin"].Text    = "1000"
        $controls["PingIntervalMax"].Text    = "5000"
    })
    $cF.Controls.Add($resetC)

    $cancelC = New-Object System.Windows.Forms.Button; $cancelC.Text = "Cancel"
    $cancelC.Location = New-Object System.Drawing.Point(390,474); $cancelC.Size = New-Object System.Drawing.Size(110,38)
    $cancelC.BackColor = [System.Drawing.Color]::FromArgb(55,58,70); $cancelC.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200)
    $cancelC.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cancelC.FlatAppearance.BorderSize = 0
    $cancelC.Cursor = [System.Windows.Forms.Cursors]::Hand; $cancelC.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cF.Controls.Add($cancelC); $cF.CancelButton = $cancelC
    $cF.ShowDialog() | Out-Null
    $cF.Dispose()
}

# ══════════════════════════════════════════════════════════════
# GRAPH PNG EXPORT — HUD-Graph als PNG speichern
# ══════════════════════════════════════════════════════════════
function Export-GraphPNG {
    # FIX: Null-Check — graphPanel existiert nur wenn HUD aktiv
    if (-not $script:graphPanel -or $script:graphPanel.IsDisposed -or
        $script:graphPanel.Width -lt 10 -or $script:graphPanel.Height -lt 10) {
        [System.Windows.Forms.MessageBox]::Show(
            "The HUD graph panel is not available.`nOpen the HUD first (Ctrl+Alt+P).",
            "Export Graph","OK","Warning")
        return
    }
    try {
        $bmp = New-Object System.Drawing.Bitmap($script:graphPanel.Width, $script:graphPanel.Height)
        $script:graphPanel.DrawToBitmap($bmp, [System.Drawing.Rectangle]::new(0, 0, $bmp.Width, $bmp.Height))
        $ts   = Get-Date -Format "yyyyMMdd_HHmmss"
        $name = "NetNinja_Graph_${ts}.png"
        # FIX: Fallback auf Desktop wenn scriptPath nicht beschreibbar
        $path = Join-Path $script:scriptPath $name
        if (-not (Test-Path (Split-Path $path))) {
            $path = Join-Path ([Environment]::GetFolderPath("Desktop")) $name
        }
        $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Add-TimelineEvent -Type "info" -Msg "Graph PNG saved: $name"
        Write-Log "Graph PNG exported: $path" "INFO"
        $trayIcon.ShowBalloonTip(3000,"📸 Graph Saved","Saved to: $path",[System.Windows.Forms.ToolTipIcon]::Info)
        Start-Process "explorer.exe" -ArgumentList "/select,`"$path`"" -ErrorAction SilentlyContinue
    } catch {
        Write-Log "PNG export failed: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Export failed:`n$_","Error","OK","Error")
    }
}


# ══════════════════════════════════════════════════════════════
# MINI-HUD — Kompakter 240x52px Modus, immer sichtbar
# ══════════════════════════════════════════════════════════════
$script:miniHUDActive = $false
$script:miniHUDForm   = $null

function Show-MiniHUD {
    if ($script:miniHUDForm -and -not $script:miniHUDForm.IsDisposed -and $script:miniHUDForm.Visible) { return }

    $mhF = New-Object System.Windows.Forms.Form
    $mhF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $mhF.TopMost = $true; $mhF.ShowInTaskbar = $false
    $mhF.Size = New-Object System.Drawing.Size(240, 52)
    $mhF.BackColor = [System.Drawing.Color]::FromArgb(10,10,16)
    $mhF.Opacity = 0.92
    $screen2 = [System.Windows.Forms.Screen]::PrimaryScreen
    $mhF.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $mhF.Location = New-Object System.Drawing.Point(($screen2.Bounds.Width - 252), 44)
    $script:miniHUDForm = $mhF

    # Ping-Zahl — FIX: Font aus Script-Fonts statt new Font
    $mhPing = New-Object System.Windows.Forms.Label
    $mhPing.Location = New-Object System.Drawing.Point(0,0)
    $mhPing.Size = New-Object System.Drawing.Size(128,52)
    $mhPing.Font = $script:Fonts.PingBig   # gecacht — kein new Font
    $mhPing.ForeColor = [System.Drawing.Color]::FromArgb(50,220,80)
    $mhPing.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $mhPing.BackColor = [System.Drawing.Color]::Transparent
    $mhPing.Text = "--"
    $mhF.Controls.Add($mhPing)

    # Stats rechts — FIX: $script:Fonts.MonoSm statt new Font
    $mhStats = New-Object System.Windows.Forms.Label
    $mhStats.Location = New-Object System.Drawing.Point(130,4)
    $mhStats.Size = New-Object System.Drawing.Size(106,44)
    $mhStats.Font = $script:Fonts.MonoSm   # gecacht
    $mhStats.ForeColor = [System.Drawing.Color]::FromArgb(80,90,110)
    $mhStats.BackColor = [System.Drawing.Color]::Transparent
    $mhStats.Text = "JIT --ms`nLOSS 0.0%`nMIN -- MAX --"
    $mhF.Controls.Add($mhStats)

    # Drag — FIX: DragOffset korrekt als Point, nicht als $null
    $script:mhDragPt = [System.Drawing.Point]::Empty
    $mhF.Add_MouseDown({
        param($s,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:mhDragPt = $e.Location
        }
    })
    $mhF.Add_MouseMove({
        param($s,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and
            $script:mhDragPt -ne [System.Drawing.Point]::Empty) {
            $mhF.Location = New-Object System.Drawing.Point(
                ($mhF.Location.X + $e.X - $script:mhDragPt.X),
                ($mhF.Location.Y + $e.Y - $script:mhDragPt.Y))
        }
    })
    $mhF.Add_MouseUp({ $script:mhDragPt = [System.Drawing.Point]::Empty })

    # Labels ebenfalls dragbar machen
    foreach ($ctrl in @($mhPing, $mhStats)) {
        $ctrl.Add_MouseDown({ param($s,$e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:mhDragPt = $e.Location }
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { Hide-MiniHUD }
        })
        $ctrl.Add_MouseMove({ param($s,$e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and
                $script:mhDragPt -ne [System.Drawing.Point]::Empty) {
                $mhF.Location = New-Object System.Drawing.Point(
                    ($mhF.Location.X + $e.X - $script:mhDragPt.X),
                    ($mhF.Location.Y + $e.Y - $script:mhDragPt.Y))
            }
        })
        $ctrl.Add_MouseUp({ $script:mhDragPt = [System.Drawing.Point]::Empty })
    }

    $script:miniHUDPingLabel  = $mhPing
    $script:miniHUDStatsLabel = $mhStats

    $mhF.Show()
    $script:miniHUDActive = $true
    Write-Log "Mini-HUD shown" "INFO"
    Add-TimelineEvent -Type "info" -Msg "Mini-HUD activated"
}

function Hide-MiniHUD {
    if ($script:miniHUDForm -and -not $script:miniHUDForm.IsDisposed) {
        $script:miniHUDForm.Hide()
        $script:miniHUDActive = $false
        $script:miniHUDPingLabel  = $null
        $script:miniHUDStatsLabel = $null
        Write-Log "Mini-HUD hidden" "INFO"
    }
}

function Toggle-MiniHUD {
    if ($script:miniHUDActive) { Hide-MiniHUD } else { Show-MiniHUD }
}

# ══════════════════════════════════════════════════════════════
# WEBHOOK ALERT — Sendet Alerts an Discord/Slack/Teams/Custom
# ══════════════════════════════════════════════════════════════
$script:webhookConfig = @{
    Enabled   = $false
    URL       = ""          # Webhook URL
    Type      = "discord"   # discord | slack | teams | generic
    OnHigh    = $true       # Sende bei High-Ping
    OnCritical= $true       # Sende bei Critical-Ping
    OnLoss    = $true       # Sende bei Packet Loss
    CooldownSec = 120       # Sekunden zwischen gleichen Webhooks
}
$script:webhookCooldown = @{ High=0; Critical=0; Loss=0 }

function Send-WebhookAlert {
    param([string]$Level, [string]$Message)
    if (-not $script:webhookConfig.Enabled) { return }
    # FIX: URL-Validation vor Nutzung
    $url = $script:webhookConfig.URL.Trim()
    if (-not $url -or $url -notmatch '^https?://') { return }

    $now = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $key = switch ($Level) { "high"{"High"}; "critical"{"Critical"}; "loss"{"Loss"}; default{"High"} }
    if (($now - $script:webhookCooldown[$key]) -lt $script:webhookConfig.CooldownSec) { return }
    $script:webhookCooldown[$key] = $now

    $wc = $null
    try {
        $color = switch ($Level) { "critical"{16711680}; "loss"{16711680}; "high"{16750848}; default{3394611} }
        $emoji = switch ($Level) { "critical"{"🔴"}; "loss"{"✖"}; "high"{"🟡"}; default{"ℹ"} }
        $ts    = Get-Date -Format "HH:mm:ss"
        $body  = switch ($script:webhookConfig.Type) {
            "discord" {
                @{ username="NetNinja"; content=$null
                   embeds=@(@{ title="$emoji NetNinja — $($Level.ToUpper())"
                               description=$Message; color=$color
                               footer=@{ text="NetNinja v$($CONFIG.Version) · $ts" }
                           }) } | ConvertTo-Json -Depth 6 -Compress
            }
            "slack" {
                @{ text="$emoji *NetNinja $($Level.ToUpper())*: $Message  _(${ts})_" } | ConvertTo-Json
            }
            "teams" {
                @{ "@type"="MessageCard"; "@context"="http://schema.org/extensions"
                   summary="NetNinja Alert"; themeColor=if($Level -eq "high"){"FF9900"} else {"FF0000"}
                   sections=@(@{ activityTitle="$emoji NetNinja Alert — $($Level.ToUpper())"
                                 activityText="$Message`n$ts" }) } | ConvertTo-Json -Depth 5 -Compress
            }
            default { @{ text="$emoji $Message"; level=$Level; time=$ts } | ConvertTo-Json }
        }
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("Content-Type","application/json")
        $wc.Headers.Add("User-Agent","NetNinja/$($CONFIG.Version)")
        $null = $wc.UploadString($url, "POST", $body)
        Write-Log "Webhook sent [$Level]: $Message" "INFO"
    } catch {
        Write-Log "Webhook failed [$Level]: $_" "WARNING"
    } finally {
        # FIX: WebClient immer disposed — auch bei Exception
        if ($wc) { try { $wc.Dispose() } catch { $null = $_ } }
    }
}

function Show-WebhookSettings {
    $wF = New-Object System.Windows.Forms.Form
    $wF.Text = "Webhook Alert Settings — NetNinja v5.0"
    $wF.Size = New-Object System.Drawing.Size(540,440); $wF.MinimumSize = $wF.MaximumSize = $wF.Size
    $wF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $wF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $wF.MaximizeBox = $false; $wF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
    $wF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $wHdr = New-Object System.Windows.Forms.Label; $wHdr.Text = "🔗  Webhook Alerts"
    $wHdr.Location = New-Object System.Drawing.Point(20,14); $wHdr.Size = New-Object System.Drawing.Size(500,28)
    $wHdr.Font = $script:Fonts.Title; $wHdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220); $wF.Controls.Add($wHdr)

    $wSub = New-Object System.Windows.Forms.Label
    $wSub.Text = "Send alerts to Discord, Slack, Teams or any webhook endpoint"
    $wSub.Location = New-Object System.Drawing.Point(20,44); $wSub.Size = New-Object System.Drawing.Size(500,18)
    $wSub.Font = $script:Fonts.Small; $wSub.ForeColor = [System.Drawing.Color]::FromArgb(90,90,115); $wF.Controls.Add($wSub)

    $mkL4 = { param($t,$x,$y,$w=120) $l=New-Object System.Windows.Forms.Label; $l.Text=$t; $l.Location=New-Object System.Drawing.Point($x,$y); $l.Size=New-Object System.Drawing.Size($w,22); $l.Font=$script:Fonts.Small; $l.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165); $wF.Controls.Add($l) }
    & $mkL4 "Webhook URL:" 20 76; & $mkL4 "Service type:" 20 108; & $mkL4 "Cooldown (s):" 20 140

    $tbURL = New-Object System.Windows.Forms.TextBox; $tbURL.Location=New-Object System.Drawing.Point(148,74); $tbURL.Size=New-Object System.Drawing.Size(368,24); $tbURL.Text=$script:webhookConfig.URL; $tbURL.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $tbURL.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $tbURL.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $tbURL.Font=$script:Fonts.Small; $wF.Controls.Add($tbURL)

    $cmbType = New-Object System.Windows.Forms.ComboBox; $cmbType.Location=New-Object System.Drawing.Point(148,106); $cmbType.Size=New-Object System.Drawing.Size(150,24); $cmbType.Font=$script:Fonts.Small; $cmbType.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $cmbType.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $cmbType.DropDownStyle=[System.Windows.Forms.ComboBoxStyle]::DropDownList; @("discord","slack","teams","generic")|ForEach-Object{$null=$cmbType.Items.Add($_)}; $cmbType.SelectedItem=$script:webhookConfig.Type; $wF.Controls.Add($cmbType)

    $numWCD = New-Object System.Windows.Forms.NumericUpDown; $numWCD.Location=New-Object System.Drawing.Point(148,138); $numWCD.Size=New-Object System.Drawing.Size(80,24); $numWCD.Minimum=10; $numWCD.Maximum=86400; $numWCD.Value=$script:webhookConfig.CooldownSec; $numWCD.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $numWCD.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $wF.Controls.Add($numWCD)

    $sep2 = New-Object System.Windows.Forms.Label; $sep2.Location=New-Object System.Drawing.Point(20,174); $sep2.Size=New-Object System.Drawing.Size(496,2); $sep2.BackColor=[System.Drawing.Color]::FromArgb(38,40,52); $wF.Controls.Add($sep2)

    $chkWEn  = New-Object System.Windows.Forms.CheckBox; $chkWEn.Text="Enable webhook alerts"; $chkWEn.Location=New-Object System.Drawing.Point(20,184); $chkWEn.Size=New-Object System.Drawing.Size(300,22); $chkWEn.Font=$script:Fonts.Small; $chkWEn.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $chkWEn.BackColor=[System.Drawing.Color]::Transparent; $chkWEn.Checked=$script:webhookConfig.Enabled; $wF.Controls.Add($chkWEn)
    $chkWH   = New-Object System.Windows.Forms.CheckBox; $chkWH.Text="Alert on High Ping"; $chkWH.Location=New-Object System.Drawing.Point(30,212); $chkWH.Size=New-Object System.Drawing.Size(200,22); $chkWH.Font=$script:Fonts.Small; $chkWH.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $chkWH.BackColor=[System.Drawing.Color]::Transparent; $chkWH.Checked=$script:webhookConfig.OnHigh; $wF.Controls.Add($chkWH)
    $chkWC   = New-Object System.Windows.Forms.CheckBox; $chkWC.Text="Alert on Critical Ping"; $chkWC.Location=New-Object System.Drawing.Point(30,236); $chkWC.Size=New-Object System.Drawing.Size(200,22); $chkWC.Font=$script:Fonts.Small; $chkWC.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $chkWC.BackColor=[System.Drawing.Color]::Transparent; $chkWC.Checked=$script:webhookConfig.OnCritical; $wF.Controls.Add($chkWC)
    $chkWL   = New-Object System.Windows.Forms.CheckBox; $chkWL.Text="Alert on Packet Loss"; $chkWL.Location=New-Object System.Drawing.Point(30,260); $chkWL.Size=New-Object System.Drawing.Size(200,22); $chkWL.Font=$script:Fonts.Small; $chkWL.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $chkWL.BackColor=[System.Drawing.Color]::Transparent; $chkWL.Checked=$script:webhookConfig.OnLoss; $wF.Controls.Add($chkWL)

    $hintL = New-Object System.Windows.Forms.Label
    $hintL.Text = "Discord: Server Settings → Integrations → New Webhook → Copy URL`nSlack: api.slack.com/apps → Incoming Webhooks → Add`nTeams: Channel → ... → Connectors → Incoming Webhook"
    $hintL.Location=New-Object System.Drawing.Point(20,292); $hintL.Size=New-Object System.Drawing.Size(496,50)
    $hintL.Font=$script:Fonts.Tiny; $hintL.ForeColor=[System.Drawing.Color]::FromArgb(65,70,90); $wF.Controls.Add($hintL)

    $testW = New-Object System.Windows.Forms.Button; $testW.Text="▶ Test"; $testW.Location=New-Object System.Drawing.Point(20,358); $testW.Size=New-Object System.Drawing.Size(90,34); $testW.BackColor=[System.Drawing.Color]::FromArgb(0,130,210); $testW.ForeColor=[System.Drawing.Color]::White; $testW.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $testW.FlatAppearance.BorderSize=0; $testW.Cursor=[System.Windows.Forms.Cursors]::Hand; $testW.Font=$script:Fonts.Small
    $testW.Add_Click({
        $script:webhookConfig.URL=$tbURL.Text.Trim(); $script:webhookConfig.Type=$cmbType.SelectedItem
        $script:webhookConfig.Enabled=$true
        $script:webhookCooldown=@{High=0;Critical=0;Loss=0}
        Send-WebhookAlert -Level "info" -Message "Test alert from NetNinja v$($CONFIG.Version) — connection OK"
        [System.Windows.Forms.MessageBox]::Show("Test sent — check your channel.","Test Webhook")
    })
    $wF.Controls.Add($testW)

    $saveW = New-Object System.Windows.Forms.Button; $saveW.Text="Save"; $saveW.Location=New-Object System.Drawing.Point(310,358); $saveW.Size=New-Object System.Drawing.Size(100,34); $saveW.BackColor=[System.Drawing.Color]::FromArgb(45,175,80); $saveW.ForeColor=[System.Drawing.Color]::White; $saveW.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $saveW.FlatAppearance.BorderSize=0; $saveW.Cursor=[System.Windows.Forms.Cursors]::Hand; $saveW.Font=$script:Fonts.Small
    $saveW.Add_Click({
        $script:webhookConfig.Enabled=$chkWEn.Checked; $script:webhookConfig.URL=$tbURL.Text.Trim()
        $script:webhookConfig.Type=$cmbType.SelectedItem; $script:webhookConfig.CooldownSec=[int]$numWCD.Value
        $script:webhookConfig.OnHigh=$chkWH.Checked; $script:webhookConfig.OnCritical=$chkWC.Checked; $script:webhookConfig.OnLoss=$chkWL.Checked
        Write-Log "Webhook config saved: enabled=$($script:webhookConfig.Enabled) type=$($script:webhookConfig.Type)" "INFO"; $wF.Close()
    })
    $wF.Controls.Add($saveW)

    $closeW = New-Object System.Windows.Forms.Button; $closeW.Text="Cancel"; $closeW.Location=New-Object System.Drawing.Point(420,358); $closeW.Size=New-Object System.Drawing.Size(100,34); $closeW.BackColor=[System.Drawing.Color]::FromArgb(55,58,70); $closeW.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200); $closeW.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $closeW.FlatAppearance.BorderSize=0; $closeW.Cursor=[System.Windows.Forms.Cursors]::Hand; $closeW.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $wF.Controls.Add($closeW); $wF.CancelButton=$closeW
    $wF.ShowDialog() | Out-Null
    $wF.Dispose()
}

# ══════════════════════════════════════════════════════════════
# FIRST-RUN ONBOARDING WIZARD
# ══════════════════════════════════════════════════════════════
$script:firstRunFile = Join-Path $script:scriptPath ".netninja_setup_done"

function Show-OnboardingWizard {
    $oF = New-Object System.Windows.Forms.Form
    $oF.Text = "Welcome to NetNinja v5.0"; $oF.Size = New-Object System.Drawing.Size(560,440)
    $oF.MinimumSize = $oF.MaximumSize = $oF.Size
    $oF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $oF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $oF.MaximizeBox = $false; $oF.BackColor = [System.Drawing.Color]::FromArgb(14,16,24)
    $oF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $step = 0
    $steps = @("welcome","server","profile","done")

    # Header
    $oHdr = New-Object System.Windows.Forms.Label; $oHdr.Location=New-Object System.Drawing.Point(0,0); $oHdr.Size=New-Object System.Drawing.Size(560,70); $oHdr.BackColor=[System.Drawing.Color]::FromArgb(0,80,150)
    $oF.Controls.Add($oHdr)
    $oLogo = New-Object System.Windows.Forms.Label; $oLogo.Text="🥷 NetNinja"; $oLogo.Location=New-Object System.Drawing.Point(20,10); $oLogo.Size=New-Object System.Drawing.Size(300,28); $oLogo.Font=$script:Fonts.Title; $oLogo.ForeColor=[System.Drawing.Color]::White; $oLogo.BackColor=[System.Drawing.Color]::Transparent; $oF.Controls.Add($oLogo)
    $oStepLbl = New-Object System.Windows.Forms.Label; $oStepLbl.Text="Step 1 of 3"; $oStepLbl.Location=New-Object System.Drawing.Point(430,15); $oStepLbl.Size=New-Object System.Drawing.Size(110,20); $oStepLbl.Font=$script:Fonts.Small; $oStepLbl.ForeColor=[System.Drawing.Color]::FromArgb(180,220,255); $oStepLbl.BackColor=[System.Drawing.Color]::Transparent; $oF.Controls.Add($oStepLbl)
    $oSubHdr = New-Object System.Windows.Forms.Label; $oSubHdr.Text="Network Performance Monitor"; $oSubHdr.Location=New-Object System.Drawing.Point(20,40); $oSubHdr.Size=New-Object System.Drawing.Size(400,20); $oSubHdr.Font=$script:Fonts.Small; $oSubHdr.ForeColor=[System.Drawing.Color]::FromArgb(160,200,240); $oSubHdr.BackColor=[System.Drawing.Color]::Transparent; $oF.Controls.Add($oSubHdr)

    # Content area
    $oCont = New-Object System.Windows.Forms.Panel; $oCont.Location=New-Object System.Drawing.Point(20,82); $oCont.Size=New-Object System.Drawing.Size(520,290); $oCont.BackColor=[System.Drawing.Color]::Transparent; $oF.Controls.Add($oCont)

    $oNext = New-Object System.Windows.Forms.Button; $oNext.Text="Next  →"; $oNext.Location=New-Object System.Drawing.Point(340,392); $oNext.Size=New-Object System.Drawing.Size(120,36); $oNext.BackColor=[System.Drawing.Color]::FromArgb(0,130,210); $oNext.ForeColor=[System.Drawing.Color]::White; $oNext.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $oNext.FlatAppearance.BorderSize=0; $oNext.Cursor=[System.Windows.Forms.Cursors]::Hand; $oNext.Font=$script:Fonts.Header; $oF.Controls.Add($oNext)
    $oSkip = New-Object System.Windows.Forms.Button; $oSkip.Text="Skip"; $oSkip.Location=New-Object System.Drawing.Point(100,392); $oSkip.Size=New-Object System.Drawing.Size(90,36); $oSkip.BackColor=[System.Drawing.Color]::FromArgb(40,42,55); $oSkip.ForeColor=[System.Drawing.Color]::FromArgb(130,130,155); $oSkip.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $oSkip.FlatAppearance.BorderSize=0; $oSkip.Cursor=[System.Windows.Forms.Cursors]::Hand; $oSkip.Font=$script:Fonts.Small; $oF.Controls.Add($oSkip)
    $oSkip.Add_Click({ New-Item $script:firstRunFile -Force | Out-Null; $oF.Close() })

    $oTbServer = $null; $oTbPort = $null

    $renderStep = {
        $oCont.Controls.Clear()
        $y2 = 0
        switch ($steps[$step]) {
            "welcome" {
                $oStepLbl.Text = "Step 1 of 3"; $oNext.Text = "Let's Go  →"
                $bullets = @("✔  Real-time TCP ping with multi-target support","✔  Auto-profile switching for 43+ games","✔  Rules Engine, Webhooks & Discord Presence","✔  ISP Speed Test & Auto-Diagnosis","✔  Live browser dashboard & HTML reports")
                $l = New-Object System.Windows.Forms.Label; $l.Text = "Welcome! NetNinja monitors your game server connection and alerts you to issues before they ruin your match."; $l.Location=New-Object System.Drawing.Point(0,0); $l.Size=New-Object System.Drawing.Size(520,46); $l.Font=$script:Fonts.Small; $l.ForeColor=[System.Drawing.Color]::FromArgb(190,190,210); $oCont.Controls.Add($l); $y2=56
                foreach ($b in $bullets) { $bl=New-Object System.Windows.Forms.Label; $bl.Text=$b; $bl.Location=New-Object System.Drawing.Point(10,$y2); $bl.Size=New-Object System.Drawing.Size(500,24); $bl.Font=$script:Fonts.Small; $bl.ForeColor=[System.Drawing.Color]::FromArgb(80,210,110); $oCont.Controls.Add($bl); $y2+=26 }
            }
            "server" {
                $oStepLbl.Text = "Step 2 of 3"; $oNext.Text = "Next  →"
                $l=New-Object System.Windows.Forms.Label; $l.Text="Enter the game server address to monitor:"; $l.Location=New-Object System.Drawing.Point(0,0); $l.Size=New-Object System.Drawing.Size(520,22); $l.Font=$script:Fonts.Small; $l.ForeColor=[System.Drawing.Color]::FromArgb(190,190,210); $oCont.Controls.Add($l)
                $lIP=New-Object System.Windows.Forms.Label; $lIP.Text="Server IP / Host:"; $lIP.Location=New-Object System.Drawing.Point(0,38); $lIP.Size=New-Object System.Drawing.Size(140,22); $lIP.Font=$script:Fonts.Small; $lIP.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165); $oCont.Controls.Add($lIP)
                $oTbServer=New-Object System.Windows.Forms.TextBox; $oTbServer.Location=New-Object System.Drawing.Point(150,36); $oTbServer.Size=New-Object System.Drawing.Size(260,24); $oTbServer.Text=$CONFIG.ServerAddress; $oTbServer.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $oTbServer.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $oTbServer.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $oTbServer.Font=$script:Fonts.Small; $oCont.Controls.Add($oTbServer)
                $lPt=New-Object System.Windows.Forms.Label; $lPt.Text="Port:"; $lPt.Location=New-Object System.Drawing.Point(0,70); $lPt.Size=New-Object System.Drawing.Size(140,22); $lPt.Font=$script:Fonts.Small; $lPt.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165); $oCont.Controls.Add($lPt)
                $oTbPort=New-Object System.Windows.Forms.TextBox; $oTbPort.Location=New-Object System.Drawing.Point(150,68); $oTbPort.Size=New-Object System.Drawing.Size(100,24); $oTbPort.Text=$CONFIG.ServerPort.ToString(); $oTbPort.BackColor=[System.Drawing.Color]::FromArgb(28,28,40); $oTbPort.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $oTbPort.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $oTbPort.Font=$script:Fonts.Small; $oCont.Controls.Add($oTbPort)
                $hint2=New-Object System.Windows.Forms.Label; $hint2.Text="Tip: Use your game server's login server IP. Port 80 works for basic connectivity tests."; $hint2.Location=New-Object System.Drawing.Point(0,106); $hint2.Size=New-Object System.Drawing.Size(510,36); $hint2.Font=$script:Fonts.Tiny; $hint2.ForeColor=[System.Drawing.Color]::FromArgb(70,75,95); $oCont.Controls.Add($hint2)
            }
            "profile" {
                $oStepLbl.Text = "Step 3 of 3"; $oNext.Text = "Start Monitoring  →"
                $l=New-Object System.Windows.Forms.Label; $l.Text="Choose a starting profile (you can change this anytime):"; $l.Location=New-Object System.Drawing.Point(0,0); $l.Size=New-Object System.Drawing.Size(520,22); $l.Font=$script:Fonts.Small; $l.ForeColor=[System.Drawing.Color]::FromArgb(190,190,210); $oCont.Controls.Add($l)
                $profs = @(
                    @{N="MMO";     D="Best for MMORPGs: low jitter, stable connection, higher ping tolerance"}
                    @{N="FPS";     D="Competitive: lowest latency, aggressive tuning, instant alerts"}
                    @{N="Analysis";D="Testing mode: logs everything, no alerts, maximum data collection"}
                    @{N="Silent";  D="Background monitoring: no sounds, no balloons, system stays clean"}
                )
                $y3=34
                foreach ($p in $profs) {
                    $rb=New-Object System.Windows.Forms.RadioButton; $rb.Text="$($p.N) — $($p.D)"; $rb.Location=New-Object System.Drawing.Point(8,$y3); $rb.Size=New-Object System.Drawing.Size(504,26); $rb.Font=$script:Fonts.Small; $rb.ForeColor=[System.Drawing.Color]::FromArgb(190,190,210); $rb.BackColor=[System.Drawing.Color]::Transparent; $rb.Tag=$p.N; if($p.N -eq $script:currentProfile){$rb.Checked=$true}; $oCont.Controls.Add($rb); $y3+=30
                }
            }
            "done" {
                $oNext.Text = "Finish"
                $dl=New-Object System.Windows.Forms.Label; $dl.Text="✅  NetNinja is ready!`n`nYour HUD will appear shortly. Right-click the tray icon for all features.`n`nKey shortcuts:`n  Ctrl+Alt+P  →  Toggle HUD`n  Ctrl+Alt+O  →  Overlay Mode`n  Ctrl+Alt+H  →  Export Report`n  Ctrl+Alt+R  →  Reset Stats"; $dl.Location=New-Object System.Drawing.Point(0,0); $dl.Size=New-Object System.Drawing.Size(520,200); $dl.Font=$script:Fonts.Small; $dl.ForeColor=[System.Drawing.Color]::FromArgb(80,210,110); $oCont.Controls.Add($dl)
            }
        }
    }
    & $renderStep

    $oNext.Add_Click({
        # Daten übernehmen
        if ($steps[$step] -eq "server" -and $oTbServer) {
            if ($oTbServer.Text.Trim()) { $CONFIG.ServerAddress=$oTbServer.Text.Trim(); $script:TargetIP=$CONFIG.ServerAddress }
            $portV=0; if ([int]::TryParse($oTbPort.Text,[ref]$portV) -and $portV -gt 0) { $CONFIG.ServerPort=$portV }
        }
        if ($steps[$step] -eq "profile") {
            foreach ($rb3 in $oCont.Controls | Where-Object { $_ -is [System.Windows.Forms.RadioButton] -and $_.Checked }) {
                Switch-Profile -ProfileName $rb3.Tag
            }
        }
        if ($step -ge $steps.Count - 1) {
            New-Item $script:firstRunFile -Force | Out-Null; Save-Config; $oF.Close(); return
        }
        $script:step = $step + 1; $step = $script:step
        & $renderStep
    })

    $oF.ShowDialog() | Out-Null
    $oF.Dispose()
}

# ══════════════════════════════════════════════════════════════
# KEYBOARD SHORTCUT MAP
# ══════════════════════════════════════════════════════════════
function Show-ShortcutMap {
    $kF = New-Object System.Windows.Forms.Form
    $kF.Text = "Keyboard Shortcuts — NetNinja v5.0"; $kF.Size = New-Object System.Drawing.Size(480,440)
    $kF.MinimumSize = $kF.MaximumSize = $kF.Size
    $kF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $kF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $kF.MaximizeBox = $false; $kF.BackColor = [System.Drawing.Color]::FromArgb(14,14,20)
    $kF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $kHdr = New-Object System.Windows.Forms.Label; $kHdr.Text = "⌨  Keyboard Shortcuts"
    $kHdr.Location = New-Object System.Drawing.Point(20,14); $kHdr.Size = New-Object System.Drawing.Size(440,28)
    $kHdr.Font = $script:Fonts.Title; $kHdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220); $kF.Controls.Add($kHdr)

    $shortcuts = @(
        @(" GLOBAL HOTKEYS", "",                                   $true)
        @("Ctrl + Alt + P",  "Toggle HUD show/hide",               $false)
        @("Ctrl + Alt + O",  "Toggle Overlay Mode (fullscreen)",    $false)
        @("Ctrl + Alt + R",  "Reset statistics",                    $false)
        @("Ctrl + Alt + M",  "Open MTU Optimizer",                  $false)
        @("Ctrl + Alt + S",  "Save config",                         $false)
        @("Ctrl + Alt + H",  "Export HTML report",                  $false)
        @("",                "",                                    $true )
        @(" TRAY MENU",      "",                                    $true )
        @("Left click",      "Show/hide HUD",                       $false)
        @("Right click",     "Open full menu",                      $false)
        @("",                "",                                    $true )
        @(" HUD CONTROLS",   "",                                    $true )
        @("⏸ button",        "Pause / resume monitoring",           $false)
        @("✕ button",        "Hide HUD (stays in tray)",            $false)
        @("Right-click graph","Reset statistics menu",              $false)
        @("Hover over graph","Crosshair + ping value at cursor",    $false)
        @("",                "",                                    $true )
        @(" MINI-HUD",       "",                                    $true )
        @("Right-click",     "Close Mini-HUD",                      $false)
        @("Drag",            "Move Mini-HUD position",              $false)
    )

    $y4 = 50
    foreach ($s in $shortcuts) {
        if ($s[2]) {
            if ($s[0]) {
                $sl = New-Object System.Windows.Forms.Label; $sl.Text = $s[0]
                $sl.Location=New-Object System.Drawing.Point(16,$y4); $sl.Size=New-Object System.Drawing.Size(446,22)
                $sl.Font=$script:Fonts.HeaderSm   # FIX: gecacht
                $sl.ForeColor=[System.Drawing.Color]::FromArgb(0,130,210); $sl.BackColor=[System.Drawing.Color]::FromArgb(16,22,32); $kF.Controls.Add($sl); $y4+=24
            } else { $y4+=6 }
            continue
        }
        $kLbl = New-Object System.Windows.Forms.Label; $kLbl.Text = $s[0]
        $kLbl.Location=New-Object System.Drawing.Point(30,$y4); $kLbl.Size=New-Object System.Drawing.Size(170,20)
        $kLbl.Font=$script:Fonts.MonoSm   # FIX: gecacht (Consolas statt new Font)
        $kLbl.ForeColor=[System.Drawing.Color]::FromArgb(180,220,180); $kF.Controls.Add($kLbl)
        $vLbl = New-Object System.Windows.Forms.Label; $vLbl.Text = $s[1]
        $vLbl.Location=New-Object System.Drawing.Point(210,$y4); $vLbl.Size=New-Object System.Drawing.Size(250,20)
        $vLbl.Font=$script:Fonts.Small; $vLbl.ForeColor=[System.Drawing.Color]::FromArgb(160,160,180); $kF.Controls.Add($vLbl)
        $y4 += 20
    }

    $kClose = New-Object System.Windows.Forms.Button; $kClose.Text="Close"
    $kClose.Location=New-Object System.Drawing.Point(360,392); $kClose.Size=New-Object System.Drawing.Size(100,32)
    $kClose.BackColor=[System.Drawing.Color]::FromArgb(55,58,70); $kClose.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200)
    $kClose.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $kClose.FlatAppearance.BorderSize=0
    $kClose.Cursor=[System.Windows.Forms.Cursors]::Hand; $kClose.DialogResult=[System.Windows.Forms.DialogResult]::OK; $kF.Controls.Add($kClose); $kF.AcceptButton=$kClose
    $kF.ShowDialog() | Out-Null
    $kF.Dispose()
}

function Show-MultiTargetManager {
    $mF = New-Object System.Windows.Forms.Form
    $mF.Text = "Multi-Target Ping Manager"; $mF.Size = New-Object System.Drawing.Size(620, 540)
    $mF.MinimumSize = $mF.MaximumSize = $mF.Size
    $mF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $mF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $mF.MaximizeBox = $false; $mF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)
    $mF.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228)

    $mTitle = New-Object System.Windows.Forms.Label
    $mTitle.Text = "Multi-Target Ping  v5.0"; $mTitle.Location = New-Object System.Drawing.Point(20,14)
    $mTitle.Size = New-Object System.Drawing.Size(400,28); $mTitle.Font = $script:Fonts.Title
    $mTitle.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220); $mF.Controls.Add($mTitle)

    $mSub = New-Object System.Windows.Forms.Label
    $mSub.Text = "Ping up to 8 targets simultaneously — each shown in the HUD graph"
    $mSub.Location = New-Object System.Drawing.Point(20,44); $mSub.Size = New-Object System.Drawing.Size(580,18)
    $mSub.Font = $script:Fonts.Small; $mSub.ForeColor = [System.Drawing.Color]::FromArgb(90,90,115)
    $mF.Controls.Add($mSub)

    # ListView for targets
    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(20,70); $lv.Size = New-Object System.Drawing.Size(578,280)
    $lv.View = [System.Windows.Forms.View]::Details; $lv.FullRowSelect = $true; $lv.GridLines = $true
    $lv.BackColor = [System.Drawing.Color]::FromArgb(14,14,20); $lv.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $lv.BorderStyle = [System.Windows.Forms.BorderStyle]::None; $lv.Font = $script:Fonts.Small
    $null = $lv.Columns.Add("#", 30); $null = $lv.Columns.Add("Label", 120)
    $null = $lv.Columns.Add("Host:Port", 200); $null = $lv.Columns.Add("Last Ping", 80); $null = $lv.Columns.Add("Status", 120)
    $mF.Controls.Add($lv)

    $refreshLv = {
        $lv.Items.Clear()
        for ($i=0; $i -lt $script:multiTargets.Count; $i++) {
            $t = $script:multiTargets[$i]
            $status = if (-not $t.Enabled) { "Disabled" } elseif ($t.LastMs -lt 0) { "Timeout" } elseif ($t.LastMs -eq 0) { "Not tested" } else { "$($t.LastMs)ms" }
            $itm = New-Object System.Windows.Forms.ListViewItem(($i+1).ToString())
            $null = $itm.SubItems.Add($t.Label); $null = $itm.SubItems.Add("$($t.Host):$($t.Port)")
            $null = $itm.SubItems.Add($status); $null = $itm.SubItems.Add($(if ($t.Enabled){"● Active"} else {"○ Off"}))
            $itm.ForeColor = $t.Color; $lv.Items.Add($itm) | Out-Null
        }
    }
    & $refreshLv

    # Add row
    $mkLbl = { param($txt,$x,$y) $l=New-Object System.Windows.Forms.Label; $l.Text=$txt; $l.Location=New-Object System.Drawing.Point($x,$y); $l.Size=New-Object System.Drawing.Size(70,22); $l.Font=$script:Fonts.Small; $l.ForeColor=[System.Drawing.Color]::FromArgb(140,140,165); $mF.Controls.Add($l) }
    & $mkLbl "Label:"   20  364; & $mkLbl "Host/IP:" 110 364; & $mkLbl "Port:" 310 364
    $tbLabel = New-Object System.Windows.Forms.TextBox; $tbLabel.Location=New-Object System.Drawing.Point(20,384); $tbLabel.Size=New-Object System.Drawing.Size(82,24); $tbLabel.Text="Server 1"; $tbLabel.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $tbLabel.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $tbLabel.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $mF.Controls.Add($tbLabel)
    $tbHost = New-Object System.Windows.Forms.TextBox; $tbHost.Location=New-Object System.Drawing.Point(110,384); $tbHost.Size=New-Object System.Drawing.Size(192,24); $tbHost.Text="8.8.8.8"; $tbHost.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $tbHost.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $tbHost.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle; $mF.Controls.Add($tbHost)
    $numPort = New-Object System.Windows.Forms.NumericUpDown; $numPort.Location=New-Object System.Drawing.Point(310,384); $numPort.Size=New-Object System.Drawing.Size(80,24); $numPort.Minimum=1; $numPort.Maximum=65535; $numPort.Value=80; $numPort.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $numPort.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $mF.Controls.Add($numPort)

    $palette = @([System.Drawing.Color]::FromArgb(50,220,80),[System.Drawing.Color]::FromArgb(0,180,255),[System.Drawing.Color]::FromArgb(255,200,0),[System.Drawing.Color]::FromArgb(255,100,100),[System.Drawing.Color]::FromArgb(200,100,255),[System.Drawing.Color]::FromArgb(255,165,0),[System.Drawing.Color]::FromArgb(0,220,200),[System.Drawing.Color]::FromArgb(255,80,180))

    $addBtn = New-Object System.Windows.Forms.Button; $addBtn.Text="+ Add"; $addBtn.Location=New-Object System.Drawing.Point(400,382); $addBtn.Size=New-Object System.Drawing.Size(80,28); $addBtn.BackColor=[System.Drawing.Color]::FromArgb(0,130,210); $addBtn.ForeColor=[System.Drawing.Color]::White; $addBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $addBtn.FlatAppearance.BorderSize=0; $addBtn.Cursor=[System.Windows.Forms.Cursors]::Hand; $addBtn.Font=$script:Fonts.Small
    $addBtn.Add_Click({
        if ($script:multiTargets.Count -ge 8) { [System.Windows.Forms.MessageBox]::Show("Maximum 8 targets","Limit"); return }
        if (-not $tbHost.Text.Trim()) { return }
        $col = $palette[$script:multiTargets.Count % $palette.Count]
        Add-PingTarget -TargetHost $tbHost.Text.Trim() -Port ([int]$numPort.Value) -Label $tbLabel.Text.Trim() -Color $col
        $tbLabel.Text = "Server " + ($script:multiTargets.Count+1); $tbHost.Text = ""
        & $refreshLv
    })
    $mF.Controls.Add($addBtn)

    $delBtn = New-Object System.Windows.Forms.Button; $delBtn.Text="✕ Remove"; $delBtn.Location=New-Object System.Drawing.Point(490,382); $delBtn.Size=New-Object System.Drawing.Size(108,28); $delBtn.BackColor=[System.Drawing.Color]::FromArgb(160,40,40); $delBtn.ForeColor=[System.Drawing.Color]::White; $delBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $delBtn.FlatAppearance.BorderSize=0; $delBtn.Cursor=[System.Windows.Forms.Cursors]::Hand; $delBtn.Font=$script:Fonts.Small
    $delBtn.Add_Click({
        if ($lv.SelectedIndices.Count -eq 0) { return }
        $idx = $lv.SelectedIndices[0]
        if ($idx -lt $script:multiTargets.Count) { $script:multiTargets.RemoveAt($idx) }
        & $refreshLv
    })
    $mF.Controls.Add($delBtn)

    # Enable toggle
    $chkMulti = New-Object System.Windows.Forms.CheckBox; $chkMulti.Text="Enable Multi-Target Mode (replaces single-server ping in HUD graph)"; $chkMulti.Location=New-Object System.Drawing.Point(20,420); $chkMulti.Size=New-Object System.Drawing.Size(578,22); $chkMulti.Font=$script:Fonts.Small; $chkMulti.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $chkMulti.BackColor=[System.Drawing.Color]::Transparent; $chkMulti.Checked=$script:multiPingEnabled; $mF.Controls.Add($chkMulti)

    # Preset quick-add
    $presetBtn = New-Object System.Windows.Forms.Button; $presetBtn.Text="Load Presets"; $presetBtn.Location=New-Object System.Drawing.Point(20,448); $presetBtn.Size=New-Object System.Drawing.Size(120,30); $presetBtn.BackColor=[System.Drawing.Color]::FromArgb(55,58,70); $presetBtn.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200); $presetBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $presetBtn.FlatAppearance.BorderSize=0; $presetBtn.Cursor=[System.Windows.Forms.Cursors]::Hand; $presetBtn.Font=$script:Fonts.Small
    $presetBtn.Add_Click({
        $presets = @(
            @{L="Cloudflare DNS"; H="1.1.1.1";    P=80};  @{L="Google DNS";    H="8.8.8.8";    P=80}
            @{L="Game Server";    H=$CONFIG.ServerAddress; P=$CONFIG.ServerPort}
            @{L="Local Router";   H="192.168.1.1"; P=80}
        )
        foreach ($p in $presets) {
            if ($script:multiTargets.Count -ge 8) { break }
            $col = $palette[$script:multiTargets.Count % $palette.Count]
            Add-PingTarget -TargetHost $p.H -Port $p.P -Label $p.L -Color $col
        }
        & $refreshLv
    })
    $mF.Controls.Add($presetBtn)

    $saveBtn = New-Object System.Windows.Forms.Button; $saveBtn.Text="Save & Close"; $saveBtn.Location=New-Object System.Drawing.Point(390,448); $saveBtn.Size=New-Object System.Drawing.Size(120,30); $saveBtn.BackColor=[System.Drawing.Color]::FromArgb(45,175,80); $saveBtn.ForeColor=[System.Drawing.Color]::White; $saveBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $saveBtn.FlatAppearance.BorderSize=0; $saveBtn.Cursor=[System.Windows.Forms.Cursors]::Hand; $saveBtn.Font=$script:Fonts.Small
    $saveBtn.Add_Click({ $script:multiPingEnabled = $chkMulti.Checked; Write-Log "Multi-target: $($script:multiTargets.Count) targets, enabled=$($script:multiPingEnabled)" "INFO"; $mF.Close() })
    $mF.Controls.Add($saveBtn)

    $clsBtn = New-Object System.Windows.Forms.Button; $clsBtn.Text="Cancel"; $clsBtn.Location=New-Object System.Drawing.Point(520,448); $clsBtn.Size=New-Object System.Drawing.Size(78,30); $clsBtn.BackColor=[System.Drawing.Color]::FromArgb(55,58,70); $clsBtn.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200); $clsBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $clsBtn.FlatAppearance.BorderSize=0; $clsBtn.Cursor=[System.Windows.Forms.Cursors]::Hand; $clsBtn.DialogResult=[System.Windows.Forms.DialogResult]::Cancel; $mF.Controls.Add($clsBtn); $mF.CancelButton=$clsBtn
    $mF.ShowDialog() | Out-Null
    $mF.Dispose()
}

# Ping Graph Variables
$script:pingHistory = New-Object System.Collections.Generic.Queue[int]
$script:maxHistorySize = 60
$script:graphPanel = $null

# Extended Graph - Multi-Timeframe
$script:pingHistory5min = New-Object System.Collections.Generic.List[int]
$script:pingHistory30min = New-Object System.Collections.Generic.List[int]
$script:pingHistory1h = New-Object System.Collections.Generic.List[int]
$script:pingHistory24h  = New-Object System.Collections.Generic.List[int]
$script:lossHistory60s  = New-Object System.Collections.Generic.List[bool]  # true=loss, false=ok
$script:lossHistory5min = New-Object System.Collections.Generic.List[bool]
$script:lossHistory30min= New-Object System.Collections.Generic.List[bool]
$script:lossHistory1h   = New-Object System.Collections.Generic.List[bool]
$script:currentTimeframe = "60s"  # Default
$script:graphUpdateCounter = 0

# ── HEATMAP-DATEN: [0..6 = Mo-So][0..23 = Stunde] ────────────
$script:heatmapData = @{}
for ($d = 0; $d -le 6; $d++) {
    $script:heatmapData[$d] = @{}
    for ($h = 0; $h -le 23; $h++) {
        $script:heatmapData[$d][$h] = @{ Sum = 0; Count = 0 }
    }
}
$script:heatmapFile = Join-Path $script:scriptPath "netninja_heatmap.json"
# Gespeicherte Heatmap laden (persistiert über Sessions)
if (Test-Path $script:heatmapFile) {
    try {
        $hm = Get-Content $script:heatmapFile -Raw | ConvertFrom-Json
        foreach ($d in 0..6) {
            foreach ($h in 0..23) {
                $cell = $hm."d$d"."h$h"
                if ($cell) {
                    $script:heatmapData[$d][$h].Sum   = [int]$cell.Sum
                    $script:heatmapData[$d][$h].Count = [int]$cell.Count
                }
            }
        }
        Write-Log "Heatmap loaded from disk" "INFO"
    } catch { Write-Log "Heatmap load failed: $_" "WARNING" }
}

# ── NETZWERK TIMELINE ─────────────────────────────────────────
$script:netTimeline     = New-Object System.Collections.Generic.List[hashtable]
$script:maxTimelineEntries = 80    # Max Einträge im Speicher
$script:timelineVisible = $true    # Timeline Panel sichtbar?

function Add-TimelineEvent {
    param(
        [string]$Type,    # spike|loss|restore|profile|info|warn|speed
        [string]$Msg
    )
    $entry = @{
        Time = Get-Date -Format "HH:mm:ss"
        Type = $Type
        Msg  = $Msg
    }
    $script:netTimeline.Insert(0, $entry)   # Neuestes oben
    if ($script:netTimeline.Count -gt $script:maxTimelineEntries) {
        $script:netTimeline.RemoveAt($script:netTimeline.Count - 1)
    }
    # Timeline-Panel refreshen
    if ($script:tlPanel -and $script:tlPanel.Visible) {
        $script:tlPanel.Invalidate()
    }
}

# Advanced Notifications
$script:lastConnectionState = $true
$script:connectionDownTime  = $null
$script:dailySummaryShown   = $false

# Adaptive Ping Rate
$script:adaptiveWindow      = [System.Collections.Generic.List[int]]::new()
$script:currentJitter       = 0
$script:crosshairX          = -1   # Mouse-X in graph (-1 = none)
$script:crosshairPingVal    = 0    # Ping-Wert an Crosshair-Position
$script:reconnectAttempts   = 0
$script:reconnectThreshold  = 10    # Packet losses before auto-reconnect
$script:lastReconnectTime   = $null
$script:reconnectCooldown   = 60    # Seconds between reconnect attempts
$script:selectedAdapter     = $null  # null = auto (first Up adapter)
$script:darkMode            = $true   # true = Dark, false = Light

# ══════════════════════════════════════════════════════════════
# CENTRAL COLOR PALETTE — all UI colors defined here
# ══════════════════════════════════════════════════════════════
function Get-ThemeColors {
    param([bool]$Dark = $true)
    if ($Dark) {
        return @{
            # Backgrounds
            BgPrimary    = [System.Drawing.Color]::FromArgb(24, 24, 28)
            BgSecondary  = [System.Drawing.Color]::FromArgb(32, 32, 38)
            BgSurface    = [System.Drawing.Color]::FromArgb(42, 42, 50)
            BgGraph      = [System.Drawing.Color]::FromArgb(14, 14, 18)
            BgInput      = [System.Drawing.Color]::FromArgb(36, 36, 44)
            # Text
            TextPrimary  = [System.Drawing.Color]::FromArgb(225, 225, 230)
            TextSecondary= [System.Drawing.Color]::FromArgb(150, 150, 160)
            TextDisabled = [System.Drawing.Color]::FromArgb(90, 90, 100)
            # Accents
            Accent       = [System.Drawing.Color]::FromArgb(0, 140, 220)
            AccentHover  = [System.Drawing.Color]::FromArgb(20, 160, 240)
            AccentGreen  = [System.Drawing.Color]::FromArgb(0, 190, 100)
            AccentRed    = [System.Drawing.Color]::FromArgb(220, 50, 50)
            AccentOrange = [System.Drawing.Color]::FromArgb(220, 130, 0)
            # Ping colors
            PingGood     = [System.Drawing.Color]::FromArgb(50, 220, 80)
            PingWarn     = [System.Drawing.Color]::FromArgb(255, 200, 0)
            PingHigh     = [System.Drawing.Color]::FromArgb(255, 140, 0)
            PingCrit     = [System.Drawing.Color]::FromArgb(255, 50, 50)
            # Borders / misc
            Border       = [System.Drawing.Color]::FromArgb(58, 58, 68)
            Separator    = [System.Drawing.Color]::FromArgb(50, 50, 60)
        }
    } else {
        return @{
            BgPrimary    = [System.Drawing.Color]::FromArgb(245, 245, 248)
            BgSecondary  = [System.Drawing.Color]::FromArgb(255, 255, 255)
            BgSurface    = [System.Drawing.Color]::FromArgb(235, 235, 240)
            BgGraph      = [System.Drawing.Color]::FromArgb(220, 220, 228)
            BgInput      = [System.Drawing.Color]::FromArgb(255, 255, 255)
            TextPrimary  = [System.Drawing.Color]::FromArgb(25, 25, 35)
            TextSecondary= [System.Drawing.Color]::FromArgb(90, 90, 110)
            TextDisabled = [System.Drawing.Color]::FromArgb(160, 160, 175)
            Accent       = [System.Drawing.Color]::FromArgb(0, 110, 190)
            AccentHover  = [System.Drawing.Color]::FromArgb(0, 130, 210)
            AccentGreen  = [System.Drawing.Color]::FromArgb(0, 160, 80)
            AccentRed    = [System.Drawing.Color]::FromArgb(190, 30, 30)
            AccentOrange = [System.Drawing.Color]::FromArgb(180, 100, 0)
            PingGood     = [System.Drawing.Color]::FromArgb(30, 160, 60)
            PingWarn     = [System.Drawing.Color]::FromArgb(180, 140, 0)
            PingHigh     = [System.Drawing.Color]::FromArgb(190, 100, 0)
            PingCrit     = [System.Drawing.Color]::FromArgb(180, 20, 20)
            Border       = [System.Drawing.Color]::FromArgb(190, 190, 200)
            Separator    = [System.Drawing.Color]::FromArgb(200, 200, 210)
        }
    }
}
$script:C = Get-ThemeColors -Dark $script:darkMode   # $script:C.Accent etc.
$script:adaptiveStableCount = 0       # Consecutive stable pings
$script:currentPingInterval = $CONFIG.PingIntervalMin
$script:adaptiveState       = "FAST"  # FAST | REDUCED | MINIMAL
$script:adaptiveLastChange  = [System.Diagnostics.Stopwatch]::StartNew()

# ══════════════════════════════════════════════════════════════
# UI HELPER FUNCTIONS — consistent controls across all dialogs
# ══════════════════════════════════════════════════════════════
function New-StyledButton {
    param(
        [string]$Text,
        [int]$X, [int]$Y, [int]$Width = 150, [int]$Height = 38,
        [System.Drawing.Color]$BgColor,
        [System.Drawing.Color]$FgColor,
        [System.Drawing.Font]$Font,
        [scriptblock]$OnClick
    )
    if (-not $BgColor) { $BgColor = $script:C.Accent }
    if (-not $FgColor) { $FgColor = [System.Drawing.Color]::White }
    if (-not $Font)    { $Font    = $script:Fonts.Body }

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = $Text
    $btn.Location  = New-Object System.Drawing.Point($X, $Y)
    $btn.Size      = New-Object System.Drawing.Size($Width, $Height)
    $btn.BackColor = $BgColor
    $btn.ForeColor = $FgColor
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize  = 0
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [math]::Min($BgColor.R + 20, 255),
        [math]::Min($BgColor.G + 20, 255),
        [math]::Min($BgColor.B + 20, 255))
    $btn.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
        [math]::Max($BgColor.R - 20, 0),
        [math]::Max($BgColor.G - 20, 0),
        [math]::Max($BgColor.B - 20, 0))
    $btn.Font      = $Font
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    if ($OnClick) { $btn.Add_Click($OnClick) }
    return $btn
}

function New-StyledLabel {
    param(
        [string]$Text,
        [int]$X, [int]$Y, [int]$Width = 200, [int]$Height = 22,
        [System.Drawing.Color]$FgColor,
        [System.Drawing.Font]$Font,
        [System.Drawing.ContentAlignment]$Align = [System.Drawing.ContentAlignment]::MiddleLeft
    )
    if (-not $FgColor) { $FgColor = $script:C.TextPrimary }
    if (-not $Font)    { $Font    = $script:Fonts.Body }
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $Text
    $lbl.Location  = New-Object System.Drawing.Point($X, $Y)
    $lbl.Size      = New-Object System.Drawing.Size($Width, $Height)
    $lbl.ForeColor = $FgColor
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $lbl.Font      = $Font
    $lbl.TextAlign = $Align
    return $lbl
}

function New-StyledForm {
    param(
        [string]$Title,
        [int]$Width = 520, [int]$Height = 370,
        [bool]$Resizable = $false
    )
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.Size = New-Object System.Drawing.Size($Width, $Height)
    $f.MinimumSize = New-Object System.Drawing.Size($Width, $Height)
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $f.FormBorderStyle = if ($Resizable) {
        [System.Windows.Forms.FormBorderStyle]::Sizable
    } else {
        [System.Windows.Forms.FormBorderStyle]::FixedDialog
    }
    $f.MaximizeBox = $Resizable
    $f.MinimizeBox = $false
    $f.BackColor   = $script:C.BgPrimary
    $f.ForeColor   = $script:C.TextPrimary
    return $f
}

# ══════════════════════════════════════════════════════════════
# FONT SYSTEM — consistent typography
# ══════════════════════════════════════════════════════════════
$script:Fonts = @{
    Title   = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
    Header  = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    Body    = New-Object System.Drawing.Font("Segoe UI", 10)
    Small   = New-Object System.Drawing.Font("Segoe UI",  9)
    Tiny    = New-Object System.Drawing.Font("Segoe UI",  8)
    TinyBold= New-Object System.Drawing.Font("Segoe UI",  8, [System.Drawing.FontStyle]::Bold)
    Micro   = New-Object System.Drawing.Font("Segoe UI",  7)
    Italic  = New-Object System.Drawing.Font("Segoe UI",  9, [System.Drawing.FontStyle]::Italic)
    Mono    = New-Object System.Drawing.Font("Consolas", 10)
    MonoSm  = New-Object System.Drawing.Font("Consolas",  9)
    HUD     = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    PingBig = New-Object System.Drawing.Font("Segoe UI", 34, [System.Drawing.FontStyle]::Bold)
}

# Balloon-Tip Shorthand
# Button-Style Shorthand (für bereits erstellte Buttons)
function Set-ButtonStyle {
    param(
        $Button,
        [System.Drawing.Color]$Bg,
        [System.Drawing.Color]$Fg = [System.Drawing.Color]::White,
        [System.Drawing.Font]  $Font = $null
    )
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.BackColor = $Bg
    $Button.ForeColor = $Fg
    $Button.Cursor    = [System.Windows.Forms.Cursors]::Hand
    if ($Font) { $Button.Font = $Font }
    $Button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(
        [math]::Min($Bg.R+25,255), [math]::Min($Bg.G+25,255), [math]::Min($Bg.B+25,255))
    $Button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::FromArgb(
        [math]::Max($Bg.R-25,0),  [math]::Max($Bg.G-25,0),  [math]::Max($Bg.B-25,0))
}

function Notify-User {
    param(
        [string]$Message,
        [string]$Title   = "NetNinja",
        [int]   $Ms      = 2000,
        [System.Windows.Forms.ToolTipIcon]$Icon = [System.Windows.Forms.ToolTipIcon]::Info
    )
    $trayIcon.ShowBalloonTip($Ms, $Title, $Message, $Icon)
}

# Context Menu Item Shorthand
function Add-MenuItem {
    param([string]$Text, [scriptblock]$Action = $null, $Menu = $contextMenu)
    if ($Text -eq "-") { return $Menu.Items.Add("-") }
    return $Menu.Items.Add($Text, $null, $Action)
}

function Write-Log {
    param([string]$Msg, [string]$Type = "INFO")
    $levelOrder = @{ "DEBUG"="0"; "INFO"="1"; "WARNING"="2"; "ERROR"="3"; "SUCCESS"="1" }
    $minLevel   = if ($script:LogLevel) { $script:LogLevel } else { "INFO" }
    $msgLvl = $levelOrder[$Type];    if (-not $msgLvl) { $msgLvl = "1" }
    $minLvl = $levelOrder[$minLevel]; if (-not $minLvl) { $minLvl = "1" }
    if ([int]$msgLvl -lt [int]$minLvl) { return }
    try {
        $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Type] $Msg"
        # FIX: StreamWriter mit Append=true + UTF8 ohne BOM — atomar, kein Out-File locking
        $sw = [System.IO.StreamWriter]::new($logFile, $true, [System.Text.UTF8Encoding]::new($false))
        try { $sw.WriteLine($logEntry) } finally { $sw.Close(); $sw.Dispose() }

        # Log-Rotation: nur alle 60s prüfen (nicht bei jedem Log-Eintrag)
        $now2 = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        if (($now2 - $script:lastLogRotationCheck) -gt 60) {
            $script:lastLogRotationCheck = $now2
            if ((Test-Path $logFile) -and (Get-Item $logFile -ErrorAction SilentlyContinue).Length -gt 5MB) {
                $arch = $logFile -replace '\.log$', "_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
                Move-Item $logFile $arch -Force -ErrorAction SilentlyContinue
                # Max 5 Archiv-Logs behalten
                Get-ChildItem -Path $script:scriptPath -Filter "netninja_*.log" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -Skip 5 |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { $null = $_ }
}

function Save-Config {
    try {
        # FIX: HUDForm null-safe — speichern auch wenn Form minimiert/versteckt
        $hudLoc = if ($hudForm -and -not $hudForm.IsDisposed) {
            @{ X = $hudForm.Location.X; Y = $hudForm.Location.Y }
        } else { @{ X = 20; Y = 20 } }
        $hudOp  = if ($hudForm -and -not $hudForm.IsDisposed) { $hudForm.Opacity  } else { 0.96 }
        $hudTM  = if ($hudForm -and -not $hudForm.IsDisposed) { $hudForm.TopMost  } else { $true }

        $saveData = @{
            ServerAddress          = $CONFIG.ServerAddress
            ServerPort             = $CONFIG.ServerPort
            AdaptiveRate           = $CONFIG.AdaptiveRate
            SpikeThreshold         = $CONFIG.SpikeThreshold
            AlertHighPing          = $CONFIG.AlertHighPing
            AlertCriticalPing      = $CONFIG.AlertCriticalPing
            PingIntervalMin        = $CONFIG.PingIntervalMin
            PingIntervalMax        = $CONFIG.PingIntervalMax
            AdaptiveStableMaxPing  = $CONFIG.AdaptiveStableMaxPing
            AdaptiveStableJitter   = $CONFIG.AdaptiveStableJitter
            AdaptiveStableWindow   = $CONFIG.AdaptiveStableWindow
            CurrentProfile         = $script:currentProfile
            SelectedAdapter        = $script:selectedAdapter
            OverlayActive          = $script:overlayActive
            DarkMode               = $script:darkMode
            AudioAlertEnabled      = $script:AudioAlertEnabled
            HUDLocation            = $hudLoc
            HUDOpacity             = $hudOp
            HUDTopMost             = $hudTM
        }
        $saveData | ConvertTo-Json -Depth 3 -Compress | Out-File $configFile -Encoding UTF8 -Force
        Write-Log "Config saved" "INFO"
    } catch {
        Write-Log "Config save failed: $_" "ERROR"
    }
}

function Load-Config {
    if (-not (Test-Path $configFile)) { return }
    try {
        $saved = Get-Content $configFile -Raw | ConvertFrom-Json
        if ($saved.ServerAddress)  { $CONFIG.ServerAddress  = $saved.ServerAddress }
        if ($saved.ServerPort)     { $CONFIG.ServerPort     = [int]$saved.ServerPort }
        if ($null -ne $saved.AdaptiveRate)   { $CONFIG.AdaptiveRate   = [bool]$saved.AdaptiveRate }
        if ($saved.SpikeThreshold)     { $CONFIG.SpikeThreshold     = [int]$saved.SpikeThreshold }
        if ($saved.AlertHighPing)     { $CONFIG.AlertHighPing     = [int]$saved.AlertHighPing }
        if ($saved.AlertCriticalPing) { $CONFIG.AlertCriticalPing = [int]$saved.AlertCriticalPing }
        if ($saved.PingIntervalMin)   { $CONFIG.PingIntervalMin   = [int]$saved.PingIntervalMin }
        if ($saved.PingIntervalMax)   { $CONFIG.PingIntervalMax   = [int]$saved.PingIntervalMax }
        if ($saved.AdaptiveStableMaxPing) { $CONFIG.AdaptiveStableMaxPing = [int]$saved.AdaptiveStableMaxPing }
        if ($saved.AdaptiveStableJitter)  { $CONFIG.AdaptiveStableJitter  = [int]$saved.AdaptiveStableJitter }
        if ($saved.AdaptiveStableWindow)  { $CONFIG.AdaptiveStableWindow  = [int]$saved.AdaptiveStableWindow }
        if ($saved.CurrentProfile)  { $script:currentProfile  = $saved.CurrentProfile }
        if ($saved.SelectedAdapter) { $script:selectedAdapter = $saved.SelectedAdapter }
        if ($null -ne $saved.OverlayActive -and $saved.OverlayActive) {
            # Overlay will be restored after UI is ready (handled in startup sequence)
            $script:restoreOverlayOnStart = $true
        }
        if ($null -ne $saved.DarkMode) { $script:darkMode = [bool]$saved.DarkMode }
        if ($null -ne $saved.AudioAlertEnabled) { $script:AudioAlertEnabled = [bool]$saved.AudioAlertEnabled }
        if ($saved.HUDOpacity)     { $hudForm.Opacity = [double]$saved.HUDOpacity }
        if ($null -ne $saved.HUDTopMost) { $hudForm.TopMost = [bool]$saved.HUDTopMost }
        if ($saved.HUDLocation) {
            $hudForm.Location = New-Object System.Drawing.Point($saved.HUDLocation.X, $saved.HUDLocation.Y)
        }
        $script:TargetIP         = $CONFIG.ServerAddress
        $script:activeServerPort = $CONFIG.ServerPort   # FIX: sync
        Write-Log "Config loaded: $($CONFIG.ServerAddress):$($CONFIG.ServerPort) Profile=$($script:currentProfile)" "INFO"
    } catch {
        Write-Log "Config load failed: $_" "ERROR"
    }
}

function Apply-Theme {
    param([bool]$Dark)
    $script:darkMode = $Dark
    $script:C        = Get-ThemeColors -Dark $Dark   # Refresh color palette

    # ── HUD Form ─────────────────────────────────────────────
    $hudForm.BackColor = $script:C.BgPrimary
    if ($hudLabel)     { $hudLabel.BackColor     = $script:C.BgPrimary }
    if ($hudPauseBtn)  { $hudPauseBtn.BackColor  = [System.Drawing.Color]::FromArgb(10, 10, 14) }
    if ($script:graphPanel)  { $script:graphPanel.BackColor = $script:C.BgGraph }
    if ($script:pingBarPanel){ $script:pingBarPanel.BackColor = $script:C.BgGraph }

    # ── Context Menus ─────────────────────────────────────────
    foreach ($menu in @($contextMenu, $hudContext)) {
        if ($menu) {
            $menu.BackColor = $script:C.BgSecondary
            $menu.ForeColor = $script:C.TextPrimary
        }
    }

    # ── Timeframe Buttons (60s/5min/30min/1h) ────────────────
    foreach ($btn in @($btn60s, $btn5min, $btn30min, $btn1h)) {
        if ($btn) {
            $btn.BackColor = $script:C.BgSurface
            $btn.ForeColor = $script:C.TextSecondary
        }
    }

    Write-Log "Theme changed to: $(if ($Dark) { 'Dark' } else { 'Light' })" "INFO"
    Save-Config
}

function Show-AdapterSelector {
    $aF = New-Object System.Windows.Forms.Form
    $aF.Text = "Select Network Adapter"
    $aF.Size = New-Object System.Drawing.Size(480, 320)
    $aF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $aF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $aF.MaximizeBox = $false
    $aF.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 28)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Choose which adapter NetNinja optimizes:"
    $lbl.Location = New-Object System.Drawing.Point(15, 15)
    $lbl.Size = New-Object System.Drawing.Size(440, 20)
    $lbl.Font      = $script:Fonts.Small
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215)
    $aF.Controls.Add($lbl)

    $listBox = New-Object System.Windows.Forms.ListBox
    $listBox.Location = New-Object System.Drawing.Point(15, 42)
    $listBox.Size = New-Object System.Drawing.Size(440, 180)
    $listBox.Font = $script:Fonts.MonoSm
    $listBox.BackColor   = [System.Drawing.Color]::FromArgb(20, 20, 28)
    $listBox.ForeColor   = [System.Drawing.Color]::FromArgb(190, 190, 210)
    $listBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    # Populate with adapters
    $adapters = Get-NetAdapter | Sort-Object Status -Descending
    $listBox.Items.Add("[AUTO] First active adapter (default)") | Out-Null
    foreach ($adp in $adapters) {
        $status = if ($adp.Status -eq "Up") { "UP  " } else { "DOWN" }
        $speed  = if ($adp.LinkSpeed) { " — $($adp.LinkSpeed)" } else { "" }
        $listBox.Items.Add("[$status] $($adp.Name)$speed") | Out-Null
    }
    # Select current
    if ($null -eq $script:selectedAdapter) {
        $listBox.SelectedIndex = 0
    } else {
        for ($i = 1; $i -lt $listBox.Items.Count; $i++) {
            if ($listBox.Items[$i] -like "*$($script:selectedAdapter)*") {
                $listBox.SelectedIndex = $i; break
            }
        }
    }
    $aF.Controls.Add($listBox)

    $infoLbl = New-Object System.Windows.Forms.Label
    $infoLbl.Text = "UP adapters are recommended. Optimizations target the selected adapter."
    $infoLbl.Location = New-Object System.Drawing.Point(15, 228)
    $infoLbl.Size = New-Object System.Drawing.Size(440, 18)
    $infoLbl.Font = $script:Fonts.Italic
    $infoLbl.ForeColor = [System.Drawing.Color]::FromArgb(130, 130, 150)
    $aF.Controls.Add($infoLbl)

    $applyBtn = New-Object System.Windows.Forms.Button
    $applyBtn.Text = "Apply"
    $applyBtn.Location = New-Object System.Drawing.Point(15, 250)
    $applyBtn.Size = New-Object System.Drawing.Size(215, 35)
    $applyBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
    $applyBtn.ForeColor = [System.Drawing.Color]::White
    $applyBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $applyBtn.FlatAppearance.BorderSize = 0
    $applyBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 165, 230)
    $applyBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $applyBtn.Font = $script:Fonts.Header
    $applyBtn.Add_Click({
        if ($listBox.SelectedIndex -le 0) {
            $script:selectedAdapter = $null
            Write-Log "Network adapter: AUTO (first Up)" "INFO"
            Notify-User "Adapter: AUTO selected" -Ms 2000
        } else {
            $adpName = $adapters[$listBox.SelectedIndex - 1].Name
            $script:selectedAdapter = $adpName
            Write-Log "Network adapter set to: $adpName" "INFO"
            Notify-User "Adapter: $adpName" -Ms 2000
        }
        Save-Config
        $aF.Close()
    })
    $aF.Controls.Add($applyBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel"
    $cancelBtn.Location = New-Object System.Drawing.Point(240, 250)
    $cancelBtn.Size = New-Object System.Drawing.Size(215, 35)
    $cancelBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
    $cancelBtn.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
    $cancelBtn.FlatAppearance.BorderSize = 0
    $cancelBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(50, 52, 62)
    $cancelBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $aF.Controls.Add($cancelBtn)
    $aF.CancelButton = $cancelBtn
    $aF.ShowDialog() | Out-Null
    $aF.Dispose()
}

function Backup-RegistryKey {
    param([string]$KeyPath, [switch]$Force)
    try {
        # FIX: -Force erlaubt explizites Überschreiben (z.B. nach großem Update)
        if ($Force -or -not (Test-Path $registryBackupFile)) {
            $regPath = $KeyPath -replace 'HKLM:\\', 'HKEY_LOCAL_MACHINE\'
            $process = Start-Process "reg" -ArgumentList "export `"$regPath`" `"$registryBackupFile`" /y" -Wait -NoNewWindow -PassThru -WindowStyle Hidden
            if ($process.ExitCode -eq 0) {
                Write-Log "Registry backup created" "INFO"
                return $true
            }
        }
        return $true
    } catch {
        Write-Log "Backup failed: $_" "WARNING"
        return $false
    }
}

function Restore-RegistryBackup {
    try {
        if (Test-Path $registryBackupFile) {
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Restore registry from backup?",
                "Restore Registry",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Start-Process "reg" -ArgumentList "import `"$registryBackupFile`"" -Wait -NoNewWindow -WindowStyle Hidden
                Write-Log "Registry restored" "INFO"
                [System.Windows.Forms.MessageBox]::Show("Registry restored successfully!", "Success")
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show("No backup found.", "Info")
        }
    } catch {
        Write-Log "Restore failed: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Restore failed: $_", "Error", "OK", "Error")
    }
}

function Backup-NetworkSettings {
    try {
        $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
        if ($adapter) {
            $dnsSettings = Get-DnsClientServerAddress -InterfaceAlias $adapter.Name
            $backup = @{
                AdapterName = $adapter.Name
                DNS = $dnsSettings | Select-Object InterfaceAlias, ServerAddresses
                Timestamp = Get-Date
            }
            $backup | ConvertTo-Json -Depth 3 | Out-File $networkBackupFile -Encoding UTF8 -Force
            Write-Log "Network settings backed up" "INFO"
        }
    } catch {
        Write-Log "Network backup failed: $_" "WARNING"
    }
}

function Restore-NetworkSettings {
    if (-not (Test-Path $networkBackupFile)) {
        [System.Windows.Forms.MessageBox]::Show(
            "No network backup found.`nCreate one via 'Backup Network Settings' first.",
            "No Backup","OK","Warning")
        return
    }
    try {
        $backup = Get-Content $networkBackupFile -Raw | ConvertFrom-Json
        if (-not $backup.AdapterName) { throw "Invalid backup file" }
        # DNS-Adressen wiederherstellen (oder zurücksetzen wenn vorher DHCP)
        $savedDNS = @($backup.DNS | Where-Object { $_.ServerAddresses.Count -gt 0 } |
                      Select-Object -ExpandProperty ServerAddresses -First 1)
        if ($savedDNS.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceAlias $backup.AdapterName -ServerAddresses $savedDNS -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceAlias $backup.AdapterName -ResetServerAddresses
        }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Log "Network settings restored: $($backup.AdapterName) DNS=$($savedDNS -join ',')" "INFO"
        [System.Windows.Forms.MessageBox]::Show(
            "Network settings restored for: $($backup.AdapterName)","Success","OK","Information")
    } catch {
        Write-Log "Network restore failed: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Restore failed:`n$_","Error","OK","Error")
    }
}

function Get-PingColor {
    # Smooth HSL-Gradient: 0ms=reines Grün → 75ms=Gelb-Grün → 150ms=Gelb → 200ms=Orange → 300ms+=Rot
    param([int]$ping)
    $p = [math]::Max(0, [math]::Min($ping, 400))
    if ($p -lt 75) {
        # Grün → Gelb-Grün (0..75ms)
        $t = $p / 75.0
        return [System.Drawing.Color]::FromArgb(
            [int](40  + $t * 185),   # R: 40→225
            [int](210 - $t * 10),    # G: 210→200
            [int](60  - $t * 50))    # B: 60→10
    } elseif ($p -lt 150) {
        # Gelb-Grün → Gelb (75..150ms)
        $t = ($p - 75) / 75.0
        return [System.Drawing.Color]::FromArgb(
            [int](225 + $t * 20),    # R: 225→245
            [int](200 - $t * 20),    # G: 200→180
            10)                      # B: 10
    } elseif ($p -lt 250) {
        # Gelb → Orange (150..250ms)
        $t = ($p - 150) / 100.0
        return [System.Drawing.Color]::FromArgb(
            245,                     # R: bleibt
            [int](180 - $t * 110),   # G: 180→70
            10)                      # B: 10
    } else {
        # Orange → Rot (250..400ms)
        $t = [math]::Min(($p - 250) / 150.0, 1.0)
        return [System.Drawing.Color]::FromArgb(
            [int](245 - $t * 20),    # R: 245→225
            [int](70  - $t * 55),    # G: 70→15
            10)                      # B: 10
    }
}

function Create-IconWithText {
    param(
        [string]$text,
        [System.Drawing.Color]$color,
        [string]$mode = "ping"   # ping | loss | waiting | detecting
    )

    # ── Cache-Key: text + mode (Farbe ergibt sich daraus) ───────
    $cacheKey = "${mode}:${text}"
    if ($script:iconCache.ContainsKey($cacheKey)) {
        return $script:iconCache[$cacheKey]
    }

    try {
        # 32×32 Bitmap mit Alpha-Kanal
        $bitmap = New-Object System.Drawing.Bitmap(32, 32, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bitmap)

        # ── Rendering-Qualität: max ──────────────────────────────
        $g.SmoothingMode         = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint     = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $g.PixelOffsetMode       = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.InterpolationMode     = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.CompositingQuality    = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

        # ── Transparenter Hintergrund ────────────────────────────
        $g.Clear([System.Drawing.Color]::Transparent)

        # ── Hintergrund-Kreis mit leichtem Glow-Effekt ───────────
        # Äußerer Glow (subtle)
        $glowColor = [System.Drawing.Color]::FromArgb(40, $color.R, $color.G, $color.B)
        $glowBrush = New-Object System.Drawing.SolidBrush($glowColor)
        $g.FillEllipse($glowBrush, 0, 0, 32, 32)
        $glowBrush.Dispose()

        # Hauptkreis
        $mainBrush = New-Object System.Drawing.SolidBrush($color)
        $g.FillEllipse($mainBrush, 2, 2, 28, 28)
        $mainBrush.Dispose()

        # Highlight (kleiner weißer Bogen oben-links = Glaseffekt)
        $hiColor = [System.Drawing.Color]::FromArgb(55, 255, 255, 255)
        $hiBrush = New-Object System.Drawing.SolidBrush($hiColor)
        $g.FillEllipse($hiBrush, 5, 4, 14, 9)
        $hiBrush.Dispose()

        # ── Adaptiver Font je nach Zeichenanzahl ─────────────────
        $fontSize = switch ($text.Length) {
            1       { 13.0 }   # "9"         → groß
            2       { 11.5 }   # "42"        → mittel-groß
            3       { 8.5  }   # "199"       → mittel
            default { 7.0  }   # "LOSS"/"---" → klein
        }
        $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold)

        # ── Perfekte Zentrierung via StringFormat ─────────────────
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment     = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $sf.FormatFlags   = [System.Drawing.StringFormatFlags]::NoWrap

        # Text-Schatten (Lesbarkeit auf hellem Hintergrund)
        $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 0, 0, 0))
        $shadowRect  = New-Object System.Drawing.RectangleF(1, 2, 32, 32)
        $g.DrawString($text, $font, $shadowBrush, $shadowRect, $sf)
        $shadowBrush.Dispose()

        # Haupttext weiß, zentriert
        $textRect = New-Object System.Drawing.RectangleF(0, 0, 32, 32)
        $g.DrawString($text, $font, [System.Drawing.Brushes]::White, $textRect, $sf)

        $font.Dispose()
        $sf.Dispose()

        # ── Icon aus Bitmap ──────────────────────────────────────
        $hIcon = $bitmap.GetHicon()
        $icon  = [System.Drawing.Icon]::FromHandle($hIcon)

        $g.Dispose()
        $bitmap.Dispose()

        # Cache: max 50 Einträge (4 Modi × ~12 Ping-Stufen)
        if ($script:iconCache.Count -lt 50) {
            $script:iconCache[$cacheKey] = $icon
        }

        return $icon
    } catch {
        Write-Log "Icon creation failed: $_" "ERROR"
        return $null
    }
}

function Cleanup-Icons {
    # FIX: Keys als Array kopieren — keine Modifikation während Iteration
    $keys = @($script:iconCache.Keys)
    foreach ($key in $keys) {
        try {
            $icon = $script:iconCache[$key]
            if ($icon) {
                # FIX: DestroyIcon + Dispose — FromHandle-Icons brauchen beide
                try { [Win32.IconHelper]::DestroyIcon($icon.Handle) | Out-Null } catch { $null = $_ }
                try { $icon.Dispose() } catch { $null = $_ }
            }
        } catch { $null = $_ }
    }
    $script:iconCache.Clear()
    Write-Log "Icon cache cleared ($($keys.Count) entries)" "INFO"
}

function Get-GameServerIP {
    try {
        $gameProc = Get-Process -Name $CONFIG.ProcessName -ErrorAction SilentlyContinue
        if (-not $gameProc) { return $false }

        # FIX: Breite Port-Range — deckt alle Ragnarok/MMO-Ports ab
        $knownPorts = @(5121, 5122, 5123, 5124, 6900, 6121, 6122, 3306, 443, 80)
        $connection = Get-NetTCPConnection -OwningProcess $gameProc.Id `
                        -State Established -ErrorAction SilentlyContinue |
                      Where-Object {
                          $_.RemoteAddress -notmatch '^(127\.|0\.0\.0\.0|::1|169\.254\.|::$)' -and
                          ($_.RemotePort -in $knownPorts -or $_.RemotePort -eq $CONFIG.ServerPort)
                      } |
                      # FIX: Priorisierung: exakter ConfigPort first, dann nächster bekannter Port
                      Sort-Object -Property @{Expression={ if ($_.RemotePort -eq $CONFIG.ServerPort){0} else {1} }} |
                      Select-Object -First 1

        if ($connection) {
            $script:TargetIP         = $connection.RemoteAddress
            $script:activeServerPort = $connection.RemotePort   # FIX: auch Port synchronisieren
            $script:IsIPDetected     = $true
            Write-Log "Server auto-detected: $($script:TargetIP):$($connection.RemotePort)" "INFO"
            Add-TimelineEvent -Type "info" -Msg "Auto-detect: $($script:TargetIP):$($connection.RemotePort)"
            return $true
        }
    } catch {
        Write-Log "IP detection error: $_" "WARNING"
    }
    return $false
}

function Apply-Optimizations {
    param([bool]$DisableAll = $false)
    
    try {
        $prof = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        
        if (-not $DisableAll) {
            Backup-RegistryKey $prof
        }
        
        if ($DisableAll) {
            Set-ItemProperty -Path $prof -Name "NetworkThrottlingIndex" -Value 10 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $prof -Name "SystemResponsiveness" -Value 20 -Force -EA SilentlyContinue
            
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Interrupt Moderation" -DisplayValue "Enabled" -EA SilentlyContinue
            }
            
            Write-Log "Optimizations reset to defaults" "INFO"
            return
        }
        
        if ($Global:OptimizationConfig.NetworkThrottling) {
            Set-ItemProperty -Path $prof -Name "NetworkThrottlingIndex" -Value 0xffffffff -Force -EA SilentlyContinue
            Write-Log "Network throttling disabled" "INFO"
        }
        
        if ($Global:OptimizationConfig.SystemResponsiveness) {
            Set-ItemProperty -Path $prof -Name "SystemResponsiveness" -Value 0 -Force -EA SilentlyContinue
            Write-Log "System responsiveness optimized" "INFO"
        }
        
        if ($Global:OptimizationConfig.NetworkOptimizations) {
            $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
            Set-ItemProperty -Path $tcpParams -Name "TcpAckFrequency" -Value 1 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $tcpParams -Name "TCPNoDelay" -Value 1 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $tcpParams -Name "TcpDelAckTicks" -Value 0 -Force -EA SilentlyContinue
            Write-Log "TCP/IP optimized (Nagle disabled)" "INFO"
        }
        
        if ($Global:OptimizationConfig.DNSCache) {
            Clear-DnsClientCache -EA SilentlyContinue
            Write-Log "DNS cache cleared" "INFO"
        }
        
        if ($Global:OptimizationConfig.NetworkPowerSaving) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                try {
                    $powerMgmt = Get-CimInstance -ClassName MSPower_DeviceEnable -Namespace root/wmi -ErrorAction SilentlyContinue | 
                                 Where-Object { $_.InstanceName -match [regex]::Escape($adapter.PnPDeviceID) }
                    if ($powerMgmt) {
                        $powerMgmt | Set-CimInstance -Property @{Enable = $false} -ErrorAction SilentlyContinue
                        Write-Log "NIC power saving disabled via WMI" "INFO"
                    } else {
                        Write-Log "NIC power management not found (may already be disabled)" "INFO"
                    }
                } catch {
                    Write-Log "NIC power saving adjustment skipped: $_" "WARNING"
                }
            }
        }
        
        if ($Global:OptimizationConfig.GameMode -and $script:isWin10Plus) {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1 -Force -EA SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -Force -EA SilentlyContinue
            Write-Log "Game Mode enabled" "INFO"
        }
        
        if ($Global:OptimizationConfig.MMCSS) {
            $mmcss = "$prof\Tasks\Games"
            if (-not (Test-Path $mmcss)) { New-Item -Path $mmcss -Force | Out-Null }
            Set-ItemProperty -Path $mmcss -Name "GPU Priority" -Value 8 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $mmcss -Name "Priority" -Value 6 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $mmcss -Name "Scheduling Category" -Value "High" -Force -EA SilentlyContinue
            Write-Log "MMCSS gaming profile set" "INFO"
        }
        
        if ($Global:OptimizationConfig.KeyboardResponse) {
            Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Value "122" -Force -EA SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "AutoRepeatDelay" -Value "200" -Force -EA SilentlyContinue
            Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "AutoRepeatRate" -Value "20" -Force -EA SilentlyContinue
            Write-Log "Keyboard response optimized" "INFO"
        }
        
        if ($Global:OptimizationConfig.DeliveryOptimization) {
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Value 0 -Force -EA SilentlyContinue
            Stop-Service -Name "DoSvc" -Force -EA SilentlyContinue
            Set-Service -Name "DoSvc" -StartupType Disabled -EA SilentlyContinue
            Write-Log "Delivery Optimization disabled" "INFO"
        }
        
        if ($Global:OptimizationConfig.CoreParkingFix) {
            powercfg -setacvalueindex scheme_current sub_processor CPMINCORES 100 2>&1 | Out-Null
            powercfg -setdcvalueindex scheme_current sub_processor CPMINCORES 100 2>&1 | Out-Null
            powercfg -setactive scheme_current 2>&1 | Out-Null
            Write-Log "Core parking disabled" "INFO"
        }
        
        if ($Global:OptimizationConfig.HAGS -and $script:isWin10Build19041Plus) {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -Force -EA SilentlyContinue
            Write-Log "HAGS enabled (restart required)" "INFO"
        }
        
        if ($Global:OptimizationConfig.InterruptModeration) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Interrupt Moderation" -DisplayValue "Disabled" -EA SilentlyContinue
                Write-Log "Interrupt Moderation disabled" "INFO"
            }
        }
        
        if ($Global:OptimizationConfig.SysMainOptimization) {
            Stop-Service -Name "SysMain" -Force -EA SilentlyContinue
            Set-Service -Name "SysMain" -StartupType Disabled -EA SilentlyContinue
            Write-Log "SysMain disabled" "INFO"
        }
        
        if ($Global:OptimizationConfig.AutoTuningLevel) {
            netsh interface tcp set global autotuninglevel=highlyrestricted 2>&1 | Out-Null
            Write-Log "TCP Auto-Tuning set to highlyrestricted (MMO optimal)" "INFO"
        }
        
        if ($Global:OptimizationConfig.LargePacketOffload) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Disable-NetAdapterLso -Name $adapter.Name -EA SilentlyContinue
                Write-Log "LSO disabled" "INFO"
            }
        }
        
        # NetworkBuffers handled by NetworkBuffersMMO (2048) and NetworkBuffersComp (64)
        
        if ($Global:OptimizationConfig.ReceiveSideScaling) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Enable-NetAdapterRss -Name $adapter.Name -EA SilentlyContinue
                Set-NetAdapterRss -Name $adapter.Name -NumberOfReceiveQueues 4 -EA SilentlyContinue
                Write-Log "RSS optimized" "INFO"
            }
        }
        
        if ($Global:OptimizationConfig.CongestionProvider) {
            netsh interface tcp set supplemental template=internet congestionprovider=ctcp 2>&1 | Out-Null
            Write-Log "CTCP enabled" "INFO"
        }

        # ── MMO-spezifische neue Optimierungen ────────────────────────

        if ($Global:OptimizationConfig.DisableNagleIface) {
            # Nagle pro Adapter deaktivieren (ergänzt globales TCPNoDelay)
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
                if (Test-Path $ifPath) {
                    Set-ItemProperty -Path $ifPath -Name "TcpAckFrequency" -Value 1 -Force -EA SilentlyContinue
                    Set-ItemProperty -Path $ifPath -Name "TCPNoDelay"      -Value 1 -Force -EA SilentlyContinue
                    Write-Log "Nagle per-interface disabled: $($adapter.Name)" "INFO"
                }
            }
        }

        if ($Global:OptimizationConfig.TcpTimedWaitDelay) {
            $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
            Set-ItemProperty -Path $tcpParams -Name "TcpTimedWaitDelay"    -Value 30  -Force -EA SilentlyContinue
            Set-ItemProperty -Path $tcpParams -Name "MaxUserPort"           -Value 65534 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $tcpParams -Name "TcpNumConnections"     -Value 16777214 -Force -EA SilentlyContinue
            Write-Log "TCP TIME_WAIT: 4min→30s, MaxUserPort: 65534" "INFO"
        }

        if ($Global:OptimizationConfig.HighPerfPowerPlan) {
            powercfg -setactive SCHEME_MIN 2>&1 | Out-Null
            Write-Log "High Performance power plan activated" "INFO"
        }

        if ($Global:OptimizationConfig.DisableNetBIOS) {
            # NetBIOS über WMI deaktivieren
            $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -EA SilentlyContinue | Where-Object IPEnabled
            foreach ($a in $adapters) {
                $a | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions = 2} -EA SilentlyContinue | Out-Null
            }
            Write-Log "NetBIOS over TCP/IP disabled on all adapters" "INFO"
        }

        if ($Global:OptimizationConfig.DisableIPv6) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -EA SilentlyContinue
                Write-Log "IPv6 disabled on: $($adapter.Name)" "INFO"
            }
        }

        if ($Global:OptimizationConfig.PagingExecutive) {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
                -Name "DisablePagingExecutive" -Value 1 -Force -EA SilentlyContinue
            Write-Log "Kernel paging disabled (PagingExecutive=1)" "INFO"
        }

        if ($Global:OptimizationConfig.TimerResolutionMMO) {
            # NtSetTimerResolution via powershell — setzt 1ms Systemtimer
            $timerPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
            Set-ItemProperty -Path $timerPath -Name "LazyModeTimeout" -Value 0 -Force -EA SilentlyContinue
            # MMCSS-basierte 1ms Auflösung aktivieren
            $gamesPath = "$timerPath\Tasks\Games"
            if (-not (Test-Path $gamesPath)) { New-Item -Path $gamesPath -Force | Out-Null }
            Set-ItemProperty -Path $gamesPath -Name "Clock Rate"  -Value 10000   -Force -EA SilentlyContinue
            Set-ItemProperty -Path $gamesPath -Name "Priority"    -Value 6       -Force -EA SilentlyContinue
            Write-Log "Timer resolution: 1ms via MMCSS" "INFO"
        }

        if ($Global:OptimizationConfig.WindowsDefenderExcl) {
            # Spielprozess-Verzeichnis zu Defender Ausnahmen hinzufügen
            try {
                $gamePaths = @(
                    "$env:ProgramFiles\Gravity\Ragnarok Online",
                    "$env:ProgramFiles (x86)\Gravity\Ragnarok Online",
                    "$env:ProgramFiles\Steam\steamapps\common",
                    "$env:ProgramFiles (x86)\Steam\steamapps\common"
                )
                foreach ($p in $gamePaths) {
                    if (Test-Path $p) {
                        Add-MpPreference -ExclusionPath $p -EA SilentlyContinue
                        Write-Log "Defender exclusion: $p" "INFO"
                    }
                }
                # Aktive Spielprozesse
                foreach ($procName in $script:gameProcesses | Select-Object -First 10) {
                    $proc = Get-Process -Name $procName -EA SilentlyContinue
                    if ($proc -and $proc.Path) {
                        $dir = Split-Path $proc.Path -Parent
                        Add-MpPreference -ExclusionPath $dir -EA SilentlyContinue
                        Write-Log "Defender exclusion (active game): $dir" "INFO"
                    }
                }
            } catch { Write-Log "Defender exclusion error: $_" "WARNING" }
        }

        if ($Global:OptimizationConfig.QoSMMO) {
            # QoS 20% Reserve entfernen
            $qosPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"
            if (-not (Test-Path $qosPath)) { New-Item -Path $qosPath -Force | Out-Null }
            Set-ItemProperty -Path $qosPath -Name "NonBestEffortLimit" -Value 0 -Force -EA SilentlyContinue
            Write-Log "QoS bandwidth reserve removed (0%)" "INFO"
        }

        if ($Global:OptimizationConfig.NetworkBuffersMMO) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Receive Buffers"  -DisplayValue "2048" -EA SilentlyContinue
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Transmit Buffers" -DisplayValue "2048" -EA SilentlyContinue
                Write-Log "NIC buffers: RX/TX → 2048" "INFO"
            }
        }

        if ($Global:OptimizationConfig.FlowControl) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Flow Control" -DisplayValue "Disabled" -EA SilentlyContinue
                Write-Log "Ethernet Flow Control disabled: $($adapter.Name)" "INFO"
            }
        }

        if ($Global:OptimizationConfig.RSSQueuesMMO) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                Enable-NetAdapterRss -Name $adapter.Name -EA SilentlyContinue
                Set-NetAdapterRss -Name $adapter.Name -NumberOfReceiveQueues 4 -EA SilentlyContinue
                Set-NetAdapterRss -Name $adapter.Name -BaseProcessorNumber 0   -EA SilentlyContinue
                Write-Log "RSS: 4 Queues optimiert" "INFO"
            }
        }

        if ($Global:OptimizationConfig.InterruptAffinityMMO) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                # Interrupt auf Core 1 (nicht Core 0 = OS-Kern)
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Preferred NUMA Node" -DisplayValue "0" -EA SilentlyContinue
                Write-Log "NIC Interrupt Affinity gesetzt: $($adapter.Name)" "INFO"
            }
        }

        if ($Global:OptimizationConfig.AutoTuningMMO) {
            netsh interface tcp set global autotuninglevel=highlyrestricted 2>&1 | Out-Null
            Write-Log "TCP AutoTuning: highlyrestricted (MMO-optimiert)" "INFO"
        }

        if ($Global:OptimizationConfig.DNSOverHTTPS) {
            if ($script:isWin10Build19041Plus) {
                Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" `
                    -Name "EnableAutoDoh" -Value 2 -Force -EA SilentlyContinue
                Set-DnsClientServerAddress -InterfaceAlias "*" -ServerAddresses "1.1.1.1","1.0.0.1" -EA SilentlyContinue
                Write-Log "DNS over HTTPS aktiviert (Cloudflare)" "INFO"
            } else {
                Write-Log "DoH: Windows 10 2004+ erforderlich" "WARNING"
            }
        }

        # ── Competitive-spezifische Optimierungen ─────────────────────────

        if ($Global:OptimizationConfig.TCPAckFreqComp) {
            $tcpParams = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
            Set-ItemProperty -Path $tcpParams -Name "TcpAckFrequency" -Value 1 -Force -EA SilentlyContinue
            Set-ItemProperty -Path $tcpParams -Name "TcpDelAckTicks"  -Value 0 -Force -EA SilentlyContinue
            # Per-Interface zusätzlich
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
                if (Test-Path $ifPath) {
                    Set-ItemProperty -Path $ifPath -Name "TcpAckFrequency" -Value 1 -Force -EA SilentlyContinue
                    Set-ItemProperty -Path $ifPath -Name "TcpDelAckTicks"  -Value 0 -Force -EA SilentlyContinue
                }
            }
            Write-Log "TCP ACK Frequency: 1 (kein Batching)" "INFO"
        }

        if ($Global:OptimizationConfig.NetworkBuffersComp) {
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -EA SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                # Small buffers for low queue latency (Competitive)
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Receive Buffers"  -DisplayValue "64"  -EA SilentlyContinue
                Set-NetAdapterAdvancedProperty -Name $adapter.Name -DisplayName "Transmit Buffers" -DisplayValue "64"  -EA SilentlyContinue
                Write-Log "NIC Buffers Competitive: RX/TX reduced to 64 (low queue latency)" "INFO"
            }
        }

        if ($Global:OptimizationConfig.CPUPriorityBoost) {
            # Spielprozesse auf AboveNormal/High Priorität — via Registry statt SetPriorityClass
            $cpuPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
            foreach ($proc in @("cs2.exe","VALORANT.exe","r5apex.exe","RainbowSix.exe","Overwatch.exe","FortniteClient-Win64-Shipping.exe")) {
                $procPath = "$cpuPath\$proc\PerfOptions"
                if (-not (Test-Path $procPath)) { New-Item -Path $procPath -Force | Out-Null }
                Set-ItemProperty -Path $procPath -Name "CpuPriorityClass" -Value 3 -Force -EA SilentlyContinue  # High Priority
            }
            Write-Log "CPU Priority Boost: Competitive Prozesse auf High" "INFO"
        }

        if ($Global:OptimizationConfig.PowerSchemeUltimate) {
            # Ultimate Performance Plan aktivieren (Win10 1803+)
            $existing = powercfg -list 2>&1 | Select-String "Ultimate"
            if (-not $existing) {
                # Plan erstellen falls nicht vorhanden
                powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-Null
            }
            $ultimateGuid = (powercfg -list 2>&1 | Select-String "Ultimate" | ForEach-Object { ($_ -split "\s+")[3] } | Select-Object -First 1)
            if ($ultimateGuid) {
                powercfg -setactive $ultimateGuid 2>&1 | Out-Null
                Write-Log "Ultimate Performance Plan activated: $ultimateGuid" "INFO"
            } else {
                # Fallback: High Performance
                powercfg -setactive SCHEME_MIN 2>&1 | Out-Null
                Write-Log "Ultimate Performance not available — High Performance activated" "INFO"
            }
        }

        Write-Log "Optimization completed" "SUCCESS"
        
    } catch {
        Write-Log "Optimization error: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Error: $_", "Optimization Error", "OK", "Error")
    }
}

function Test-DNSServer {
    param([string]$ServerIP)
    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $result = $ping.Send($ServerIP, 2000)
        return ($result.Status -eq 'Success')
    } catch {
        return $false
    } finally {
        if ($ping) { $ping.Dispose() }
    }
}

function Set-DNS { 
    param([string]$Type)
    
    try {
        $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
        
        if (-not $adapter) {
            [System.Windows.Forms.MessageBox]::Show("No active adapter found!", "Error", "OK", "Error")
            return
        }
        
        Backup-NetworkSettings
        
        $dnsServers = @()
        $serverName = ""
        
        switch ($Type) {
            "Cloudflare" { 
                $dnsServers = @("1.1.1.1", "1.0.0.1")
                $serverName = "Cloudflare"
            }
            "Google" { 
                $dnsServers = @("8.8.8.8", "8.8.4.4")
                $serverName = "Google"
            }
            "Reset" {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ResetServerAddresses
                Clear-DnsClientCache -EA SilentlyContinue
                [System.Windows.Forms.MessageBox]::Show("DNS reset to automatic.", "Success")
                Write-Log "DNS reset to automatic" "INFO"
                return
            }
        }
        
        if ($dnsServers.Count -gt 0) {
            Write-Log "Testing DNS server $($dnsServers[0])..." "INFO"
            
            if (Test-DNSServer $dnsServers[0]) {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers
                Clear-DnsClientCache -EA SilentlyContinue
                
                $msg = "DNS updated to $serverName`nPrimary: $($dnsServers[0])`nSecondary: $($dnsServers[1])"
                [System.Windows.Forms.MessageBox]::Show($msg, "Success")
                Write-Log "DNS changed to $serverName" "INFO"
            } else {
                $result = [System.Windows.Forms.MessageBox]::Show(
                    "DNS server $($dnsServers[0]) appears unreachable! Apply anyway?",
                    "Warning",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                
                if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers
                    Write-Log "DNS changed (forced)" "WARNING"
                } else {
                    Write-Log "DNS change cancelled" "INFO"
                }
            }
        }
        
    } catch {
        Write-Log "DNS change error: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("DNS change failed: $_", "Error", "OK", "Error")
    }
}

function Reset-NetworkAdapter {
    try {
        $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
        
        if (-not $adapter) {
            [System.Windows.Forms.MessageBox]::Show("No active adapter found!", "Error", "OK", "Error")
            return
        }
        
        $msg = "This will restart adapter: $($adapter.Name)`n`nInternet will disconnect for ~5 seconds. Continue?"
        $result = [System.Windows.Forms.MessageBox]::Show(
            $msg,
            "Confirm Restart",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "Restarting network adapter: $($adapter.Name)" "INFO"
            
            Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 3
            Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 2
            # FIX: Warten bis Adapter wieder "Up"
            $waited = 0
            while ((Get-NetAdapter -Name $adapter.Name -EA SilentlyContinue).Status -ne "Up" -and $waited -lt 10) {
                Start-Sleep -Seconds 1; $waited++
            }
            [System.Windows.Forms.MessageBox]::Show("Network adapter restarted successfully!", "Success")
            Write-Log "Network adapter restart completed (${waited}s wait)" "INFO"
        }
    } catch {
        Write-Log "Adapter reset error: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Reset failed: $_", "Error", "OK", "Error")
    }
}

function Optimize-RAM { 
    try {
        Write-Log "Starting RAM optimization..." "INFO"
        
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        
        # FIX: FreePhysicalMemory ist in KB, nicht Bytes
        $ramKB = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).FreePhysicalMemory
        $ramGB = if ($ramKB) { [math]::Round($ramKB / 1MB, 2) } else { "?" }
        $msg = "RAM garbage collection completed!`n`nFree RAM: ${ramGB} GB"
        [System.Windows.Forms.MessageBox]::Show($msg, "RAM Optimizer")
        
        Write-Log "RAM optimization completed. Free RAM: $ramBefore GB" "INFO"
    } catch {
        Write-Log "RAM optimization error: $_" "ERROR"
    }
}

# ============================================
# FPS COMPETITIVE OPTIMIZATIONS
# ============================================

function Apply-FPSOptimizations {
    Write-Log "=== APPLYING FPS COMPETITIVE OPTIMIZATIONS ===" "INFO"
    
    $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
    if (-not $adapter) {
        Write-Log "No active network adapter found" "WARNING"
        return $false
    }
    
    try {
        # Reduce buffering
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*ReceiveBuffers" -RegistryValue 64 -EA SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*TransmitBuffers" -RegistryValue 64 -EA SilentlyContinue
        
        # Disable interrupt coalescing
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*InterruptModeration" -RegistryValue 0 -EA SilentlyContinue
        
        # Disable flow control
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*FlowControl" -RegistryValue 0 -EA SilentlyContinue
        
        # UDP optimization
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Set-ItemProperty -Path $regPath -Name "MaxDatagramSize" -Value 65500 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "MaxUserPort" -Value 65534 -Type DWord -Force -EA SilentlyContinue
        
        # Reduce jitter
        Set-ItemProperty -Path $regPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -EA SilentlyContinue
        Set-ItemProperty -Path $regPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -EA SilentlyContinue
        
        # Minimize ACK delay
        $interfaces = Get-NetAdapter | Where-Object Status -eq 'Up'
        foreach ($int in $interfaces) {
            $intPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($int.InterfaceGuid)"
            if (Test-Path $intPath) {
                Set-ItemProperty -Path $intPath -Name "TcpAckFrequency" -Value 1 -Type DWord -Force -EA SilentlyContinue
                Set-ItemProperty -Path $intPath -Name "TCPNoDelay" -Value 1 -Type DWord -Force -EA SilentlyContinue
                Set-ItemProperty -Path $intPath -Name "TcpDelAckTicks" -Value 0 -Type DWord -Force -EA SilentlyContinue
            }
        }
        
        Write-Log "FPS optimizations applied successfully!" "SUCCESS"
        return $true
        
    } catch {
        Write-Log "FPS optimization error: $_" "ERROR"
        return $false
    }
}

function Restore-FPSOptimizations {
    $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
    if (-not $adapter) { return }
    
    try {
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*ReceiveBuffers" -RegistryValue 256 -EA SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*TransmitBuffers" -RegistryValue 256 -EA SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*InterruptModeration" -RegistryValue 1 -EA SilentlyContinue
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword "*FlowControl" -RegistryValue 3 -EA SilentlyContinue
        
        Write-Log "Normal settings restored" "SUCCESS"
    } catch {
        Write-Log "Restore error: $_" "ERROR"
    }
}

# ============================================
# CONFIG PROFILES SYSTEM
# ============================================

function Switch-Profile {
    param([string]$ProfileName)
    
    $profile = $script:Profiles[$ProfileName]
    if (-not $profile) { 
        Write-Log "Profile $ProfileName not found" "ERROR"
        return 
    }
    
    $oldProfile = $script:currentProfile
    $script:currentProfile = $ProfileName
    
    # Apply profile settings
    $script:AudioAlertEnabled = $profile.AudioAlerts
    
    # Apply FPS optimizations if FPS profile
    if ($ProfileName -eq "FPS") {
        $result = Apply-FPSOptimizations
        if ($result) {
            # FIX: BalloonTip statt MessageBox — blockiert nicht den Ping-Timer
            $trayIcon.ShowBalloonTip(5000, "⚡ Competitive Profile",
                "FPS optimizations applied:`nBuffering, ACK delay, interrupt coalescing adjusted.",
                [System.Windows.Forms.ToolTipIcon]::Info)
            Write-Log "FPS optimizations applied with profile switch" "INFO"
        }
    } elseif ($oldProfile -eq "FPS" -and $ProfileName -ne "FPS") {
        # Restore normal settings when switching away from FPS
        Restore-FPSOptimizations
    }
    
    # ── AUTO MTU ON PROFILE SWITCH ──────────────────────────────
    if ($profile.AutoMTU -and $script:TargetIP) {
        $mtuResult = [System.Windows.Forms.MessageBox]::Show(
            "Profile '$($profile.Name)' recommends MTU: $($profile.OptimalMTU)`n`n" +
            "Run automatic MTU scan now?`n" +
            "(Takes ~30 seconds — can be skipped)",
            "Auto MTU Check",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($mtuResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            Write-Log "Auto-MTU scan triggered by profile switch to $ProfileName" "INFO"
            # Run MTU optimizer in background (non-blocking)
            $null = [System.Threading.Tasks.Task]::Run({
                try {
                    # Find optimal MTU via ping with DF bit
                    $testMTUs = @(1480, 1450, 1400, 1350, 1300, 1280)
                    $bestMTU  = 1280
                    foreach ($mtu in $testMTUs) {
                        $packetSize = $mtu - 28  # IP + ICMP overhead
                        $pingResult = ping $script:TargetIP -f -l $packetSize -n 2 2>$null
                        if ($pingResult -match "Reply from") {
                            $bestMTU = $mtu
                            break
                        }
                    }
                    # Apply MTU
                    $adapterName = if ($script:selectedAdapter) {
                        $script:selectedAdapter
                    } else {
                        (Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1).Name
                    }
                    if ($adapterName) {
                        netsh interface ipv4 set subinterface "$adapterName" mtu=$bestMTU store=persistent 2>$null
                        Write-Log "Auto-MTU set to ${bestMTU} on $adapterName (Profile: $ProfileName)" "INFO"
                        $trayIcon.ShowBalloonTip(
                            4000, "NetNinja — MTU Set",
                            "Profile: $ProfileName`nMTU set to: ${bestMTU}",
                            [System.Windows.Forms.ToolTipIcon]::Info
                        )
                    }
                } catch {
                    Write-Log "Auto-MTU error: $_" "ERROR"
                }
            })
        }
    } elseif ($profile.OptimalMTU -and -not $profile.AutoMTU) {
        # Show recommended MTU as hint (no automatic scan)
        Write-Log "Profile $ProfileName recommends MTU: $($profile.OptimalMTU) (AutoMTU disabled)" "INFO"
    }
    # ────────────────────────────────────────────────────────────

    # Update UI visibility
    try {
        if ($profile.MonitorVisible) {
            Show-HUD
        } else {
            Hide-HUD
        }
    } catch {
        Write-Log "UI update error: $_" "WARNING"
    }
    
    # Update graph timeframe (with error handling)
    try {
        $script:currentTimeframe = $profile.GraphTimeframe
        
        if ($script:graphPanel) {
            switch ($profile.GraphTimeframe) {
                "60s"   { if ($btn60s) { $btn60s.PerformClick() } }
                "5min"  { if ($btn5min) { $btn5min.PerformClick() } }
                "30min" { if ($btn30min) { $btn30min.PerformClick() } }
                "1h"    { if ($btn1h) { $btn1h.PerformClick() } }
            }
        }
    } catch {
        Write-Log "Graph update error: $_" "WARNING"
    }
    
    # Update profile menu markers
    try {
        & $script:UpdateProfileMenu
    } catch {
        Write-Log "Menu update error: $_" "WARNING"
    }
    
    Add-TimelineEvent -Type "profile" -Msg "Profile → $($profile.Name)"
    Write-Log "Switched to profile: $($profile.Name)" "INFO"
    $trayIcon.ShowBalloonTip(
        3000,
        "Profile Changed",
        "Now using: $($profile.Name)",
        [System.Windows.Forms.ToolTipIcon]::Info
    )
}



function Export-HTMLReport {
    param([string]$Path = "")
    if (-not $Path) {
        $ts   = Get-Date -Format "yyyyMMdd_HHmmss"
        $name = "NetNinja_Report_$ts.html"
        $Path = Join-Path $script:scriptPath $name
        # FIX: Fallback auf Desktop wenn scriptPath nicht beschreibbar
        if (-not (Test-Path (Split-Path $Path) -PathType Container)) {
            $Path = Join-Path ([Environment]::GetFolderPath("Desktop")) $name
        }
    }

    # ── Daten sammeln ──────────────────────────────────────────
    $now          = Get-Date
    $sessionDur   = $now - $script:sessionStartTime
    $durStr       = "$([math]::Floor($sessionDur.TotalHours))h $($sessionDur.Minutes)m"
    $avgPing      = if ($script:totalPings -gt 0 -and $script:pingHistory.Count -gt 0) {
        [math]::Round(($script:pingHistory | Measure-Object -Average).Average, 1)
    } else { 0 }
    $lossP        = if ($script:totalPings -gt 0) {
        [math]::Round(($script:lostPings / $script:totalPings) * 100, 2)
    } else { 0 }
    $score        = [math]::Max(0, [math]::Round(100 - ($lossP*10) -
        (if ($script:maxLat -gt 200) {20} else {0}) -
        (if ($script:totalSpikes -gt 10) {10} else {0}), 0))
    $rating       = if ($score -ge 90) {"EXCELLENT"} elseif ($score -ge 75) {"GOOD"} elseif ($score -ge 50) {"FAIR"} else {"POOR"}
    $ratingColor  = if ($score -ge 90) {"#32dc50"} elseif ($score -ge 75) {"#ffe040"} elseif ($score -ge 50) {"#ff9900"} else {"#ff3232"}

    # ── Empfehlungen ───────────────────────────────────────────
    $recommendations = @()
    if ($lossP -gt 2)                { $recommendations += "⚠ Packet loss $lossP% — check cable/WiFi or contact ISP" }
    if ($script:currentJitter -gt 20){ $recommendations += "⚠ High jitter ${script:currentJitter}ms — consider wired connection" }
    if ($script:maxLat -gt 300)      { $recommendations += "⚠ Peak ping $($script:maxLat)ms — possible ISP congestion" }
    if ($avgPing -gt 100)            { $recommendations += "💡 Average ping ${avgPing}ms — try switching DNS or server region" }
    if ($script:totalSpikes -gt 20)  { $recommendations += "💡 $($script:totalSpikes) spikes detected — run Optimization Manager" }
    if ($recommendations.Count -eq 0){ $recommendations += "✅ Connection looks healthy — no issues detected" }

    # ── Ping-Verlauf als SVG-Sparkline ─────────────────────────
    $histArr = @($script:pingHistory)
    $svgW = 820; $svgH = 120; $svgPad = 10
    $svgPaths = ""
    if ($histArr.Count -gt 1) {
        $maxV = [math]::Max(($histArr | Measure-Object -Maximum).Maximum, 1)
        $step = ($svgW - 2*$svgPad) / [math]::Max(($histArr.Count-1), 1)
        $pts  = for ($i = 0; $i -lt $histArr.Count; $i++) {
            $x = $svgPad + $i * $step
            $y = $svgH - $svgPad - (($histArr[$i] / $maxV) * ($svgH - 2*$svgPad))
            "$([math]::Round($x,1)),$([math]::Round($y,1))"
        }
        $ptStr = $pts -join " "
        $svgPaths = "<polyline points='$ptStr' fill='none' stroke='#32dc50' stroke-width='2'/>"
        # Loss-Marker
        $lossArr2 = @($script:lossHistory60s)
        for ($li = 0; $li -lt [math]::Min($lossArr2.Count, $histArr.Count); $li++) {
            if ($lossArr2[$li]) {
                $lx = $svgPad + $li * $step
                $svgPaths += "<line x1='$([math]::Round($lx,1))' y1='$svgPad' x2='$([math]::Round($lx,1))' y2='$($svgH-$svgPad)' stroke='#ff3232' stroke-width='2' opacity='0.8'/>"
            }
        }
    }

    # ── Heatmap HTML-Tabelle ───────────────────────────────────
    $dayN  = @("Mon","Tue","Wed","Thu","Fri","Sat","Sun")
    $hmRows = ""
    $allHM = @()
    for ($d = 0; $d -le 6; $d++) {
        for ($h = 0; $h -le 23; $h++) {
            $c = $script:heatmapData[$d][$h].Count
            if ($c -gt 0) { $allHM += [int]($script:heatmapData[$d][$h].Sum / $c) }
        }
    }
    $hmMax = if ($allHM.Count -gt 0) { ($allHM | Measure-Object -Maximum).Maximum } else { 200 }
    if ($hmMax -lt 1) { $hmMax = 200 }

    for ($d = 0; $d -le 6; $d++) {
        $hmRows += "<tr><td style='color:#888;font-weight:bold;padding:2px 6px;'>$($dayN[$d])</td>"
        for ($h = 0; $h -le 23; $h++) {
            $c = $script:heatmapData[$d][$h].Count
            if ($c -gt 0) {
                $av   = [int]($script:heatmapData[$d][$h].Sum / $c)
                $norm = [math]::Min($av / $hmMax, 1.0)
                $r    = [int]([math]::Min($norm * 2, 1.0) * 200)
                $g2   = [int]([math]::Min((1-$norm)*2, 1.0) * 180)
                $bg   = "rgb($r,$g2,20)"
                $fg   = if ($norm -gt 0.5) { "#eee" } else { "#111" }
                $hmRows += "<td style='background:$bg;color:$fg;font-size:9px;padding:2px 3px;text-align:center;'>$av</td>"
            } else {
                $hmRows += "<td style='background:#1a1a24;color:#333;font-size:9px;padding:2px 3px;text-align:center;'>—</td>"
            }
        }
        $hmRows += "</tr>"
    }
    $hmHours = "<tr><td></td>"
    for ($h = 0; $h -le 23; $h++) { $hmHours += "<td style='color:#555;font-size:9px;text-align:center;'>$h</td>" }
    $hmHours += "</tr>"

    # ── Empfehlungs-HTML ───────────────────────────────────────
    $recHtml = ($recommendations | ForEach-Object { "<li>$_</li>" }) -join ""

    # ── HTML zusammensetzen ────────────────────────────────────
    $html = @"
<!DOCTYPE html><html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NetNinja Report — $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#0f0f16;color:#d8d8e4;font-family:'Segoe UI',sans-serif;font-size:14px;padding:32px}
  h1{color:#0096e0;font-size:26px;margin-bottom:4px}
  h2{color:#a0a0c0;font-size:15px;margin:28px 0 10px;border-bottom:1px solid #2a2a3a;padding-bottom:6px}
  .meta{color:#666;font-size:12px;margin-bottom:24px}
  .cards{display:flex;gap:14px;flex-wrap:wrap;margin-bottom:20px}
  .card{background:#16161e;border-radius:8px;padding:16px 22px;flex:1;min-width:130px;border:1px solid #2a2a3a}
  .card-val{font-size:28px;font-weight:bold;margin-bottom:2px}
  .card-label{color:#666;font-size:11px;text-transform:uppercase;letter-spacing:.06em}
  .score{font-size:42px;font-weight:bold;color:$ratingColor}
  .rating{font-size:13px;color:$ratingColor;letter-spacing:.12em;font-weight:bold}
  .graph-box{background:#0a0a10;border-radius:8px;padding:14px;margin-bottom:6px;border:1px solid #1e1e2a}
  .recs{background:#16161e;border-radius:8px;padding:16px 20px;border:1px solid #2a2a3a}
  .recs li{padding:5px 0;border-bottom:1px solid #1e1e2a;list-style:none}
  .recs li:last-child{border:none}
  table.hm{border-collapse:collapse;width:100%;font-size:11px}
  table.hm td{width:32px;height:28px}
  footer{margin-top:40px;color:#333;font-size:11px;text-align:center}
</style></head><body>
<h1>🥷 NetNinja — Connection Report</h1>
<div class="meta">Generated: $(Get-Date -Format 'dddd, MMMM d yyyy — HH:mm:ss') &nbsp;|&nbsp; Session: $durStr &nbsp;|&nbsp; Server: $script:TargetIP &nbsp;|&nbsp; Profile: $($script:currentProfile)</div>

<h2>Session Overview</h2>
<div class="cards">
  <div class="card"><div class="card-val" style="color:#32dc50">${avgPing}ms</div><div class="card-label">Avg Ping</div></div>
  <div class="card"><div class="card-val" style="color:#32dc50">$($script:minLat)ms</div><div class="card-label">Min Ping</div></div>
  <div class="card"><div class="card-val" style="color:#ff9900">$($script:maxLat)ms</div><div class="card-label">Max Ping</div></div>
  <div class="card"><div class="card-val" style="color:#ff3232">${lossP}%</div><div class="card-label">Packet Loss</div></div>
  <div class="card"><div class="card-val">$($script:currentJitter)ms</div><div class="card-label">Jitter</div></div>
  <div class="card"><div class="card-val">$($script:totalSpikes)</div><div class="card-label">Spikes</div></div>
  <div class="card"><div class="score">$score</div><div class="rating">$rating</div><div class="card-label">Score / 100</div></div>
</div>

<h2>Ping Graph — Last 60 Seconds</h2>
<div class="graph-box">
<svg width="$svgW" height="$svgH" style="display:block">
  <rect width="$svgW" height="$svgH" fill="#0a0a10"/>
  $svgPaths
</svg>
<div style="font-size:11px;color:#444;margin-top:4px">Green = latency &nbsp;|&nbsp; Red lines = packet loss</div>
</div>

<h2>Ping Heatmap — Average Latency by Hour &amp; Day</h2>
<div style="overflow-x:auto;margin-bottom:6px">
<table class="hm"><thead>$hmHours</thead><tbody>$hmRows</tbody></table>
</div>
<div style="font-size:11px;color:#444;margin-top:4px">Values in ms — empty cells = no data collected yet</div>

<h2>Recommendations</h2>
<div class="recs"><ul>$recHtml</ul></div>

<h2>Details</h2>
<div class="recs">
<ul>
  <li>Total pings: $($script:totalPings) &nbsp;|&nbsp; Lost: $($script:lostPings)</li>
  <li>Worst spike: $($script:worstSpikeValue)ms$(if ($script:worstSpikeTime) {" at $($script:worstSpikeTime.ToString('HH:mm:ss'))"} else {""})</li>
  <li>Profile: $($script:currentProfile) — $($script:profiles[$script:currentProfile].Name)</li>
  <li>Adapter: $(if ($script:selectedAdapter) {$script:selectedAdapter} else {"Auto"})</li>
  <li>NetNinja v$($CONFIG.Version)</li>
</ul>
</div>

<footer>NetNinja v$($CONFIG.Version) &nbsp;·&nbsp; Report generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') &nbsp;·&nbsp; github.com/netninja</footer>
</body></html>
"@

    try {
        $html | Out-File $Path -Encoding UTF8 -Force
        Write-Log "HTML report exported: $Path" "INFO"
        # Im Browser öffnen
        Start-Process $Path
        Notify-User "Report saved and opened in browser" -Ms 3000
    } catch {
        Write-Log "HTML report export failed: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Export failed: $_", "Error")
    }
}



# ── SOUND-PROFIL SYSTEM ────────────────────────────────────────
$script:soundProfile = @{
    Enabled       = $true
    Mode          = "system"   # "system" | "custom"
    CustomHigh    = ""         # Pfad zur MP3/WAV für High-Ping
    CustomCritical= ""         # Pfad zur MP3/WAV für Critical
    CustomLoss    = ""         # Pfad zur MP3/WAV für Packet Loss
    NotifyHigh    = $true      # Windows-Balloon für High-Ping
    NotifyCritical= $true      # Windows-Balloon für Critical
    NotifyLoss    = $true      # Windows-Balloon für Packet Loss
    CooldownSec   = 30         # Sekunden zwischen gleichen Alarmen
}
$script:soundCooldown = @{ High=0; Critical=0; Loss=0 }  # Unix-Timestamp letzter Alarm

function Play-AlertSound {
    param([string]$Level)   # "high" | "critical" | "loss"
    if (-not $script:soundProfile.Enabled) { return }

    $now = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    $key = switch ($Level) { "high"{"High"}; "critical"{"Critical"}; "loss"{"Loss"}; default{"High"} }
    if (($now - $script:soundCooldown[$key]) -lt $script:soundProfile.CooldownSec) { return }
    $script:soundCooldown[$key] = $now

    if ($script:soundProfile.Mode -eq "custom") {
        $file = switch ($Level) {
            "high"     { $script:soundProfile.CustomHigh }
            "critical" { $script:soundProfile.CustomCritical }
            "loss"     { $script:soundProfile.CustomLoss }
        }
        if ($file -and (Test-Path $file)) {
            try {
                # Windows Media Player COM — unterstützt MP3, WAV, WMA, OGG
                $wmp = New-Object -ComObject WMPlayer.OCX.7 -ErrorAction Stop
                $wmp.URL    = $file
                $wmp.settings.volume = 80
                $wmp.controls.play()
                Write-Log "Custom sound played: $file ($Level)" "INFO"
                return
            } catch {
                # Fallback auf System-Sound
                Write-Log "WMP unavailable, using system sound: $_" "WARNING"
            }
        }
    }
    # FIX: System-Sounds über Runspace — kein Start-Sleep im UI-Thread
    $lvl = $Level
    $null = [System.Threading.Tasks.Task]::Run([System.Action]{
        switch ($lvl) {
            "critical" {
                [System.Media.SystemSounds]::Hand.Play(); Start-Sleep -Milliseconds 150
                [System.Media.SystemSounds]::Hand.Play(); Start-Sleep -Milliseconds 150
                [System.Media.SystemSounds]::Hand.Play()
            }
            "high"  { [System.Media.SystemSounds]::Exclamation.Play() }
            "loss"  { [System.Media.SystemSounds]::Hand.Play() }
        }
    })
}

function Show-AlertSettings {
    $asF = New-Object System.Windows.Forms.Form
    $asF.Text            = "Ping Alert Settings"
    $asF.Size            = New-Object System.Drawing.Size(520, 480)
    $asF.MinimumSize     = New-Object System.Drawing.Size(520, 480)
    $asF.MaximumSize     = New-Object System.Drawing.Size(520, 480)
    $asF.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $asF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $asF.MaximizeBox     = $false; $asF.MinimizeBox = $false
    $asF.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $asF.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 228)

    $mkLabel = { param($txt,$x,$y,$w)
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $txt; $l.Location = New-Object System.Drawing.Point($x,$y)
        $l.Size = New-Object System.Drawing.Size($w,20)
        $l.Font = $script:Fonts.Small
        $l.ForeColor = [System.Drawing.Color]::FromArgb(160,160,180)
        $asF.Controls.Add($l)
    }
    $mkCheck = { param($txt,$x,$y,$checked)
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text = $txt; $c.Location = New-Object System.Drawing.Point($x,$y)
        $c.Size = New-Object System.Drawing.Size(220,22)
        $c.Font = $script:Fonts.Small; $c.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
        $c.BackColor = [System.Drawing.Color]::Transparent; $c.Checked = $checked
        $asF.Controls.Add($c); return $c
    }

    # Header
    $asTitle = New-Object System.Windows.Forms.Label
    $asTitle.Text = "Ping Alert & Sound Settings"
    $asTitle.Location = New-Object System.Drawing.Point(20,14); $asTitle.Size = New-Object System.Drawing.Size(480,28)
    $asTitle.Font = $script:Fonts.Title; $asTitle.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220)
    $asF.Controls.Add($asTitle)

    # Toggle
    $chkEnabled = & $mkCheck "Enable alert sounds & notifications" 20 54 $script:soundProfile.Enabled

    # Notification checkboxes
    & $mkLabel "Trigger notifications for:" 20 86 200
    $chkHigh     = & $mkCheck "High Ping (>${CONFIG.AlertHighPing}ms)"     30 108 $script:soundProfile.NotifyHigh
    $chkCritical = & $mkCheck "Critical Ping (>${CONFIG.AlertCriticalPing}ms)" 30 132 $script:soundProfile.NotifyCritical
    $chkLoss     = & $mkCheck "Packet Loss events"               30 156 $script:soundProfile.NotifyLoss

    # Cooldown
    & $mkLabel "Alert cooldown (seconds):" 20 188 180
    $numCooldown = New-Object System.Windows.Forms.NumericUpDown
    $numCooldown.Location = New-Object System.Drawing.Point(200,185)
    $numCooldown.Size = New-Object System.Drawing.Size(80,26)
    $numCooldown.Minimum=5; $numCooldown.Maximum=300; $numCooldown.Value=$script:soundProfile.CooldownSec
    $numCooldown.BackColor=[System.Drawing.Color]::FromArgb(30,30,42)
    $numCooldown.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215)
    $asF.Controls.Add($numCooldown)

    # Separator
    $sep = New-Object System.Windows.Forms.Label
    $sep.Location=New-Object System.Drawing.Point(20,220); $sep.Size=New-Object System.Drawing.Size(470,2)
    $sep.BackColor=[System.Drawing.Color]::FromArgb(38,40,52); $asF.Controls.Add($sep)

    # Sound Mode
    & $mkLabel "Sound mode:" 20 232 120
    $rdSystem = New-Object System.Windows.Forms.RadioButton
    $rdSystem.Text="System sounds"; $rdSystem.Location=New-Object System.Drawing.Point(140,229)
    $rdSystem.Size=New-Object System.Drawing.Size(140,22); $rdSystem.Font=$script:Fonts.Small
    $rdSystem.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $rdSystem.BackColor=[System.Drawing.Color]::Transparent
    $rdSystem.Checked=($script:soundProfile.Mode -eq "system"); $asF.Controls.Add($rdSystem)

    $rdCustom = New-Object System.Windows.Forms.RadioButton
    $rdCustom.Text="Custom sounds (MP3/WAV)"; $rdCustom.Location=New-Object System.Drawing.Point(290,229)
    $rdCustom.Size=New-Object System.Drawing.Size(200,22); $rdCustom.Font=$script:Fonts.Small
    $rdCustom.ForeColor=[System.Drawing.Color]::FromArgb(200,200,215); $rdCustom.BackColor=[System.Drawing.Color]::Transparent
    $rdCustom.Checked=($script:soundProfile.Mode -eq "custom"); $asF.Controls.Add($rdCustom)

    # Custom Sound File Pickers
    $mkFilePicker = { param($lbl,$y,$prop)
        & $mkLabel $lbl 20 $y 130
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location=New-Object System.Drawing.Point(152,$y); $tb.Size=New-Object System.Drawing.Size(250,24)
        $tb.BackColor=[System.Drawing.Color]::FromArgb(30,30,42); $tb.ForeColor=[System.Drawing.Color]::FromArgb(180,180,200)
        $tb.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
        $tb.Text = $script:soundProfile[$prop]; $asF.Controls.Add($tb)
        $btn = New-Object System.Windows.Forms.Button
        $btn.Text="…"; $btn.Location=New-Object System.Drawing.Point(410,$y); $btn.Size=New-Object System.Drawing.Size(36,24)
        $btn.BackColor=[System.Drawing.Color]::FromArgb(55,58,70); $btn.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200)
        $btn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $btn.FlatAppearance.BorderSize=0
        $btn.Cursor=[System.Windows.Forms.Cursors]::Hand; $btn.Font=$script:Fonts.Small
        $capTb=$tb; $btn.Add_Click({
            $ofd=New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter="Sound files|*.mp3;*.wav;*.wma;*.ogg|All files|*.*"
            $ofd.Title="Select sound file"
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $capTb.Text=$ofd.FileName }
        })
        $asF.Controls.Add($btn)
        return $tb
    }
    $tbHigh     = & $mkFilePicker "High ping sound:"     264 "CustomHigh"
    $tbCritical = & $mkFilePicker "Critical sound:"      294 "CustomCritical"
    $tbLoss     = & $mkFilePicker "Loss sound:"          324 "CustomLoss"

    $noteTxt = New-Object System.Windows.Forms.Label
    $noteTxt.Text="MP3/WAV played via Windows Media Player (WMP). WAV files are always supported."
    $noteTxt.Location=New-Object System.Drawing.Point(20,356); $noteTxt.Size=New-Object System.Drawing.Size(470,32)
    $noteTxt.Font=$script:Fonts.Tiny; $noteTxt.ForeColor=[System.Drawing.Color]::FromArgb(70,70,90)
    $asF.Controls.Add($noteTxt)

    # Test Button
    $testBtn = New-Object System.Windows.Forms.Button
    $testBtn.Text="▶ Test Sound"; $testBtn.Location=New-Object System.Drawing.Point(20,398)
    $testBtn.Size=New-Object System.Drawing.Size(130,36); $testBtn.BackColor=[System.Drawing.Color]::FromArgb(0,130,210)
    $testBtn.ForeColor=[System.Drawing.Color]::White; $testBtn.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $testBtn.FlatAppearance.BorderSize=0; $testBtn.Cursor=[System.Windows.Forms.Cursors]::Hand; $testBtn.Font=$script:Fonts.Small
    $testBtn.Add_Click({
        $script:soundProfile.Mode     = if ($rdCustom.Checked) {"custom"} else {"system"}
        $script:soundProfile.CustomHigh = $tbHigh.Text
        Play-AlertSound -Level "high"
    })
    $asF.Controls.Add($testBtn)

    # Save + Close
    $saveBtn2 = New-Object System.Windows.Forms.Button
    $saveBtn2.Text="Save"; $saveBtn2.Location=New-Object System.Drawing.Point(260,398)
    $saveBtn2.Size=New-Object System.Drawing.Size(100,36); $saveBtn2.BackColor=[System.Drawing.Color]::FromArgb(45,175,80)
    $saveBtn2.ForeColor=[System.Drawing.Color]::White; $saveBtn2.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $saveBtn2.FlatAppearance.BorderSize=0; $saveBtn2.Cursor=[System.Windows.Forms.Cursors]::Hand; $saveBtn2.Font=$script:Fonts.Small
    $saveBtn2.Add_Click({
        $script:soundProfile.Enabled       = $chkEnabled.Checked
        $script:soundProfile.NotifyHigh    = $chkHigh.Checked
        $script:soundProfile.NotifyCritical= $chkCritical.Checked
        $script:soundProfile.NotifyLoss    = $chkLoss.Checked
        $script:soundProfile.CooldownSec   = [int]$numCooldown.Value
        $script:soundProfile.Mode          = if ($rdCustom.Checked) {"custom"} else {"system"}
        $script:soundProfile.CustomHigh    = $tbHigh.Text
        $script:soundProfile.CustomCritical= $tbCritical.Text
        $script:soundProfile.CustomLoss    = $tbLoss.Text
        Write-Log "Sound profile saved: mode=$($script:soundProfile.Mode) enabled=$($script:soundProfile.Enabled)" "INFO"
        $asF.Close()
    })
    $asF.Controls.Add($saveBtn2)

    $closeBtn2 = New-Object System.Windows.Forms.Button
    $closeBtn2.Text="Cancel"; $closeBtn2.Location=New-Object System.Drawing.Point(375,398)
    $closeBtn2.Size=New-Object System.Drawing.Size(100,36); $closeBtn2.BackColor=[System.Drawing.Color]::FromArgb(55,58,70)
    $closeBtn2.ForeColor=[System.Drawing.Color]::FromArgb(185,185,200); $closeBtn2.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $closeBtn2.FlatAppearance.BorderSize=0; $closeBtn2.Cursor=[System.Windows.Forms.Cursors]::Hand
    $closeBtn2.DialogResult=[System.Windows.Forms.DialogResult]::Cancel
    $asF.Controls.Add($closeBtn2); $asF.CancelButton=$closeBtn2

    $asF.ShowDialog() | Out-Null
    $asF.Dispose()
}


# ══════════════════════════════════════════════════════════════
# DISCORD RICH PRESENCE — Named Pipe IPC
# ══════════════════════════════════════════════════════════════
$script:discordEnabled    = $false
$script:discordConnected  = $false
$script:discordPipe       = $null
$script:discordAppId      = "1234567890123456"  # Platzhalter — User muss eigene App-ID eintragen
$script:discordSessionStart = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

function Connect-Discord {
    try {
        # Discord IPC Pipe suchen (0..9)
        for ($i = 0; $i -le 9; $i++) {
            $pipeName = "discord-ipc-$i"
            try {
                $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName,
                    [System.IO.Pipes.PipeDirection]::InOut,
                    [System.IO.Pipes.PipeOptions]::None)
                $pipe.Connect(500)   # 500ms Timeout
                $script:discordPipe = $pipe
                Write-Log "Discord IPC connected on pipe $i" "INFO"
                break
            } catch { $null = $_ }
        }
        if (-not $script:discordPipe -or -not $script:discordPipe.IsConnected) {
            Write-Log "Discord not running or IPC unavailable" "WARNING"
            return $false
        }

        # Handshake senden (opcode 0)
        $handshake = '{"v":1,"client_id":"' + $script:discordAppId + '"}'
        Send-DiscordPacket -OpCode 0 -Data $handshake

        # Response lesen
        $resp = Read-DiscordPacket
        if ($resp -and $resp -match '"code":1000') {
            $script:discordConnected = $true
            Write-Log "Discord Rich Presence handshake OK" "INFO"
            Add-TimelineEvent -Type "info" -Msg "Discord Rich Presence connected"
            return $true
        }
        return $false
    } catch {
        Write-Log "Discord connect failed: $_" "WARNING"
        return $false
    }
}

function Send-DiscordPacket {
    param([int]$OpCode, [string]$Data)
    try {
        if (-not $script:discordPipe -or -not $script:discordPipe.IsConnected) { return }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
        $header = [byte[]]@(
            ($OpCode -band 0xFF), (($OpCode -shr 8) -band 0xFF),
            (($OpCode -shr 16) -band 0xFF), (($OpCode -shr 24) -band 0xFF),
            ($bytes.Length -band 0xFF), (($bytes.Length -shr 8) -band 0xFF),
            (($bytes.Length -shr 16) -band 0xFF), (($bytes.Length -shr 24) -band 0xFF)
        )
        $script:discordPipe.Write($header, 0, 8)
        $script:discordPipe.Write($bytes, 0, $bytes.Length)
        $script:discordPipe.Flush()
    } catch {
        $script:discordConnected = $false
        Write-Log "Discord send failed: $_" "WARNING"
    }
}

function Read-DiscordPacket {
    try {
        if (-not $script:discordPipe -or -not $script:discordPipe.IsConnected) { return $null }
        $header = New-Object byte[] 8
        $script:discordPipe.Read($header, 0, 8) | Out-Null
        $len = [BitConverter]::ToInt32($header, 4)
        if ($len -le 0 -or $len -gt 65536) { return $null }
        $buf = New-Object byte[] $len
        $script:discordPipe.Read($buf, 0, $len) | Out-Null
        return [System.Text.Encoding]::UTF8.GetString($buf)
    } catch { return $null }
}

function Update-DiscordPresence {
    param([int]$ping, [string]$profile, [int]$jitter, [decimal]$loss)
    if (-not $script:discordEnabled -or -not $script:discordConnected) { return }
    try {
        $state   = if ($ping -lt 75) {"🟢 Good"} elseif ($ping -lt 150) {"🟡 Fair"} elseif ($ping -lt 250) {"🟠 High"} else {"🔴 Critical"}
        $detail  = "${ping}ms  |  Jitter: ${jitter}ms  |  Loss: ${loss}%"
        $elapsed = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $nonce   = [System.Guid]::NewGuid().ToString()

        $payload = '{"cmd":"SET_ACTIVITY","args":{"pid":' + [System.Diagnostics.Process]::GetCurrentProcess().Id + ',"activity":{"details":"' + $detail + '","state":"' + $state + ' | ' + $profile + '","timestamps":{"start":' + $script:discordSessionStart + '},"assets":{"large_image":"logo","large_text":"NetNinja v' + $($CONFIG.Version) + '"},"party":{"id":"netninja"}}},"nonce":"' + $nonce + '"}'
        Send-DiscordPacket -OpCode 1 -Data $payload
        Read-DiscordPacket | Out-Null   # Response konsumieren
    } catch {
        $script:discordConnected = $false
        Write-Log "Discord presence update failed: $_" "WARNING"
    }
}

function Disconnect-Discord {
    try {
        if ($script:discordPipe) {
            $script:discordPipe.Close()
            $script:discordPipe.Dispose()
            $script:discordPipe = $null
        }
        $script:discordConnected = $false
        Write-Log "Discord disconnected" "INFO"
    } catch { $null = $_ }
}

function Show-DiscordSettings {
    $dF = New-Object System.Windows.Forms.Form
    $dF.Text = "Discord Rich Presence Settings"
    $dF.Size = New-Object System.Drawing.Size(480, 340)
    $dF.MinimumSize = $dF.MaximumSize = $dF.Size
    $dF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dF.MaximizeBox = $false; $dF.MinimizeBox = $false
    $dF.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $dF.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)

    $dTitle = New-Object System.Windows.Forms.Label
    $dTitle.Text = "Discord Rich Presence"
    $dTitle.Location = New-Object System.Drawing.Point(20, 14); $dTitle.Size = New-Object System.Drawing.Size(440, 28)
    $dTitle.Font = $script:Fonts.Title; $dTitle.ForeColor = [System.Drawing.Color]::FromArgb(88, 101, 242)
    $dF.Controls.Add($dTitle)

    $dSub = New-Object System.Windows.Forms.Label
    $dSub.Text = "Shows ping, jitter and profile in your Discord status"
    $dSub.Location = New-Object System.Drawing.Point(20, 44); $dSub.Size = New-Object System.Drawing.Size(440, 18)
    $dSub.Font = $script:Fonts.Small; $dSub.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 115)
    $dF.Controls.Add($dSub)

    # Status indicator
    $dStatus = New-Object System.Windows.Forms.Label
    $dStatus.Text = if ($script:discordConnected) {"● Connected to Discord"} else {"○ Not connected"}
    $dStatus.Location = New-Object System.Drawing.Point(20, 72); $dStatus.Size = New-Object System.Drawing.Size(440, 20)
    $dStatus.Font = $script:Fonts.Small
    $dStatus.ForeColor = if ($script:discordConnected) { [System.Drawing.Color]::FromArgb(50,210,80) } else { [System.Drawing.Color]::FromArgb(180,80,80) }
    $dF.Controls.Add($dStatus)

    # App-ID
    $dIdLabel = New-Object System.Windows.Forms.Label
    $dIdLabel.Text = "Discord App ID:"
    $dIdLabel.Location = New-Object System.Drawing.Point(20, 104); $dIdLabel.Size = New-Object System.Drawing.Size(130, 22)
    $dIdLabel.Font = $script:Fonts.Small; $dIdLabel.ForeColor = [System.Drawing.Color]::FromArgb(160,160,180)
    $dF.Controls.Add($dIdLabel)

    $dIdBox = New-Object System.Windows.Forms.TextBox
    $dIdBox.Text = $script:discordAppId
    $dIdBox.Location = New-Object System.Drawing.Point(155, 102); $dIdBox.Size = New-Object System.Drawing.Size(290, 24)
    $dIdBox.BackColor = [System.Drawing.Color]::FromArgb(30,30,42); $dIdBox.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $dIdBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $dIdBox.Font = $script:Fonts.Small
    $dF.Controls.Add($dIdBox)

    $dHint = New-Object System.Windows.Forms.Label
    $dHint.Text = "Create a free app at discord.com/developers — paste the Application ID above"
    $dHint.Location = New-Object System.Drawing.Point(20, 130); $dHint.Size = New-Object System.Drawing.Size(440, 32)
    $dHint.Font = $script:Fonts.Tiny; $dHint.ForeColor = [System.Drawing.Color]::FromArgb(70,70,95)
    $dF.Controls.Add($dHint)

    # Enable toggle
    $dChk = New-Object System.Windows.Forms.CheckBox
    $dChk.Text = "Enable Discord Rich Presence"
    $dChk.Location = New-Object System.Drawing.Point(20, 168); $dChk.Size = New-Object System.Drawing.Size(300, 22)
    $dChk.Font = $script:Fonts.Small; $dChk.ForeColor = [System.Drawing.Color]::FromArgb(200,200,215)
    $dChk.BackColor = [System.Drawing.Color]::Transparent; $dChk.Checked = $script:discordEnabled
    $dF.Controls.Add($dChk)

    # Preview
    $prevPanel = New-Object System.Windows.Forms.Panel
    $prevPanel.Location = New-Object System.Drawing.Point(20, 200); $prevPanel.Size = New-Object System.Drawing.Size(440, 66)
    $prevPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 33, 36)
    $dF.Controls.Add($prevPanel)
    $prevLabel = New-Object System.Windows.Forms.Label
    $prevLabel.Text = "Preview:`n  Playing NetNinja   $($script:currentLatency)ms | Jitter: $($script:currentJitter)ms | Loss: 0%`n  $( if($script:currentLatency -lt 75){'🟢 Good'} else {'🟡 Fair'} ) | $($script:currentProfile)"
    $prevLabel.Location = New-Object System.Drawing.Point(10, 8); $prevLabel.Size = New-Object System.Drawing.Size(420, 52)
    $prevLabel.Font = $script:Fonts.Small; $prevLabel.ForeColor = [System.Drawing.Color]::FromArgb(185,187,190)
    $prevPanel.Controls.Add($prevLabel)

    # Buttons
    $dConnect = New-Object System.Windows.Forms.Button
    $dConnect.Text = "Connect"; $dConnect.Location = New-Object System.Drawing.Point(20, 280)
    $dConnect.Size = New-Object System.Drawing.Size(110, 36); $dConnect.BackColor = [System.Drawing.Color]::FromArgb(88,101,242)
    $dConnect.ForeColor = [System.Drawing.Color]::White; $dConnect.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dConnect.FlatAppearance.BorderSize = 0; $dConnect.Cursor = [System.Windows.Forms.Cursors]::Hand; $dConnect.Font = $script:Fonts.Small
    $dConnect.Add_Click({
        $script:discordAppId = $dIdBox.Text.Trim()
        $ok = Connect-Discord
        $dStatus.Text = if ($ok) {"● Connected to Discord"} else {"○ Connection failed — is Discord running?"}
        $dStatus.ForeColor = if ($ok) { [System.Drawing.Color]::FromArgb(50,210,80) } else { [System.Drawing.Color]::FromArgb(180,80,80) }
    })
    $dF.Controls.Add($dConnect)

    $dSave = New-Object System.Windows.Forms.Button
    $dSave.Text = "Save"; $dSave.Location = New-Object System.Drawing.Point(148, 280)
    $dSave.Size = New-Object System.Drawing.Size(100, 36); $dSave.BackColor = [System.Drawing.Color]::FromArgb(45,175,80)
    $dSave.ForeColor = [System.Drawing.Color]::White; $dSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dSave.FlatAppearance.BorderSize = 0; $dSave.Cursor = [System.Windows.Forms.Cursors]::Hand; $dSave.Font = $script:Fonts.Small
    $dSave.Add_Click({
        $script:discordEnabled = $dChk.Checked
        $script:discordAppId   = $dIdBox.Text.Trim()
        if (-not $script:discordEnabled) { Disconnect-Discord }
        Write-Log "Discord settings saved: enabled=$($script:discordEnabled)" "INFO"
        $dF.Close()
    })
    $dF.Controls.Add($dSave)

    $dClose = New-Object System.Windows.Forms.Button
    $dClose.Text = "Cancel"; $dClose.Location = New-Object System.Drawing.Point(360, 280)
    $dClose.Size = New-Object System.Drawing.Size(100, 36); $dClose.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $dClose.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200); $dClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dClose.FlatAppearance.BorderSize = 0; $dClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $dClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dF.Controls.Add($dClose); $dF.CancelButton = $dClose
    $dF.ShowDialog() | Out-Null
    $dF.Dispose()
}


function Invoke-AutoDiagnosis {
    param([switch]$Detailed)
    $hist = @($script:pingHistory5min)
    $diag = [System.Collections.Generic.List[hashtable]]::new()

    if ($hist.Count -lt 10) {
        return @(@{ Severity="INFO"; Title="Not enough data"; Detail="Run monitor for at least 60 seconds before diagnosis." })
    }

    $stats = $hist | Measure-Object -Average -Maximum -Minimum
    $avg   = [math]::Round($stats.Average, 1)
    $max   = $stats.Maximum
    $min   = $stats.Minimum
    # FIX: Jitter = mittlere absolute Abweichung aufeinanderfolgender Pings (richtiger als max-min)
    $diffs2 = [System.Collections.Generic.List[double]]::new()
    for ($ii=1; $ii -lt $hist.Count; $ii++) { $diffs2.Add([math]::Abs($hist[$ii]-$hist[$ii-1])) }
    $jit = if ($diffs2.Count -gt 0) { [int](($diffs2 | Measure-Object -Average).Average) } else { $max - $min }
    $lossP = if ($script:totalPings -gt 0) { [math]::Round(($script:lostPings/$script:totalPings)*100,2) } else { 0 }

    # ── BUFFER BLOAT: Regelmäßige Spikes, kein echter Loss ────
    $spikes = ($hist | Where-Object { $_ -gt ($avg * 2.5) }).Count
    $spikeRatio = $spikes / $hist.Count
    if ($spikeRatio -gt 0.08 -and $lossP -lt 2) {
        $diag.Add(@{ Severity="WARN"; Title="Buffer Bloat detected"
            Detail="Ping spikes to ${max}ms (${spikes} events, avg ${avg}ms) without packet loss. Your router or ISP is buffering too aggressively. Fix: Enable QoS/SQM on router, reduce upload to 80% of max, or enable 'Disable QoS' in Optimization Manager." })
    }

    # ── ISP CONGESTION: Hoher Avg, zeitabhängig ────────────────
    $heatHour = [int](Get-Date).Hour
    $heatDay  = ([int](Get-Date).DayOfWeek + 6) % 7
    $heatCell = $script:heatmapData[$heatDay][$heatHour]
    $heatAvg  = if ($heatCell.Count -gt 5) { [int]($heatCell.Sum / $heatCell.Count) } else { 0 }
    if ($avg -gt 80 -and $heatAvg -gt 0 -and ($avg / [math]::Max($heatAvg, 1)) -gt 1.5) {
        $diag.Add(@{ Severity="WARN"; Title="ISP Congestion (time-based)"
            Detail="Current avg ${avg}ms is $([math]::Round($avg/$heatAvg,1))x higher than your historical avg ${heatAvg}ms for this time slot. ISP peak-hour congestion likely. Fix: Contact ISP, use VPN to bypass throttling, or schedule heavy downloads off-peak." })
    }

    # ── WLAN INTERFERENCE: Periodische Spikes ─────────────────
    if ($hist.Count -ge 30) {
        $diffs = for ($i=1; $i -lt $hist.Count; $i++) { [math]::Abs($hist[$i]-$hist[$i-1]) }
        $avgDiff = ($diffs | Measure-Object -Average).Average
        $bigJumps = ($diffs | Where-Object { $_ -gt 50 }).Count
        if ($bigJumps -gt 5 -and $jit -gt 40) {
            $diag.Add(@{ Severity="WARN"; Title="WiFi Interference / Unstable Link"
                Detail="High jitter ${jit}ms with $bigJumps sudden jumps detected. Likely WiFi channel collision, 2.4GHz interference, or weak signal. Fix: Switch to 5GHz, change WiFi channel (1/6/11), move closer to AP, or use Ethernet." })
        }
    }

    # ── PACKET LOSS: Spezifische Ursachen ─────────────────────
    if ($lossP -gt 1 -and $lossP -le 5) {
        $diag.Add(@{ Severity="WARN"; Title="Moderate packet loss ($lossP%)"
            Detail="Small but consistent loss. Possible causes: overloaded server, ISP routing issue, or NIC driver problem. Fix: Run MTU optimizer, check NIC settings in Optimization Manager, or try different DNS." })
    } elseif ($lossP -gt 5) {
        $diag.Add(@{ Severity="CRIT"; Title="Critical packet loss ($lossP%)"
            Detail="Severe loss — game is likely unplayable. Possible causes: cable fault, router overload, ISP outage, or IP conflict. Fix: Reboot router, swap network cable, run 'ipconfig /release & /renew', check for IP conflicts on LAN." })
    }

    # ── DNS PROBLEM: Erster Hop viel höher als Folge-Pings ─────
    if ($min -lt 5 -and $avg -gt 40) {
        $diag.Add(@{ Severity="INFO"; Title="Possible DNS latency hidden"
            Detail="Very low minimum (${min}ms) vs high average (${avg}ms) suggests initial DNS resolution adds latency. Fix: Switch to DoH DNS (1.1.1.1 or 8.8.8.8) in DNS Switcher." })
    }

    # ── BASELINE-ANALYSE: Alles gut ───────────────────────────
    if ($avg -lt 60 -and $lossP -lt 0.5 -and $jit -lt 30) {
        $diag.Add(@{ Severity="OK"; Title="Connection looks healthy"
            Detail="Avg: ${avg}ms  |  Jitter: ${jit}ms  |  Loss: ${lossP}%  |  Max: ${max}ms. No issues detected. Your connection is performing well for online gaming." })
    }

    # ── ROUTING ANOMALIE: Plötzlicher Anstieg ohne Recovery ───
    if ($hist.Count -ge 20) {
        $mid = [int]($hist.Count / 2)
        # FIX: Null-safe Slice — $hist als Array sicherstellen
        $h = @($hist)
        $firstHalf = $h[0..($mid-1)] | Measure-Object -Average
        $secHalf   = $h[$mid..($h.Count-1)] | Measure-Object -Average
        if ($firstHalf.Average -gt 1 -and $secHalf.Average -gt 1 -and ($secHalf.Average / $firstHalf.Average) -gt 1.6) {
            $diag.Add(@{ Severity="WARN"; Title="Routing change detected"
                Detail="Ping increased $([math]::Round($secHalf.Average/$firstHalf.Average,1))x in this session ($([math]::Round($firstHalf.Average,0))ms → $([math]::Round($secHalf.Average,0))ms). Your ISP may have rerouted traffic. Fix: Traceroute to identify new hop, consider VPN." })
        }
    }

    return $diag
}

function Show-DiagnosisReport {
    $diag = Invoke-AutoDiagnosis
    $dF = New-Object System.Windows.Forms.Form
    $dF.Text = "Auto-Diagnosis Report — NetNinja v5.0"
    $dF.Size = New-Object System.Drawing.Size(640, 560)
    $dF.MinimumSize = $dF.MaximumSize = $dF.Size
    $dF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $dF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dF.MaximizeBox = $false; $dF.BackColor = [System.Drawing.Color]::FromArgb(18,18,24)

    $hdr = New-Object System.Windows.Forms.Label
    $hdr.Text = "🔬  Connection Auto-Diagnosis"; $hdr.Location = New-Object System.Drawing.Point(20,14)
    $hdr.Size = New-Object System.Drawing.Size(600,28); $hdr.Font = $script:Fonts.Title
    $hdr.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220); $dF.Controls.Add($hdr)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "NetNinja analyzed your last $(($script:pingHistory5min).Count) pings — $(Get-Date -Format 'HH:mm:ss')"
    $sub.Location = New-Object System.Drawing.Point(20,44); $sub.Size = New-Object System.Drawing.Size(600,18)
    $sub.Font = $script:Fonts.Small; $sub.ForeColor = [System.Drawing.Color]::FromArgb(90,90,115)
    $dF.Controls.Add($sub)

    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(16,70); $panel.Size = New-Object System.Drawing.Size(606,424)
    $panel.AutoScroll = $true; $panel.BackColor = [System.Drawing.Color]::FromArgb(14,14,20)
    $dF.Controls.Add($panel)

    $y = 10
    foreach ($d in $diag) {
        $sev = $d.Severity
        $bgColor = switch ($sev) {
            "CRIT" { [System.Drawing.Color]::FromArgb(60,15,15) }
            "WARN" { [System.Drawing.Color]::FromArgb(55,40,10) }
            "OK"   { [System.Drawing.Color]::FromArgb(10,50,20) }
            default{ [System.Drawing.Color]::FromArgb(20,25,35) }
        }
        $fgColor = switch ($sev) {
            "CRIT" { [System.Drawing.Color]::FromArgb(255,80,80)  }
            "WARN" { [System.Drawing.Color]::FromArgb(255,200,40) }
            "OK"   { [System.Drawing.Color]::FromArgb(60,220,90)  }
            default{ [System.Drawing.Color]::FromArgb(100,160,220)}
        }
        $badge = switch ($sev) { "CRIT"{"🔴"}; "WARN"{"🟡"}; "OK"{"🟢"}; default{"🔵"} }

        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point(8,$y); $card.Size = New-Object System.Drawing.Size(578,0)
        $card.BackColor = $bgColor; $panel.Controls.Add($card)

        $tLbl = New-Object System.Windows.Forms.Label
        $tLbl.Text = "$badge  $($d.Title)"
        $tLbl.Location = New-Object System.Drawing.Point(10,8); $tLbl.Size = New-Object System.Drawing.Size(558,22)
        $tLbl.Font = $script:Fonts.Header   # FIX: gecacht, kein new Font
        $tLbl.ForeColor = $fgColor; $tLbl.BackColor = [System.Drawing.Color]::Transparent; $card.Controls.Add($tLbl)

        $dLbl = New-Object System.Windows.Forms.Label
        $dLbl.Text = $d.Detail; $dLbl.Location = New-Object System.Drawing.Point(10,32)
        $dLbl.Size = New-Object System.Drawing.Size(556,0); $dLbl.Font = $script:Fonts.Small
        $dLbl.ForeColor = [System.Drawing.Color]::FromArgb(190,190,210)
        $dLbl.BackColor = [System.Drawing.Color]::Transparent; $dLbl.MaximumSize = New-Object System.Drawing.Size(556,0)
        $dLbl.AutoSize = $true; $card.Controls.Add($dLbl)
        $card.Height = $dLbl.Bottom + 12; $y += $card.Height + 8
    }

    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = "Close"; $closeBtn.Location = New-Object System.Drawing.Point(460,500)
    $closeBtn.Size = New-Object System.Drawing.Size(120,36)
    $closeBtn.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(185,185,200)
    $closeBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $closeBtn.FlatAppearance.BorderSize = 0
    $closeBtn.Cursor = [System.Windows.Forms.Cursors]::Hand; $closeBtn.Font = $script:Fonts.Small
    $closeBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dF.Controls.Add($closeBtn)
    $dF.ShowDialog() | Out-Null
    $dF.Dispose()
}

function Show-SpeedTest {
    $stF = New-Object System.Windows.Forms.Form
    $stF.Text            = "ISP Speed Test"
    $stF.Size            = New-Object System.Drawing.Size(500, 420)
    $stF.MinimumSize     = New-Object System.Drawing.Size(500, 420)
    $stF.MaximumSize     = New-Object System.Drawing.Size(500, 420)
    $stF.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $stF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $stF.MaximizeBox     = $false; $stF.MinimizeBox = $false
    $stF.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $stF.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 228)

    # Header
    $stTitle = New-Object System.Windows.Forms.Label
    $stTitle.Text = "ISP Speed Test"
    $stTitle.Location = New-Object System.Drawing.Point(20, 14); $stTitle.Size = New-Object System.Drawing.Size(300, 28)
    $stTitle.Font = $script:Fonts.Title; $stTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 220)
    $stF.Controls.Add($stTitle)

    $stSub = New-Object System.Windows.Forms.Label
    $stSub.Text = "Native TCP throughput test — no external tools needed"
    $stSub.Location = New-Object System.Drawing.Point(20, 44); $stSub.Size = New-Object System.Drawing.Size(460, 18)
    $stSub.Font = $script:Fonts.Small; $stSub.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 115)
    $stF.Controls.Add($stSub)

    # Ergebnis-Karten
    $mkCard = {
        param($x, $label, $init)
        $card = New-Object System.Windows.Forms.Panel
        $card.Location = New-Object System.Drawing.Point($x, 75)
        $card.Size = New-Object System.Drawing.Size(140, 80)
        $card.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)
        $stF.Controls.Add($card)
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $init; $lbl.Location = New-Object System.Drawing.Point(0, 10)
        $lbl.Size = New-Object System.Drawing.Size(140, 38)
        $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
        $lbl.ForeColor = [System.Drawing.Color]::FromArgb(50, 220, 80)
        $lbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $card.Controls.Add($lbl)
        $sub = New-Object System.Windows.Forms.Label
        $sub.Text = $label; $sub.Location = New-Object System.Drawing.Point(0, 52)
        $sub.Size = New-Object System.Drawing.Size(140, 20)
        $sub.Font = $script:Fonts.Tiny; $sub.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 105)
        $sub.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $card.Controls.Add($sub)
        return $lbl
    }
    $dlLabel  = & $mkCard 20   "DOWNLOAD"  "--"
    $ulLabel  = & $mkCard 178  "UPLOAD"    "--"
    $latLabel = & $mkCard 336  "LATENCY"   "--"

    # Progress + Status
    $stProg = New-Object System.Windows.Forms.ProgressBar
    $stProg.Location = New-Object System.Drawing.Point(20, 175)
    $stProg.Size = New-Object System.Drawing.Size(458, 14)
    $stProg.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $stProg.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
    $stProg.Minimum = 0; $stProg.Maximum = 100; $stProg.Value = 0
    $stF.Controls.Add($stProg)

    $stStatus = New-Object System.Windows.Forms.Label
    $stStatus.Text = "Press Start to begin the speed test"
    $stStatus.Location = New-Object System.Drawing.Point(20, 195)
    $stStatus.Size = New-Object System.Drawing.Size(458, 18)
    $stStatus.Font = $script:Fonts.Small
    $stStatus.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 130)
    $stStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $stF.Controls.Add($stStatus)

    # Log-Box
    $stLog = New-Object System.Windows.Forms.RichTextBox
    $stLog.Location = New-Object System.Drawing.Point(20, 220)
    $stLog.Size = New-Object System.Drawing.Size(458, 110)
    $stLog.ReadOnly = $true
    $stLog.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 18)
    $stLog.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 170)
    $stLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $stLog.Font = New-Object System.Drawing.Font("Consolas", 8)
    $stF.Controls.Add($stLog)

    # Start + Close Buttons
    $stStart = New-Object System.Windows.Forms.Button
    $stStart.Text = "▶  Start Test"
    $stStart.Location = New-Object System.Drawing.Point(20, 348)
    $stStart.Size = New-Object System.Drawing.Size(200, 38)
    $stStart.BackColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
    $stStart.ForeColor = [System.Drawing.Color]::White
    $stStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $stStart.FlatAppearance.BorderSize = 0
    $stStart.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 150, 230)
    $stStart.Cursor = [System.Windows.Forms.Cursors]::Hand
    $stStart.Font = $script:Fonts.Header
    $stF.Controls.Add($stStart)

    $stClose = New-Object System.Windows.Forms.Button
    $stClose.Text = "Close"
    $stClose.Location = New-Object System.Drawing.Point(278, 348)
    $stClose.Size = New-Object System.Drawing.Size(200, 38)
    $stClose.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
    $stClose.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
    $stClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $stClose.FlatAppearance.BorderSize = 0
    $stClose.Cursor = [System.Windows.Forms.Cursors]::Hand
    $stClose.Font = $script:Fonts.Small
    $stClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $stF.Controls.Add($stClose)
    $stF.AcceptButton = $stClose

    # ── Test-Logik ────────────────────────────────────────────────
    $stStart.Add_Click({
        $stStart.Enabled = $false
        $stStart.Text    = "Testing..."
        $dlLabel.Text = "--"; $ulLabel.Text = "--"; $latLabel.Text = "--"
        $stProg.Value = 0
        $stLog.Clear()

        # Test-Endpunkte (öffentliche, schnelle Server)
        $endpoints = @(
            @{ Host="speed.cloudflare.com"; Port=80;   Path="/__down?bytes=5000000" }
            @{ Host="httpbin.org";          Port=80;   Path="/get" }
        )

        # Latenz-Test
        $stStatus.Text = "Testing latency..."
        $stLog.AppendText("Latency test...`n")
        $stF.Refresh()
        $latencies = @()
        for ($i = 0; $i -lt 5; $i++) {
            $sw2 = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $tc2 = New-Object System.Net.Sockets.TcpClient
                $ar2 = $tc2.BeginConnect("1.1.1.1", 80, $null, $null)
                if ($ar2.AsyncWaitHandle.WaitOne(2000, $false)) {
                    $tc2.EndConnect($ar2)
                    $sw2.Stop()
                    $latencies += $sw2.ElapsedMilliseconds
                }
                $tc2.Close()
            } catch { $null = $_ }
        }
        $avgLat = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average, 0) } else { 0 }
        $latLabel.Text = "${avgLat}ms"
        $latLabel.ForeColor = if ($avgLat -lt 50) { [System.Drawing.Color]::FromArgb(50,220,80) } elseif ($avgLat -lt 100) { [System.Drawing.Color]::FromArgb(255,200,0) } else { [System.Drawing.Color]::FromArgb(220,60,60) }
        $stLog.AppendText("  Avg latency: ${avgLat}ms`n")
        $stProg.Value = 25
        $stF.Refresh()

        # Download-Test via HTTP (WebClient chunks messen)
        $stStatus.Text = "Testing download speed..."
        $stLog.AppendText("Download test (5MB chunk from Cloudflare)...`n")
        $stF.Refresh()
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "NetNinja/$($CONFIG.Version)")
            [System.Net.ServicePointManager]::DefaultConnectionLimit = 4
            $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
            $data = $wc.DownloadData("https://speed.cloudflare.com/__down?bytes=5000000")
            $dlSw.Stop()
            $wc.Dispose()
            $dlMbps = [math]::Round(($data.Length * 8) / ($dlSw.Elapsed.TotalSeconds * 1000000), 2)
            $dlLabel.Text = "${dlMbps}`nMbps"
            $dlLabel.ForeColor = if ($dlMbps -gt 50) { [System.Drawing.Color]::FromArgb(50,220,80) } elseif ($dlMbps -gt 10) { [System.Drawing.Color]::FromArgb(255,200,0) } else { [System.Drawing.Color]::FromArgb(220,60,60) }
            $stLog.AppendText("  Download: ${dlMbps} Mbps ($([math]::Round($data.Length/1048576,1))MB in $([math]::Round($dlSw.Elapsed.TotalSeconds,1))s)`n")
            Add-TimelineEvent -Type "speed" -Msg "Speed test: DL ${dlMbps}Mbps, LAT ${avgLat}ms"
        } catch {
            $dlLabel.Text = "ERR"
            $stLog.AppendText("  Download failed: $_`n")
        }
        $stProg.Value = 75
        $stF.Refresh()

        # Upload-Test via HTTP POST
        $stStatus.Text = "Testing upload speed..."
        $stLog.AppendText("Upload test (2MB POST to httpbin)...`n")
        $stF.Refresh()
        try {
            $upData = New-Object byte[] (2 * 1024 * 1024)
            [System.Random]::new().NextBytes($upData)
            $wc2 = New-Object System.Net.WebClient
            $wc2.Headers.Add("User-Agent", "NetNinja/$($CONFIG.Version)")
            $wc2.Headers.Add("Content-Type", "application/octet-stream")
            $ulSw = [System.Diagnostics.Stopwatch]::StartNew()
            $res = $wc2.UploadData("https://httpbin.org/post", $upData)
            $ulSw.Stop()
            $wc2.Dispose()
            $ulMbps = [math]::Round(($upData.Length * 8) / ($ulSw.Elapsed.TotalSeconds * 1000000), 2)
            $ulLabel.Text = "${ulMbps}`nMbps"
            $ulLabel.ForeColor = if ($ulMbps -gt 20) { [System.Drawing.Color]::FromArgb(50,220,80) } elseif ($ulMbps -gt 5) { [System.Drawing.Color]::FromArgb(255,200,0) } else { [System.Drawing.Color]::FromArgb(220,60,60) }
            $stLog.AppendText("  Upload: ${ulMbps} Mbps (2MB in $([math]::Round($ulSw.Elapsed.TotalSeconds,1))s)`n")
        } catch {
            $ulLabel.Text = "N/A"
            $stLog.AppendText("  Upload test skipped (endpoint unavailable)`n")
        }
        $stProg.Value = 100
        $stStatus.Text = "Test complete"
        $stLog.AppendText("Done.`n")
        $stStart.Enabled = $true
        $stStart.Text = "▶  Run Again"
        Write-Log "Speed test complete: DL=$($dlLabel.Text) UP=$($ulLabel.Text) LAT=${avgLat}ms" "INFO"
    })

    $stF.ShowDialog() | Out-Null
    $stF.Dispose()
}

function Show-Heatmap {
    $hF = New-Object System.Windows.Forms.Form
    $hF.Text            = "Ping Heatmap — Average Latency by Hour & Day"
    $hF.Size            = New-Object System.Drawing.Size(900, 540)
    $hF.MinimumSize     = New-Object System.Drawing.Size(900, 540)
    $hF.MaximumSize     = New-Object System.Drawing.Size(900, 540)
    $hF.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $hF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $hF.MaximizeBox     = $false
    $hF.MinimizeBox     = $false
    $hF.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $hF.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 228)

    # Header
    $hTitle = New-Object System.Windows.Forms.Label
    $hTitle.Text      = "Ping Heatmap"
    $hTitle.Location  = New-Object System.Drawing.Point(20, 14)
    $hTitle.Size      = New-Object System.Drawing.Size(300, 28)
    $hTitle.Font      = $script:Fonts.Title
    $hTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 220)
    $hF.Controls.Add($hTitle)

    $hSub = New-Object System.Windows.Forms.Label
    $hSub.Text      = "Average ping per hour of day × day of week  (darker = higher latency)"
    $hSub.Location  = New-Object System.Drawing.Point(20, 44)
    $hSub.Size      = New-Object System.Drawing.Size(860, 18)
    $hSub.Font      = $script:Fonts.Small
    $hSub.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 140)
    $hF.Controls.Add($hSub)

    # Heatmap Panel (GDI-gezeichnet)
    $hmPanel = New-Object System.Windows.Forms.Panel
    $hmPanel.Location  = New-Object System.Drawing.Point(16, 68)
    $hmPanel.Size      = New-Object System.Drawing.Size(860, 390)
    $hmPanel.BackColor = [System.Drawing.Color]::FromArgb(14, 14, 20)
    $hF.Controls.Add($hmPanel)

    $dayNames  = @("Mon","Tue","Wed","Thu","Fri","Sat","Sun")
    $cellW = 33; $cellH = 48
    $marginL = 42; $marginT = 26

    $hmPanel.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::FromArgb(14, 14, 20))

        # Globales Max für Normalisierung
        $allVals = @()
        for ($d = 0; $d -le 6; $d++) {
            for ($h = 0; $h -le 23; $h++) {
                $c = $script:heatmapData[$d][$h].Count
                if ($c -gt 0) { $allVals += [int]($script:heatmapData[$d][$h].Sum / $c) }
            }
        }
        $globalMax = if ($allVals.Count -gt 0) { ($allVals | Measure-Object -Maximum).Maximum } else { 200 }
        if ($globalMax -lt 1) { $globalMax = 200 }

        $fntSmall = $script:gfxCache.FontHeatmapSm
        $fntTiny  = $script:gfxCache.FontHeatmapTiny

        # Stunden-Header (0-23)
        for ($h = 0; $h -le 23; $h++) {
            $x = $marginL + $h * $cellW + ($cellW / 2) - 7
            $lbl = if ($h % 3 -eq 0) { "$h" } else { "" }
            if ($lbl) {
                $g.DrawString($lbl, $fntSmall,
                    [System.Drawing.Brushes]::DimGray,
                    [float]$x, [float]4)
            }
        }

        # Tag-Labels (Mo-So) + Zellen
        for ($d = 0; $d -le 6; $d++) {
            $y = $marginT + $d * $cellH
            $g.DrawString($dayNames[$d], $fntSmall,
                [System.Drawing.Brushes]::DimGray,
                [float]2, [float]($y + $cellH/2 - 8))

            for ($h = 0; $h -le 23; $h++) {
                $x    = $marginL + $h * $cellW
                $cnt  = $script:heatmapData[$d][$h].Count
                $avg  = if ($cnt -gt 0) { [int]($script:heatmapData[$d][$h].Sum / $cnt) } else { -1 }

                if ($avg -ge 0) {
                    $norm = [math]::Min($avg / $globalMax, 1.0)
                    # Farb-Gradient: Grün(niedrig) → Gelb → Rot(hoch)
                    $r = [int]([math]::Min($norm * 2,   1.0) * 220)
                    $g2= [int]([math]::Min((1-$norm)*2, 1.0) * 200)
                    $cellColor = [System.Drawing.Color]::FromArgb(220, $r, $g2, 30)
                    $brush = New-Object System.Drawing.SolidBrush($cellColor)
                    $g.FillRectangle($brush, $x+1, $y+1, $cellW-2, $cellH-2)
                    $brush.Dispose()

                    # Wert-Text im Feld
                    $valTxt = "${avg}ms"
                    $txtBrush = if ($norm -gt 0.5) {
                        New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(240,240,240))
                    } else {
                        New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,30,30))
                    }
                    $g.DrawString($valTxt, $fntTiny, $txtBrush,
                        [float]($x + 2), [float]($y + $cellH/2 - 6))
                    $txtBrush.Dispose()
                } else {
                    # Keine Daten
                    $emptyBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(28,28,38))
                    $g.FillRectangle($emptyBrush, $x+1, $y+1, $cellW-2, $cellH-2)
                    $emptyBrush.Dispose()
                    $g.DrawString("—", $fntTiny,
                        [System.Drawing.Brushes]::DimGray,
                        [float]($x + 9), [float]($y + $cellH/2 - 6))
                }
            }
        }

        # Grid-Linien
        $gridPen = $script:gfxCache.PenGrid
        for ($h = 0; $h -le 24; $h++) {
            $x = $marginL + $h * $cellW
            $g.DrawLine($gridPen, $x, $marginT, $x, $marginT + 7*$cellH)
        }
        for ($d = 0; $d -le 7; $d++) {
            $y = $marginT + $d * $cellH
            $g.DrawLine($gridPen, $marginL, $y, $marginL + 24*$cellW, $y)
        }
        # PenGrid gecacht
        # gecacht; # gecacht
    })

    # Legend
    $legPanel = New-Object System.Windows.Forms.Panel
    $legPanel.Location  = New-Object System.Drawing.Point(16, 462)
    $legPanel.Size      = New-Object System.Drawing.Size(860, 20)
    $legPanel.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $hF.Controls.Add($legPanel)
    $legPanel.Add_Paint({
        param($s,$e)
        $g = $e.Graphics
        $g.DrawString("Low latency", $script:Fonts.Tiny,
            [System.Drawing.Brushes]::DimGray, [float]0, [float]3)
        for ($i = 0; $i -lt 200; $i++) {
            $norm = $i / 200.0
            $r = [int]([math]::Min($norm * 2, 1.0) * 220)
            $g2= [int]([math]::Min((1-$norm)*2, 1.0) * 200)
            $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, $r, $g2, 30))
            $g.FillRectangle($b, 80 + $i, 6, 1, 10)
            $b.Dispose()
        }
        $g.DrawString("High latency", $script:Fonts.Tiny,
            [System.Drawing.Brushes]::DimGray, [float]285, [float]3)
    })

    # Clear + Close Buttons
    $hmClearBtn = New-Object System.Windows.Forms.Button
    $hmClearBtn.Text     = "Clear Data"
    $hmClearBtn.Location = New-Object System.Drawing.Point(620, 490)
    $hmClearBtn.Size     = New-Object System.Drawing.Size(110, 32)
    $hmClearBtn.BackColor= [System.Drawing.Color]::FromArgb(195, 55, 55)
    $hmClearBtn.ForeColor= [System.Drawing.Color]::White
    $hmClearBtn.FlatStyle= [System.Windows.Forms.FlatStyle]::Flat
    $hmClearBtn.FlatAppearance.BorderSize = 0
    $hmClearBtn.Cursor   = [System.Windows.Forms.Cursors]::Hand
    $hmClearBtn.Font     = $script:Fonts.Small
    $hmClearBtn.Add_Click({
        for ($dd = 0; $dd -le 6; $dd++) {
            for ($hh = 0; $hh -le 23; $hh++) {
                $script:heatmapData[$dd][$hh] = @{ Sum = 0; Count = 0 }
            }
        }
        if (Test-Path $script:heatmapFile) { Remove-Item $script:heatmapFile -Force -EA SilentlyContinue }
        $hmPanel.Invalidate()
        Write-Log "Heatmap data cleared by user" "INFO"
    })
    $hF.Controls.Add($hmClearBtn)

    $hmCloseBtn = New-Object System.Windows.Forms.Button
    $hmCloseBtn.Text     = "Close"
    $hmCloseBtn.Location = New-Object System.Drawing.Point(745, 490)
    $hmCloseBtn.Size     = New-Object System.Drawing.Size(110, 32)
    $hmCloseBtn.BackColor= [System.Drawing.Color]::FromArgb(55, 58, 70)
    $hmCloseBtn.ForeColor= [System.Drawing.Color]::FromArgb(185, 185, 200)
    $hmCloseBtn.FlatStyle= [System.Windows.Forms.FlatStyle]::Flat
    $hmCloseBtn.FlatAppearance.BorderSize = 0
    $hmCloseBtn.Cursor   = [System.Windows.Forms.Cursors]::Hand
    $hmCloseBtn.Font     = $script:Fonts.Small
    $hmCloseBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $hF.Controls.Add($hmCloseBtn)
    $hF.AcceptButton = $hmCloseBtn

    $hF.ShowDialog() | Out-Null
    $hF.Dispose()
}

function Show-StatsDashboard {
    $statsForm = New-Object System.Windows.Forms.Form
    $statsForm.Text = "Statistics Dashboard"
    $statsForm.Size        = New-Object System.Drawing.Size(640, 720)
    $statsForm.MinimumSize = New-Object System.Drawing.Size(600, 620)
    $statsForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $statsForm.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $statsForm.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)
    $statsForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $statsForm.MaximizeBox = $false
    
    # Calculate statistics
    $sessionDuration = (Get-Date) - $script:sessionStartTime
    $hours = [math]::Floor($sessionDuration.TotalHours)
    $minutes = $sessionDuration.Minutes
    $seconds = $sessionDuration.Seconds
    
    $avgLat = if ($script:totalPings -gt 0 -and $script:pingHistory.Count -gt 0) {
        $avgMeasure = ($script:pingHistory | Measure-Object -Average).Average
        if ($avgMeasure) {
            $script:avgLatency = [math]::Round($avgMeasure, 2)
            $script:avgLatency
        } else { 0 }
    } else { 0 }
    
    $lossRate = if ($script:totalPings -gt 0) {
        [math]::Round(($script:lostPings / $script:totalPings) * 100, 2)
    } else { 0 }
    
    # Calculate stability score (0-100)
    $stabilityScore = 100
    if ($lossRate -gt 0) { $stabilityScore -= ($lossRate * 10) }
    if ($script:maxLat -gt 200) { $stabilityScore -= 20 }
    if ($script:totalSpikes -gt 10) { $stabilityScore -= 10 }
    if ($stabilityScore -lt 0) { $stabilityScore = 0 }
    
    # FIX: StdDev nutzt $avgLat (bereits berechnet) statt erneuten Measure-Object
    $stdDev = 0
    if ($script:pingHistory.Count -gt 1 -and $avgLat -gt 0) {
        $variance = ($script:pingHistory | ForEach-Object { [math]::Pow($_ - $avgLat, 2) } | Measure-Object -Average).Average
        if ($variance) { $stdDev = [math]::Round([math]::Sqrt($variance), 2) }
    }
    
    # Main text box
    $statsText = New-Object System.Windows.Forms.RichTextBox
    $statsText.Location = New-Object System.Drawing.Point(20, 20)
    $statsText.Size = New-Object System.Drawing.Size(590, 560)
    $statsText.ReadOnly = $true
    $statsText.Font = $script:Fonts.Mono
    $statsText.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $statsText.ForeColor = [System.Drawing.Color]::FromArgb(190, 190, 205)
    $statsText.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    
    # Build stats text
    $statsContent = @"
===================================================
           SESSION STATISTICS
===================================================

DURATION
  Session Started:    $($script:sessionStartTime.ToString('yyyy-MM-dd HH:mm:ss'))
  Uptime:             ${hours}h ${minutes}m ${seconds}s

PING STATISTICS
  Total Pings:        $($script:totalPings)
  Packet Loss:        $lossRate% ($script:lostPings packets)
  
LATENCY
  Current:            $script:currentLatency ms
  Average:            $avgLat ms
  Minimum:            $script:minLat ms
  Maximum:            $script:maxLat ms
  Std. Deviation:     $stdDev ms

STABILITY
  Stability Score:    $([math]::Round($stabilityScore, 0))/100
  Total Spikes:       $script:totalSpikes (>150ms)
  Worst Spike:        $script:worstSpikeValue ms
  Spike Time:         $(if ($script:worstSpikeTime) { $script:worstSpikeTime.ToString('HH:mm:ss') } else { 'N/A' })

CONNECTION
  Server:             $script:TargetIP
  Auto-detected:      $(if ($script:IsIPDetected) { 'Yes' } else { 'No' })

PERFORMANCE RATING
$(if ($stabilityScore -ge 90) {
"  Rating:             EXCELLENT"
} elseif ($stabilityScore -ge 75) {
"  Rating:             GOOD"
} elseif ($stabilityScore -ge 50) {
"  Rating:             FAIR"
} else {
"  Rating:             POOR"
})

RECOMMENDATIONS
$(if ($lossRate -gt 5) {
"  - High packet loss detected! Check connection."
} elseif ($lossRate -gt 1) {
"  - Moderate packet loss. Monitor closely."
} else {
"  - Packet loss is acceptable."
})
$(if ($script:maxLat -gt 300) {
"  - Very high latency spikes detected!"
} elseif ($script:maxLat -gt 150) {
"  - High latency spikes present."
} else {
"  - Latency is stable."
})
$(if ($stdDev -gt 30) {
"  - High latency variance. Connection unstable."
} elseif ($stdDev -gt 15) {
"  - Moderate variance detected."
} else {
"  - Low variance. Connection stable."
})

===================================================
"@
    
    $statsText.Text = $statsContent
    $statsForm.Controls.Add($statsText)
    
    # Export buttons
    $exportBtn = New-Object System.Windows.Forms.Button
    $exportBtn.Text = "Export to CSV"
    $exportBtn.Location = New-Object System.Drawing.Point(20, 600)
    $exportBtn.Size = New-Object System.Drawing.Size(130, 40)
    $exportBtn.BackColor = [System.Drawing.Color]::FromArgb(45, 175, 80)
    $exportBtn.ForeColor = [System.Drawing.Color]::White
    $exportBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $exportBtn.FlatAppearance.BorderSize = 0
    $exportBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55, 195, 95)
    $exportBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    
    $exportBtn.Add_Click({
        try {
            # Recalculate values in this scope
            $sessionDur = (Get-Date) - $script:sessionStartTime
            $hrs = [math]::Floor($sessionDur.TotalHours)
            $mins = $sessionDur.Minutes
            $secs = $sessionDur.Seconds
            
            $loss = if ($script:totalPings -gt 0) {
                [math]::Round(($script:lostPings / $script:totalPings) * 100, 2)
            } else { 0 }
            
            $avg = if ($script:pingHistory.Count -gt 0) {
                $avgM = ($script:pingHistory | Measure-Object -Average).Average
                if ($avgM) { [math]::Round($avgM, 2) } else { 0 }
            } else { 0 }
            
            $std = 0
            if ($script:pingHistory.Count -gt 1) {
                $avgM = ($script:pingHistory | Measure-Object -Average).Average
                if ($avgM) {
                    $var = ($script:pingHistory | ForEach-Object { [math]::Pow($_ - $avgM, 2) } | Measure-Object -Average).Average
                    if ($var) { $std = [math]::Round([math]::Sqrt($var), 2) }
                }
            }
            
            $score = 100
            if ($loss -gt 0) { $score -= ($loss * 10) }
            if ($script:maxLat -gt 200) { $score -= 20 }
            if ($script:totalSpikes -gt 10) { $score -= 10 }
            if ($score -lt 0) { $score = 0 }
            $score = [math]::Round($score, 0)
            
            $csvName = "stats_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $csvPath = Join-Path $script:scriptPath $csvName
            if (-not (Test-Path (Split-Path $csvPath) -PathType Container)) {
                $csvPath = Join-Path ([Environment]::GetFolderPath("Desktop")) $csvName
            }
            $csvData = @"
"Metric","Value"
"Session Start","$($script:sessionStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
"Duration","${hrs}h ${mins}m ${secs}s"
"Total Pings","$($script:totalPings)"
"Packet Loss %","$loss"
"Packets Lost","$script:lostPings"
"Current Ping","$script:currentLatency"
"Average Ping","$avg"
"Min Ping","$script:minLat"
"Max Ping","$script:maxLat"
"Std Deviation","$std"
"Stability Score","$score"
"Total Spikes","$script:totalSpikes"
"Worst Spike","$script:worstSpikeValue"
"Server","$script:TargetIP"
"@
            $csvData | Out-File $csvPath -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("Stats exported to:`n$csvPath", "Export Success")
            Write-Log "Stats exported to CSV: $csvPath" "INFO"
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Export failed: $_", "Error", "OK", "Error")
        }
    })
    $statsForm.Controls.Add($exportBtn)
    
    $refreshBtn = New-Object System.Windows.Forms.Button
    $refreshBtn.Text = "Refresh"
    $refreshBtn.Location = New-Object System.Drawing.Point(160, 600)
    $refreshBtn.Size = New-Object System.Drawing.Size(130, 40)
    $refreshBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
    $refreshBtn.ForeColor = [System.Drawing.Color]::White
    $refreshBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $refreshBtn.FlatAppearance.BorderSize = 0
    $refreshBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 150, 230)
    $refreshBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    
    $refreshBtn.Add_Click({
        # FIX: Timer-Tick manuell auslösen statt Form schließen und neu öffnen
        $statsRefreshTimer.Stop()
        $sessionDur2 = (Get-Date) - $script:sessionStartTime
        $loss2 = if ($script:totalPings -gt 0) { [math]::Round(($script:lostPings / $script:totalPings) * 100, 2) } else { 0 }
        $avg2  = if ($script:pingHistory.Count -gt 0) {
            $m = ($script:pingHistory | Measure-Object -Average).Average
            if ($m) { [math]::Round($m, 2) } else { 0 }
        } else { 0 }
        $score2 = [math]::Max(0, [math]::Round(100 - ($loss2*10) - (if ($script:maxLat -gt 200) {20} else {0}) - (if ($script:totalSpikes -gt 10) {10} else {0}), 0))
        $rating2 = if ($score2 -ge 90) {"EXCELLENT"} elseif ($score2 -ge 75) {"GOOD"} elseif ($score2 -ge 50) {"FAIR"} else {"POOR"}
        $hrs2 = [math]::Floor($sessionDur2.TotalHours); $mins2 = $sessionDur2.Minutes; $secs2 = $sessionDur2.Seconds
        $newText = $statsText.Text -replace 'Uptime:.*', "Uptime:             ${hrs2}h ${mins2}m ${secs2}s"
        $newText = $newText -replace 'Current:.*', "Current:            $script:currentLatency ms"
        $newText = $newText -replace 'Average:.*', "Average:            $avg2 ms"
        $newText = $newText -replace 'Packet Loss:.*', "Packet Loss:        $loss2% ($script:lostPings packets)"
        $newText = $newText -replace 'Total Pings:.*', "Total Pings:        $($script:totalPings)"
        $newText = $newText -replace 'Stability Score:.*', "Stability Score:    $score2/100"
        $newText = $newText -replace 'Rating:.*', "  Rating:             $rating2"
        $statsText.Text = $newText
        $statsRefreshTimer.Start()
    })
    $statsForm.Controls.Add($refreshBtn)
    
    $resetBtn = New-Object System.Windows.Forms.Button
    $resetBtn.Text = "Reset Stats"
    $resetBtn.Location = New-Object System.Drawing.Point(300, 600)
    $resetBtn.Size = New-Object System.Drawing.Size(130, 40)
    $resetBtn.BackColor = [System.Drawing.Color]::FromArgb(195, 55, 55)
    $resetBtn.ForeColor = [System.Drawing.Color]::White
    $resetBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $resetBtn.FlatAppearance.BorderSize = 0
    $resetBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(215, 70, 70)
    $resetBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    
    $resetBtn.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Reset all statistics?`n`nThis will clear all session data.",
            "Confirm Reset",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:sessionStartTime = Get-Date
            $script:totalPings = 0
            $script:lostPings = 0
            $script:minLat = 999
            $script:maxLat = 0
            $script:totalSpikes = 0
            $script:worstSpikeValue = 0
            $script:worstSpikeTime = $null
            $script:Last60sSpike = 0
            $script:SpikeTimer.Restart()
            $script:avgLatency = 0
            $script:pingHistory.Clear()
            $script:pingHistory5min.Clear(); $script:pingHistory30min.Clear()
            $script:pingHistory1h.Clear();   $script:pingHistory24h.Clear()
            $script:lossHistory60s.Clear();  $script:lossHistory5min.Clear()
            $script:lossHistory30min.Clear(); $script:lossHistory1h.Clear()
            Write-Log "Statistics reset" "INFO"
            $statsForm.Close()
            Show-StatsDashboard
        }
    })
    $statsForm.Controls.Add($resetBtn)
    
    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = "Close"
    $closeBtn.Location = New-Object System.Drawing.Point(440, 600)
    $closeBtn.Size = New-Object System.Drawing.Size(130, 40)
    $closeBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
    $closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
    $closeBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeBtn.FlatAppearance.BorderSize = 0
    $closeBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(68, 72, 88)
    $closeBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $closeBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $statsForm.Controls.Add($closeBtn)
    $statsForm.AcceptButton = $closeBtn
    
    # Auto-Refresh Timer (every 5 seconds)
    $statsRefreshTimer = New-Object System.Windows.Forms.Timer
    $statsRefreshTimer.Interval = 5000
    $statsRefreshTimer.Add_Tick({
        if (-not $statsForm.Visible) { $statsRefreshTimer.Stop(); $statsRefreshTimer.Dispose(); return }
        $sessionDur2 = (Get-Date) - $script:sessionStartTime
        $loss2 = if ($script:totalPings -gt 0) { [math]::Round(($script:lostPings / $script:totalPings) * 100, 2) } else { 0 }
        $avg2  = if ($script:pingHistory.Count -gt 0) {
            $m = ($script:pingHistory | Measure-Object -Average).Average
            if ($m) { [math]::Round($m, 2) } else { 0 }
        } else { 0 }
        $score2 = [math]::Max(0, [math]::Round(100 - ($loss2*10) - (if ($script:maxLat -gt 200) {20} else {0}) - (if ($script:totalSpikes -gt 10) {10} else {0}), 0))
        $rating2 = if ($score2 -ge 90) {"EXCELLENT"} elseif ($score2 -ge 75) {"GOOD"} elseif ($score2 -ge 50) {"FAIR"} else {"POOR"}
        $hrs2  = [math]::Floor($sessionDur2.TotalHours)
        $mins2 = $sessionDur2.Minutes
        $secs2 = $sessionDur2.Seconds
        $newText = $statsText.Text -replace 'Uptime:.*', "Uptime:             ${hrs2}h ${mins2}m ${secs2}s"
        $newText = $newText        -replace 'Current:.*',  "Current:            $script:currentLatency ms"
        $newText = $newText        -replace 'Average:.*',  "Average:            $avg2 ms"
        $newText = $newText        -replace 'Packet Loss:.*', "Packet Loss:        $loss2% ($script:lostPings packets)"
        $newText = $newText        -replace 'Total Pings:.*', "Total Pings:        $($script:totalPings)"
        $newText = $newText        -replace 'Stability Score:.*', "Stability Score:    $score2/100"
        $newText = $newText        -replace 'Total Spikes:.*', "Total Spikes:       $script:totalSpikes (>150ms)"
        $newText = $newText        -replace 'Rating:.*', "  Rating:             $rating2"
        if ($statsText.Text -ne $newText) { $statsText.Text = $newText }
    })
    $statsRefreshTimer.Start()
    $statsForm.Add_FormClosed({ $statsRefreshTimer.Stop(); $statsRefreshTimer.Dispose() })

    $statsForm.ShowDialog() | Out-Null
    $statsForm.Dispose()
}

function Load-SessionHistory {
    try {
        if (Test-Path $script:sessionHistoryFile) {
            $json = Get-Content $script:sessionHistoryFile -Raw | ConvertFrom-Json
            $script:sessionHistory = @($json)
            Write-Log "Loaded $($script:sessionHistory.Count) sessions from history" "INFO"
        } else {
            $script:sessionHistory = @()
            Write-Log "No session history file found, starting fresh" "INFO"
        }
    } catch {
        Write-Log "Error loading session history: $_" "ERROR"
        $script:sessionHistory = @()
    }
}

function Save-CurrentSession {
    try {
        $sessionDuration = (Get-Date) - $script:sessionStartTime
        
        # Calculate stats for current session
        $avgLat = 0
        if ($script:pingHistory.Count -gt 0) {
            $avgM = ($script:pingHistory | Measure-Object -Average).Average
            if ($avgM) { $avgLat = [math]::Round($avgM, 2) }
        }
        
        $lossRate = 0
        if ($script:totalPings -gt 0) {
            $lossRate = [math]::Round(($script:lostPings / $script:totalPings) * 100, 2)
        }
        
        $stabilityScore = 100
        if ($lossRate -gt 0) { $stabilityScore -= ($lossRate * 10) }
        if ($script:maxLat -gt 200) { $stabilityScore -= 20 }
        if ($script:totalSpikes -gt 10) { $stabilityScore -= 10 }
        if ($stabilityScore -lt 0) { $stabilityScore = 0 }
        
        # Create session object
        $session = [PSCustomObject]@{
            StartTime = $script:sessionStartTime.ToString('yyyy-MM-dd HH:mm:ss')
            EndTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            DurationMinutes = [math]::Round($sessionDuration.TotalMinutes, 1)
            TotalPings = $script:totalPings
            PacketLoss = $lossRate
            AvgPing = $avgLat
            MinPing = $script:minLat
            MaxPing = $script:maxLat
            TotalSpikes = $script:totalSpikes
            WorstSpike = $script:worstSpikeValue
            StabilityScore = [math]::Round($stabilityScore, 0)
            Server = $script:TargetIP
        }
        
        # FIX: List statt += für O(1) append
        if (-not $script:sessionHistoryList) {
            $script:sessionHistoryList = [System.Collections.Generic.List[object]]::new()
            foreach ($s in $script:sessionHistory) { $script:sessionHistoryList.Add($s) }
        }
        $script:sessionHistoryList.Add($session)
        while ($script:sessionHistoryList.Count -gt $script:maxHistorySessions) {
            $script:sessionHistoryList.RemoveAt(0)
        }
        $script:sessionHistory = @($script:sessionHistoryList)
        # FIX: -Depth 3 damit PSCustomObject vollständig serialisiert wird
        $script:sessionHistory | ConvertTo-Json -Depth 3 | Out-File $script:sessionHistoryFile -Encoding UTF8
        Write-Log "Session saved to history (Duration: $($sessionDuration.TotalMinutes)m, Score: $stabilityScore)" "INFO"
        
    } catch {
        Write-Log "Error saving session: $_" "ERROR"
    }
}

function Show-SessionHistory {
    $histForm = New-Object System.Windows.Forms.Form
    $histForm.Text = "Session History"
    $histForm.Size        = New-Object System.Drawing.Size(960, 720)
    $histForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $histForm.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $histForm.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)
    $histForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $histForm.MinimizeBox = $false
    $histForm.MinimumSize = New-Object System.Drawing.Size(900, 700)
    
    # Title Label
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "SESSION HISTORY - Last $($script:sessionHistory.Count) Sessions"
    $titleLabel.Location = New-Object System.Drawing.Point(20, 20)
    $titleLabel.Size = New-Object System.Drawing.Size(850, 30)
    $titleLabel.Font = $script:Fonts.Title
    $titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 220)
    $histForm.Controls.Add($titleLabel)
    
    # Filter Buttons
    $filterPanel = New-Object System.Windows.Forms.Panel
    $filterPanel.Location = New-Object System.Drawing.Point(20, 60)
    $filterPanel.Size = New-Object System.Drawing.Size(850, 40)
    $histForm.Controls.Add($filterPanel)
    
    $btnAll = New-Object System.Windows.Forms.Button
    $btnAll.Text = "All"
    $btnAll.Location = New-Object System.Drawing.Point(0, 0)
    $btnAll.Size = New-Object System.Drawing.Size(80, 35)
    $btnAll.BackColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
    $btnAll.ForeColor = [System.Drawing.Color]::White
    $btnAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnAll.FlatAppearance.BorderSize = 0
    $btnAll.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $filterPanel.Controls.Add($btnAll)
    
    $btnToday = New-Object System.Windows.Forms.Button
    $btnToday.Text = "Today"
    $btnToday.Location = New-Object System.Drawing.Point(90, 0)
    $btnToday.Size = New-Object System.Drawing.Size(80, 35)
    $btnToday.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 52)
    $btnToday.ForeColor = [System.Drawing.Color]::FromArgb(145, 145, 165)
    $btnToday.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnToday.FlatAppearance.BorderSize = 0
    $btnToday.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $filterPanel.Controls.Add($btnToday)
    
    $btnWeek = New-Object System.Windows.Forms.Button
    $btnWeek.Text = "Last 7 Days"
    $btnWeek.Location = New-Object System.Drawing.Point(180, 0)
    $btnWeek.Size = New-Object System.Drawing.Size(100, 35)
    $btnWeek.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 52)
    $btnWeek.ForeColor = [System.Drawing.Color]::FromArgb(145, 145, 165)
    $btnWeek.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnWeek.FlatAppearance.BorderSize = 0
    $btnWeek.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $filterPanel.Controls.Add($btnWeek)
    
    $btnMonth = New-Object System.Windows.Forms.Button
    $btnMonth.Text = "Last 30 Days"
    $btnMonth.Location = New-Object System.Drawing.Point(290, 0)
    $btnMonth.Size = New-Object System.Drawing.Size(110, 35)
    $btnMonth.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 52)
    $btnMonth.ForeColor = [System.Drawing.Color]::FromArgb(145, 145, 165)
    $btnMonth.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnMonth.FlatAppearance.BorderSize = 0
    $btnMonth.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $filterPanel.Controls.Add($btnMonth)
    
    # ListView for sessions
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(20, 110)
    $listView.Size = New-Object System.Drawing.Size(850, 400)
    $listView.View             = [System.Windows.Forms.View]::Details
    $listView.BackColor        = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $listView.ForeColor        = [System.Drawing.Color]::FromArgb(200, 200, 215)
    $listView.BorderStyle      = [System.Windows.Forms.BorderStyle]::FixedSingle
    $listView.FullRowSelect = $true
    $listView.GridLines = $true
    $listView.Font = $script:Fonts.MonoSm
    
    # Add columns
    $null = $listView.Columns.Add("Date", 130)
    $null = $listView.Columns.Add("Time", 130)
    $null = $listView.Columns.Add("Duration", 80)
    $null = $listView.Columns.Add("Avg Ping", 80)
    $null = $listView.Columns.Add("Loss %", 70)
    $null = $listView.Columns.Add("Spikes", 70)
    $null = $listView.Columns.Add("Score", 70)
    $null = $listView.Columns.Add("Rating", 100)
    
    $histForm.Controls.Add($listView)

    # ── Doppelklick → Session-Detail ────────────────────────────
    $listView.Add_DoubleClick({
        if ($listView.SelectedItems.Count -eq 0) { return }
        $sel = $listView.SelectedItems[0]
        $idx = $sel.Index
        if ($idx -lt 0 -or $idx -ge $script:sessionHistory.Count) { return }
        $sess = $script:sessionHistory[$idx]

        $dF = New-Object System.Windows.Forms.Form
        $dF.Text            = "Session Detail — $($sess.StartTime)"
        $dF.Size            = New-Object System.Drawing.Size(460, 380)
        $dF.StartPosition   = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $dF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dF.MaximizeBox     = $false
        $dF.MinimizeBox     = $false
        $dF.BackColor       = [System.Drawing.Color]::FromArgb(18, 18, 24)
        $dF.ForeColor       = [System.Drawing.Color]::FromArgb(220, 220, 228)

        $dBox = New-Object System.Windows.Forms.RichTextBox
        $dBox.Location    = New-Object System.Drawing.Point(16, 16)
        $dBox.Size        = New-Object System.Drawing.Size(414, 290)
        $dBox.ReadOnly    = $true
        $dBox.Font        = $script:Fonts.MonoSm
        $dBox.BackColor   = [System.Drawing.Color]::FromArgb(22, 22, 30)
        $dBox.ForeColor   = [System.Drawing.Color]::FromArgb(185, 185, 205)
        $dBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
        $dBox.Text = @"
SESSION DETAIL
══════════════════════════════════════
Started:        $($sess.StartTime)
Duration:       $($sess.Duration)
Server:         $($sess.ServerIP)

LATENCY
  Average:      $($sess.AvgPing) ms
  Minimum:      $($sess.MinPing) ms
  Maximum:      $($sess.MaxPing) ms

STABILITY
  Score:        $($sess.StabilityScore)/100
  Rating:       $($sess.Rating)
  Packet Loss:  $($sess.PacketLoss)%
  Spikes:       $($sess.Spikes)

PROFILE
  Profile:      $($sess.Profile)
══════════════════════════════════════
"@
        $dF.Controls.Add($dBox)

        $dClose = New-Object System.Windows.Forms.Button
        $dClose.Text      = "Close"
        $dClose.Location  = New-Object System.Drawing.Point(155, 318)
        $dClose.Size      = New-Object System.Drawing.Size(130, 32)
        $dClose.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
        $dClose.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
        $dClose.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $dClose.FlatAppearance.BorderSize = 0
        $dClose.Cursor    = [System.Windows.Forms.Cursors]::Hand
        $dClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dF.Controls.Add($dClose)
        $dF.AcceptButton = $dClose
        $dF.ShowDialog() | Out-Null
        $dF.Dispose()
    })

    # ── ListView Klick-Sortierung ─────────────────────────────
    $script:lvSortColumn = -1
    $script:lvSortAsc    = $true

    $listView.Add_ColumnClick({
        param($s, $e)
        $col = $e.Column
        if ($script:lvSortColumn -eq $col) {
            $script:lvSortAsc = -not $script:lvSortAsc
        } else {
            $script:lvSortColumn = $col
            $script:lvSortAsc    = $true
        }

        $items = @($listView.Items)
        $sorted = $items | Sort-Object {
            $val = $_.SubItems[$col].Text
            # Numeric sort für Zahlen-Spalten
            $num = 0
            if ([double]::TryParse($val.Trim('%'), [ref]$num)) { $num } else { $val }
        }
        if (-not $script:lvSortAsc) { $sorted = @($sorted)[-1..0] }

        $listView.BeginUpdate()
        $listView.Items.Clear()
        foreach ($item in $sorted) { $listView.Items.Add($item) }
        $listView.EndUpdate()

        # Spalten-Header mit Pfeil aktualisieren
        for ($ci = 0; $ci -lt $listView.Columns.Count; $ci++) {
            $header = $listView.Columns[$ci].Text -replace ' [▲▼]$', ''
            if ($ci -eq $col) {
                $listView.Columns[$ci].Text = "$header $(if ($script:lvSortAsc) { '▲' } else { '▼' })"
            } else {
                $listView.Columns[$ci].Text = $header
            }
        }
    })
    
    # Function to populate ListView
    $populateList = {
        param($filter)
        $listView.Items.Clear()
        
        $filtered = $script:sessionHistory
        $now = Get-Date
        
        switch ($filter) {
            "Today" {
                $filtered = $script:sessionHistory | Where-Object {
                    $startDate = [DateTime]::ParseExact($_.StartTime, 'yyyy-MM-dd HH:mm:ss', $null)
                    $startDate.Date -eq $now.Date
                }
            }
            "Week" {
                $weekAgo = $now.AddDays(-7)
                $filtered = $script:sessionHistory | Where-Object {
                    $startDate = [DateTime]::ParseExact($_.StartTime, 'yyyy-MM-dd HH:mm:ss', $null)
                    $startDate -gt $weekAgo
                }
            }
            "Month" {
                $monthAgo = $now.AddDays(-30)
                $filtered = $script:sessionHistory | Where-Object {
                    $startDate = [DateTime]::ParseExact($_.StartTime, 'yyyy-MM-dd HH:mm:ss', $null)
                    $startDate -gt $monthAgo
                }
            }
        }
        
        # Sort by date descending
        $sorted = $filtered | Sort-Object { [DateTime]::ParseExact($_.StartTime, 'yyyy-MM-dd HH:mm:ss', $null) } -Descending
        
        foreach ($session in $sorted) {
            $startDate = [DateTime]::ParseExact($session.StartTime, 'yyyy-MM-dd HH:mm:ss', $null)
            
            $rating = if ($session.StabilityScore -ge 90) { "EXCELLENT" }
                     elseif ($session.StabilityScore -ge 75) { "GOOD" }
                     elseif ($session.StabilityScore -ge 50) { "FAIR" }
                     else { "POOR" }
            
            $item = New-Object System.Windows.Forms.ListViewItem($startDate.ToString('yyyy-MM-dd'))
            $null = $item.SubItems.Add($startDate.ToString('HH:mm:ss'))
            $null = $item.SubItems.Add("$($session.DurationMinutes)m")
            $null = $item.SubItems.Add("$($session.AvgPing)ms")
            $null = $item.SubItems.Add("$($session.PacketLoss)%")
            $null = $item.SubItems.Add($session.TotalSpikes)
            $null = $item.SubItems.Add($session.StabilityScore)
            $null = $item.SubItems.Add($rating)
            
            # Color coding
            if ($session.StabilityScore -ge 90) {
                $item.BackColor = [System.Drawing.Color]::FromArgb(230, 255, 230)
            } elseif ($session.StabilityScore -ge 75) {
                $item.BackColor = [System.Drawing.Color]::FromArgb(255, 255, 230)
            } elseif ($session.StabilityScore -ge 50) {
                $item.BackColor = [System.Drawing.Color]::FromArgb(255, 245, 230)
            } else {
                $item.BackColor = [System.Drawing.Color]::FromArgb(255, 230, 230)
            }
            
            $null = $listView.Items.Add($item)
        }
        
        # Update button colors
        $btnAll.BackColor   = if ($filter -eq "All")   { [System.Drawing.Color]::FromArgb(0,130,210) } else { [System.Drawing.Color]::FromArgb(38,40,52) }
        $btnAll.ForeColor   = if ($filter -eq "All")   { [System.Drawing.Color]::White }               else { [System.Drawing.Color]::FromArgb(145,145,165) }
        $btnToday.BackColor = if ($filter -eq "Today") { [System.Drawing.Color]::FromArgb(0,130,210) } else { [System.Drawing.Color]::FromArgb(38,40,52) }
        $btnToday.ForeColor = if ($filter -eq "Today") { [System.Drawing.Color]::White }               else { [System.Drawing.Color]::FromArgb(145,145,165) }
        $btnWeek.BackColor  = if ($filter -eq "Week")  { [System.Drawing.Color]::FromArgb(0,130,210) } else { [System.Drawing.Color]::FromArgb(38,40,52) }
        $btnWeek.ForeColor  = if ($filter -eq "Week")  { [System.Drawing.Color]::White }               else { [System.Drawing.Color]::FromArgb(145,145,165) }
        $btnMonth.BackColor = if ($filter -eq "Month") { [System.Drawing.Color]::FromArgb(0,130,210) } else { [System.Drawing.Color]::FromArgb(38,40,52) }
        $btnMonth.ForeColor = if ($filter -eq "Month") { [System.Drawing.Color]::White }               else { [System.Drawing.Color]::FromArgb(145,145,165) }
    }
    
    # Filter button events
    $btnAll.Add_Click({ & $populateList "All" })
    $btnToday.Add_Click({ & $populateList "Today" })
    $btnWeek.Add_Click({ & $populateList "Week" })
    $btnMonth.Add_Click({ & $populateList "Month" })
    
    # Summary Panel
    $summaryPanel = New-Object System.Windows.Forms.Panel
    $summaryPanel.Location = New-Object System.Drawing.Point(20, 520)
    $summaryPanel.Size = New-Object System.Drawing.Size(850, 80)
    $summaryPanel.BackColor = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $summaryPanel.BackColor   = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $summaryPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $histForm.Controls.Add($summaryPanel)
    
    $summaryLabel = New-Object System.Windows.Forms.Label
    $summaryLabel.Location = New-Object System.Drawing.Point(10, 10)
    $summaryLabel.Size = New-Object System.Drawing.Size(830, 60)
    $summaryLabel.Font     = $script:Fonts.MonoSm
    $summaryLabel.ForeColor = [System.Drawing.Color]::FromArgb(165, 165, 185)
    
    # Calculate summary
    if ($script:sessionHistory.Count -gt 0) {
        $totalSessions = $script:sessionHistory.Count
        $avgScore = [math]::Round(($script:sessionHistory | Measure-Object -Property StabilityScore -Average).Average, 1)
        $avgPing = [math]::Round(($script:sessionHistory | Measure-Object -Property AvgPing -Average).Average, 1)
        $bestSession = $script:sessionHistory | Sort-Object StabilityScore -Descending | Select-Object -First 1
        $worstSession = $script:sessionHistory | Sort-Object StabilityScore | Select-Object -First 1
        
        $summaryLabel.Text = "Total Sessions: $totalSessions  |  Avg Score: $avgScore/100  |  Avg Ping: ${avgPing}ms`n" +
                            "Best Session: $($bestSession.StabilityScore)/100 on $($bestSession.StartTime)  |  " +
                            "Worst Session: $($worstSession.StabilityScore)/100 on $($worstSession.StartTime)"
    } else {
        $summaryLabel.Text = "No sessions recorded yet."
    }
    
    $summaryPanel.Controls.Add($summaryLabel)
    
    # Buttons
    $exportBtn = New-Object System.Windows.Forms.Button
    $exportBtn.Text = "Export All to Excel"
    $exportBtn.Location = New-Object System.Drawing.Point(20, 615)
    $exportBtn.Size = New-Object System.Drawing.Size(150, 40)
    $exportBtn.BackColor = [System.Drawing.Color]::FromArgb(45, 175, 80)
    $exportBtn.ForeColor = [System.Drawing.Color]::White
    $exportBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $exportBtn.FlatAppearance.BorderSize = 0
    $exportBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55, 195, 95)
    $exportBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $exportBtn.Add_Click({
        try {
            $csvPath = Join-Path $script:scriptPath "session_history_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $script:sessionHistory | Export-Csv $csvPath -NoTypeInformation -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show("History exported to:`n$csvPath", "Export Success")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Export failed: $_", "Error", "OK", "Error")
        }
    })
    $histForm.Controls.Add($exportBtn)
    
    $clearBtn = New-Object System.Windows.Forms.Button
    $clearBtn.Text = "Clear History"
    $clearBtn.Location = New-Object System.Drawing.Point(180, 615)
    $clearBtn.Size = New-Object System.Drawing.Size(150, 40)
    $clearBtn.BackColor = [System.Drawing.Color]::FromArgb(195, 55, 55)
    $clearBtn.ForeColor = [System.Drawing.Color]::White
    $clearBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $clearBtn.FlatAppearance.BorderSize = 0
    $clearBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(215, 70, 70)
    $clearBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $clearBtn.Add_Click({
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Clear all session history?`n`nThis cannot be undone!",
            "Confirm Clear",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:sessionHistory = @()
            if (Test-Path $script:sessionHistoryFile) {
                Remove-Item $script:sessionHistoryFile -Force
            }
            & $populateList "All"
            [System.Windows.Forms.MessageBox]::Show("History cleared.", "Success")
        }
    })
    $histForm.Controls.Add($clearBtn)
    
    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = "Close"
    $closeBtn.Location = New-Object System.Drawing.Point(720, 615)
    $closeBtn.Size = New-Object System.Drawing.Size(150, 40)
    $closeBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
    $closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
    $closeBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeBtn.FlatAppearance.BorderSize = 0
    $closeBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(68, 72, 88)
    $closeBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $closeBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $histForm.Controls.Add($closeBtn)
    $histForm.AcceptButton = $closeBtn
    
    # Initial populate
    & $populateList "All"
    
    $histForm.ShowDialog() | Out-Null
    $histForm.Dispose()
}

function Show-MTUOptimizer {
    $target = $script:TargetIP
    
    $mF = New-Object System.Windows.Forms.Form
    $mF.Text = "MTU Optimizer - Binary Search"
    $mF.Size = New-Object System.Drawing.Size(450, 480)
    $mF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $mF.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $mF.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)
    $mF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $mF.MaximizeBox = $false
    
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "Target: $target`nOptimal MTU = Largest successful packet + 28 bytes"
    $infoLabel.Location = New-Object System.Drawing.Point(20, 20)
    $infoLabel.Size = New-Object System.Drawing.Size(400, 50)
    $infoLabel.Font = $script:Fonts.Small
    $infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $mF.Controls.Add($infoLabel)
    
    $stat = New-Object System.Windows.Forms.RichTextBox
    $stat.Location = New-Object System.Drawing.Point(20, 80)
    $stat.Size = New-Object System.Drawing.Size(400, 180)
    $stat.ReadOnly = $true
    $stat.Font      = $script:Fonts.MonoSm
    $stat.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $stat.ForeColor = [System.Drawing.Color]::FromArgb(180, 200, 180)
    $stat.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $mF.Controls.Add($stat)
    
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(20, 270)
    $progressBar.Size = New-Object System.Drawing.Size(400, 25)
    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $mF.Controls.Add($progressBar)
    
    $sBtn = New-Object System.Windows.Forms.Button
    $sBtn.Text = "START BINARY SEARCH"
    $sBtn.Location = New-Object System.Drawing.Point(20, 310)
    $sBtn.Size = New-Object System.Drawing.Size(400, 40)
    $sBtn.BackColor = [System.Drawing.Color]::FromArgb(45, 175, 80)
    $sBtn.ForeColor = [System.Drawing.Color]::White
    $sBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $sBtn.FlatAppearance.BorderSize = 0
    $sBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55, 195, 95)
    $sBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $sBtn.Font = $script:Fonts.Header
    $mF.Controls.Add($sBtn)
    
    $script:bestMTUFound = 0
    
    $sBtn.Add_Click({
        $sBtn.Enabled = $false
        $stat.Clear()
        $script:bestMTUFound = 0
        
        $stat.AppendText("Starting binary search algorithm...`n`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        $low = 1200
        $high = 1472
        $bestPacketSize = 0
        $iterations = 0
        $maxIterations = [math]::Ceiling([math]::Log($high - $low, 2))
        
        $progressBar.Maximum = $maxIterations
        $progressBar.Value = 0
        
        while ($low -le $high) {
            $iterations++
            $mid = [math]::Floor(($low + $high) / 2)
            
            $stat.AppendText("[$iterations/$maxIterations] Testing packet size: $mid bytes...")
            [System.Windows.Forms.Application]::DoEvents()
            
            $pingResult = ping -n 1 -f -l $mid $target 2>&1
            
            if ($pingResult -match 'TTL=' -and $pingResult -notmatch 'needs to be fragmented') {
                $stat.AppendText(" SUCCESS`n")
                $bestPacketSize = $mid
                $low = $mid + 1
            } else {
                $stat.AppendText(" FAILED (too large)`n")
                $high = $mid - 1
            }
            
            $progressBar.Value = $iterations
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        if ($bestPacketSize -gt 0) {
            $script:bestMTUFound = $bestPacketSize + 28
            $stat.AppendText("`n" + "=" * 50 + "`n")
            $stat.AppendText("OPTIMAL MTU FOUND: $script:bestMTUFound bytes`n")
            $stat.AppendText("(Packet: $bestPacketSize + Header: 28)`n")
            $stat.AppendText("=" * 50 + "`n")
            $saveB.Enabled = $true
        } else {
            $stat.AppendText("`nERROR: No successful packet size found!`n")
        }
        
        $sBtn.Enabled = $true
    })
    
    $saveB = New-Object System.Windows.Forms.Button
    $saveB.Text = "APPLY MTU AND SAVE"
    $saveB.Location = New-Object System.Drawing.Point(20, 360)
    $saveB.Size = New-Object System.Drawing.Size(400, 40)
    $saveB.BackColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
    $saveB.ForeColor = [System.Drawing.Color]::White
    $saveB.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $saveB.FlatAppearance.BorderSize = 0
    $saveB.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 150, 230)
    $saveB.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $saveB.Enabled = $false
    
    $saveB.Add_Click({
        if ($script:bestMTUFound -gt 0) {
            "$script:bestMTUFound" | Out-File $mtuConfigFile -Force
            
            $adapter = if ($script:selectedAdapter) { Get-NetAdapter -Name $script:selectedAdapter -ErrorAction SilentlyContinue } else { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1 }
            if ($adapter) {
                netsh interface ipv4 set subinterface "$($adapter.Name)" mtu=$script:bestMTUFound store=persistent 2>&1 | Out-Null
                Write-Log "MTU set to $script:bestMTUFound" "INFO"
            }
            
            $msg = "MTU set to $script:bestMTUFound and saved!`n`nRecommended: Restart network adapter."
            [System.Windows.Forms.MessageBox]::Show($msg, "Success")
            $mF.Close()
        }
    })
    
    $mF.Controls.Add($saveB)
    $mF.ShowDialog() | Out-Null
    $mF.Dispose()
}

function Show-BenchmarkABGUI {
    $target = $script:TargetIP
    
    $bF = New-Object System.Windows.Forms.Form
    $bF.Text = "A/B Precision Benchmark"
    $bF.Size = New-Object System.Drawing.Size(500, 620)
    $bF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $bF.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $bF.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)
    $bF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $bF.MaximizeBox = $false
    
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "Compares performance BEFORE and AFTER optimizations`nTarget: $target"
    $infoLabel.Location = New-Object System.Drawing.Point(20, 20)
    $infoLabel.Size = New-Object System.Drawing.Size(450, 35)
    $infoLabel.Font     = $script:Fonts.Small
    $infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(150, 150, 170)
    $bF.Controls.Add($infoLabel)
    
    $lProg = New-Object System.Windows.Forms.Label
    $lProg.Text      = "Progress: Ready"
    $lProg.Location  = New-Object System.Drawing.Point(20, 60)
    $lProg.Size      = New-Object System.Drawing.Size(400, 20)
    $lProg.Font      = $script:Fonts.Small
    $lProg.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 165)
    $bF.Controls.Add($lProg)
    
    $pb = New-Object System.Windows.Forms.ProgressBar
    $pb.Location = New-Object System.Drawing.Point(20, 85)
    $pb.Size = New-Object System.Drawing.Size(450, 30)
    $pb.Maximum = 650
    $pb.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $bF.Controls.Add($pb)
    
    $res = New-Object System.Windows.Forms.RichTextBox
    $res.Location = New-Object System.Drawing.Point(20, 130)
    $res.Size = New-Object System.Drawing.Size(450, 350)
    $res.ReadOnly = $true
    $res.Font       = $script:Fonts.Mono
    $res.BackColor  = [System.Drawing.Color]::FromArgb(12, 12, 18)
    $res.ForeColor  = [System.Drawing.Color]::FromArgb(160, 220, 160)
    $res.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $bF.Controls.Add($res)
    
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text      = "START 3-MINUTE TEST"
    $btn.Location  = New-Object System.Drawing.Point(20, 500)
    $btn.Size      = New-Object System.Drawing.Size(450, 60)
    $btn.Font      = $script:Fonts.Header
    $btn.BackColor = [System.Drawing.Color]::FromArgb(45, 175, 80)
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btn.FlatAppearance.BorderSize = 0
    $btn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55, 195, 95)
    $btn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    
    $btn.Add_Click({
        $btn.Enabled = $false
        $pb.Value = 0
        $res.Clear()
        
        $res.AppendText("Phase 0: Warmup (50 pings)...`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        for ($i = 1; $i -le 50; $i++) {
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $ar = $tcp.BeginConnect($target, $CONFIG.ServerPort, $null, $null)
                if ($ar.AsyncWaitHandle.WaitOne(1000, $false)) {
                    $tcp.EndConnect($ar)
                }
            } finally {
                $tcp.Close()
                $tcp.Dispose()
            }
            $pb.Value = $i
            if ($i % 10 -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
        }
        
        $res.AppendText("Warmup complete. Waiting 5 seconds...`n`n")
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 5
        
        $res.AppendText("Phase 1: BASELINE (optimizations OFF)...`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        Apply-Optimizations -DisableAll $true
        Start-Sleep -Seconds 3
        
        $pB = @()
        for ($i = 1; $i -le 300; $i++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $ar = $tcp.BeginConnect($target, $CONFIG.ServerPort, $null, $null)
                if ($ar.AsyncWaitHandle.WaitOne(1000, $false)) {
                    $tcp.EndConnect($ar)
                    $sw.Stop()
                    $pB += $sw.ElapsedMilliseconds
                }
            } finally {
                $tcp.Close()
                $tcp.Dispose()
            }
            
            $v = 50 + $i
            $lProg.Text = "Baseline: $i / 300"
            $pb.Value = $v
            
            if ($i % 10 -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
            Start-Sleep -Milliseconds 200
        }
        
        $res.AppendText("Baseline complete. Waiting 5 seconds...`n`n")
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Seconds 5
        
        $res.AppendText("Phase 2: OPTIMIZED (optimizations ON)...`n")
        [System.Windows.Forms.Application]::DoEvents()
        
        Apply-Optimizations -DisableAll $false
        Start-Sleep -Seconds 3
        
        $pA = @()
        for ($i = 1; $i -le 300; $i++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $tcp = New-Object System.Net.Sockets.TcpClient
            try {
                $ar = $tcp.BeginConnect($target, $CONFIG.ServerPort, $null, $null)
                if ($ar.AsyncWaitHandle.WaitOne(1000, $false)) {
                    $tcp.EndConnect($ar)
                    $sw.Stop()
                    $pA += $sw.ElapsedMilliseconds
                }
            } finally {
                $tcp.Close()
                $tcp.Dispose()
            }
            
            $v = 350 + $i
            $lProg.Text = "Optimized: $i / 300"
            $pb.Value = $v
            
            if ($i % 10 -eq 0) { [System.Windows.Forms.Application]::DoEvents() }
            Start-Sleep -Milliseconds 200
        }
        
        $avgB = if ($pB.Count -gt 0) { ($pB | Measure-Object -Average).Average } else { 0 }
        $avgA = if ($pA.Count -gt 0) { ($pA | Measure-Object -Average).Average } else { 0 }
        $minB = if ($pB.Count -gt 0) { ($pB | Measure-Object -Minimum).Minimum } else { 0 }
        $minA = if ($pA.Count -gt 0) { ($pA | Measure-Object -Minimum).Minimum } else { 0 }
        $maxB = if ($pB.Count -gt 0) { ($pB | Measure-Object -Maximum).Maximum } else { 0 }
        $maxA = if ($pA.Count -gt 0) { ($pA | Measure-Object -Maximum).Maximum } else { 0 }
        
        $imp = if ($avgB -gt 0) { (($avgB - $avgA) / $avgB) * 100 } else { 0 }
        
        $res.Clear()
        $res.SelectionFont = $script:Fonts.Header
        $res.AppendText("=======================================`n")
        $res.AppendText("        BENCHMARK RESULTS`n")
        $res.AppendText("=======================================`n`n")
        
        $res.SelectionFont = $script:Fonts.Mono
        $res.AppendText("BASELINE (Optimizations OFF):`n")
        $res.AppendText("  Average: $([math]::Round($avgB, 2)) ms`n")
        $res.AppendText("  Min:     $([math]::Round($minB, 2)) ms`n")
        $res.AppendText("  Max:     $([math]::Round($maxB, 2)) ms`n`n")
        
        $res.AppendText("OPTIMIZED (Optimizations ON):`n")
        $res.AppendText("  Average: $([math]::Round($avgA, 2)) ms`n")
        $res.AppendText("  Min:     $([math]::Round($minA, 2)) ms`n")
        $res.AppendText("  Max:     $([math]::Round($maxA, 2)) ms`n`n")
        
        $res.SelectionFont = $script:Fonts.Header
        if ($imp -gt 0) {
            $res.SelectionColor = [System.Drawing.Color]::Green
            $res.AppendText("IMPROVEMENT: $([math]::Round($imp, 2))%`n")
        } elseif ($imp -lt 0) {
            $res.SelectionColor = [System.Drawing.Color]::Red
            $res.AppendText("DEGRADATION: $([math]::Round([math]::Abs($imp), 2))%`n")
        } else {
            $res.AppendText("NO CHANGE`n")
        }
        
        $res.SelectionColor = [System.Drawing.Color]::Black
        $res.SelectionFont = $script:Fonts.Mono
        $res.AppendText("`nDifference: $([math]::Round($avgB - $avgA, 2)) ms`n")
        
        Write-Log "Benchmark completed. Improvement: $([math]::Round($imp, 2))%" "INFO"
        
        $btn.Enabled = $true
    })
    
    $bF.Controls.Add($btn)
    $bF.ShowDialog() | Out-Null
    $bF.Dispose()
}

function Show-TracerouteGUI {
    $target = $script:TargetIP
    if (-not $target -or $target -eq "0.0.0.0") {
        [System.Windows.Forms.MessageBox]::Show("No target IP configured.","Traceroute","OK","Warning")
        return
    }
    
    $tF = New-Object System.Windows.Forms.Form
    $tF.Text = "Traceroute — $target"
    $tF.Size = New-Object System.Drawing.Size(640, 600)
    $tF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $tF.BackColor = [System.Drawing.Color]::FromArgb(10, 12, 16)
    $tF.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 230)
    $tF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $tF.MinimumSize = New-Object System.Drawing.Size(500, 400)
    
    # FIX: Prozess-Referenz für Cleanup bei Form-Close
    $script:traceProcess = $null

    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "Tracing network path to:  $target"
    $infoLabel.Location = New-Object System.Drawing.Point(16, 16)
    $infoLabel.Size = New-Object System.Drawing.Size(580, 24)
    $infoLabel.Font = $script:Fonts.Body
    $infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(0,140,220)
    $tF.Controls.Add($infoLabel)
    
    $tBox = New-Object System.Windows.Forms.RichTextBox
    $tBox.Location = New-Object System.Drawing.Point(16, 46)
    $tBox.Size = New-Object System.Drawing.Size(596, 446)
    $tBox.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor
                   [System.Windows.Forms.AnchorStyles]::Bottom -bor
                   [System.Windows.Forms.AnchorStyles]::Left -bor
                   [System.Windows.Forms.AnchorStyles]::Right
    $tBox.ReadOnly = $true
    $tBox.Font = $script:gfxCache.FontTimeline   # FIX: gecacht
    $tBox.BackColor = [System.Drawing.Color]::FromArgb(8, 10, 14)
    $tBox.ForeColor = [System.Drawing.Color]::FromArgb(80, 220, 80)
    $tBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tBox.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
    $tF.Controls.Add($tBox)
    
    $btnPanel = New-Object System.Windows.Forms.Panel
    $btnPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $btnPanel.Height = 52
    $btnPanel.BackColor = [System.Drawing.Color]::FromArgb(14,16,22)
    $tF.Controls.Add($btnPanel)

    $stB = New-Object System.Windows.Forms.Button
    $stB.Text = "▶ Start Traceroute"
    $stB.Location = New-Object System.Drawing.Point(16, 9)
    $stB.Size = New-Object System.Drawing.Size(180, 36)
    $stB.BackColor = [System.Drawing.Color]::FromArgb(190, 50, 50)
    $stB.ForeColor = [System.Drawing.Color]::White
    $stB.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $stB.FlatAppearance.BorderSize = 0
    $stB.Cursor = [System.Windows.Forms.Cursors]::Hand
    $stB.Font = $script:Fonts.Header
    $btnPanel.Controls.Add($stB)

    $stbCancel = New-Object System.Windows.Forms.Button
    $stbCancel.Text = "■ Stop"
    $stbCancel.Location = New-Object System.Drawing.Point(204, 9)
    $stbCancel.Size = New-Object System.Drawing.Size(80, 36)
    $stbCancel.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $stbCancel.ForeColor = [System.Drawing.Color]::FromArgb(180,180,200)
    $stbCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $stbCancel.FlatAppearance.BorderSize = 0
    $stbCancel.Enabled = $false
    $stbCancel.Cursor = [System.Windows.Forms.Cursors]::Hand
    $stbCancel.Font = $script:Fonts.Small
    $stbCancel.Add_Click({
        # FIX: Prozess beenden
        if ($script:traceProcess -and -not $script:traceProcess.HasExited) {
            try { $script:traceProcess.Kill() } catch { $null = $_ }
        }
        $stbCancel.Enabled = $false
        $stB.Enabled = $true
        $tBox.AppendText("`n[Traceroute stopped by user]`n")
    })
    $btnPanel.Controls.Add($stbCancel)

    $closeBtn2 = New-Object System.Windows.Forms.Button
    $closeBtn2.Text = "Close"
    $closeBtn2.Location = New-Object System.Drawing.Point(490, 9)
    $closeBtn2.Size = New-Object System.Drawing.Size(100, 36)
    $closeBtn2.BackColor = [System.Drawing.Color]::FromArgb(55,58,70)
    $closeBtn2.ForeColor = [System.Drawing.Color]::FromArgb(180,180,200)
    $closeBtn2.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeBtn2.FlatAppearance.BorderSize = 0
    $closeBtn2.Cursor = [System.Windows.Forms.Cursors]::Hand
    $closeBtn2.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnPanel.Controls.Add($closeBtn2)
    $tF.CancelButton = $closeBtn2

    # FIX: Bei Form-Close laufenden Prozess beenden
    $tF.Add_FormClosing({
        if ($script:traceProcess -and -not $script:traceProcess.HasExited) {
            try { $script:traceProcess.Kill() } catch { $null = $_ }
        }
        $script:traceProcess = $null
    })

    $stB.Add_Click({
        $stB.Enabled = $false; $stbCancel.Enabled = $true
        $tBox.Clear()
        $tBox.SelectionColor = [System.Drawing.Color]::FromArgb(0,140,220)
        $tBox.AppendText("Tracing to $target  (max 30 hops)`n")
        $tBox.AppendText("=" * 50 + "`n`n")
        $tBox.SelectionColor = [System.Drawing.Color]::FromArgb(80,220,80)
        [System.Windows.Forms.Application]::DoEvents()
        
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "tracert.exe"
            $psi.Arguments = "-d -h 30 $target"
            $psi.RedirectStandardOutput = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            
            $script:traceProcess = [System.Diagnostics.Process]::Start($psi)
            
            while (-not $script:traceProcess.HasExited) {
                $line = $script:traceProcess.StandardOutput.ReadLine()
                if ($null -eq $line) { break }
                if ($line.Trim()) {
                    # Zeilen einfärben
                    $color = if ($line -match 'Request timed out|Timeout') {
                        [System.Drawing.Color]::FromArgb(200,80,80)
                    } elseif ($line -match '^\s+\d+') {
                        [System.Drawing.Color]::FromArgb(80,220,80)
                    } else {
                        [System.Drawing.Color]::FromArgb(120,125,155)
                    }
                    $tBox.SelectionColor = $color
                    $tBox.AppendText($line + "`n")
                    $tBox.ScrollToCaret()
                }
                [System.Windows.Forms.Application]::DoEvents()
                if (-not $tF.Visible) { break }   # Form geschlossen
            }
            # Restliche Output lesen
            $remainder = $script:traceProcess.StandardOutput.ReadToEnd()
            if ($remainder) { $tBox.AppendText($remainder) }
            
            $tBox.SelectionColor = [System.Drawing.Color]::FromArgb(0,140,220)
            $tBox.AppendText("`nTrace complete.`n")
            Write-Log "Traceroute to $target completed" "INFO"
        } catch {
            $tBox.AppendText("`nError: $_`n")
            Write-Log "Traceroute error: $_" "WARNING"
        }
        $stB.Enabled = $true; $stbCancel.Enabled = $false
        $script:traceProcess = $null
    })
    
    $tF.ShowDialog() | Out-Null
    $tF.Dispose()
}

function Show-OptimizationManager {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Optimization Manager v$($CONFIG.Version) - Profile: $($script:Profiles[$script:currentProfile].Name)"
    $f.Size = New-Object System.Drawing.Size(600, 840)
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.MaximizeBox = $false
    $f.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $f.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)
    
    $toolTip = New-Object System.Windows.Forms.ToolTip
    $toolTip.IsBalloon = $true
    $toolTip.InitialDelay = 400
    $toolTip.AutoPopDelay = 20000
    
    # Header
    $header = New-Object System.Windows.Forms.Label
    $header.Text      = "Optimization Manager"
    $header.Font      = $script:Fonts.Title
    $header.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)
    $header.Location  = New-Object System.Drawing.Point(20, 15)
    $header.Size      = New-Object System.Drawing.Size(300, 30)
    $f.Controls.Add($header)
    
    # Profile Indicator
    $profileLabel = New-Object System.Windows.Forms.Label
    $profileLabel.Text = "Active Profile: $($script:Profiles[$script:currentProfile].Name)"
    $profileLabel.Font      = $script:Fonts.Header
    $profileLabel.Location  = New-Object System.Drawing.Point(20, 50)
    $profileLabel.Size      = New-Object System.Drawing.Size(250, 25)
    $profileLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 220)
    $f.Controls.Add($profileLabel)
    
    # Profile Switch Buttons
    $btnMMO = New-Object System.Windows.Forms.Button
    $btnMMO.Text = "MMO"
    $btnMMO.Location = New-Object System.Drawing.Point(278, 48)
    $btnMMO.Size = New-Object System.Drawing.Size(55, 25)
    $btnMMO.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnMMO.ForeColor = [System.Drawing.Color]::White
    $btnMMO.BackColor      = if ($script:currentProfile -eq "MMO")      { [System.Drawing.Color]::FromArgb(0,120,200) } else { [System.Drawing.Color]::FromArgb(55,55,70) }
    $f.Controls.Add($btnMMO)
    
    $btnFPS = New-Object System.Windows.Forms.Button
    $btnFPS.Text = "COMP"
    $btnFPS.Location = New-Object System.Drawing.Point(336, 48)
    $btnFPS.Size = New-Object System.Drawing.Size(55, 25)
    $btnFPS.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnFPS.ForeColor = [System.Drawing.Color]::White
    $btnFPS.BackColor      = if ($script:currentProfile -eq "FPS")      { [System.Drawing.Color]::FromArgb(0,120,200) } else { [System.Drawing.Color]::FromArgb(55,55,70) }
    $f.Controls.Add($btnFPS)
    
    $btnAnalysis = New-Object System.Windows.Forms.Button
    $btnAnalysis.Text = "Analysis"
    $btnAnalysis.Location = New-Object System.Drawing.Point(394, 48)
    $btnAnalysis.Size = New-Object System.Drawing.Size(62, 25)
    $btnAnalysis.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnAnalysis.ForeColor = [System.Drawing.Color]::White
    $btnAnalysis.BackColor = if ($script:currentProfile -eq "Analysis") { [System.Drawing.Color]::FromArgb(0,120,200) } else { [System.Drawing.Color]::FromArgb(55,55,70) }
    $f.Controls.Add($btnAnalysis)
    
    $btnSilent = New-Object System.Windows.Forms.Button
    $btnSilent.Text = "Silent"
    $btnSilent.Location = New-Object System.Drawing.Point(459, 48)
    $btnSilent.Size = New-Object System.Drawing.Size(55, 25)
    $btnSilent.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSilent.ForeColor = [System.Drawing.Color]::White
    $btnSilent.BackColor   = if ($script:currentProfile -eq "Silent")   { [System.Drawing.Color]::FromArgb(0,120,200) } else { [System.Drawing.Color]::FromArgb(55,55,70) }
    $f.Controls.Add($btnSilent)
    
    $sep1 = New-Object System.Windows.Forms.Label
    $sep1.Text      = ""
    $sep1.Location  = New-Object System.Drawing.Point(20, 78)
    $sep1.Size      = New-Object System.Drawing.Size(555, 2)
    $sep1.BackColor = [System.Drawing.Color]::FromArgb(38, 40, 52)
    $f.Controls.Add($sep1)
    
    # Scrollable Panel for Checkboxes
    $scrollPanel = New-Object System.Windows.Forms.Panel
    # Search/Filter Box
    $searchBox = New-Object System.Windows.Forms.TextBox
    $searchBox.Location  = New-Object System.Drawing.Point(20, 95)
    $searchBox.Size      = New-Object System.Drawing.Size(555, 24)
    $searchBox.Font      = $script:Fonts.Small
    $searchBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 42)
    $searchBox.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 200)
    $searchBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $searchBox.Text = "Search optimizations..."
    $searchBox.Add_GotFocus({ if ($searchBox.Text -eq "Search optimizations...") { $searchBox.Text = ""; $searchBox.ForeColor = [System.Drawing.Color]::FromArgb(220,220,228) } })
    $searchBox.Add_LostFocus({ if ($searchBox.Text -eq "") { $searchBox.Text = "Search optimizations..."; $searchBox.ForeColor = [System.Drawing.Color]::FromArgb(100,100,120) } })
    $f.Controls.Add($searchBox)

    $scrollPanel = New-Object System.Windows.Forms.Panel
    $scrollPanel.Location   = New-Object System.Drawing.Point(20, 125)
    $scrollPanel.Size       = New-Object System.Drawing.Size(555, 560)
    $scrollPanel.AutoScroll = $true
    $scrollPanel.BackColor  = [System.Drawing.Color]::FromArgb(22, 22, 30)
    $scrollPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $f.Controls.Add($scrollPanel)
    
    $checkboxes = @{}
    
    # Function to populate optimizations based on profile
    $populateOptimizations = {
        param($profileName)
        
        $scrollPanel.Controls.Clear()
        $checkboxes.Clear()
        
        $y = 10
        
        # Define optimizations per profile
        $opts = @()
        
        if ($profileName -eq "MMO") {
            # MMO Profile - Comprehensive MMO/MMORPG optimizations
            $opts = @(
                # ── GRÜN: Sicher für alle Systeme ───────────────────────
                @{K="NetworkThrottling";    N="[SAFE] Disable Network Throttling";         C="Green";  D="Removes artificial bandwidth limits`nEssential for all MMOs`nImpact: High | Risk: None"}
                @{K="SystemResponsiveness"; N="[SAFE] System Responsiveness 100%";         C="Green";  D="Reserves 100% CPU for applications`nDual-Core+ recommended`nImpact: High | Risk: None"}
                @{K="NetworkOptimizations"; N="[SAFE] Disable TCP Nagle Algorithm"; C="Green";  D="Removes 200ms packet delay`nCritical for MMO combat system`nImpact: Medium | Risk: None"}
                @{K="DisableNagleIface";    N="[SAFE] Disable Nagle per NIC";         C="Green";  D="Complements global Nagle disable at adapter level`nPrevents residual latency from interface buffering`nImpact: Medium | Risk: None"}
                @{K="TcpTimedWaitDelay";    N="[SAFE] Reduce TCP TIME_WAIT (30s)";      C="Green";  D="Connection teardown 4min → 30s`nMMOs open many short TCP connections`nImpact: Medium | Risk: None"}
                @{K="NetworkPowerSaving";   N="[SAFE] Disable NIC Power Saving";        C="Green";  D="No NIC sleep mode`nEliminates random latency spikes`nImpact: Medium | Risk: Power usage"}
                @{K="HighPerfPowerPlan";    N="[SAFE] High Performance Power Plan";   C="Green";  D="No CPU/RAM throttling at idle`nCritical during combat after idle periods`nImpact: High | Risk: Power usage"}
                @{K="DisableNetBIOS";       N="[SAFE] Disable NetBIOS over TCP/IP";   C="Green";  D="Eliminates NetBIOS broadcast traffic`nUseless for MMO connections`nImpact: Low | Risk: None"}
                @{K="DisableIPv6";          N="[SAFE] Disable IPv6 on Game Adapter"; C="Green";  D="MMO servers use IPv4 exclusively`nIPv6 causes fallback delays`nImpact: Low | Risk: None"}
                @{K="PagingExecutive";      N="[SAFE] Keep Kernel in RAM";               C="Green";  D="DisablePagingExecutive=1`nPrevents kernel paging to disk`nImpact: Medium | Risk: None (8GB+ RAM)"}
                @{K="TimerResolutionMMO";   N="[SAFE] Timer Resolution 1ms";               C="Green";  D="System clock precision 15ms → 1ms`nSmoother ping measurement intervals`nImpact: Medium | Risk: Power usage"}
                @{K="GameMode";             N="[SAFE] Enable Windows Game Mode";       C="Green";  D="Native Windows optimization`nWin 10+ only`nImpact: Low | Risk: None"}
                @{K="MMCSS";               N="[SAFE] MMCSS Gaming Profile";               C="Green";  D="Highest priority for game processes`nPrevents process interference`nImpact: Medium | Risk: None"}
                @{K="CoreParkingFix";       N="[SAFE] Disable CPU Core Parking";      C="Green";  D="All CPU cores permanently active`nCritical on Dual-Core systems`nImpact: High | Risk: Power usage"}
                @{K="KeyboardResponse";     N="[SAFE] Optimize Keyboard Response";     C="Green";  D="Key repeat delay 200ms → 31ms`nFaster skill input in combat`nImpact: Medium | Risk: None"}
                @{K="DNSCache";             N="[SAFE] Clear DNS Cache";                   C="Green";  D="Remove stale DNS cache entries`nRun when connection issues occur`nImpact: Low | Risk: None"}
                @{K="DeliveryOptimization"; N="[SAFE] Disable Windows Update P2P";    C="Green";  D="Stops P2P Windows Update sharing`nWin 10/11 — saves bandwidth in-game`nImpact: Medium | Risk: None"}
                @{K="WindowsDefenderExcl";  N="[SAFE] Defender: Exclude Game Folder"; C="Green";  D="Disable real-time scan on game directory`nReduces disk latency during loading`nImpact: Medium | Risk: Review security"}

                # ── ORANGE: System-abhängig — vor Aktivierung testen ────
                @{K="SysMainOptimization";  N="[TEST] Disable SysMain/Superfetch";    C="Orange"; D="Stops disk prefetching`nHDDs benefit the most`nCON: Slower game launch on SSD"}
                @{K="HAGS";                N="[TEST] GPU Hardware Scheduling";             C="Orange"; D="Reduces GPU latency`nWin10 2004+ and modern GPU required`nRestart required"}
                @{K="QoSMMO";              N="[TEST] Disable QoS Packet Scheduler";   C="Orange"; D="Removes 20% bandwidth reserve`nCON: Only use without router-side QoS`nImpact: Medium"}
                @{K="NetworkBuffersMMO";   N="[TEST] Increase NIC Buffers (2048)";          C="Orange"; D="RX/TX buffer 256 → 2048`nStabilizes data throughput`nCON: Higher RAM consumption"}
                @{K="FlowControl";         N="[TEST] Disable Ethernet Flow Control";          C="Orange"; D="Prevents PAUSE frames causing latency spikes`nCON: NIC driver dependent`nAdapter restart required"}
                @{K="LargePacketOffload";  N="[TEST] Disable LSO (Large Send Offload)";       C="Orange"; D="More consistent latency`nCON: Higher CPU load (+5-10%)`nGood for low-latency MMOs"}
                @{K="RSSQueuesMMO";        N="[TEST] Optimize RSS Queue Count";          C="Orange"; D="Distributes network load across CPU cores`nCON: Quad-Core minimum required`nAdapter restart required"}
                @{K="InterruptAffinityMMO";N="[TEST] Set NIC Interrupt Affinity";      C="Orange"; D="NIC interrupts on dedicated CPU core`nCON: System dependent — test first`nImpact: Medium"}
                @{K="AutoTuningMMO";       N="[TEST] Adjust TCP AutoTuning";             C="Orange"; D="'highlyrestricted' for stable MMO traffic`nCON: May worsen on fiber connections`nMeasure baseline ping first"}
                @{K="DNSOverHTTPS";        N="[TEST] Enable DNS over HTTPS (DoH)";    C="Orange"; D="Encrypted + often faster DNS`nCON: First lookup slightly slower`nWin10 2004+ / Win11"}
            )
        }
        elseif ($profileName -eq "FPS") {
            # Competitive Profile - Maximale Low-Latency für Ranked/Competitive Gaming
            $opts = @(
                # ── GRÜN: Sicher für alle Systeme ───────────────────────────────
                @{K="NetworkThrottling";    N="[SAFE] Disable Network Throttling";          C="Green"; D="Removes artificial bandwidth limit`nEssential for competitive gaming`nImpact: High | Risk: None"}
                @{K="SystemResponsiveness"; N="[SAFE] System Responsiveness 100%";          C="Green"; D="0% CPU reserved for system tasks`nMaximum performance for game process`nImpact: High | Risk: None"}
                @{K="NetworkOptimizations"; N="[SAFE] Disable TCP Nagle Algorithm";  C="Green"; D="Removes 200ms packet delay`nCritical for hitbox registration`nImpact: High | Risk: None"}
                @{K="DisableNagleIface";    N="[SAFE] Disable Nagle per NIC";          C="Green"; D="Complements global Nagle at adapter level`nPrevents interface buffering`nImpact: Medium | Risk: None"}
                @{K="TcpTimedWaitDelay";    N="[SAFE] Reduce TCP TIME_WAIT (30s)";       C="Green"; D="Connection teardown 4min → 30s`nFaster reconnect after match end`nImpact: Medium | Risk: None"}
                @{K="NetworkPowerSaving";   N="[SAFE] Disable NIC Power Saving";         C="Green"; D="No NIC sleep mode`nEliminates random latency spikes im Match`nImpact: High | Risk: Power usage"}
                @{K="HighPerfPowerPlan";    N="[SAFE] High Performance Power Plan";    C="Green"; D="No CPU/RAM throttling`nCritical for consistent FPS in long sessions`nImpact: High | Risk: Power usage"}
                @{K="CoreParkingFix";       N="[SAFE] Disable CPU Core Parking";       C="Green"; D="All CPU cores permanently active`nCritical for stable FPS — eliminates stutter`nImpact: Very High | Risk: Power usage"}
                @{K="MMCSS";               N="[SAFE] MMCSS Gaming Profile";                C="Green"; D="Highest priority for game process`nNetwork tasks prioritized`nImpact: High | Risk: None"}
                @{K="GameMode";            N="[SAFE] Enable Windows Game Mode";         C="Green"; D="Native Windows FPS optimization`nWin 10+ only`nImpact: Medium | Risk: None"}
                @{K="TimerResolutionMMO";   N="[SAFE] Timer Resolution 1ms";                C="Green"; D="System clock 15ms → 1ms`nSmoother input handling and frame timing`nImpact: Medium | Risk: Power usage"}
                @{K="DisableIPv6";          N="[SAFE] Disable IPv6 on Game Adapter";  C="Green"; D="Competitive servers use IPv4`nIPv6 fallback adds 10-50ms extra delay`nImpact: Medium | Risk: None"}
                @{K="QoSMMO";              N="[SAFE] Remove QoS Bandwidth Reserve";   C="Green"; D="Windows reserves 20% bandwidth for QoS`nRemoves this limit completely`nImpact: Medium | Risk: None"}
                @{K="DisableNetBIOS";       N="[SAFE] Disable NetBIOS over TCP/IP";    C="Green"; D="Eliminates NetBIOS broadcast traffic`nReduces unnecessary network background traffic`nImpact: Low | Risk: None"}
                @{K="PagingExecutive";      N="[SAFE] Keep Kernel in RAM";                C="Green"; D="DisablePagingExecutive=1`nNo kernel paging to disk`nImpact: Medium | Risk: None (8GB+ RAM)"}
                @{K="DeliveryOptimization"; N="[SAFE] Disable Windows Update P2P";     C="Green"; D="Stops P2P update sharing during match`nPrevents ping spikes from background uploads`nImpact: Medium | Risk: None"}
                @{K="KeyboardResponse";     N="[SAFE] Optimize Keyboard Response";        C="Green"; D="Key repeat delay 200ms → 31ms`nFaster input in ranked matches`nImpact: Medium | Risk: None"}
                @{K="WindowsDefenderExcl";  N="[SAFE] Defender: Exclude Game Folder";  C="Green"; D="Disable real-time scan on game directory`nPrevents FPS drops from file scanning`nImpact: High | Risk: Review security"}
                @{K="DNSCache";             N="[SAFE] Clear DNS Cache";                    C="Green"; D="Remove stale DNS cache entries`nRecommended before each ranked match`nImpact: Low | Risk: None"}

                # ── ROT: Aggressiv — nur mit Weitblick aktivieren ────────────────
                @{K="InterruptModeration";  N="[AGGRO] Disable Interrupt Moderation"; C="Red";    D="5-10ms lower latency`nCON: +10-30% CPU load`nREQUIRES: 4+ cores — monitor CPU usage"}
                @{K="LargePacketOffload";   N="[AGGRO] Disable LSO (Large Send Offload)";      C="Red";    D="Consistent packet latency without offload delay`nCON: +15% CPU load`nEssential for top competitive"}
                @{K="TimerResolution";      N="[AGGRO] High Timer Resolution";             C="Red";    D="System clock 0.5ms precision (maximum)`nCON: External tool required (TimerResolution.exe)`nCON: Power usage — dedicated gaming PCs only"}

                # ── ORANGE: System-abhängig — vor Ranked-Session testen ─────────
                @{K="ReceiveSideScaling";   N="[TEST] RSS Multi-Core Network";             C="Orange"; D="Distributes network load across CPU cores`nCON: Quad-Core minimum required`nAdapter restart required"}
                @{K="TCPAckFreqComp";       N="[TEST] Set TCP ACK Frequency to 1";             C="Orange"; D="Acknowledge every packet immediately (no batching)`nReduces ACK delay latency`nCON: More small packets = higher CPU load"}
                @{K="NetworkBuffersComp";   N="[TEST] Reduce NIC Buffers (64 Frames)";  C="Orange"; D="Small buffers = less queue latency`nCON: Packet loss possible on unstable connections`nOnly for stable LAN/fiber connections"}
                @{K="FlowControl";          N="[TEST] Disable Ethernet Flow Control";           C="Orange"; D="Prevents PAUSE frames increasing input lag`nCON: NIC driver dependent — test before use`nAdapter restart required"}
                @{K="InterruptAffinityMMO"; N="[TEST] Set NIC Interrupt Affinity";       C="Orange"; D="NIC interrupts on dedicated CPU core`nReduces CPU contention under high traffic`nCON: System dependent — test carefully"}
                @{K="AutoTuningLevel";      N="[TEST] Adjust TCP Auto-Tuning";            C="Orange"; D="Fiber / Gigabit benefits most`nCON: May worsen on DSL connections`nMeasure baseline ping first"}
                @{K="CongestionProvider";   N="[TEST] CTCP Congestion Provider";            C="Orange"; D="Faster recovery after packet loss`nCON: Requires router with QoS support`nAdvanced users only"}
                @{K="CPUPriorityBoost";     N="[TEST] CPU Priority Boost (Game Process)";  C="Orange"; D="Sets game process to highest priority`nCON: May destabilize system with low RAM`nOnly on dedicated gaming PCs"}
                @{K="PowerSchemeUltimate";  N="[TEST] Ultimate Performance Plan";           C="Orange"; D="Most aggressive Windows power plan`nNo CPU/GPU throttling under load`nCON: High power usage | Win10 1803+ required"}
                @{K="SysMainOptimization";  N="[TEST] Disable SysMain/Superfetch";    C="Orange"; D="Prevents disk prefetch during match`nCON: Slower game launch after restart`nHDDs profitieren mehr als SSDs"}
                @{K="DNSOverHTTPS";         N="[TEST] Enable DNS over HTTPS (DoH)";    C="Orange"; D="Schnelleres + verschlüsseltes DNS`nCON: First lookup slightly slower`nWin10 2004+ required / Win11"}
                @{K="HAGS";                N="[TEST] GPU Hardware Scheduling";             C="Orange"; D="Reduziert GPU-Frame-Latenz`nWin10 2004+ and modern GPU required`nRestart required"}
            )
        }
        elseif ($profileName -eq "Analysis") {
            # Analysis Profile - Minimal optimizations, don't interfere with measurements
            $opts = @(
                @{K="NetworkThrottling"; N="Disable Network Throttling"; C="Green"; D="PRO: Removes limit`nMinimal impact`nImpact: Low | Risk: None"}
                @{K="DNSCache"; N="Clear DNS Cache"; C="Green"; D="PRO: Fresh DNS`nGood for testing`nImpact: Low | Risk: None"}
                @{K="GameMode"; N="Windows Game Mode"; C="Green"; D="PRO: Native mode`nWin 10+`nImpact: Low | Risk: None"}
            )
        }
        else {
            # Silent Profile - Basic optimizations only
            $opts = @(
                @{K="NetworkThrottling"; N="Disable Network Throttling"; C="Green"; D="PRO: Basic optimization`nLow impact`nRisk: None"}
                @{K="DNSCache"; N="Clear DNS Cache"; C="Green"; D="PRO: Clean DNS`nBasic maintenance`nRisk: None"}
            )
        }
        
        # Create checkboxes
        foreach ($o in $opts) {
            $cb = New-Object System.Windows.Forms.CheckBox
            $cb.Text = $o.N
            $cb.Location = New-Object System.Drawing.Point(10, $y)
            $cb.Size = New-Object System.Drawing.Size(535, 25)
            $cb.Checked = $Global:OptimizationConfig[$o.K]
            $cb.Font = $script:Fonts.Small
            
            if ($o.C -eq "Green") {
                $cb.ForeColor = [System.Drawing.Color]::FromArgb(60, 200, 100)
            } elseif ($o.C -eq "Red") {
                $cb.ForeColor = [System.Drawing.Color]::FromArgb(220, 80, 80)
            } else {
                $cb.ForeColor = [System.Drawing.Color]::DarkOrange
            }
            
            $toolTip.SetToolTip($cb, $o.D)
            $checkboxes[$o.K] = $cb
            $scrollPanel.Controls.Add($cb)
            
            $y += 30
        }
    }
    
    # Initial populate
    & $populateOptimizations $script:currentProfile
    
    # Profile button click events
    $btnMMO.Add_Click({
        $script:currentProfile = "MMO"
        Switch-Profile "MMO"
        & $populateOptimizations "MMO"
        $btnMMO.BackColor = [System.Drawing.Color]::FromArgb(0,120,200)
        $btnFPS.BackColor = [System.Drawing.Color]::FromArgb(35,35,48)
        $btnAnalysis.BackColor = [System.Drawing.Color]::FromArgb(55,55,70)
        $btnSilent.BackColor   = [System.Drawing.Color]::FromArgb(55,55,70)
        $profileLabel.Text = "Active Profile: MMO Gaming"
        $f.Text = "Optimization Manager v$($CONFIG.Version) - Profile: MMO Gaming"
    })
    
    $btnFPS.Add_Click({
        $script:currentProfile = "FPS"
        Switch-Profile "FPS"
        & $populateOptimizations "FPS"
        $btnMMO.BackColor = [System.Drawing.Color]::FromArgb(35,35,48)
        $btnFPS.BackColor = [System.Drawing.Color]::FromArgb(0,120,200)
        $btnAnalysis.BackColor = [System.Drawing.Color]::FromArgb(55,55,70)
        $btnSilent.BackColor   = [System.Drawing.Color]::FromArgb(55,55,70)
        $profileLabel.Text = "Active Profile: Competitive"
        $f.Text = "Optimization Manager v$($CONFIG.Version) - Profile: Competitive"
    })
    
    $btnAnalysis.Add_Click({
        $script:currentProfile = "Analysis"
        Switch-Profile "Analysis"
        & $populateOptimizations "Analysis"
        $btnMMO.BackColor = [System.Drawing.Color]::FromArgb(35,35,48)
        $btnFPS.BackColor = [System.Drawing.Color]::FromArgb(35,35,48)
        $btnAnalysis.BackColor = [System.Drawing.Color]::FromArgb(0,120,200)
        $btnSilent.BackColor   = [System.Drawing.Color]::FromArgb(55,55,70)
        $profileLabel.Text = "Active Profile: Analysis Mode"
        $f.Text = "Optimization Manager v$($CONFIG.Version) - Profile: Analysis Mode"
    })
    
    $btnSilent.Add_Click({
        $script:currentProfile = "Silent"
        Switch-Profile "Silent"
        & $populateOptimizations "Silent"
        $btnMMO.BackColor = [System.Drawing.Color]::FromArgb(35,35,48)
        $btnFPS.BackColor = [System.Drawing.Color]::FromArgb(35,35,48)
        $btnAnalysis.BackColor = [System.Drawing.Color]::FromArgb(55,55,70)
        $btnSilent.BackColor   = [System.Drawing.Color]::FromArgb(0,120,200)
        $profileLabel.Text = "Active Profile: Silent Background"
        $f.Text = "Optimization Manager v$($CONFIG.Version) - Profile: Silent Background"
    })
    
    # Bottom buttons
    $y = 730
    
    $legend = New-Object System.Windows.Forms.Label
    $legend.Text      = "●  Safe   ●  Advanced   ●  Competitive Only"
    $legend.Location  = New-Object System.Drawing.Point(20, $y)
    $legend.Size      = New-Object System.Drawing.Size(555, 20)
    $legend.Font      = $script:Fonts.Italic
    $legend.ForeColor = [System.Drawing.Color]::FromArgb(90, 95, 110)
    $f.Controls.Add($legend)
    $y += 25

    # ── Search Filter Event (nach Populate) ─────────────────────
    $searchBox.Add_TextChanged({
        $term = $searchBox.Text.Trim().ToLower()
        if ($term -eq "search optimizations...") { $term = "" }
        $yy = 5
        foreach ($k in @($checkboxes.Keys)) {
            $cb = $checkboxes[$k]
            $visible = ($term -eq "") -or ($cb.Text.ToLower().Contains($term))
            $cb.Visible = $visible
        }
        $yy = 5
        foreach ($k in @($checkboxes.Keys)) {
            $cb = $checkboxes[$k]
            if ($cb.Visible) {
                $cb.Location = New-Object System.Drawing.Point(10, $yy)
                $yy += 30
            }
        }
    })

    $saveBtn = New-Object System.Windows.Forms.Button
    $saveBtn.Text = "SAVE AND APPLY"
    $saveBtn.Location = New-Object System.Drawing.Point(30, $y)
    $saveBtn.Size = New-Object System.Drawing.Size(150, 45)
    $saveBtn.BackColor = [System.Drawing.Color]::FromArgb(45, 175, 80)
    $saveBtn.ForeColor = [System.Drawing.Color]::White
    $saveBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $saveBtn.FlatAppearance.BorderSize = 0
    $saveBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(55, 195, 95)
    $saveBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $saveBtn.Font      = $script:Fonts.Header
    
    $saveBtn.Add_Click({
        foreach ($k in $checkboxes.Keys) {
            $Global:OptimizationConfig[$k] = $checkboxes[$k].Checked
        }
        
        $Global:OptimizationConfig | ConvertTo-Json | Out-File $configFile -Force
        Write-Log "Configuration saved for profile: $script:currentProfile" "INFO"
        
        Apply-Optimizations
        
        $msg = "Settings saved and applied!`n`nProfile: $($script:Profiles[$script:currentProfile].Name)`n`nSome changes require a restart."
        [System.Windows.Forms.MessageBox]::Show($msg, "Success")
        
        $f.Close()
    })
    $f.Controls.Add($saveBtn)
    
    $auditBtn = New-Object System.Windows.Forms.Button
    $auditBtn.Text = "AUDIT"
    $auditBtn.Location = New-Object System.Drawing.Point(195, $y)
    $auditBtn.Size = New-Object System.Drawing.Size(90, 45)
    $auditBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
    $auditBtn.ForeColor = [System.Drawing.Color]::White
    $auditBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $auditBtn.FlatAppearance.BorderSize = 0
    $auditBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 150, 230)
    $auditBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $auditBtn.Font      = $script:Fonts.Small
    $auditBtn.Add_Click({
        $val = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -EA SilentlyContinue).NetworkThrottlingIndex
        
        $status = if ($val -eq 4294967295 -or $val -eq -1) {
            "Optimizations are ACTIVE"
        } else {
            "Optimizations INACTIVE"
        }
        
        [System.Windows.Forms.MessageBox]::Show($status, "Audit Result")
    })
    $f.Controls.Add($auditBtn)
    
    $restoreBtn = New-Object System.Windows.Forms.Button
    $restoreBtn.Text = "RESTORE"
    $restoreBtn.Location = New-Object System.Drawing.Point(295, $y)
    $restoreBtn.Size = New-Object System.Drawing.Size(130, 45)
    $restoreBtn.BackColor = [System.Drawing.Color]::FromArgb(195, 55, 55)
    $restoreBtn.ForeColor = [System.Drawing.Color]::White
    $restoreBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $restoreBtn.FlatAppearance.BorderSize = 0
    $restoreBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(215, 70, 70)
    $restoreBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $restoreBtn.Font      = $script:Fonts.Small
    $restoreBtn.Add_Click({
        Restore-RegistryBackup
    })
    $f.Controls.Add($restoreBtn)
    
    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = "Close"
    $closeBtn.Location = New-Object System.Drawing.Point(435, $y)
    $closeBtn.Size = New-Object System.Drawing.Size(120, 45)
    $closeBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
    $closeBtn.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
    $closeBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $closeBtn.FlatAppearance.BorderSize = 0
    $closeBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(68, 72, 88)
    $closeBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $closeBtn.Font      = $script:Fonts.Small
    $closeBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $f.Controls.Add($closeBtn)
    $f.CancelButton = $closeBtn
    
    $f.ShowDialog() | Out-Null
    $f.Dispose()
}

# ═══════════════════════════════════════════════════════════════
# HUD FORM — Modern borderless overlay
# ═══════════════════════════════════════════════════════════════
$hudForm = New-Object System.Windows.Forms.Form
$hudForm.Text            = "NetNinja"
$hudForm.Size            = New-Object System.Drawing.Size(440, 680)
$hudForm.BackColor       = [System.Drawing.Color]::FromArgb(15, 15, 20)
$hudForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$hudForm.MinimizeBox     = $false
$hudForm.MaximizeBox     = $false
$hudForm.TopMost         = $true
$hudForm.Opacity         = 0.96
$hudForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$hudForm.Location        = New-Object System.Drawing.Point(10, 10)
$hudForm.MinimumSize     = New-Object System.Drawing.Size(440, 680)
$hudForm.MaximumSize     = New-Object System.Drawing.Size(440, 680)

# ── Drag-to-move ohne Titelleiste ───────────────────────────
$script:hudDragStart = $null
$hudForm.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:hudDragStart = $e.Location
    }
})
$hudForm.Add_MouseMove({
    param($s, $e)
    if ($script:hudDragStart -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $dx = $e.X - $script:hudDragStart.X
        $dy = $e.Y - $script:hudDragStart.Y
        $hudForm.Location = New-Object System.Drawing.Point(
            ($hudForm.Location.X + $dx),
            ($hudForm.Location.Y + $dy))
    }
})
$hudForm.Add_MouseUp({ $script:hudDragStart = $null })

# Drag auch auf Label (größte klickbare Fläche)
$hudForm.Add_Load({
    # Label-drag wird nach Erstellung hinzugefügt
})

# ── Fade-In / Fade-Out ──────────────────────────────────────
$script:fadeTimer     = New-Object System.Windows.Forms.Timer
$script:fadeTimer.Interval = 16   # ~60fps
$script:fadeDirection = 0         # +1 = fade in, -1 = fade out
$script:fadeTarget    = 0.95      # Ziel-Opacity

$script:fadeTimer.Add_Tick({
    $current = $hudForm.Opacity
    $step    = 0.06
    if ($script:fadeDirection -eq 1) {
        $new = [math]::Min($current + $step, $script:fadeTarget)
        $hudForm.Opacity = $new
        if ($new -ge $script:fadeTarget) { $script:fadeTimer.Stop() }
    } elseif ($script:fadeDirection -eq -1) {
        $new = [math]::Max($current - $step, 0.0)
        $hudForm.Opacity = $new
        if ($new -le 0.0) {
            $script:fadeTimer.Stop()
            $hudForm.Hide()
            $hudForm.Opacity = $script:fadeTarget
        }
    }
})

function Show-HUD {
    $hudForm.Opacity = 0.0
    $hudForm.Show()
    $hudForm.BringToFront()
    $script:fadeDirection = 1
    $script:fadeTimer.Start()
}

function Hide-HUD {
    $script:fadeDirection = -1
    $script:fadeTimer.Start()
}

# ══════════════════════════════════════════════════════════════
# COMPACT OVERLAY — Vollbild-taugliches Click-Through Overlay
# Nur Text sichtbar — kein Rahmen, kein Hintergrund
# Toggle: Tray → "Overlay Mode" oder Ctrl+Alt+O
# ══════════════════════════════════════════════════════════════
$script:overlayActive = $false
$script:LogLevel       = "INFO"   # DEBUG | INFO | WARNING | ERROR
$script:hudPaused      = $false

$overlayForm = New-Object System.Windows.Forms.Form
$overlayForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$overlayForm.TopMost         = $true
$overlayForm.ShowInTaskbar   = $false
$overlayForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$overlayForm.BackColor       = [System.Drawing.Color]::Black     # wird transparent via ColorKey
$overlayForm.TransparencyKey = [System.Drawing.Color]::Black     # Schwarz = unsichtbar
$overlayForm.Opacity         = 1.0
$overlayForm.Size            = New-Object System.Drawing.Size(400, 26)

# Bildschirm-Abmessungen: oben rechts positionieren
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$overlayForm.Location = New-Object System.Drawing.Point(
    ($screen.Bounds.Width - 408),   # 8px Abstand vom rechten Rand
    8)                               # 8px vom oberen Rand

# Overlay Label — nur Schrift sichtbar, Rest transparent
$overlayLabel = New-Object System.Windows.Forms.Label
$overlayLabel.Location  = New-Object System.Drawing.Point(0, 0)
$overlayLabel.Size      = New-Object System.Drawing.Size(400, 26)
$overlayLabel.BackColor = [System.Drawing.Color]::Black         # = transparent via TransparencyKey
$overlayLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 255, 80)  # Stechendes Grün
$overlayLabel.Font      = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)
$overlayLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$overlayLabel.Text      = "PING --ms  JIT --ms  LOSS 0%"
$overlayForm.Controls.Add($overlayLabel)

# Click-Through aktivieren nach Form Handle erstellt
$overlayForm.Add_HandleCreated({
    try {
        $h   = $overlayForm.Handle
        $ex  = [OverlayHelper]::GetWindowLong($h, [OverlayHelper]::GWL_EXSTYLE)
        $ex  = $ex -bor [OverlayHelper]::WS_EX_LAYERED `
                   -bor [OverlayHelper]::WS_EX_TRANSPARENT `
                   -bor [OverlayHelper]::WS_EX_TOOLWINDOW
        [OverlayHelper]::SetWindowLong($h, [OverlayHelper]::GWL_EXSTYLE, $ex) | Out-Null
        # Immer über allen anderen Fenstern — auch Vollbild
        $flags = [OverlayHelper]::SWP_NOMOVE -bor [OverlayHelper]::SWP_NOSIZE -bor [OverlayHelper]::SWP_NOACTIVATE
        [OverlayHelper]::SetWindowPos($h, [OverlayHelper]::HWND_TOPMOST, 0, 0, 0, 0, $flags) | Out-Null
    } catch {}
})

function Enable-Overlay {
    # HUD schließen
    $hudForm.Hide()
    # Overlay anzeigen
    $overlayForm.Show()
    try {
        [OverlayHelper]::SetWindowPos(
            $overlayForm.Handle, [OverlayHelper]::HWND_TOPMOST,
            0, 0, 0, 0,
            ([OverlayHelper]::SWP_NOMOVE -bor [OverlayHelper]::SWP_NOSIZE -bor [OverlayHelper]::SWP_NOACTIVATE)
        ) | Out-Null
    } catch {}
    $script:overlayActive = $true
    Write-Log "Overlay Mode enabled" "INFO"
}

function Disable-Overlay {
    $overlayForm.Hide()
    $script:overlayActive = $false
$script:LogLevel       = "INFO"   # DEBUG | INFO | WARNING | ERROR
$script:hudPaused      = $false
    Show-HUD
    Write-Log "Overlay Mode disabled" "INFO"
}

function Toggle-Overlay {
    if ($script:overlayActive) {
        Disable-Overlay
        $script:menuOverlay.Text = "🎮  Overlay Mode: OFF              Ctrl+Alt+O"
        $trayIcon.ShowBalloonTip(2000, "NetNinja",
            "Overlay disabled — HUD restored",
            [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        Enable-Overlay
        $script:menuOverlay.Text = "🎮  Overlay Mode: ON               Ctrl+Alt+O"
        $trayIcon.ShowBalloonTip(2000, "NetNinja",
            "Overlay active — Fullscreen compatible`nCtrl+Alt+O to disable",
            [System.Windows.Forms.ToolTipIcon]::Info)
    }
}

# ─────────────────────────────────────────────────────────────
# TOP HEADER BAR — drag zone + close + profile pill
# ─────────────────────────────────────────────────────────────
$hudHeader = New-Object System.Windows.Forms.Panel
$hudHeader.Location  = New-Object System.Drawing.Point(0, 0)
$hudHeader.Size      = New-Object System.Drawing.Size(440, 36)
$hudHeader.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)

$hudAppTitle = New-Object System.Windows.Forms.Label
$hudAppTitle.Text      = "NetNinja"
$hudAppTitle.Location  = New-Object System.Drawing.Point(14, 0)
$hudAppTitle.Size      = New-Object System.Drawing.Size(200, 36)
$hudAppTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 150, 230)
$hudAppTitle.Font      = $script:Fonts.Header
$hudAppTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$hudHeader.Controls.Add($hudAppTitle)

$hudProfilePill = New-Object System.Windows.Forms.Label
$hudProfilePill.Text      = "  $($script:currentProfile)  "
$hudProfilePill.Location  = New-Object System.Drawing.Point(195, 8)
$hudProfilePill.Size      = New-Object System.Drawing.Size(70, 20)
$hudProfilePill.ForeColor = [System.Drawing.Color]::FromArgb(0, 150, 230)
$hudProfilePill.BackColor = [System.Drawing.Color]::FromArgb(0, 55, 90)
$hudProfilePill.Font      = $script:Fonts.TinyBold
$hudProfilePill.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hudHeader.Controls.Add($hudProfilePill)

$hudPauseBtn = New-Object System.Windows.Forms.Label
$hudPauseBtn.Text      = " ⏸ "
$hudPauseBtn.Location  = New-Object System.Drawing.Point(372, 0)
$hudPauseBtn.Size      = New-Object System.Drawing.Size(34, 36)
$hudPauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 115)
$hudPauseBtn.Font      = $script:Fonts.Body
$hudPauseBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hudPauseBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$hudPauseBtn.Add_Click({
    $script:hudPaused = -not $script:hudPaused
    if ($script:hudPaused) {
        $pingTimer.Stop()
        $hudPauseBtn.Text      = " ▶ "
        $hudPauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(255, 200, 0)
        $hudLabel.ForeColor    = [System.Drawing.Color]::FromArgb(90, 90, 115)
        if ($hudSubStats) { $hudSubStats.Text = "Monitoring paused — click ▶ to resume" }
        Write-Log "Monitoring paused by user" "INFO"
    } else {
        $pingTimer.Start()
        $hudPauseBtn.Text      = " ⏸ "
        $hudPauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 115)
        Write-Log "Monitoring resumed by user" "INFO"
    }
})
$hudPauseBtn.Add_MouseEnter({ $hudPauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 215) })
$hudPauseBtn.Add_MouseLeave({
    $hudPauseBtn.ForeColor = if ($script:hudPaused) {
        [System.Drawing.Color]::FromArgb(255, 200, 0)
    } else {
        [System.Drawing.Color]::FromArgb(90, 90, 115)
    }
})
$hudHeader.Controls.Add($hudPauseBtn)
& $script:AddDrag $hudPauseBtn

$hudCloseBtn = New-Object System.Windows.Forms.Label
$hudCloseBtn.Text      = " ✕ "
$hudCloseBtn.Location  = New-Object System.Drawing.Point(406, 0)
$hudCloseBtn.Size      = New-Object System.Drawing.Size(34, 36)
$hudCloseBtn.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 135)
$hudCloseBtn.Font      = $script:Fonts.Body
$hudCloseBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hudCloseBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$hudCloseBtn.Add_Click({ $hudForm.Hide() })
$hudCloseBtn.Add_MouseEnter({
    $hudCloseBtn.ForeColor = [System.Drawing.Color]::FromArgb(230, 60, 60)
    $hudCloseBtn.BackColor = [System.Drawing.Color]::FromArgb(50, 10, 10)
})
$hudCloseBtn.Add_MouseLeave({
    $hudCloseBtn.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 135)
    $hudCloseBtn.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
})
$hudHeader.Controls.Add($hudCloseBtn)
$null = $hudForm.Controls.Add($hudHeader)

# Drag helpers
$script:AddDrag = {
    param($ctrl)
    $ctrl.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:hudDragStart = $e.Location
        }
    })
    $ctrl.Add_MouseMove({
        param($s, $e)
        if ($script:hudDragStart -and ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left)) {
            $hudForm.Location = New-Object System.Drawing.Point(
                ($hudForm.Location.X + $e.X - $script:hudDragStart.X),
                ($hudForm.Location.Y + $e.Y - $script:hudDragStart.Y))
        }
    })
    $ctrl.Add_MouseUp({ $script:hudDragStart = $null })
}
& $script:AddDrag $hudHeader
& $script:AddDrag $hudAppTitle
& $script:AddDrag $hudProfilePill

# ─────────────────────────────────────────────────────────────
# MAIN PING CARD
# ─────────────────────────────────────────────────────────────
$pingCard = New-Object System.Windows.Forms.Panel
$pingCard.Location  = New-Object System.Drawing.Point(10, 44)
$pingCard.Size      = New-Object System.Drawing.Size(420, 108)
$pingCard.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
$null = $hudForm.Controls.Add($pingCard)
& $script:AddDrag $pingCard

# Big ping number
$hudLabel = New-Object System.Windows.Forms.Label
$hudLabel.Location  = New-Object System.Drawing.Point(0, 4)
$hudLabel.Size      = New-Object System.Drawing.Size(420, 68)
$hudLabel.ForeColor = [System.Drawing.Color]::FromArgb(50, 220, 80)
$hudLabel.BackColor = [System.Drawing.Color]::Transparent
$hudLabel.Font      = $script:Fonts.PingBig
$hudLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hudLabel.Text      = "-- ms"
$hudLabel.Cursor = [System.Windows.Forms.Cursors]::SizeAll
$pingCard.Controls.Add($hudLabel)
& $script:AddDrag $hudLabel

# Sub stats row
$hudSubStats = New-Object System.Windows.Forms.Label
$hudSubStats.Location  = New-Object System.Drawing.Point(0, 72)
$hudSubStats.Size      = New-Object System.Drawing.Size(420, 22)
$hudSubStats.ForeColor = [System.Drawing.Color]::FromArgb(110, 110, 140)
$hudSubStats.BackColor = [System.Drawing.Color]::Transparent
$hudSubStats.Font      = New-Object System.Drawing.Font("Consolas", 8)
$hudSubStats.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hudSubStats.Text      = "JITTER -- ms   |   LOSS 0%   |   MIN -- / MAX --"
$pingCard.Controls.Add($hudSubStats)
& $script:AddDrag $hudSubStats

# pingBarPanel defined below with graphPanel

# ─────────────────────────────────────────────────────────────
# SERVER / ADAPTIVE ROW
# ─────────────────────────────────────────────────────────────
$hudServerLabel = New-Object System.Windows.Forms.Label
$hudServerLabel.Location  = New-Object System.Drawing.Point(10, 163)
$hudServerLabel.Size      = New-Object System.Drawing.Size(420, 20)
$hudServerLabel.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 105)
$hudServerLabel.BackColor = [System.Drawing.Color]::Transparent
$hudServerLabel.Font      = New-Object System.Drawing.Font("Consolas", 8)
$hudServerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$hudServerLabel.Text      = "$($script:TargetIP)  ●"
$null = $hudForm.Controls.Add($hudServerLabel)
& $script:AddDrag $hudServerLabel

# ─────────────────────────────────────────────────────────────
# TIMEFRAME TABS — pill buttons
# ─────────────────────────────────────────────────────────────
$timeframePanel = New-Object System.Windows.Forms.Panel
$timeframePanel.Location  = New-Object System.Drawing.Point(10, 184)
$timeframePanel.Size      = New-Object System.Drawing.Size(420, 32)
$timeframePanel.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 18)
$null = $hudForm.Controls.Add($timeframePanel)

$tfActive   = [System.Drawing.Color]::FromArgb(0, 130, 210)
$tfInactive = [System.Drawing.Color]::FromArgb(26, 26, 36)
$tfFgActive = [System.Drawing.Color]::White
$tfFgInact  = [System.Drawing.Color]::FromArgb(90, 90, 115)

$script:tfButtons = @()
$tfDefs = @(
    @{ Text="60s";   X=0;   TF="60s"   }
    @{ Text="5min";  X=73;  TF="5min"  }
    @{ Text="30min"; X=146; TF="30min" }
    @{ Text="1h";    X=219; TF="1h"    }
)
foreach ($td in $tfDefs) {
    $tb = New-Object System.Windows.Forms.Button
    $tb.Text      = $td.Text
    $tb.Location  = New-Object System.Drawing.Point($td.X, 2)
    $tb.Size      = New-Object System.Drawing.Size(68, 28)
    $tb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $tb.FlatAppearance.BorderSize = 0
    $tb.BackColor = if ($td.TF -eq "60s") { $tfActive } else { $tfInactive }
    $tb.ForeColor = if ($td.TF -eq "60s") { $tfFgActive } else { $tfFgInact }
    $tb.Font      = $script:Fonts.TinyBold
    $tb.Tag       = $td.TF
    $tb.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $tb.Add_Click({
        $script:currentTimeframe = $this.Tag
        foreach ($b in $script:tfButtons) {
            $b.BackColor = if ($b.Tag -eq $this.Tag) { $tfActive } else { $tfInactive }
            $b.ForeColor = if ($b.Tag -eq $this.Tag) { $tfFgActive } else { $tfFgInact }
        }
        & $script:UpdateGraph
    })
    $timeframePanel.Controls.Add($tb)
    $script:tfButtons += $tb
}
$btn60s   = $script:tfButtons[0]
$btn5min  = $script:tfButtons[1]
$btn30min = $script:tfButtons[2]
$btn1h    = $script:tfButtons[3]

$tfLabel = New-Object System.Windows.Forms.Label
$tfLabel.Text      = "Last 60 seconds"
$tfLabel.Location  = New-Object System.Drawing.Point(298, 8)
$tfLabel.Size      = New-Object System.Drawing.Size(120, 16)
$tfLabel.ForeColor = [System.Drawing.Color]::FromArgb(75, 75, 100)
$tfLabel.BackColor = [System.Drawing.Color]::Transparent
$tfLabel.Font      = $script:Fonts.Micro
$tfLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$timeframePanel.Controls.Add($tfLabel)

# ─────────────────────────────────────────────────────────────
# GRAPH PANEL
# ─────────────────────────────────────────────────────────────
$script:graphPanel = New-Object System.Windows.Forms.Panel
$script:graphPanel.Location    = New-Object System.Drawing.Point(10, 220)
$script:graphPanel.Size        = New-Object System.Drawing.Size(420, 272)
$script:graphPanel.BackColor   = [System.Drawing.Color]::FromArgb(10, 10, 15)
$script:graphPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
# ── PING BAR — visueller Balken unter HUD-Label ─────────────
$script:pingBarPanel = New-Object System.Windows.Forms.Panel
$script:pingBarPanel.Location  = New-Object System.Drawing.Point(10, 155)
$script:pingBarPanel.Size      = New-Object System.Drawing.Size(420, 6)
$script:pingBarPanel.BackColor = [System.Drawing.Color]::FromArgb(22, 22, 30)

$script:pingBarFill = New-Object System.Windows.Forms.Panel
$script:pingBarFill.Location  = New-Object System.Drawing.Point(0, 0)
$script:pingBarFill.Size      = New-Object System.Drawing.Size(0, 6)
$script:pingBarFill.BackColor = [System.Drawing.Color]::FromArgb(50, 220, 80)
$script:pingBarPanel.Controls.Add($script:pingBarFill)
$null = $hudForm.Controls.Add($script:pingBarPanel)

$null = $hudForm.Controls.Add($script:graphPanel)

# ── HUD Context Menu (Rechtsklick auf HUD) ─────────────────
$hudContext = New-Object System.Windows.Forms.ContextMenuStrip
$hudContext.Renderer        = New-Object NetNinjaMenuRenderer
$hudContext.ShowImageMargin = $false
$hudContext.ShowCheckMargin = $false
$hudContext.BackColor       = [System.Drawing.Color]::FromArgb(26, 26, 34)
$hudContext.Font            = $script:Fonts.Small

# Reset Stats
$null = $hudContext.Items.Add("Reset Statistics", $null, {
    $script:totalPings    = 0
    $script:lostPings     = 0
    $script:minLat        = 9999
    $script:maxLat        = 0
    $script:Last60sSpike  = 0
    $script:currentJitter = 0
    $script:pingHistory.Clear()
    $script:pingHistory5min.Clear()
    $script:pingHistory30min.Clear()
    $script:pingHistory1h.Clear()
    $script:adaptiveWindow.Clear()
    $script:graphUpdateCounter = 0
    $hudLabel.Text = "Reset!"
    if ($hudSubStats) { $hudSubStats.Text = "Statistics cleared" }
    Write-Log "Stats manually reset by user" "INFO"
})

# Separator
$null = $hudContext.Items.Add("-")

# HUD ausblenden
$null = $hudContext.Items.Add("Hide HUD", $null, {
    $hudForm.Hide()
})

$hudForm.ContextMenuStrip    = $hudContext
$hudLabel.ContextMenuStrip   = $hudContext
$script:graphPanel.ContextMenuStrip = $hudContext

# ─────────────────────────────────────────────────────────────
# NETWORK TIMELINE PANEL — Event Log unter Graph
# ─────────────────────────────────────────────────────────────
$tlHeader = New-Object System.Windows.Forms.Label
$tlHeader.Location  = New-Object System.Drawing.Point(10, 498)
$tlHeader.Size      = New-Object System.Drawing.Size(420, 22)
$tlHeader.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
$tlHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
$tlHeader.Font      = $script:Fonts.TinyBold
$tlHeader.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$tlHeader.Text      = "  ⟳ NETWORK TIMELINE"
$tlHeader.Cursor    = [System.Windows.Forms.Cursors]::Hand
$null = $hudForm.Controls.Add($tlHeader)
& $script:AddDrag $tlHeader

# Toggle-Button rechts
$tlToggleBtn = New-Object System.Windows.Forms.Label
$tlToggleBtn.Location  = New-Object System.Drawing.Point(380, 498)
$tlToggleBtn.Size      = New-Object System.Drawing.Size(50, 22)
$tlToggleBtn.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 14)
$tlToggleBtn.ForeColor = [System.Drawing.Color]::FromArgb(70, 70, 90)
$tlToggleBtn.Font      = $script:Fonts.Tiny
$tlToggleBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$tlToggleBtn.Text      = "CLEAR"
$tlToggleBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
$tlToggleBtn.Add_Click({
    $script:netTimeline.Clear()
    if ($script:tlPanel) { $script:tlPanel.Invalidate() }
    Write-Log "Timeline cleared by user" "INFO"
})
$null = $hudForm.Controls.Add($tlToggleBtn)

$script:tlPanel = New-Object System.Windows.Forms.Panel
$script:tlPanel.Location  = New-Object System.Drawing.Point(10, 520)
$script:tlPanel.Size      = New-Object System.Drawing.Size(420, 148)
$script:tlPanel.BackColor = [System.Drawing.Color]::FromArgb(10, 12, 16)
$null = $hudForm.Controls.Add($script:tlPanel)

$script:tlPanel.Add_Paint({
    param($s, $e)
    $g  = $e.Graphics
    $g.Clear([System.Drawing.Color]::FromArgb(10, 12, 16))
    $fnt = $script:gfxCache.FontTimeline
    $fntTime = $script:gfxCache.FontTimelineSm
    $y  = 4
    $maxShow = 9
    $shown = 0
    foreach ($entry in $script:netTimeline) {
        if ($shown -ge $maxShow) { break }
        # Farbe je nach Typ
        $fg = switch ($entry.Type) {
            "spike"   { [System.Drawing.Color]::FromArgb(255, 180, 40) }
            "loss"    { [System.Drawing.Color]::FromArgb(220, 60, 60)  }
            "restore" { [System.Drawing.Color]::FromArgb(50, 210, 80)  }
            "profile" { [System.Drawing.Color]::FromArgb(0, 140, 220)  }
            "speed"   { [System.Drawing.Color]::FromArgb(160, 100, 255)}
            "warn"    { [System.Drawing.Color]::FromArgb(255, 140, 0)  }
            default   { [System.Drawing.Color]::FromArgb(100, 100, 130)}
        }
        $dot = switch ($entry.Type) {
            "spike"   { "⚡" }; "loss"    { "✖" }; "restore" { "✔" }
            "profile" { "🎮" }; "speed"   { "📶" }; "warn"    { "⚠" }
            default   { "·" }
        }
        $timeBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(55, 55, 75))
        $g.DrawString($entry.Time, $fntTime, $timeBr, [float]4, [float]($y+1))
        $timeBr.Dispose()
        $msgBr = New-Object System.Drawing.SolidBrush($fg)
        $g.DrawString("$dot $($entry.Msg)", $fnt, $msgBr, [float]62, [float]$y)
        $msgBr.Dispose()
        $y += 15
        $shown++
    }
    if ($script:netTimeline.Count -eq 0) {
        $emptyBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 45, 65))
        $g.DrawString("No events yet — monitoring active", $fnt, $emptyBr, [float]10, [float]60)
        $emptyBr.Dispose()
    }
    # FontTimeline/FontTimelineSm sind gecacht
})

# ── Gecachte Graph-Ressourcen (erstellt einmalig, nicht bei jedem Paint) ──
$script:gfxCache = @{
    PenGoodLine    = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50,220,80), 2)
    PenWarnLine    = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,220,50), 2)
    PenHighLine    = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,165,0), 2)
    PenCritLine    = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,60,60), 2)
    PenLoss        = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200,255,40,40), 2)
    BrushLoss      = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220,255,40,40))
    PenGrid        = $(($p=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22,255,255,255),1)); $p.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dot; $p)
    PenVertLine    = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,255,255,255), 1)
    PenCrosshair   = $(($p2=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130,255,255,255),1)); $p2.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dash; $p2)
    PenCrosshairH  = $(($p3=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(50,255,255,255),1));  $p3.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dot; $p3)
    FontTimeline   = New-Object System.Drawing.Font("Consolas", 7.5)
    FontTimelineSm = New-Object System.Drawing.Font("Consolas", 7)
    FontHeatmapSm  = New-Object System.Drawing.Font("Segoe UI", 7)
    FontHeatmapTiny= New-Object System.Drawing.Font("Segoe UI", 6)
    FontOverlay    = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    PenGrid       = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(18,100,100,140), 1)
    PenGridEdge   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(30,100,100,140), 1)
    PenAxis       = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(35,80,80,120), 1)
    PenThresh     = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80,255,165,0), 1)
    PenCrit       = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80,255,60,60), 1)
    PenCursor     = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(60,255,255,255), 1)
    BrushLabel    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90,90,115))
    BrushThresh   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,255,165,0))
    BrushCrit     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(160,255,80,80))
    BrushStats    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,140,160))
    FontAxis      = New-Object System.Drawing.Font("Segoe UI", 7)
}
$script:gfxCache.PenThresh.DashStyle  = [System.Drawing.Drawing2D.DashStyle]::Dash
$script:gfxCache.PenCrit.DashStyle    = [System.Drawing.Drawing2D.DashStyle]::Dash

# Graph Paint Event
$script:graphPanel.Add_Paint({
    param($sender, $e)
    
    # Select data based on timeframe
    $data = switch ($script:currentTimeframe) {
        "60s"   { @($script:pingHistory) }
        "5min"  { $script:pingHistory5min }
        "30min" { $script:pingHistory30min }
        "1h"    { $script:pingHistory1h }
        default { @($script:pingHistory) }
    }
    
    if ($data.Count -eq 0) { return }
    
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $width = $script:graphPanel.Width - 52
    $height = $script:graphPanel.Height - 40
    $marginLeft = 50
    $marginBottom = 30
    
    # Background gradient (top darker, bottom slightly lighter)
    $g.Clear([System.Drawing.Color]::FromArgb(10, 10, 15))

    # Subtle horizontal grid lines (cached pens — no GC pressure)
    for ($i = 0; $i -le 4; $i++) {
        $y = $marginBottom + ($height / 4) * $i
        $gp = if ($i -eq 0 -or $i -eq 4) { $script:gfxCache.PenGridEdge } else { $script:gfxCache.PenGrid }
        $g.DrawLine($gp, $marginLeft, $y, $marginLeft + $width, $y)
    }

    # Left axis accent line
    $g.DrawLine($script:gfxCache.PenAxis, $marginLeft, $marginBottom, $marginLeft, $marginBottom + $height)
    
    # Find max ping for scaling
    $maxPing = 200
    if ($data.Count -gt 0) {
        $actualMax = ($data | Measure-Object -Maximum).Maximum
        if ($actualMax -gt $maxPing) { $maxPing = [math]::Ceiling($actualMax / 50) * 50 }
    }
    
    # Y-axis labels
    $font = $script:gfxCache.FontAxis
    for ($i = 0; $i -le 4; $i++) {
        $value = [int]($maxPing - ($maxPing / 4) * $i)
        $y     = $marginBottom + ($height / 4) * $i
        $g.DrawString("${value}ms", $font, $script:gfxCache.BrushLabel, 2, ($y - 8))
    }
    
    # X-axis time label
    $xBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(80, 80, 105))
    $xFont  = $script:gfxCache.FontHeatmapSm
    $timeLabel = switch ($script:currentTimeframe) {
        "60s"   { "← 60 seconds" }
        "5min"  { "← 5 minutes" }
        "30min" { "← 30 minutes" }
        "1h"    { "← 1 hour" }
    }
    # (Time label rendered below stats bar in stats section)
    $xFont.Dispose(); $xBrush.Dispose()
    
    # Threshold lines
    # Threshold lines — all cached

    # High ping line
    $threshY = $marginBottom + $height - (([math]::Min($CONFIG.AlertHighPing, $maxPing) / $maxPing) * $height)
    if ($threshY -gt $marginBottom -and $threshY -lt ($marginBottom + $height)) {
        $g.DrawLine($script:gfxCache.PenThresh, $marginLeft, $threshY, $marginLeft + $width, $threshY)
        $g.DrawString("$($CONFIG.AlertHighPing)ms", $font, $script:gfxCache.BrushThresh, $marginLeft + $width - 45, $threshY - 14)
    }

    # Critical ping line
    $critY = $marginBottom + $height - (([math]::Min($CONFIG.AlertCriticalPing, $maxPing) / $maxPing) * $height)
    if ($critY -gt $marginBottom -and $critY -lt ($marginBottom + $height)) {
        $g.DrawLine($script:gfxCache.PenCrit, $marginLeft, $critY, $marginLeft + $width, $critY)
        $g.DrawString("$($CONFIG.AlertCriticalPing)ms", $font, $script:gfxCache.BrushCrit, $marginLeft + $width - 55, $critY - 14)
    }

    # (threshold resources cached — no dispose needed)

    # Plot ping data — segment-by-segment with dynamic color
    if ($data.Count -gt 1) {
        $dataArr = @($data)
        $step    = $width / [math]::Max(($dataArr.Count - 1), 1)

        # Build all points
        $allPts = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
        for ($idx = 0; $idx -lt $dataArr.Count; $idx++) {
            $px = $marginLeft + ($idx * $step)
            $py = $marginBottom + $height - (([math]::Min($dataArr[$idx], $maxPing) / $maxPing) * $height)
            if ($py -lt $marginBottom) { $py = $marginBottom }
            $allPts.Add([System.Drawing.PointF]::new($px, $py))
        }

        # Draw segments with color per value
        for ($idx = 0; $idx -lt ($allPts.Count - 1); $idx++) {
            $val = $dataArr[$idx]
            $segPen = if ($val -ge $CONFIG.AlertCriticalPing) { $script:gfxCache.PenCritLine
            } elseif ($val -ge $CONFIG.AlertHighPing)              { $script:gfxCache.PenHighLine
            } elseif ($val -ge $CONFIG.SpikeThreshold)             { $script:gfxCache.PenWarnLine
            } else                                                  { $script:gfxCache.PenGoodLine }
            $g.DrawLine($segPen, $allPts[$idx], $allPts[$idx + 1])
        }

        # ══ v5.0: MULTI-TARGET OVERLAY im Graph ══════════════════
    if ($script:multiPingEnabled -and $script:multiTargets.Count -gt 0) {
        foreach ($mt in $script:multiTargets) {
            if (-not $mt.Enabled -or $mt.History.Count -lt 2) { continue }
            $mtArr  = @($mt.History)
            $mtStep = $width / [math]::Max(($mtArr.Count - 1), 1)
            $mtMaxP = [math]::Max(($mtArr | Measure-Object -Maximum).Maximum, 1)
            $mtMaxV = [math]::Max($mtMaxP, $maxPing)
            $allPtsM = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
            for ($mi = 0; $mi -lt $mtArr.Count; $mi++) {
                $mx = $marginLeft + ($mi * $mtStep)
                $my = $marginBottom + $height - (([math]::Min($mtArr[$mi], $mtMaxV) / $mtMaxV) * $height)
                $allPtsM.Add([System.Drawing.PointF]::new($mx, $my))
            }
            if ($allPtsM.Count -gt 1) {
                $g.DrawLines($mt.PenCache, $allPtsM.ToArray())
                # Label am rechten Ende
                $lastM = $allPtsM[$allPtsM.Count-1]
                $lblBr = New-Object System.Drawing.SolidBrush($mt.Color)
                $g.DrawString($mt.Label, $script:Fonts.Micro, $lblBr, [float]($lastM.X + 2), [float]($lastM.Y - 6))
                $lblBr.Dispose()
            }
        }
        # Legende unten rechts
        $legY = $marginBottom + $height - 4
        $xi = 0
        foreach ($mt in $script:multiTargets) {
            if (-not $mt.Enabled) { continue }
            $msStr = if ($mt.LastMs -ge 0) { "$($mt.LastMs)ms" } else { "---" }
            $lBr = New-Object System.Drawing.SolidBrush($mt.Color)
            $g.DrawString("■ $($mt.Label) $msStr", $script:Fonts.Micro, $lBr, [float]($marginLeft + $xi), [float]$legY)
            $lBr.Dispose()
            $xi += 110
        }
    }
    # ── PACKET LOSS VISUALISIERUNG — rote Linien ────────────
        $lossArr = switch ($script:currentTimeframe) {
            "60s"   { if ($script:lossHistory60s.Count  -gt 0) { @($script:lossHistory60s) }  else { @() } }
            "5min"  { if ($script:lossHistory5min.Count -gt 0) { @($script:lossHistory5min) } else { @() } }
            "30min" { if ($script:lossHistory30min.Count -gt 0){ @($script:lossHistory30min)} else { @() } }
            "1h"    { if ($script:lossHistory1h.Count   -gt 0) { @($script:lossHistory1h) }   else { @() } }
            default { @() }
        }
        if ($lossArr.Count -gt 1) {
            $lossStep = $width / [math]::Max(($lossArr.Count - 1), 1)
            $lossPen   = $script:gfxCache.PenLoss
            $lossBrush = $script:gfxCache.BrushLoss
            for ($li = 0; $li -lt $lossArr.Count; $li++) {
                if ($lossArr[$li] -eq $true) {
                    $lx = $marginLeft + ($li * $lossStep)
                    $g.DrawLine($lossPen, $lx, $marginBottom, $lx, $marginBottom + $height)
                    # Kleines "X"-Dreieck oben
                    $g.FillEllipse($lossBrush, $lx - 4, $marginBottom - 1, 8, 8)
                }
            }
            # PenLoss/BrushLoss gecacht — kein Dispose
        }
        # ─────────────────────────────────────────────────────────

        # Spike dots (60s only for performance)
        if ($script:currentTimeframe -eq "60s") {
            for ($idx = 0; $idx -lt $allPts.Count; $idx++) {
                $val = $dataArr[$idx]
                $dotColor = if ($val -ge $CONFIG.AlertCriticalPing) {
                    [System.Drawing.Brushes]::Red
                } elseif ($val -ge $CONFIG.AlertHighPing) {
                    [System.Drawing.Brushes]::Orange
                } else {
                    [System.Drawing.Brushes]::LimeGreen
                }
                $dotSize = if ($val -ge $CONFIG.AlertHighPing) { 6 } else { 4 }
                $g.FillEllipse($dotColor, $allPts[$idx].X - ($dotSize/2), $allPts[$idx].Y - ($dotSize/2), $dotSize, $dotSize)
            }
        }
    }
    
    # ── OVERLAY: Aktueller Ping groß rechts oben ─────────────
    if ($script:currentLatency -gt 0) {
        $overlayFont  = $script:gfxCache.FontOverlay
        $overlayColor = if ($script:currentLatency -ge $CONFIG.AlertCriticalPing) {
            [System.Drawing.Color]::FromArgb(255, 60, 60)
        } elseif ($script:currentLatency -ge $CONFIG.AlertHighPing) {
            [System.Drawing.Color]::FromArgb(255, 165, 0)
        } else {
            [System.Drawing.Color]::FromArgb(50, 220, 80)
        }
        $overlayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, $overlayColor.R, $overlayColor.G, $overlayColor.B))
        $overlayText  = "$($script:currentLatency)ms"
        $sz = $g.MeasureString($overlayText, $overlayFont)
        $g.DrawString($overlayText, $overlayFont, $overlayBrush, ($marginLeft + $width - $sz.Width - 5), ($marginBottom + 4))
        # gecacht
        $overlayBrush.Dispose()
    }

    # ── STATS BAR: AVG / MIN / MAX unterhalb ─────────────────
    if ($data.Count -gt 2) {
        $avg = [math]::Round(($data | Measure-Object -Average).Average, 0)
        $mn  = ($data | Measure-Object -Minimum).Minimum
        $mx  = ($data | Measure-Object -Maximum).Maximum
        $jit = if ($script:currentJitter -gt 0) { "  JIT: $($script:currentJitter)ms" } else { "" }
        $statText  = "AVG: ${avg}ms   MIN: ${mn}ms   MAX: ${mx}ms${jit}"
        $statBrush = $script:gfxCache.BrushStats
        $statFont  = $script:gfxCache.FontHeatmapSm   # local, safe to dispose
        $g.DrawString($statText, $statFont, $statBrush, [float]($marginLeft + 2), [float]($marginBottom + $height + 6))
        $statFont.Dispose()  # local copy, ok to dispose
        # statBrush is cached — do not dispose
    }

    # ── Vertikale LINIE am neuesten Datenpunkt ───────────────
    if ($data.Count -gt 1 -and $allPts -and $allPts.Count -gt 0) {
        $lastPt  = $allPts[$allPts.Count - 1]
        $linePen = $script:gfxCache.PenVertLine
        $g.DrawLine($linePen, $lastPt.X, $marginBottom, $lastPt.X, $marginBottom + $height)
        # PenVertLine ist gecacht
    }

    # ── CROSSHAIR bei Mouse-Hover ────────────────────────────
    if ($script:crosshairX -gt $marginLeft -and $script:crosshairX -lt ($marginLeft + $width) -and $data.Count -gt 1) {
        # Vertikale Crosshair-Linie
        $xhPen = $script:gfxCache.PenCrosshair
        $g.DrawLine($xhPen, $script:crosshairX, $marginBottom, $script:crosshairX, ($marginBottom + $height))

        # Ping-Wert an Cursor-Position interpolieren
        $dataArr2  = @($data)
        $step2     = $width / [math]::Max(($dataArr2.Count - 1), 1)
        $idx2      = [math]::Round(($script:crosshairX - $marginLeft) / $step2)
        $idx2      = [math]::Max(0, [math]::Min($idx2, $dataArr2.Count - 1))
        $hoverPing = $dataArr2[$idx2]

        # Tooltip-Box oben am Crosshair
        $tipText  = "$hoverPing ms"
        $tipFont  = $script:Fonts.MonoSm
        $tipSz    = $g.MeasureString($tipText, $tipFont)
        $tipX     = $script:crosshairX - ($tipSz.Width / 2)
        $tipX     = [math]::Max($marginLeft, [math]::Min($tipX, $marginLeft + $width - $tipSz.Width))
        $tipY     = $marginBottom - $tipSz.Height - 4

        $tipBgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 20, 20, 28))
        $tipFgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 230, 240))
        $g.FillRectangle($tipBgBrush, $tipX - 4, $tipY - 2, $tipSz.Width + 8, $tipSz.Height + 4)
        $g.DrawString($tipText, $tipFont, $tipFgBrush, $tipX, $tipY)
        $tipBgBrush.Dispose(); $tipFgBrush.Dispose()

        # Horizontale Hilfslinie
        $pingY2 = $marginBottom + $height - (([math]::Min($hoverPing, $maxPing) / $maxPing) * $height)
        $g.DrawLine($script:gfxCache.PenCrosshairH, $marginLeft, $pingY2, ($marginLeft + $width), $pingY2)
    }

    $font.Dispose()
})

# Update graph helper function
# ── Graph MouseMove → Crosshair ─────────────────────────────
$script:graphPanel.Add_MouseMove({
    param($s, $e)
    $script:crosshairX = $e.X
    $script:graphPanel.Invalidate()
})
$script:graphPanel.Add_MouseLeave({
    $script:crosshairX = -1
    $script:graphPanel.Invalidate()
})

$script:UpdateGraph = {
    if ($script:graphPanel) {
        $script:graphPanel.Invalidate()
    }
}

$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Visible = $true
$trayIcon.Text    = "NetNinja v$($CONFIG.Version) — Starting..."
# Sofort ein Start-Icon setzen (grau = wartend)
$startColor = [System.Drawing.Color]::FromArgb(70, 72, 90)
$startIcon  = Create-IconWithText -text "..." -color $startColor -mode "waiting"
if ($startIcon) { $trayIcon.Icon = $startIcon }

# ── Register Global Hotkeys ──────────────────────────────────
$script:hotkeyHandle = $hudForm.Handle  # attach to HUD window
try {
    $CA = [HotkeyHelper]::MOD_CTRL -bor [HotkeyHelper]::MOD_ALT
    $hk = $script:hotkeyHandle
    # ID  Key                         Shortcut
    [HotkeyHelper]::RegisterHotKey($hk, 1, $CA, [HotkeyHelper]::VK_P) | Out-Null  # Ctrl+Alt+P → HUD
    [HotkeyHelper]::RegisterHotKey($hk, 2, $CA, [HotkeyHelper]::VK_R) | Out-Null  # Ctrl+Alt+R → Reset Stats
    [HotkeyHelper]::RegisterHotKey($hk, 3, $CA, [HotkeyHelper]::VK_M) | Out-Null  # Ctrl+Alt+M → MTU
    [HotkeyHelper]::RegisterHotKey($hk, 4, $CA, [HotkeyHelper]::VK_S) | Out-Null  # Ctrl+Alt+S → Save
    [HotkeyHelper]::RegisterHotKey($hk, 5, $CA, [HotkeyHelper]::VK_O) | Out-Null  # Ctrl+Alt+O → Overlay
    [HotkeyHelper]::RegisterHotKey($hk, 6, $CA, 72) | Out-Null                 # Ctrl+Alt+H → HTML Report
    Write-Log "Hotkeys registered: Ctrl+Alt+P/R/M/S/O" "INFO"
} catch {
    Write-Log "Hotkey registration failed (non-critical): $_" "WARNING"
}

# WndProc hook to catch WM_HOTKEY messages
$script:hotkeyFilter = {
    param($msg)
    if ($msg.Msg -eq 0x0312) {
        switch ($msg.WParam) {
            1 {  # Ctrl+Alt+P → Toggle HUD
                if ($hudForm.Visible) { Hide-HUD } else { Show-HUD }
            }
            2 {  # Ctrl+Alt+R → Reset Stats
                $script:totalPings    = 0; $script:lostPings = 0
                $script:minLat        = 9999; $script:maxLat  = 0
                $script:Last60sSpike  = 0; $script:currentJitter = 0
                $script:pingHistory.Clear(); $script:pingHistory5min.Clear()
                $script:pingHistory30min.Clear(); $script:pingHistory1h.Clear()
                $script:adaptiveWindow.Clear()
                Write-Log "Stats reset via hotkey Ctrl+Alt+R" "INFO"
                Notify-User "Stats reset (Ctrl+Alt+R)" -Ms 1500
            }
            3 {  # Ctrl+Alt+M → MTU Optimizer
                Show-MTUOptimizer
            }
            4 {  # Ctrl+Alt+S → Save Config
                Save-Config
                Notify-User "Settings saved (Ctrl+Alt+S)" -Ms 1500
            }
            5 {  # Ctrl+Alt+O → Toggle Overlay
                Toggle-Overlay
            }
            6 {  # Ctrl+Alt+H → HTML Report
                Export-HTMLReport
            }
        }
    }
}
$hudForm.Add_HandleCreated({ [System.Windows.Forms.Application]::AddMessageFilter([System.Windows.Forms.IMessageFilter]$script:hotkeyFilter) })
$trayIcon.Text = "NetNinja v$($CONFIG.Version)"

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# ── CUSTOM RENDERER: kein grauer Streifen, dezentes Hover-Highlighting ──
Add-Type -TypeDefinition @"
using System;
using System.Drawing;
using System.Windows.Forms;

public class NetNinjaMenuRenderer : ToolStripProfessionalRenderer {
    public NetNinjaMenuRenderer() : base(new NetNinjaColorTable()) {}

    // Kein Image-Margin Streifen links
    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }

    // Dezenter Hover: hellgrau, schwarze Schrift
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        var item = e.Item;
        var g    = e.Graphics;
        var rect = new Rectangle(Point.Empty, item.Size);

        if (!item.Enabled) {
            g.FillRectangle(new SolidBrush(Color.FromArgb(245, 245, 245)), rect);
        } else if (item.Selected) {
            g.FillRectangle(new SolidBrush(Color.FromArgb(225, 225, 225)), rect);
        } else {
            g.FillRectangle(new SolidBrush(Color.White), rect);
        }
    }

    // Separator dezenter
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        var g = e.Graphics;
        int y = e.Item.Height / 2;
        g.DrawLine(new Pen(Color.FromArgb(210, 210, 210)), 8, y, e.Item.Width - 8, y);
    }

    // Kein Rahmen um die ganze DropDown
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        var g    = e.Graphics;
        var rect = new Rectangle(Point.Empty, e.ToolStrip.Size);
        rect.Width  -= 1;
        rect.Height -= 1;
        g.DrawRectangle(new Pen(Color.FromArgb(190, 190, 190)), rect);
    }

    // Text immer schwarz (auch bei Hover)
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        e.TextColor = e.Item.Enabled ? Color.FromArgb(30, 30, 30) : Color.FromArgb(160, 160, 160);
        base.OnRenderItemText(e);
    }
}

public class NetNinjaColorTable : ProfessionalColorTable {
    public override Color MenuItemSelected         { get { return Color.FromArgb(225,225,225); } }
    public override Color MenuItemBorder           { get { return Color.FromArgb(225,225,225); } }
    public override Color MenuItemSelectedGradientBegin { get { return Color.FromArgb(225,225,225); } }
    public override Color MenuItemSelectedGradientEnd   { get { return Color.FromArgb(225,225,225); } }
    public override Color MenuBorder               { get { return Color.FromArgb(190,190,190); } }
    public override Color ToolStripDropDownBackground  { get { return Color.White; } }
    public override Color ImageMarginGradientBegin { get { return Color.White; } }
    public override Color ImageMarginGradientMiddle{ get { return Color.White; } }
    public override Color ImageMarginGradientEnd   { get { return Color.White; } }
}
"@ -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction SilentlyContinue

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$contextMenu.Renderer        = New-Object NetNinjaMenuRenderer
$contextMenu.ShowImageMargin = $false
$contextMenu.ShowCheckMargin = $false
$contextMenu.BackColor       = [System.Drawing.Color]::FromArgb(26, 26, 34)
$contextMenu.Font            = $script:Fonts.Small

# ── STATUS HEADER (disabled — display only) ─────────────────
$menuStatusPing = New-Object System.Windows.Forms.ToolStripMenuItem("📡  Ping: -- ms  |  Jitter: --  |  Loss: --%")
$menuStatusPing.Enabled = $false
$contextMenu.Items.Add($menuStatusPing) | Out-Null

$menuStatusProfile = New-Object System.Windows.Forms.ToolStripMenuItem("🎮  Profile: MMO Gaming")
$menuStatusProfile.Enabled = $false
$contextMenu.Items.Add($menuStatusProfile) | Out-Null


# ── HUD & ANZEIGE ─────────────────────────────────────
Add-MenuItem "-"
# PING MONITOR TOGGLE
$script:monitorEnabled = $true
$menuMonitor = $contextMenu.Items.Add("📺  HUD Monitor: ON")
$menuMonitor.Add_Click({
    $script:monitorEnabled = -not $script:monitorEnabled
    
    if ($script:monitorEnabled) {
        # Enable monitoring — reset pause state
        $script:hudPaused = $false
        if ($hudPauseBtn) {
            $hudPauseBtn.Text      = " ⏸ "
            $hudPauseBtn.ForeColor = [System.Drawing.Color]::FromArgb(90, 90, 115)
        }
        $pingTimer.Start()
        $menuMonitor.Text = "📺  HUD Monitor: ON"
        Show-HUD
        Write-Log "Ping monitoring enabled" "INFO"
        Notify-User "Ping Monitor enabled" -Ms 2000
    } else {
        # Disable monitoring
        $pingTimer.Stop()
        $menuMonitor.Text = "📺  HUD Monitor: OFF"
        $hudForm.Hide()
        Write-Log "Ping monitoring disabled" "INFO"
        Notify-User "Ping Monitor disabled (running in background)" -Ms 2000
    }
})
# OVERLAY MODE TOGGLE
$script:menuOverlay = $contextMenu.Items.Add("🎮  Overlay Mode: OFF              Ctrl+Alt+O")
$script:menuOverlay.Add_Click({ Toggle-Overlay })
Add-MenuItem "-"
$menuAlwaysOnTop = $contextMenu.Items.Add("📌  Always on Top: ON")
$menuAlwaysOnTop.Add_Click({
    $hudForm.TopMost = -not $hudForm.TopMost
    $menuAlwaysOnTop.Text = "📌  Always on Top: " + $(if ($hudForm.TopMost) {"ON"} else {"OFF"})
})
$null = $contextMenu.Items.Add("🔆  HUD Transparency...", $null, {
    $opF = New-Object System.Windows.Forms.Form
    $opF.Text = "HUD Transparency"
    $opF.Size = New-Object System.Drawing.Size(350, 180)
    $opF.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $opF.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $opF.MaximizeBox = $false
    
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Transparency: $([math]::Round($hudForm.Opacity * 100))%"
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(300, 20)
    $opF.Controls.Add($label)
    
    $slider = New-Object System.Windows.Forms.TrackBar
    $slider.Minimum = 30
    $slider.Maximum = 100
    $slider.Value = [int]($hudForm.Opacity * 100)
    $slider.TickFrequency = 10
    $slider.Location = New-Object System.Drawing.Point(20, 50)
    $slider.Size = New-Object System.Drawing.Size(300, 45)
    $slider.Add_ValueChanged({
        $hudForm.Opacity = $slider.Value / 100.0
        $label.Text = "Transparency: $($slider.Value)%"
    })
    $opF.Controls.Add($slider)
    
    $okBtn = New-Object System.Windows.Forms.Button
    $okBtn.Text = "OK"
    $okBtn.Location = New-Object System.Drawing.Point(120, 110)
    $okBtn.Size = New-Object System.Drawing.Size(100, 30)
    $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $opF.Controls.Add($okBtn)
    $opF.AcceptButton = $okBtn
    $opF.ShowDialog() | Out-Null
    $opF.Dispose()
})
$menuTheme = $contextMenu.Items.Add("🎨  Theme: Dark Mode")
$menuTheme.Add_Click({
    $script:darkMode = -not $script:darkMode
    Apply-Theme -Dark $script:darkMode
    $menuTheme.Text = if ($script:darkMode) { "🎨  Theme: Dark Mode" } else { "🎨  Theme: Light Mode" }
    Notify-User "Theme: $(if ($script:darkMode) { "Dark" } else { "Light" }) Mode" -Ms 1500
})

# ── PROFILE ───────────────────────────────────────────
Add-MenuItem "-"
# Config Profiles Submenu
$profilesMenu = New-Object System.Windows.Forms.ToolStripMenuItem("Profiles")

$script:menuMMO = New-Object System.Windows.Forms.ToolStripMenuItem("● MMO Gaming")
$script:menuMMO.Add_Click({ Switch-Profile "MMO" })
$profilesMenu.DropDownItems.Add($script:menuMMO) | Out-Null

$script:menuFPS = New-Object System.Windows.Forms.ToolStripMenuItem("○ Competitive")
$script:menuFPS.Add_Click({ Switch-Profile "FPS" })
$profilesMenu.DropDownItems.Add($script:menuFPS) | Out-Null

$script:menuAnalysis = New-Object System.Windows.Forms.ToolStripMenuItem("○ Analysis Mode")
$script:menuAnalysis.Add_Click({ Switch-Profile "Analysis" })
$profilesMenu.DropDownItems.Add($script:menuAnalysis) | Out-Null

$script:menuSilent = New-Object System.Windows.Forms.ToolStripMenuItem("○ Silent Background")
$script:menuSilent.Add_Click({ Switch-Profile "Silent" })
$profilesMenu.DropDownItems.Add($script:menuSilent) | Out-Null

$contextMenu.Items.Add($profilesMenu) | Out-Null

# Update profile menu markers
$script:UpdateProfileMenu = {
    $script:menuMMO.Text = if ($script:currentProfile -eq "MMO") { "● MMO Gaming" } else { "○ MMO Gaming" }
    $script:menuFPS.Text = if ($script:currentProfile -eq "FPS") { "● Competitive" } else { "○ Competitive" }
    $script:menuAnalysis.Text = if ($script:currentProfile -eq "Analysis") { "● Analysis Mode" } else { "○ Analysis Mode" }
    $script:menuSilent.Text = if ($script:currentProfile -eq "Silent") { "● Silent Background" } else { "○ Silent Background" }
}

& $script:UpdateProfileMenu

# ── OPTIMIERUNGEN ─────────────────────────────────────
Add-MenuItem "-"
Add-MenuItem "⚙️   Optimization Manager" { Show-OptimizationManager }
Add-MenuItem "📡  MTU Optimizer                    Ctrl+Alt+M" { Show-MTUOptimizer }
Add-MenuItem "🔔  Alert Settings...                Ctrl+Alt+A" { Show-AlertSettings }
Add-MenuItem "🌐  Network Adapter..." { Show-AdapterSelector }
# ADAPTIVE PING RATE TOGGLE
$menuAdaptive = $contextMenu.Items.Add("🔄  Adaptive Ping Rate: ON")
$menuAdaptive.Add_Click({
    $CONFIG.AdaptiveRate = -not $CONFIG.AdaptiveRate

    if ($CONFIG.AdaptiveRate) {
        $menuAdaptive.Text = "🔄  Adaptive Ping Rate: ON"
        $script:adaptiveWindow.Clear()
        $script:adaptiveState = "FAST"
        $script:currentPingInterval = $CONFIG.PingIntervalMin
        $pingTimer.Interval = $CONFIG.PingIntervalMin
        Write-Log "Adaptive rate enabled" "INFO"
        Notify-User "Adaptive Ping Rate AN — Interval: 1s→5s je Stabilität" -Ms 3000
    } else {
        $menuAdaptive.Text = "🔄  Adaptive Ping Rate: OFF"
        $script:currentPingInterval = $CONFIG.PingIntervalMin
        $pingTimer.Interval = $CONFIG.PingIntervalMin
        $script:adaptiveState = "FAST"
        Write-Log "Adaptive rate disabled — fixed 1s interval" "INFO"
        Notify-User "Adaptive Ping Rate AUS — fester 1s Takt" -Ms 2000
    }
})
# AUTO-START TOGGLE
$menuAutoStart = $contextMenu.Items.Add("🎯  Game Auto-Detect: ON")
$menuAutoStart.Add_Click({
    $script:processMonitorEnabled = -not $script:processMonitorEnabled
    
    if ($script:processMonitorEnabled) {
        $menuAutoStart.Text = "🎯  Game Auto-Detect: ON"
        $processMonitorTimer.Start()
        Write-Log "Auto-Start enabled" "INFO"
        Notify-User "Game Auto-Detect enabled" -Ms 2000
    } else {
        $menuAutoStart.Text = "🎯  Game Auto-Detect: OFF"
        $processMonitorTimer.Stop()
        Write-Log "Auto-Start disabled" "INFO"
        Notify-User "Game Auto-Detect disabled" -Ms 2000
    }
})

# ── NETZWERK-TOOLS ────────────────────────────────────
Add-MenuItem "-"
$menuDNS = $contextMenu.Items.Add("🌍  DNS Switcher")
$null = $menuDNS.DropDownItems.Add("Cloudflare (1.1.1.1)", $null, { Set-DNS "Cloudflare" })
$null = $menuDNS.DropDownItems.Add("Google (8.8.8.8)",     $null, { Set-DNS "Google" })
$null = $menuDNS.DropDownItems.Add("Reset to DHCP",        $null, { Set-DNS "Reset" })
Add-MenuItem "🔁  Restart Network Adapter" { Reset-NetworkAdapter }
$null = $contextMenu.Items.Add("🔍  Check Server IP & Port...", $null, {

    $checkForm = New-Object System.Windows.Forms.Form
    $checkForm.Text = "Check Server IP & Port"
    $checkForm.Size = New-Object System.Drawing.Size(520, 370)
    $checkForm.MinimumSize = New-Object System.Drawing.Size(520, 370)
    $checkForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $checkForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $checkForm.MaximizeBox = $false
    $checkForm.MinimizeBox = $false
    $checkForm.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 24)
    $checkForm.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 228)

    # Header Label
    $infoLabel = New-Object System.Windows.Forms.Label
    $infoLabel.Text = "Detect server IP and port from active game, or enter manually:"
    $infoLabel.Location = New-Object System.Drawing.Point(15, 15)
    $infoLabel.Size = New-Object System.Drawing.Size(475, 20)
    $infoLabel.Font      = $script:Fonts.Small
    $infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 165)
    $checkForm.Controls.Add($infoLabel)

    # AUTO-DETECT Button
    $autoBtn = New-Object System.Windows.Forms.Button
    $autoBtn.Text = "AUTO-DETECT"
    $autoBtn.Location = New-Object System.Drawing.Point(15, 45)
    $autoBtn.Size = New-Object System.Drawing.Size(475, 45)
    $autoBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
    $autoBtn.ForeColor = [System.Drawing.Color]::White
    $autoBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $autoBtn.FlatAppearance.BorderSize = 0
    $autoBtn.Font      = $script:Fonts.Title
    $autoBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $autoBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(20, 165, 230)

    $autoBtn.Add_Click({
        $autoBtn.Enabled = $false
        $autoBtn.Text = "Scanning connections..."
        $autoBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
        [System.Windows.Forms.Application]::DoEvents()

        try {
            # Find running game process
            $gameProc = $null
            $gameName = ""
            foreach ($procName in $script:gameProcesses) {
                $found = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($found) {
                    $gameProc = $found
                    $gameName = $procName
                    break
                }
            }

            if (-not $gameProc) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No supported game detected!`n`n" +
                    "MMORPGs:`n" +
                    "  Ragnarok, WoW, FF14, ESO`n" +
                    "  GW2, Lost Ark, Black Desert`n" +
                    "  TERA, Aion, Lineage2, MapleStory`n" +
                    "  RuneScape / OSRS`n`n" +
                    "Battle Royale:`n" +
                    "  PUBG, Fortnite, Naraka`n`n" +
                    "MOBA:`n" +
                    "  League of Legends, Dota 2, Smite`n`n" +
                    "FPS / Shooter:`n" +
                    "  CS:GO/CS2, Valorant, Apex, R6`n" +
                    "  CoD, Battlefield, Overwatch`n`n" +
                    "Survival / Co-op:`n" +
                    "  Rust, ARK, Escape from Tarkov`n`n" +
                    "Please start your game first!",
                    "No Game Running",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
                $autoBtn.Enabled = $true
                $autoBtn.Text = "AUTO-DETECT"
                $autoBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
                return
            }

            Write-Log "Auto-detect: Found $gameName (PID: $($gameProc.Id))" "INFO"

            # Use Get-NetTCPConnection (more reliable than netstat)
            $connections = @()

            try {
                $tcpConns = Get-NetTCPConnection -State Established -ErrorAction Stop |
                    Where-Object { $_.OwningProcess -eq $gameProc.Id }

                foreach ($conn in $tcpConns) {
                    $remoteIP = $conn.RemoteAddress
                    $remotePort = $conn.RemotePort

                    # Filter private/local IPs
                    if ($remoteIP -notmatch "^(127\.|::1|0\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)") {
                        $connections += [PSCustomObject]@{
                            RemoteIP   = $remoteIP
                            RemotePort = $remotePort
                        }
                    }
                }
            } catch {
                # Fallback to netstat if Get-NetTCPConnection fails
                Write-Log "Get-NetTCPConnection failed, using netstat fallback" "WARNING"
                $netstatOut = netstat -ano 2>$null
                foreach ($line in $netstatOut) {
                    if ($line -match "TCP\s+([\d\.]+):(\d+)\s+([\d\.]+):(\d+)\s+ESTABLISHED\s+(\d+)") {
                        if ($matches[5] -eq $gameProc.Id) {
                            $rIP = $matches[3]
                            $rPort = $matches[4]
                            if ($rIP -notmatch "^(127\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)") {
                                $connections += [PSCustomObject]@{
                                    RemoteIP   = $rIP
                                    RemotePort = [int]$rPort
                                }
                            }
                        }
                    }
                }
            }

            if ($connections.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Game found: $gameName`n" +
                    "PID: $($gameProc.Id)`n`n" +
                    "No server connection detected!`n`n" +
                    "Possible reasons:`n" +
                    "- Not logged into a server yet`n" +
                    "- Game uses only UDP traffic`n" +
                    "- Firewall blocking detection`n`n" +
                    "Try entering the IP manually.",
                    "No Connection Found",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                $autoBtn.Enabled = $true
                $autoBtn.Text = "AUTO-DETECT"
                $autoBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
                return
            }

            # Port ranges per game for smart selection
            $gamePortRanges = @{
                # ── Ragnarok Online ──────────────────────
                "Ragnarok"            = @(5000..6500)
                "Ragnarokplus"        = @(5000..6500)
                "RagnarokOnline"      = @(5000..6500)

                # ── World of Warcraft ────────────────────
                "Wow"                 = @(3724..3725)
                "WowClassic"          = @(3724..3725)
                "Wow-64"              = @(3724..3725)

                # ── Final Fantasy XIV ────────────────────
                "ffxiv_dx11"          = @(54992..55000)
                "ffxiv"               = @(54992..55000)

                # ── Elder Scrolls Online ─────────────────
                "eso64"               = @(24100..24131)
                "eso"                 = @(24100..24131)

                # ── Guild Wars 2 ─────────────────────────
                "GuildWars2"          = @(443, 6112)
                "Gw2-64"              = @(443, 6112)

                # ── TERA ─────────────────────────────────
                "TERA"                = @(10001..10002)

                # ── Aion / Lineage 2 (NCSoft ports) ──────
                "aion"                = @(2106, 7777)
                "aion64"              = @(2106, 7777)
                "lineage2"            = @(2106, 7777)
                "L2"                  = @(2106, 7777)

                # ── MapleStory ───────────────────────────
                "MapleStory"          = @(8484, 8585)
                "MapleStory2"         = @(11000..11999)

                # ── Lost Ark ─────────────────────────────
                "LostArk"             = @(6040..6044)

                # ── Black Desert Online ──────────────────
                "BlackDesertOnline"   = @(25000..25100)
                "BlackDesert"         = @(25000..25100)
                "bdo"                 = @(25000..25100)

                # ── RuneScape ────────────────────────────
                "rs2client"           = @(43594..43595)
                "osclient"            = @(43594..43595)
                "jagexlauncher"       = @(43594..43595)

                # ── PUBG ─────────────────────────────────
                "TslGame"             = @(7086, 27015..27030)
                "PUBG"                = @(7086, 27015..27030)

                # ── Fortnite ─────────────────────────────
                "FortniteClient-Win64-Shipping" = @(5222, 5795..5847)
                "Fortnite"            = @(5222, 5795..5847)

                # ── Naraka: Bladepoint ───────────────────
                "NarakaBladePoint"    = @(17500..17510)
                "NARAKA"              = @(17500..17510)

                # ── League of Legends ────────────────────
                "League of Legends"   = @(5000..5500)
                "LeagueofLegends"     = @(5000..5500)

                # ── Dota 2 ───────────────────────────────
                "dota2"               = @(27015..27030)

                # ── Smite ────────────────────────────────
                "smite"               = @(5222, 27015..27030)
                "SmiteGame"           = @(5222, 27015..27030)

                # ── CS:GO / CS2 ──────────────────────────
                "csgo"                = @(27000..28000)
                "cs2"                 = @(27000..28000)

                # ── Valorant ─────────────────────────────
                "VALORANT"            = @(8000..9000)
                "VALORANT-Win64-Shipping" = @(8000..9000)

                # ── Apex Legends ─────────────────────────
                "r5apex"              = @(37000..37015)

                # ── Rainbow Six Siege ────────────────────
                "RainbowSix"          = @(10000..10100)
                "RainbowSix_BE"       = @(10000..10100)

                # ── Overwatch ────────────────────────────
                "Overwatch"           = @(3724, 6113)

                # ── Call of Duty ─────────────────────────
                "BlackOpsColdWar"     = @(3074..3075)
                "ModernWarfare"       = @(3074..3075)
                "Warzone"             = @(3074..3075)
                "cod"                 = @(3074..3075)
                "iw8ship"             = @(3074..3075)
                "CoDMW"               = @(3074..3075)

                # ── Battlefield ──────────────────────────
                "bf1"                 = @(3544..3545)
                "bfv"                 = @(3544..3545)
                "Battlefield2042"     = @(3544..3545)
                "bf2042"              = @(3544..3545)
                "bf4"                 = @(3544..3545)
                "bfh"                 = @(3544..3545)

                # ── Rust ─────────────────────────────────
                "RustClient"          = @(28015..28016)
                "rust"                = @(28015..28016)

                # ── ARK: Survival ────────────────────────
                "ShooterGame"         = @(7777, 27015)
                "ArkAscended"         = @(7777, 27015)

                # ── Escape from Tarkov ───────────────────
                "EscapeFromTarkov"    = @(7000..8000)
                "EFT"                 = @(7000..8000)

                # ── New World ─────────────────────────────
                "NewWorld"            = @(7777, 443)
                "NewWorld_Shipping"   = @(7777, 443)

                # ── Star Wars: The Old Republic ───────────
                "swtor"               = @(12049, 12999)

                # ── Neverwinter ───────────────────────────
                "NW_game"             = @(20010..20014)

                # ── RIFT ──────────────────────────────────
                "RIFT"                = @(8005, 8006)

                # ── ArcheAge ─────────────────────────────
                "ArcheAge"            = @(1259, 1260)

                # ── Albion Online ─────────────────────────
                "AlbionOnline"        = @(5056)
                "Albion-Online"       = @(5056)

                # ── Path of Exile ─────────────────────────
                "PathOfExile"         = @(6112, 20481)
                "PathOfExile_x64"     = @(6112, 20481)
                "PathOfExile2"        = @(6112, 20481)

                # ── Elden Ring / Dark Souls III ───────────
                "eldenring"           = @(21000..21199)
                "DarkSoulsIII"        = @(21000..21199)

                # ── Throne and Liberty ───────────────────
                "THRONE"              = @(10000..10200)
                "ThroneLobby"         = @(10000..10200)

                # ── Phantasy Star Online 2 ───────────────
                "pso2"                = @(12000..12199)
                "pso2_bin"            = @(12000..12199)

                # ── Metin2 ───────────────────────────────
                "metin2client"        = @(13000..13050)
                "metin2"              = @(13000..13050)

                # ── Silkroad Online ───────────────────────
                "sro_client"          = @(15779, 15880)
                "sro"                 = @(15779, 15880)

                # ── Dungeon Fighter Online ────────────────
                "DnF"                 = @(10103, 10104)

                # ── Dragon Nest ───────────────────────────
                "DragonNest"          = @(10040..10050)

                # ── MU Online ─────────────────────────────
                "mu"                  = @(55901..55910)
                "MuOnline"            = @(55901..55910)

                # ── Cabal Online ──────────────────────────
                "CabalMain"           = @(38180, 38190)
                "cabal"               = @(38180, 38190)

                # ── Mabinogi ─────────────────────────────
                "Mabinogi"            = @(11000..11010)

                # ── Forsaken World ────────────────────────
                "ForsakenWorld"       = @(29000..29100)

                # ── Riders of Icarus ──────────────────────
                "RidersOfIcarus"      = @(27500..27600)

                # ── Wakfu ────────────────────────────────
                "Wakfu"               = @(5555, 443)

                # ── RF Online ────────────────────────────
                "rf_online"           = @(10100..10110)
                "RFOnline"            = @(10100..10110)
            }

            $bestConnection = $null

            # Try matching known port ranges first
            if ($gamePortRanges.ContainsKey($gameName)) {
                $portRange = $gamePortRanges[$gameName]
                $bestConnection = $connections | Where-Object {
                    $portRange -contains [int]$_.RemotePort
                } | Select-Object -First 1
            }

            # Fallback to first connection
            if (-not $bestConnection) {
                $bestConnection = $connections[0]
            }

            # Fill IP and Port into form
            $ipBox.Text   = $bestConnection.RemoteIP
            $portBox.Text = [string]$bestConnection.RemotePort

            # Test ping
            try {
                $pingResult = Test-Connection -ComputerName $bestConnection.RemoteIP -Count 2 -ErrorAction Stop
                $avgPing = [math]::Round(($pingResult | Measure-Object -Property ResponseTime -Average).Average, 0)

                $noteMulti = if ($connections.Count -gt 1) {
                    "`nNote: $($connections.Count) connections found - selected best match."
                } else { "" }

                [System.Windows.Forms.MessageBox]::Show(
                    "Server detected successfully!`n`n" +
                    "Game:    $gameName`n" +
                    "IP:      $($bestConnection.RemoteIP)`n" +
                    "Port:    $($bestConnection.RemotePort)`n" +
                    "Ping:    ${avgPing}ms`n" +
                    $noteMulti + "`n`n" +
                    "IP and Port have been filled in.`n" +
                    "Click 'Set & Test' or 'MTU Check'.",
                    "Detection Successful",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )

                Write-Log "Auto-detect success: $($bestConnection.RemoteIP)`:$($bestConnection.RemotePort) (${avgPing}ms)" "INFO"

            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Server found but ping failed.`n`n" +
                    "IP:   $($bestConnection.RemoteIP)`n" +
                    "Port: $($bestConnection.RemotePort)`n`n" +
                    "Server may block ICMP ping.`n" +
                    "IP filled in - try 'Set & Test'.",
                    "Detection Complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }

        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Auto-detection failed!`n`nError: $_`n`nPlease enter IP manually.",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            Write-Log "Auto-detect error: $_" "ERROR"
        }

        $autoBtn.Enabled = $true
        $autoBtn.Text = "AUTO-DETECT"
        $autoBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
    })
    $checkForm.Controls.Add($autoBtn)

    # Separator label
    $sepLabel = New-Object System.Windows.Forms.Label
    $sepLabel.Text = "──────────────── Or enter manually ────────────────"
    $sepLabel.Location = New-Object System.Drawing.Point(15, 103)
    $sepLabel.Size = New-Object System.Drawing.Size(475, 18)
    $sepLabel.Font = $script:Fonts.Italic
    $sepLabel.ForeColor = [System.Drawing.Color]::Gray
    $sepLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $checkForm.Controls.Add($sepLabel)

    # IP Row
    $ipLabel = New-Object System.Windows.Forms.Label
    $ipLabel.Text = "Server IP:"
    $ipLabel.Location = New-Object System.Drawing.Point(15, 132)
    $ipLabel.Size = New-Object System.Drawing.Size(80, 26)
    $ipLabel.Font = $script:Fonts.Body
    $ipLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $checkForm.Controls.Add($ipLabel)

    $ipBox = New-Object System.Windows.Forms.TextBox
    $ipBox.Location = New-Object System.Drawing.Point(100, 132)
    $ipBox.Size = New-Object System.Drawing.Size(390, 26)
    $ipBox.Text = $CONFIG.ServerAddress
    $ipBox.Font = $script:Fonts.Mono
    $ipBox.TabIndex = 1
    $ipBox.BackColor = $script:C.BgInput
    $ipBox.ForeColor = $script:C.TextPrimary
    $checkForm.Controls.Add($ipBox)

    # Port Row
    $portLabel = New-Object System.Windows.Forms.Label
    $portLabel.Text = "Port:"
    $portLabel.Location = New-Object System.Drawing.Point(15, 170)
    $portLabel.Size = New-Object System.Drawing.Size(80, 26)
    $portLabel.Font = $script:Fonts.Body
    $portLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $checkForm.Controls.Add($portLabel)

    $portBox = New-Object System.Windows.Forms.TextBox
    $portBox.Location = New-Object System.Drawing.Point(100, 170)
    $portBox.Size = New-Object System.Drawing.Size(120, 26)
    $portBox.Text = [string]$CONFIG.ServerPort
    $portBox.Font = $script:Fonts.Mono
    $portBox.TabIndex = 2
    $portBox.BackColor = $script:C.BgInput
    $portBox.ForeColor = $script:C.TextPrimary
    $checkForm.Controls.Add($portBox)

    # Separator line
    $line = New-Object System.Windows.Forms.Label
    $line.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
    $line.Location = New-Object System.Drawing.Point(15, 210)
    $line.Size = New-Object System.Drawing.Size(475, 2)
    $checkForm.Controls.Add($line)

    # Bottom Buttons - evenly spaced
    $setBtn = New-Object System.Windows.Forms.Button
    $setBtn.Text = "Set & Test"
    $setBtn.Location = New-Object System.Drawing.Point(15, 222)
    $setBtn.Size = New-Object System.Drawing.Size(148, 38)
    $setBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 150, 215)
    $setBtn.ForeColor = [System.Drawing.Color]::White
    $setBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $setBtn.FlatAppearance.BorderSize = 0
    $setBtn.Font = $script:Fonts.Header

    $setBtn.Add_Click({
        $newIP   = $ipBox.Text.Trim()
        $newPort = 0
        [int]::TryParse($portBox.Text.Trim(), [ref]$newPort) | Out-Null

        if ([string]::IsNullOrEmpty($newIP)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a server IP address.", "Missing IP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        try {
            $testResult = Test-Connection -ComputerName $newIP -Count 2 -ErrorAction Stop
            $avgPing = [math]::Round(($testResult | Measure-Object -Property ResponseTime -Average).Average, 0)

            $CONFIG.ServerAddress  = $newIP
            $CONFIG.ServerPort     = $newPort
            $script:TargetIP       = $newIP

            Write-Log "Server updated: $newIP`:$newPort (${avgPing}ms)" "INFO"

            [System.Windows.Forms.MessageBox]::Show(
                "Server updated!`n`nIP: $newIP`nPort: $newPort`nPing: ${avgPing}ms`n`nMonitoring now uses this server.",
                "Success",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            $checkForm.Close()

        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Cannot reach server!`n`nIP: $newIP`nError: $_`n`nCheck the IP address.",
                "Connection Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    })
    $checkForm.Controls.Add($setBtn)

    $mtuBtn = New-Object System.Windows.Forms.Button
    $mtuBtn.Text = "MTU Check"
    $mtuBtn.Location = New-Object System.Drawing.Point(173, 222)
    $mtuBtn.Size = New-Object System.Drawing.Size(148, 38)
    $mtuBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 180, 100)
    $mtuBtn.ForeColor = [System.Drawing.Color]::White
    $mtuBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $mtuBtn.FlatAppearance.BorderSize = 0
    $mtuBtn.Font = $script:Fonts.Header

    $mtuBtn.Add_Click({
        $newIP = $ipBox.Text.Trim()
        if ([string]::IsNullOrEmpty($newIP)) {
            [System.Windows.Forms.MessageBox]::Show("Please enter or detect a server IP first.", "Missing IP", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        $script:TargetIP      = $newIP
        $CONFIG.ServerAddress = $newIP
        $checkForm.Close()
        Show-MTUOptimizer
    })
    $checkForm.Controls.Add($mtuBtn)

    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Cancel"
    $cancelBtn.Location = New-Object System.Drawing.Point(331, 222)
    $cancelBtn.Size = New-Object System.Drawing.Size(159, 38)
    $cancelBtn.BackColor = [System.Drawing.Color]::FromArgb(55, 58, 70)
    $cancelBtn.ForeColor = [System.Drawing.Color]::FromArgb(185, 185, 200)
    $cancelBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cancelBtn.FlatAppearance.BorderSize = 0
    $cancelBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(68, 72, 88)
    $cancelBtn.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $cancelBtn.Font      = $script:Fonts.Body
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $checkForm.Controls.Add($cancelBtn)
    $checkForm.CancelButton = $cancelBtn

    $checkForm.AcceptButton = $setBtn
    $checkForm.BackColor    = $script:C.BgPrimary
    $checkForm.ForeColor    = $script:C.TextPrimary
    $checkForm.ShowDialog() | Out-Null
    $checkForm.Dispose()
})
Add-MenuItem "🗺️   Traceroute" { Show-TracerouteGUI }
Add-MenuItem "📊  A/B Benchmark" { Show-BenchmarkABGUI }
Add-MenuItem "🧹  Clear RAM" { Optimize-RAM }

# ── STATISTIK ─────────────────────────────────────────
Add-MenuItem "-"
Add-MenuItem "📈  Statistics Dashboard..." { Show-StatsDashboard }
Add-MenuItem "🕐  Session History..." { Show-SessionHistory }
Add-MenuItem "🌡  Ping Heatmap..."    { Show-Heatmap }
Add-MenuItem "📄  Export HTML Report" { Export-HTMLReport }
Add-MenuItem "📶  ISP Speed Test..."  { Show-SpeedTest }
Add-MenuItem "-"
# ── v5.0 ─────────────────────────────────────────────────
$menuWebDash = $contextMenu.Items.Add("🌐  Live Dashboard (localhost:$($script:webDashPort)): OFF")
$menuWebDash.ForeColor = [System.Drawing.Color]::FromArgb(0, 200, 100)
$menuWebDash.Add_Click({
    if ($script:webDashEnabled) {
        Stop-WebDashboard
        $menuWebDash.Text = "🌐  Live Dashboard (localhost:$($script:webDashPort)): OFF"
    } else {
        Start-WebDashboard
        $menuWebDash.Text = "🌐  Live Dashboard (localhost:$($script:webDashPort)): ON"
        Start-Process "http://localhost:$($script:webDashPort)/"
    }
})
Add-MenuItem "🎯  Multi-Target Ping..."     { Show-MultiTargetManager }
Add-MenuItem "🔬  Auto-Diagnose..."         { Show-DiagnosisReport }
Add-MenuItem "⚙  Rules Engine..."          { Show-RulesEngine }
Add-MenuItem "⚡  Server Failover..."       { Show-FailoverSettings }
Add-MenuItem "-"
# ── v5.0 Tools ───────────────────────────────────────────────
Add-MenuItem "🌍  Server Location (GeoIP)..."  { Show-GeoIPInfo }
Add-MenuItem "📋  Log Viewer..."               { Show-LogViewer }
Add-MenuItem "⚙  Config Editor..."            { Show-ConfigEditor }
Add-MenuItem "📷  Save Graph as PNG"           { Export-GraphPNG }
$null = $contextMenu.Items.Add("🪟  Mini-HUD", $null, { Toggle-MiniHUD })
Add-MenuItem "🔗  Webhook Alerts..."           { Show-WebhookSettings }
Add-MenuItem "⌨  Keyboard Shortcuts"          { Show-ShortcutMap }
Add-MenuItem "🧙  Setup Wizard..."             { Show-OnboardingWizard }
$null = $contextMenu.Items.Add("📋  Copy Stats to Clipboard", $null, {
    try {
        $lossP = if ($script:totalPings -gt 0) {
            [math]::Round(($script:lostPings / $script:totalPings) * 100, 1)
        } else { 0 }
        $stats = @"
NETNINJA STATS - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================
Server: $script:TargetIP
Current Ping: $script:currentLatency ms
Average Loss: $lossP%
Min Ping: $script:minLat ms
Max Ping: $script:maxLat ms
Max Spike (60s): $script:Last60sSpike ms
Total Pings: $script:totalPings
Packets Lost: $script:lostPings
================================================
"@
        Set-Clipboard -Value $stats
        Notify-User "Stats copied to clipboard!" -Ms 2000
        Write-Log "Stats copied to clipboard" "INFO"
    } catch {
        Write-Log "Clipboard export error: $_" "ERROR"
    }
})

# ── EINSTELLUNGEN ─────────────────────────────────────
Add-MenuItem "-"
$menuAudio = $contextMenu.Items.Add("🔊  Audio Alerts: OFF")
$menuAudio.Add_Click({
    $script:AudioAlertEnabled = -not $script:AudioAlertEnabled
    $menuAudio.Text = if ($script:AudioAlertEnabled) { "🔊  Audio Alerts: ON" } else { "🔊  Audio Alerts: OFF" }
})
$null = $contextMenu.Items.Add("🔔  Alert & Sound Settings...", $null, { Show-AlertSettings })
$null = $contextMenu.Items.Add("🟣  Discord Rich Presence...",  $null, { Show-DiscordSettings })
$menuAutoProfile = $contextMenu.Items.Add("🎮  Auto-Profile: ON")
$menuAutoProfile.Add_Click({
    $script:autoProfileEnabled = -not $script:autoProfileEnabled
    $menuAutoProfile.Text = "🎮  Auto-Profile: " + $(if ($script:autoProfileEnabled) {"ON"} else {"OFF"})
    Write-Log "Auto-profile detection toggled: $($script:autoProfileEnabled)" "INFO"
    Notify-User "Auto-Profile $( if ($script:autoProfileEnabled) {'enabled'} else {'disabled'} )" -Ms 2000
})
# LAUNCH ON WINDOWS STARTUP
$script:startupEnabled = $false
$startupPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$startupName = "NetNinja"
try {
    $startupValue = Get-ItemProperty -Path $startupPath -Name $startupName -ErrorAction SilentlyContinue
    $script:startupEnabled = ($null -ne $startupValue)
} catch { $script:startupEnabled = $false }

$menuStartup = $contextMenu.Items.Add("🚀  Launch on Windows Startup: " + $(if ($script:startupEnabled) {"ON"} else {"OFF"}))
$menuStartup.Add_Click({
    try {
        $scriptFullPath = $PSCommandPath
        if (-not $scriptFullPath) { $scriptFullPath = $MyInvocation.ScriptName }
        
        if ($script:startupEnabled) {
            Remove-ItemProperty -Path $startupPath -Name $startupName -ErrorAction SilentlyContinue
            $script:startupEnabled = $false
            $menuStartup.Text = "🚀  Launch on Windows Startup: OFF"
            Notify-User "Removed from Windows Startup" -Ms 2000
            Write-Log "Removed from Windows Startup" "INFO"
        } else {
            $command = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptFullPath`""
            Set-ItemProperty -Path $startupPath -Name $startupName -Value $command
            $script:startupEnabled = $true
            $menuStartup.Text = "🚀  Launch on Windows Startup: ON"
            Notify-User "Added to Windows Startup" -Ms 2000
            Write-Log "Added to Windows Startup" "INFO"
        }
    } catch {
        Write-Log "Startup toggle error: $_" "ERROR"
        [System.Windows.Forms.MessageBox]::Show("Failed to toggle startup: $_", "Error", "OK", "Error")
    }
})
$null = $contextMenu.Items.Add("💾  Save Settings                  Ctrl+Alt+S", $null, {
    Save-Config
    Notify-User "Settings saved!" -Ms 1500
})
$null = $contextMenu.Items.Add("🔄  Restore Backups", $null, { 
    Restore-RegistryBackup
    Restore-NetworkSettings
})

Add-MenuItem "-"
$null = $contextMenu.Items.Add("❌  Exit and Reset", $null, {
    try {
        $msg = "This will:`n- Stop monitoring`n- Reset optimizations`n- Clean up resources`n`nContinue?"
        $result = [System.Windows.Forms.MessageBox]::Show(
            $msg, "Confirm Exit",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) { Cleanup-AndExit }
    } catch {
        Write-Log "Exit menu error: $_" "ERROR"
        [System.Environment]::Exit(1)
    }
})

$trayIcon.ContextMenuStrip = $contextMenu

# ============================================
# PROCESS MONITOR - AUTO START ON GAME LAUNCH
# ============================================

$script:gameProcesses = @(
    # ── Ragnarok Online ──────────────────────────
    "Ragnarokplus",
    "RagnarokOnline",
    "Ragnarok",

    # ── MMORPGs ──────────────────────────────────
    "Wow",                          # World of Warcraft (Retail)
    "WowClassic",                   # WoW Classic / Era
    "Wow-64",                       # WoW 64-bit
    "ffxiv_dx11",                   # Final Fantasy XIV (DX11)
    "ffxiv",                        # Final Fantasy XIV (DX9)
    "eso64",                        # Elder Scrolls Online (64-bit)
    "eso",                          # Elder Scrolls Online (32-bit)
    "GuildWars2",                   # Guild Wars 2
    "Gw2-64",                       # Guild Wars 2 (64-bit)
    "TERA",                         # TERA Online
    "tera",                         # TERA Online (alternative)
    "aion",                         # Aion
    "aion64",                       # Aion (64-bit)
    "lineage2",                     # Lineage 2
    "L2",                           # Lineage 2 (alternative)
    "MapleStory",                   # MapleStory
    "MapleStory2",                  # MapleStory 2
    "LostArk",                      # Lost Ark
    "LOSTARK",                      # Lost Ark (alternative)
    "BlackDesertOnline",            # Black Desert Online
    "BlackDesert",                  # Black Desert Online (alternative)
    "bdo",                          # Black Desert Online (short)
    "rs2client",                    # RuneScape (NXT Client)
    "osclient",                     # Old School RuneScape (official)
    "jagexlauncher",                # RuneScape Launcher

    # ── Battle Royale ─────────────────────────────
    "TslGame",                      # PUBG: Battlegrounds
    "PUBG",                         # PUBG (alternative)
    "FortniteClient-Win64-Shipping", # Fortnite
    "Fortnite",                     # Fortnite (alternative)
    "NarakaBladePoint",             # Naraka: Bladepoint
    "NARAKA",                       # Naraka (alternative)

    # ── MOBA ─────────────────────────────────────
    "League of Legends",            # League of Legends
    "LeagueofLegends",              # LoL (no spaces)
    "dota2",                        # Dota 2
    "smite",                        # Smite
    "SmiteGame",                    # Smite (UE version)

    # ── Competitive ─────────────────────────────
    "csgo",                         # Counter-Strike: Global Offensive
    "cs2",                          # Counter-Strike 2
    "VALORANT",                     # Valorant
    "VALORANT-Win64-Shipping",      # Valorant (Shipping build)
    "r5apex",                       # Apex Legends
    "RainbowSix",                   # Rainbow Six Siege
    "RainbowSix_BE",                # Rainbow Six Siege (BattleEye)
    "Overwatch",                    # Overwatch 1 & 2

    # ── Call of Duty ─────────────────────────────
    "BlackOpsColdWar",              # CoD: Black Ops Cold War
    "ModernWarfare",                # CoD: Modern Warfare
    "Warzone",                      # CoD: Warzone / Warzone 2.0
    "cod",                          # CoD (generic)
    "iw8ship",                      # CoD: MW 2019 (Shipping)
    "CoDMW",                        # CoD: Modern Warfare (alt)

    # ── Battlefield ──────────────────────────────
    "bf1",                          # Battlefield 1
    "bfv",                          # Battlefield V
    "Battlefield2042",              # Battlefield 2042
    "bf2042",                       # Battlefield 2042 (alternative)
    "bf4",                          # Battlefield 4
    "bfh",                          # Battlefield Hardline

    # ── Survival / Co-op ─────────────────────────
    "RustClient",                   # Rust
    "rust",                         # Rust (alternative)
    "ShooterGame",                  # ARK: Survival Evolved / Ascended
    "ArkAscended",                  # ARK: Survival Ascended
    "EscapeFromTarkov",             # Escape from Tarkov
    "EFT",                          # Escape from Tarkov (short)

    # ── Western MMORPGs ──────────────────────────
    "NewWorld",                     # New World (Amazon Games)
    "NewWorld_Shipping",            # New World (Shipping build)
    "swtor",                        # Star Wars: The Old Republic
    "NW_game",                      # Neverwinter
    "RIFT",                         # RIFT (Trion Worlds)
    "rift",                         # RIFT (alternative)
    "ArcheAge",                     # ArcheAge / ArcheAge Unchained
    "archeage",                     # ArcheAge (alternative)
    "AlbionOnline",                 # Albion Online
    "Albion-Online",                # Albion Online (alternative)

    # ── Action RPG / Soulslike (Online) ──────────
    "PathOfExile",                  # Path of Exile
    "PathOfExile_x64",              # Path of Exile (64-bit)
    "PathOfExile2",                 # Path of Exile 2
    "eldenring",                    # Elden Ring (online / invasions)
    "DarkSoulsIII",                 # Dark Souls III (PvP)

    # ── Korean / Asian MMORPGs ────────────────────
    "THRONE",                       # Throne and Liberty (NCSoft)
    "ThroneLobby",                  # Throne and Liberty Launcher
    "pso2",                         # Phantasy Star Online 2
    "pso2_bin",                     # PSO2: New Genesis (64-bit)
    "metin2client",                 # Metin2
    "metin2",                       # Metin2 (alternative)
    "sro_client",                   # Silkroad Online
    "sro",                          # Silkroad Online (short)
    "DnF",                          # Dungeon Fighter Online
    "DNF",                          # DFO (alternative)
    "DragonNest",                   # Dragon Nest
    "dragonnest",                   # Dragon Nest (alternative)
    "mu",                           # MU Online
    "MuOnline",                     # MU Online (alternative)
    "main",                         # MU Online / Cabal (generic client)
    "CabalMain",                    # Cabal Online
    "cabal",                        # Cabal Online (alternative)
    "Mabinogi",                     # Mabinogi (Nexon)
    "Client",                       # Mabinogi / Fiesta (generic)
    "ForsakenWorld",                # Forsaken World (Perfect World)
    "RidersOfIcarus",               # Riders of Icarus (Nexon)
    "Wakfu",                        # Wakfu (Ankama)
    "wakfu",                        # Wakfu (alternative)
    "rf_online",                    # RF Online (CCR)
    "RFOnline"                      # RF Online (alternative)
)

$script:processMonitorEnabled = $true
$script:gameDetected = $false

$processMonitorTimer = New-Object System.Windows.Forms.Timer
$processMonitorTimer.Interval = 3000  # Check every 3 seconds

$processMonitorTimer.Add_Tick({
    if (-not $script:processMonitorEnabled) { return }
    
    foreach ($procName in $script:gameProcesses) {
        $proc = Get-Process -Name $procName -ErrorAction SilentlyContinue
        
        if ($proc -and -not $script:gameDetected) {
            # Game detected!
            $script:gameDetected = $true
            Write-Log "Game detected: $procName" "INFO"

            # ── AUTO-PROFIL-ERKENNUNG ─────────────────────────────
            if ($script:autoProfileEnabled -and $script:gameProfileMap.ContainsKey($procName)) {
                $targetProfile = $script:gameProfileMap[$procName]
                if ($targetProfile -ne $script:currentProfile -and $targetProfile -ne $script:lastAutoProfile) {
                    $script:lastAutoProfile = $targetProfile
                    Write-Log "Auto-profile: $procName → $targetProfile" "INFO"
                    Switch-Profile -ProfileName $targetProfile
                    $trayIcon.ShowBalloonTip(3000,
                        "🎮 Auto-Profile: $targetProfile",
                        "$procName erkannt`nProfil automatisch gewechselt → $targetProfile",
                        [System.Windows.Forms.ToolTipIcon]::Info)
                }
            }
            # ─────────────────────────────────────────────────────

            # Auto-start monitoring if not already running
            if (-not $script:monitorEnabled) {
                $script:monitorEnabled = $true
                $pingTimer.Start()
                $menuMonitor.Text = "📺  HUD Monitor: ON"
                $hudForm.Show()
                $hudForm.BringToFront()
                
                $trayIcon.ShowBalloonTip(
                    4000,
                    "🎮 Game Detected!",
                    "$procName started`nPing Monitor auto-enabled",
                    [System.Windows.Forms.ToolTipIcon]::Info
                )
                
                Write-Log "Auto-started monitoring for $procName" "INFO"
            }
            
            break
        }
    }
    
    # Check if game closed
    if ($script:gameDetected) {
        $anyGameRunning = $false
        foreach ($procName in $script:gameProcesses) {
            if (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
                $anyGameRunning = $true
                break
            }
        }
        
        if (-not $anyGameRunning) {
            $script:gameDetected    = $false
            $script:lastAutoProfile = ""   # Reset → nächstes Spiel kann erneut auto-switchen
            Write-Log "Game closed - Process monitor reset" "INFO"
        }
    }
})

$processMonitorTimer.Start()
Write-Log "Process monitor started (checking every 3s)" "INFO"

# ============================================
# PING TIMER
# ============================================

$pingTimer = New-Object System.Windows.Forms.Timer
$pingTimer.Interval = $CONFIG.PingIntervalMin

$pingTimer.Add_Tick({
    try {
        $gameProc = Get-Process -Name $CONFIG.ProcessName -EA SilentlyContinue
        
        if (-not $gameProc) {
            $hudLabel.Text = "Waiting..."
            if ($hudSubStats) { $hudSubStats.Text = "$($CONFIG.ProcessName) not running" }
            $hudLabel.ForeColor = $script:DarkGray
            $script:IsIPDetected = $false
            # Tray-Icon: grau "---" (kein Game)
            if ($script:lastIconText -ne "---") {
                $wColor = [System.Drawing.Color]::FromArgb(70, 72, 90)
                $wIcon  = Create-IconWithText -text "---" -color $wColor -mode "waiting"
                if ($wIcon) {
                    $oldI = $trayIcon.Icon
                    $trayIcon.Icon = $wIcon
                    if ($oldI -and -not $script:iconCache.ContainsValue($oldI)) {
                        try { [Win32.IconHelper]::DestroyIcon($oldI.Handle) | Out-Null; $oldI.Dispose() } catch { $null = $_ }
                    }
                }
                $script:lastIconText = "---"
                $trayIcon.Text = "NetNinja — Waiting for $($CONFIG.ProcessName)..."
            }
            return
        }
        
        if (-not $script:IsIPDetected) {
            $hudLabel.Text = "Detecting..."
            if ($hudSubStats) { $hudSubStats.Text = "Scanning network connections" }
            $hudLabel.ForeColor = [System.Drawing.Color]::Yellow
            # Tray-Icon: blau "IP?" (Server wird gesucht)
            if ($script:lastIconText -ne "IP?") {
                $dColor = [System.Drawing.Color]::FromArgb(0, 130, 210)
                $dIcon  = Create-IconWithText -text "IP?" -color $dColor -mode "detecting"
                if ($dIcon) {
                    $oldI2 = $trayIcon.Icon
                    $trayIcon.Icon = $dIcon
                    if ($oldI2 -and -not $script:iconCache.ContainsValue($oldI2)) {
                        try { [Win32.IconHelper]::DestroyIcon($oldI2.Handle) | Out-Null; $oldI2.Dispose() } catch { $null = $_ }
                    }
                }
                $script:lastIconText = "IP?"
                $trayIcon.Text = "NetNinja — Detecting server IP..."
            }
            Get-GameServerIP | Out-Null
            return
        }
        
        if ($script:SpikeTimer.Elapsed.TotalSeconds -gt 60) {
            $script:Last60sSpike = 0
            $script:SpikeTimer.Restart()
        }
        
        $script:totalPings++
        
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = New-Object System.Net.Sockets.TcpClient
        
        try {
            $ar = $tcp.BeginConnect($script:TargetIP, $script:activeServerPort, $null, $null)
            
            if ($ar.AsyncWaitHandle.WaitOne(1000, $false)) {
                $tcp.EndConnect($ar)
                $sw.Stop()
                $lat = [int]$sw.ElapsedMilliseconds
                
                if ($lat -lt $script:minLat) { $script:minLat = $lat }
                if ($lat -gt $script:maxLat) { $script:maxLat = $lat }
                if ($lat -gt $script:Last60sSpike) { $script:Last60sSpike = $lat }
                
                # QUICK WIN: Store current latency
                $script:currentLatency = $lat
                try { Invoke-FailoverCheck -isLoss $false } catch { $null = $_ }
                # ── HEATMAP: Bucket für Tag/Stunde befüllen ────────────
                $now  = Get-Date
                $hDay = [int]$now.DayOfWeek   # 0=So .. 6=Sa → wir nutzen 0=Mo
                $hDay = ($hDay + 6) % 7       # 0=Mo, 6=So
                $hHour= $now.Hour
                $script:heatmapData[$hDay][$hHour].Sum   += $lat
                $script:heatmapData[$hDay][$hHour].Count += 1
                # Alle 60 Pings auf Disk speichern
                if ($script:graphUpdateCounter % 60 -eq 0) {
                    try {
                        $obj = @{}
                        for ($dd = 0; $dd -le 6; $dd++) {
                            $obj["d$dd"] = @{}
                            for ($hh = 0; $hh -le 23; $hh++) {
                                $obj["d$dd"]["h$hh"] = @{
                                    Sum   = $script:heatmapData[$dd][$hh].Sum
                                    Count = $script:heatmapData[$dd][$hh].Count
                                }
                            }
                        }
                        $obj | ConvertTo-Json -Depth 4 | Out-File $script:heatmapFile -Encoding UTF8 -Force
                    } catch { $null = $_ }
                }
                # ─────────────────────────────────────────────────────
                
                # ── SOUND-PROFIL + WEBHOOK ALERTS ───────────────────────
                if ($lat -gt $CONFIG.AlertCriticalPing) {
                    if ($script:soundProfile.NotifyCritical) { Play-AlertSound -Level "critical" }
                    if ($script:webhookConfig.OnCritical) {
                        Send-WebhookAlert -Level "critical" -Message "Critical ping: ${lat}ms | Jitter: ${jitterMs}ms | Profile: $script:currentProfile"
                    }
                } elseif ($lat -gt $CONFIG.AlertHighPing) {
                    if ($script:soundProfile.NotifyHigh) { Play-AlertSound -Level "high" }
                    if ($script:webhookConfig.OnHigh) {
                        Send-WebhookAlert -Level "high" -Message "High ping: ${lat}ms | Jitter: ${jitterMs}ms | Server: $script:TargetIP"
                    }
                }
                
                # Track spikes for statistics
                if ($lat -gt $CONFIG.SpikeThreshold) {
                    $script:totalSpikes++
                    if ($lat -gt $script:worstSpikeValue) {
                        $script:worstSpikeValue = $lat
                        $script:worstSpikeTime = Get-Date
                    }
                    Add-TimelineEvent -Type "spike" -Msg "Spike ${lat}ms (threshold: $($CONFIG.SpikeThreshold)ms)"
                }
                
                # DESKTOP NOTIFICATIONS for critical events
                $timeSinceLastNotification = ((Get-Date) - $script:lastNotificationTime).TotalSeconds
                if ($timeSinceLastNotification -gt $script:notificationCooldown) {
                    # Critical Ping Notification
                    if ($lat -gt $CONFIG.AlertCriticalPing) {
                        $trayIcon.ShowBalloonTip(
                            5000,
                            "CRITICAL PING!",
                            "Current ping: $lat ms`nThis is extremely high!",
                            [System.Windows.Forms.ToolTipIcon]::Error
                        )
                        $script:lastNotificationTime = Get-Date
                        Write-Log "Critical ping notification shown: $lat ms" "WARNING"
                    }
                    # High Ping Notification  
                    elseif ($lat -gt $CONFIG.AlertHighPing) {
                        $trayIcon.ShowBalloonTip(
                            4000,
                            "High Ping Detected",
                            "Current ping: $lat ms`nConnection degraded",
                            [System.Windows.Forms.ToolTipIcon]::Warning
                        )
                        $script:lastNotificationTime = Get-Date
                        Write-Log "High ping notification shown: $lat ms" "WARNING"
                    }
                }
                
                # ADVANCED NOTIFICATION: Connection Restored
                if ($script:lastConnectionState -eq $false -and $lat -lt 150) {
                    if ($script:connectionDownTime) {
                        $downDuration = (Get-Date) - $script:connectionDownTime
                        $trayIcon.ShowBalloonTip(
                            4000,
                            "🟢 Connection Restored",
                            "Ping back to normal: ${lat}ms`nDowntime: $([math]::Floor($downDuration.TotalMinutes))m $($downDuration.Seconds)s",
                            [System.Windows.Forms.ToolTipIcon]::Info
                        )
                        $dtm = "$([math]::Floor($downDuration.TotalMinutes))m $($downDuration.Seconds)s"
                        Add-TimelineEvent -Type "restore" -Msg "Connection restored — downtime ${dtm}"
                        Write-Log "Connection restored after $([math]::Floor($downDuration.TotalMinutes))m $($downDuration.Seconds)s" "INFO"
                        $script:connectionDownTime = $null
                    }
                    $script:lastConnectionState = $true
                }
                
                # Track connection degradation
                if ($lat -gt 200) {
                    if ($script:lastConnectionState -eq $true) {
                        $script:connectionDownTime = Get-Date
                        $script:lastConnectionState = $false
                    }
                }
                
                # Add to extended history buffers
                $script:graphUpdateCounter++
                
                # Add to 60s history (always)
                if ($script:pingHistory.Count -ge $script:maxHistorySize) {
                    $script:pingHistory.Dequeue() | Out-Null
                }
                $script:pingHistory.Enqueue($lat)
                # Loss-Marker: false = kein Loss bei diesem Ping
                if ($script:lossHistory60s.Count -ge $script:maxHistorySize) { $script:lossHistory60s.RemoveAt(0) }
                $script:lossHistory60s.Add($false)
                
                # Add to 5min history (every ping)
                $script:pingHistory5min.Add($lat)
                $script:lossHistory5min.Add($false)
                if ($script:lossHistory5min.Count -gt 300) { $script:lossHistory5min.RemoveAt(0) }
                if ($script:pingHistory5min.Count -gt 300) {
                    $script:pingHistory5min.RemoveAt(0)
                }
                
                # Add to 30min history (every 6th ping = ~6 seconds)
                if ($script:graphUpdateCounter % 6 -eq 0) {
                    $script:pingHistory30min.Add($lat)
                    if ($script:pingHistory30min.Count -gt 300) { $script:pingHistory30min.RemoveAt(0) }
                    $script:lossHistory30min.Add($false)
                    if ($script:lossHistory30min.Count -gt 300) { $script:lossHistory30min.RemoveAt(0) }
                }
                
                # Add to 1h history (every 36th ping = ~36 seconds)
                if ($script:graphUpdateCounter % 36 -eq 0) {
                    $script:pingHistory1h.Add($lat)
                    if ($script:pingHistory1h.Count -gt 100) { $script:pingHistory1h.RemoveAt(0) }
                    $script:lossHistory1h.Add($false)
                    if ($script:lossHistory1h.Count -gt 100) { $script:lossHistory1h.RemoveAt(0) }
                }
                
                # Update timeframe label
                $tfLabel.Text = switch ($script:currentTimeframe) {
                    "60s"   { "Last 60 seconds" }
                    "5min"  { "Last 5 minutes ($($script:pingHistory5min.Count) points)" }
                    "30min" { "Last 30 minutes ($($script:pingHistory30min.Count) points)" }
                    "1h"    { "Last 1 hour ($($script:pingHistory1h.Count) points)" }
                }
                
                & $script:UpdateGraph
                
                $color = Get-PingColor -ping $lat
                
                $lossP = if ($script:totalPings -gt 0) {
                    [math]::Round(($script:lostPings / $script:totalPings) * 100, 1)
                } else {
                    0
                }
                
                $rateIndicator = switch ($script:adaptiveState) {
                    "FAST"    { "●" }
                    "REDUCED" { "◑" }
                    "MINIMAL" { "○" }
                }

                # Jitter = avg absolute difference of last 10 pings
                $jitterMs = 0
                if ($script:pingHistory.Count -ge 2) {
                    $recentPings = @($script:pingHistory)[-10..-1]
                    $diffs = for ($ji = 1; $ji -lt $recentPings.Count; $ji++) {
                        [math]::Abs($recentPings[$ji] - $recentPings[$ji - 1])
                    }
                    if ($diffs) {
                        $jitterMs = [math]::Round(($diffs | Measure-Object -Average).Average, 0)
                    }
                }
                $script:currentJitter = $jitterMs

                # ── MINI-HUD UPDATE ─────────────────────────────────────
                if ($script:miniHUDActive -and $script:miniHUDPingLabel) {
                    $script:miniHUDPingLabel.Text     = "${lat}ms"
                    $script:miniHUDPingLabel.ForeColor = $color
                    if ($script:miniHUDStatsLabel) {
                        $script:miniHUDStatsLabel.Text = "JIT ${jitterMs}ms`nLOSS ${lossP}%`nMIN $script:minLat / MAX $script:maxLat"
                    }
                }
                # ── HUD TEXT UPDATE ────────────────────────────────────
                $hudLabel.Text = "$lat ms"
                if ($hudSubStats) {
                    $hudSubStats.Text = "JITTER ${jitterMs}ms   |   LOSS $lossP%   |   MIN $script:minLat / MAX $script:maxLat"
                }
                if ($hudServerLabel) {
                    $hudServerLabel.Text = "$script:TargetIP   $rateIndicator"
                }
                if ($hudProfilePill) {
                    $hudProfilePill.Text = "  $script:currentProfile  "
                }

                # ── UPDATE PING BAR ─────────────────────────────────────
                if ($script:pingBarFill -and $script:pingBarPanel) {
                    $maxBarPing  = [math]::Max($CONFIG.AlertCriticalPing * 1.2, 400)
                    $barFraction = [math]::Min($lat / $maxBarPing, 1.0)
                    $barWidth    = [int]($script:pingBarPanel.Width * $barFraction)
                    $barColor    = if ($lat -ge $CONFIG.AlertCriticalPing) {
                        [System.Drawing.Color]::FromArgb(220, 50, 50)
                    } elseif ($lat -ge $CONFIG.AlertHighPing) {
                        [System.Drawing.Color]::FromArgb(220, 130, 0)
                    } elseif ($lat -ge $CONFIG.SpikeThreshold) {
                        [System.Drawing.Color]::FromArgb(200, 180, 0)
                    } else {
                        [System.Drawing.Color]::FromArgb(50, 220, 80)
                    }
                    if ($script:pingBarFill.Width -ne $barWidth)    { $script:pingBarFill.Width    = $barWidth }
                    if ($script:pingBarFill.BackColor -ne $barColor) { $script:pingBarFill.BackColor = $barColor }
                }
                # ────────────────────────────────────────────────────────

                # Live Tray Tooltip Update
                $trayTooltip = "NetNinja ${lat}ms | Jitter:${jitterMs}ms | Loss:${lossP}% | $($script:currentProfile) $rateIndicator"
                if ($trayIcon.Text -ne $trayTooltip) {
                    $pauseSuffix = if ($script:hudPaused) { " [PAUSED]" } else { "" }
                    $fullTip = "$trayTooltip$pauseSuffix"
                    $trayIcon.Text = if ($fullTip.Length -gt 63) { $fullTip.Substring(0, 63) } else { $fullTip }
                }

                # ══ v5.0: REGELN-ENGINE ═══════════════════════════════════
                if ($script:pingRules.Count -gt 0) {
                    try { Evaluate-PingRules -lat $lat -lossP $lossP -jitter $jitterMs } catch { $null = $_ }
                }
                # ── DISCORD RICH PRESENCE UPDATE ────────────────────────
                if ($script:discordEnabled -and $script:discordConnected) {
                    if ($script:graphUpdateCounter % 5 -eq 0) {   # Alle 5 Pings (~5s)
                        Update-DiscordPresence -ping $lat -profile $script:currentProfile -jitter $jitterMs -loss $lossP
                    }
                }
                # ── GEO-IP: Bei erstem Connect abrufen ──────────────────
                if ($script:totalPings -eq 3 -and $script:TargetIP -and $script:TargetIP -notmatch "^192\.|^10\.|^172\.") {
                    try { $null = Get-GeoIP -IP $script:TargetIP } catch { $null = $_ }
                }
                # ── STATUS HEADER UPDATE (Tray Menü) ────────────────────
                if ($menuStatusPing) {
                    $menuStatusPing.Text    = "📡  Ping: ${lat}ms  |  Jitter: ${jitterMs}ms  |  Loss: ${lossP}%"
                    $menuStatusProfile.Text = "🎮  Profile: $($script:Profiles[$script:currentProfile].Name)"
                }

                # ── OVERLAY UPDATE ───────────────────────────────────────
                if ($script:overlayActive -and $overlayLabel) {
                    $overlayLabel.Text = "PING ${lat}ms   JIT ${jitterMs}ms   LOSS ${lossP}%"
                    # Farbe dynamisch je nach Ping
                    $overlayLabel.ForeColor = if ($lat -ge $CONFIG.AlertCriticalPing) {
                        [System.Drawing.Color]::FromArgb(255, 50, 50)     # Rot
                    } elseif ($lat -ge $CONFIG.AlertHighPing) {
                        [System.Drawing.Color]::FromArgb(255, 165, 0)     # Orange
                    } else {
                        [System.Drawing.Color]::FromArgb(0, 255, 80)      # Stechendes Grün
                    }
                }
                # ────────────────────────────────────────────────────────
                
                if ($hudLabel.ForeColor -ne $color) {
                    $hudLabel.ForeColor = $color
                }
                
                # ── ADAPTIVE PING RATE ──────────────────────────────────
                if ($CONFIG.AdaptiveRate) {
                    # Add to rolling window
                    $script:adaptiveWindow.Add($lat)
                    if ($script:adaptiveWindow.Count -gt $CONFIG.AdaptiveStableWindow) {
                        $script:adaptiveWindow.RemoveAt(0)
                    }

                    if ($script:adaptiveWindow.Count -ge $CONFIG.AdaptiveStableWindow) {
                        $avgPing  = [math]::Round(($script:adaptiveWindow | Measure-Object -Average).Average, 1)
                        $maxPing  = ($script:adaptiveWindow | Measure-Object -Maximum).Maximum
                        $minPing  = ($script:adaptiveWindow | Measure-Object -Minimum).Minimum
                        $jitter   = $maxPing - $minPing

                        $isStable = ($avgPing -le $CONFIG.AdaptiveStableMaxPing) -and
                                    ($jitter  -le $CONFIG.AdaptiveStableJitter)   -and
                                    ($lat     -le $CONFIG.SpikeThreshold)

                        if ($isStable) {
                            # Stable → slow down gradually
                            if ($script:currentPingInterval -lt $CONFIG.PingIntervalMax -and
                                $script:adaptiveLastChange.Elapsed.TotalSeconds -ge 10) {

                                $newInterval = [math]::Min(
                                    $script:currentPingInterval + $CONFIG.AdaptiveStepUp,
                                    $CONFIG.PingIntervalMax
                                )

                                if ($newInterval -ne $script:currentPingInterval) {
                                    $script:currentPingInterval = $newInterval
                                    $pingTimer.Interval = $newInterval

                                    $script:adaptiveState = switch ($newInterval) {
                                        { $_ -le 1500 } { "FAST" }
                                        { $_ -le 3000 } { "REDUCED" }
                                        default          { "MINIMAL" }
                                    }

                                    Write-Log "Adaptive rate: slowed to ${newInterval}ms (stable: avg=${avgPing}ms jitter=${jitter}ms)" "INFO"
                                    $script:adaptiveLastChange.Restart()
                                }
                            }
                        } else {
                            # Unstable → speed up immediately
                            if ($script:currentPingInterval -gt $CONFIG.PingIntervalMin) {
                                $newInterval = [math]::Max(
                                    $script:currentPingInterval - $CONFIG.AdaptiveStepDown,
                                    $CONFIG.PingIntervalMin
                                )

                                $script:currentPingInterval = $newInterval
                                $pingTimer.Interval = $newInterval
                                $script:adaptiveState = "FAST"
                                $script:adaptiveWindow.Clear()

                                Write-Log "Adaptive rate: sped up to ${newInterval}ms (unstable: avg=${avgPing}ms jitter=${jitter}ms lat=${lat}ms)" "WARNING"
                                $script:adaptiveLastChange.Restart()
                            }
                        }
                    }
                }
                # ────────────────────────────────────────────────────────
                
                # ── TRAY-ICON UPDATE ─────────────────────────────────
                $latText = $lat.ToString()
                if ($script:lastIconText -ne $latText -or $script:lastColor -ne $color) {
                    $newIcon = Create-IconWithText -text $latText -color $color -mode "ping"
                    if ($newIcon) {
                        $oldIcon = $trayIcon.Icon
                        $trayIcon.Icon = $newIcon
                        if ($oldIcon -and -not $script:iconCache.ContainsValue($oldIcon)) {
                            try { [Win32.IconHelper]::DestroyIcon($oldIcon.Handle) | Out-Null; $oldIcon.Dispose() } catch { $null = $_ }
                        }
                        $script:lastIconText = $latText
                        $script:lastColor    = $color
                    }
                }
                
            } else {
                throw "Connection timeout"
            }
            
        } catch {
            $script:lostPings++
            # Loss-Marker im Graph-Buffer eintragen
            if ($script:lossHistory60s.Count -ge $script:maxHistorySize) { $script:lossHistory60s.RemoveAt(0) }
            $script:lossHistory60s.Add($true)
            $script:lossHistory5min.Add($true)
            if ($script:lossHistory5min.Count -gt 300) { $script:lossHistory5min.RemoveAt(0) }
            if ($script:graphUpdateCounter % 6 -eq 0) {
                $script:lossHistory30min.Add($true)
                if ($script:lossHistory30min.Count -gt 300) { $script:lossHistory30min.RemoveAt(0) }
            }
            if ($script:graphUpdateCounter % 36 -eq 0) {
                $script:lossHistory1h.Add($true)
                if ($script:lossHistory1h.Count -gt 100) { $script:lossHistory1h.RemoveAt(0) }
            }
            
            # ── AUTO-RECONNECT LOGIC ────────────────────────────────
            $consecutiveLoss = $script:lostPings - ($script:totalPings - $script:lostPings)
            $canReconnect = ($null -eq $script:lastReconnectTime) -or
                            (((Get-Date) - $script:lastReconnectTime).TotalSeconds -ge $script:reconnectCooldown)

            if ($script:lostPings -gt 0 -and ($script:lostPings % $script:reconnectThreshold -eq 0) -and $canReconnect) {
                $script:lastReconnectTime = Get-Date
                $script:reconnectAttempts++
                Write-Log "Auto-reconnect attempt #$($script:reconnectAttempts) after $($script:lostPings) losses" "WARNING"

                # Step 1: Flush DNS cache
                try {
                    Clear-DnsClientCache -ErrorAction SilentlyContinue
                    Write-Log "Reconnect: DNS cache flushed" "INFO"
                } catch {}

                # Step 2: Try to ping — if server back, notify and reset stats
                $testPing = Test-Connection -ComputerName $script:TargetIP -Count 1 -ErrorAction SilentlyContinue
                if ($testPing) {
                    $trayIcon.ShowBalloonTip(
                        4000, "NetNinja — Reconnected!",
                        "Connection restored after $($script:lostPings) lost packets.`nDNS cache flushed.",
                        [System.Windows.Forms.ToolTipIcon]::Info
                    )
                    $script:lostPings   = 0
                    $script:totalPings  = [math]::Max($script:totalPings - $script:lostPings, 0)
                    Write-Log "Reconnect successful — connection restored" "INFO"
                } else {
                    $trayIcon.ShowBalloonTip(
                        4000, "NetNinja — Reconnect Failed",
                        "Server still unreachable after attempt #$($script:reconnectAttempts)",
                        [System.Windows.Forms.ToolTipIcon]::Warning
                    )
                }
            }
            # ────────────────────────────────────────────────────────

            # Adaptive Rate: Packet loss → immediately back to FAST
            if ($CONFIG.AdaptiveRate -and $script:currentPingInterval -gt $CONFIG.PingIntervalMin) {
                $script:currentPingInterval = $CONFIG.PingIntervalMin
                $pingTimer.Interval = $CONFIG.PingIntervalMin
                $script:adaptiveState = "FAST"
                $script:adaptiveWindow.Clear()
                Write-Log "Adaptive rate: FAST (packet loss detected)" "WARNING"
            }
            
            $lossP = if ($script:totalPings -gt 0) {
                [math]::Round(($script:lostPings / $script:totalPings) * 100, 1)
            } else {
                0
            }
            
            # Tray-Icon: rot "!!" bei Packet-Loss
            if ($script:lastIconText -ne "!!") {
                $lColor = [System.Drawing.Color]::FromArgb(210, 40, 40)
                $lIcon  = Create-IconWithText -text "!!" -color $lColor -mode "loss"
                if ($lIcon) {
                    $oldI3 = $trayIcon.Icon
                    $trayIcon.Icon = $lIcon
                    if ($oldI3 -and -not $script:iconCache.ContainsValue($oldI3)) {
                        try { [Win32.IconHelper]::DestroyIcon($oldI3.Handle) | Out-Null; $oldI3.Dispose() } catch { $null = $_ }
                    }
                }
                $script:lastIconText = "!!"
            }
            Add-TimelineEvent -Type "loss" -Msg "Packet loss — total $script:lostPings lost ($lossP%)"
            try { Invoke-FailoverCheck -isLoss $true } catch { $null = $_ }
            $hudLabel.Text = "LOSS!"
            if ($hudSubStats) { $hudSubStats.Text = "Loss: $lossP%   |   Packets lost: $script:lostPings" }
            if ($script:overlayActive -and $overlayLabel) {
                $overlayLabel.Text      = "PING LOSS   JIT --ms   LOSS ${lossP}%"
                $overlayLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 50, 50)
            }
            $hudLabel.ForeColor = $script:DeepRed
            
            Write-Log "Packet loss. Total: $script:lostPings / $script:totalPings" "WARNING"
            
            # QUICK WIN: High Packet Loss Alert
            if ($script:totalPings -gt 50) {
                $currentLoss = if ($script:totalPings -gt 0) {
                    [math]::Round(($script:lostPings / $script:totalPings) * 100, 1)
                } else { 0 }
                
                if ($currentLoss -gt 5 -and -not $script:lossAlertShown) {
                    if ($script:soundProfile.NotifyLoss) { Play-AlertSound -Level "loss" }
                    if ($script:webhookConfig.OnLoss) {
                        Send-WebhookAlert -Level "loss" -Message "Packet loss $lossP%: $script:lostPings packets lost — Server: $script:TargetIP"
                    }
                    $trayIcon.ShowBalloonTip(
                        6000, 
                        "HIGH PACKET LOSS!", 
                        "Current loss: $currentLoss%`nTotal lost: $script:lostPings packets`n`nCheck your connection immediately!",
                        [System.Windows.Forms.ToolTipIcon]::Error
                    )
                    $script:lossAlertShown = $true
                    Write-Log "High packet loss alert triggered: $currentLoss%" "WARNING"
                }
                
                if ($currentLoss -lt 3) { $script:lossAlertShown = $false }
            }
        } finally {
            if ($tcp) {
                $tcp.Close()
                $tcp.Dispose()
            }
        }
        # ══ v5.0: MULTI-TARGET PING ══════════════════════════════
        if ($script:multiPingEnabled -and $script:multiTargets.Count -gt 0) {
            try {
                if ($script:graphUpdateCounter % 3 -eq 0) {  # Alle 3 Pings ~3s
                    Invoke-MultiPing
                }
            } catch { $null = $_ }
        }
        # ═════════════════════════════════════════════════════════
    } catch {
        Write-Log "Ping timer error: $_" "ERROR"
    }
})

function Cleanup-AndExit {
    param([bool]$FromFormClose = $false)
    
    # Prevent multiple simultaneous cleanup calls
    if ($script:CleanupInProgress) { return }
    $script:CleanupInProgress = $true
    
    try {
        Write-Log "=== SHUTDOWN INITIATED ===" "INFO"

        # Unregister Global Hotkeys
        try {
            for ($hkId = 1; $hkId -le 5; $hkId++) {
                [HotkeyHelper]::UnregisterHotKey($script:hotkeyHandle, $hkId) | Out-Null
            }
            Write-Log "Hotkeys unregistered" "INFO"
        } catch {}

        # Overlay schließen
        try { if ($overlayForm) { $overlayForm.Hide(); $overlayForm.Dispose() } } catch {}

        # Save current session to history
        if ($script:totalPings -gt 0) {
            try {
                Save-CurrentSession
            } catch {
                Write-Log "Failed to save session: $_" "ERROR"
            }
        }
        
        # 1. Stop timer first to prevent new operations
        # Fade timer
        if ($script:fadeTimer) {
            try { $script:fadeTimer.Stop(); $script:fadeTimer.Dispose() } catch {}
        }

        if ($pingTimer) {
            try {
                $pingTimer.Stop()
                $pingTimer.Dispose()
                Write-Log "Ping timer stopped" "INFO"
            } catch {
                Write-Log "Ping timer cleanup error: $_" "WARNING"
            }
        }
        
        # Stop process monitor timer
        if ($processMonitorTimer) {
            try {
                $processMonitorTimer.Stop()
                $processMonitorTimer.Dispose()
                Write-Log "Process monitor stopped" "INFO"
            } catch {
                Write-Log "Process monitor cleanup error: $_" "WARNING"
            }
        }
        
        # 2. Reset optimizations
        try {
            Apply-Optimizations -DisableAll $true
            Write-Log "Optimizations reset" "INFO"
        } catch {
            Write-Log "Optimization reset error: $_" "WARNING"
        }
        
        # 3. Cleanup icons + GfxCache
        try {
            # Web-Dashboard stoppen
            Stop-WebDashboard
            # Multi-Target PenCache bereinigen
            if ($script:multiTargets) {
                foreach ($mtt in $script:multiTargets) {
                    try { if ($mtt.PenCache) { $mtt.PenCache.Dispose() } } catch { $null = $_ }
                }
            }
            # Discord trennen
            Disconnect-Discord
            # Dispose cached graph resources (Pens, Brushes)
            if ($script:gfxCache) {
                foreach ($key in $script:gfxCache.Keys) {
                    try { $script:gfxCache[$key].Dispose() } catch { $null = $_ }
                }
                $script:gfxCache.Clear()
                Write-Log "GfxCache disposed" "INFO"
            }
            Cleanup-Icons
        } catch {
            Write-Log "Icon cleanup error: $_" "WARNING"
        }
        
        # 4. Dispose tray icon
        if ($trayIcon) {
            try {
                $trayIcon.Visible = $false
                if ($trayIcon.Icon) {
                    [Win32.IconHelper]::DestroyIcon($trayIcon.Icon.Handle) | Out-Null
                    $trayIcon.Icon.Dispose()
                }
                $trayIcon.Dispose()
                Write-Log "Tray disposed" "INFO"
            } catch {
                Write-Log "Tray cleanup error: $_" "WARNING"
            }
        }
        
        # 5. Close form properly
        if ($hudForm -and -not $FromFormClose) {
            try {
                # Remove event handler to prevent recursion
                $hudForm.remove_FormClosing($formClosingHandler)
                $hudForm.Close()
                $hudForm.Dispose()
                Write-Log "Form closed" "INFO"
            } catch {
                Write-Log "Form cleanup error: $_" "WARNING"
            }
        }
        
        # Save config before exit
        try { Save-Config } catch { Write-Log "Save-Config on exit failed: $_" "ERROR" }

        Write-Log "=== NETNINJA STOPPED ===" "INFO"
        Write-Log "=== SHUTDOWN COMPLETE ===" "INFO"
        
        # 6. Exit application
        [System.Windows.Forms.Application]::Exit()
        
        # 7. Force PowerShell exit after short delay
        Start-Sleep -Milliseconds 500
        [System.Environment]::Exit(0)
        
    } catch {
        Write-Log "Critical cleanup error: $_" "ERROR"
        # Force exit even on error
        [System.Environment]::Exit(1)
    }
}

# Initialize cleanup flag
$script:CleanupInProgress = $false

# Form closing handler with proper event handling
$formClosingHandler = {
    param($sender, $e)
    
    # Ask for confirmation
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Exit NetNinja?`n`nOptimizations will be reset.",
        "Confirm Exit",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        # Allow the close and trigger cleanup
        $e.Cancel = $false
        Cleanup-AndExit -FromFormClose $true
    } else {
        # Cancel the close
        $e.Cancel = $true
    }
}

$hudForm.Add_FormClosing($formClosingHandler)

# QUICK WIN: Minimize to Tray
$hudForm.Add_Resize({
    if ($hudForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $hudForm.Hide()
        $hudForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        Notify-User "Minimized to system tray" -Ms 2000
    }
})

# QUICK WIN: Double-Click Tray to Restore
$trayIcon.Add_DoubleClick({
    $hudForm.Show()
    $hudForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    $hudForm.BringToFront()
})

# QUICK WIN: Global Hotkeys - DISABLED due to compatibility issues
# Hotkeys can cause Add-Type errors on some systems
# All features still accessible via Context Menu
# To re-enable: Uncomment the hotkey section below

<# HOTKEY CODE - DISABLED
try {
    if (-not ([System.Management.Automation.PSTypeName]'HotKeyManager').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class HotKeyManager {
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@
    }

    if (-not ([System.Management.Automation.PSTypeName]'HotKeyNativeWindow').Type) {
        Add-Type -ReferencedAssemblies 'System.Windows.Forms' -TypeDefinition @"
using System;
using System.Windows.Forms;
public class HotKeyNativeWindow : NativeWindow {
    public event EventHandler<int> HotKeyPressed;
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) {
            if (HotKeyPressed != null) {
                HotKeyPressed(this, m.WParam.ToInt32());
            }
        }
        base.WndProc(ref m);
    }
}
"@
    }

    $HOTKEY_TOGGLE_HUD = 1
    $HOTKEY_RESTART_ADAPTER = 2
    $HOTKEY_OPEN_OPTIMIZER = 3
    $MOD_CTRL_SHIFT = 0x0002 -bor 0x0004
    
    $hudForm.Add_Shown({
        try {
            [HotKeyManager]::RegisterHotKey($hudForm.Handle, $HOTKEY_TOGGLE_HUD, $MOD_CTRL_SHIFT, 0x50) | Out-Null
            [HotKeyManager]::RegisterHotKey($hudForm.Handle, $HOTKEY_RESTART_ADAPTER, $MOD_CTRL_SHIFT, 0x52) | Out-Null
            [HotKeyManager]::RegisterHotKey($hudForm.Handle, $HOTKEY_OPEN_OPTIMIZER, $MOD_CTRL_SHIFT, 0x4F) | Out-Null
            Write-Log "Hotkeys registered: Ctrl+Shift+P/R/O" "INFO"
        } catch {
            Write-Log "Hotkey registration failed: $_" "WARNING"
        }
    })
    
    $script:hotKeyWindow = New-Object HotKeyNativeWindow
    $hudForm.Add_HandleCreated({
        $script:hotKeyWindow.AssignHandle($hudForm.Handle)
    })
    
    $script:hotKeyWindow.add_HotKeyPressed({
        param($sender, $hotkeyId)
        switch ($hotkeyId) {
            $HOTKEY_TOGGLE_HUD {
                if ($hudForm.Visible) { $hudForm.Hide() } else { $hudForm.Show(); $hudForm.BringToFront() }
            }
            $HOTKEY_RESTART_ADAPTER { Reset-NetworkAdapter }
            $HOTKEY_OPEN_OPTIMIZER { Show-OptimizationManager }
        }
    })
    
} catch {
    Write-Log "Hotkey setup failed (non-critical): $_" "WARNING"
}
#>

Write-Log "Hotkeys disabled (compatibility mode)" "INFO"

# Remove the problematic EngineEvent registration
# Register-EngineEvent can cause hanging
# Instead, rely on FormClosing event

# Load persisted config
Load-Config

# ── First-Run Onboarding ─────────────────────────────────────
if (-not (Test-Path $script:firstRunFile)) {
    $script:showOnboarding = $true
}
Apply-Theme -Dark $script:darkMode

Write-Log "=== NETNINJA v$($CONFIG.Version) STARTED ===" "INFO"
Write-Log "Path: $script:scriptPath" "INFO"
Write-Log "Target: $($CONFIG.ServerAddress)`:$($CONFIG.ServerPort)" "INFO"
Write-Log "Windows: $($script:WinVersion.Major).$($script:WinVersion.Minor) Build $($script:WinVersion.Build)" "INFO"

# Load session history
Load-SessionHistory

# ADVANCED NOTIFICATION: Daily Summary
if ($script:sessionHistory.Count -gt 0) {
    $today = Get-Date
    $todaySessions = $script:sessionHistory | Where-Object {
        $startDate = [DateTime]::ParseExact($_.StartTime, 'yyyy-MM-dd HH:mm:ss', $null)
        $startDate.Date -eq $today.Date
    }
    
    if ($todaySessions.Count -gt 0 -and -not $script:dailySummaryShown) {
        $totalTime = ($todaySessions | Measure-Object -Property DurationMinutes -Sum).Sum
        $avgScore = [math]::Round(($todaySessions | Measure-Object -Property StabilityScore -Average).Average, 0)
        $avgPing = [math]::Round(($todaySessions | Measure-Object -Property AvgPing -Average).Average, 1)
        
        $hours = [math]::Floor($totalTime / 60)
        $mins = $totalTime % 60
        
        Start-Sleep -Seconds 3  # Wait a bit after start
        
        $trayIcon.ShowBalloonTip(
            6000,
            "📊 Today's Summary",
            "Sessions: $($todaySessions.Count)`nTotal time: ${hours}h ${mins}m`nAvg Ping: ${avgPing}ms`nStability: $avgScore/100",
            [System.Windows.Forms.ToolTipIcon]::Info
        )
        $script:dailySummaryShown = $true
        Write-Log "Daily summary shown: $($todaySessions.Count) sessions, ${hours}h ${mins}m" "INFO"
    }
}

Apply-Optimizations
Write-Log "Optimizations applied" "INFO"

$pingTimer.Start()
Write-Log "Monitoring started (interval: $($pingTimer.Interval)ms)" "INFO"

$hudForm.Show()

[System.Windows.Forms.Application]::Run($hudForm)