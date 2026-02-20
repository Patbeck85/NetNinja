#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Restores all network and registry settings changed by NetNinja.
.DESCRIPTION
    Removes the desktop shortcut and restores:
    - Registry values (Multimedia/SystemProfile tweaks)
    - DNS settings (resets to DHCP/automatic)
    - MTU (resets to 1500)
    - Power scheme (back to Balanced)
    Run this if you want to fully remove NetNinja's changes.
.EXAMPLE
    .\scripts\Uninstall.ps1
#>

$scriptDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host "NetNinja Uninstaller" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Cyan

# ── 1. Shortcut entfernen ──────────────────────────────────────
$shortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "NetNinja.lnk"
if (Test-Path $shortcut) {
    Remove-Item $shortcut -Force
    Write-Host "✅ Desktop shortcut removed" -ForegroundColor Green
}

# ── 2. Registry-Backup einspielen ─────────────────────────────
$regBackup = Join-Path $scriptDir "netninja_registry_backup.reg"
if (Test-Path $regBackup) {
    Write-Host "Restoring registry from backup..." -ForegroundColor Yellow
    $p = Start-Process "reg" -ArgumentList "import `"$regBackup`"" -Wait -NoNewWindow -PassThru
    if ($p.ExitCode -eq 0) {
        Write-Host "✅ Registry restored" -ForegroundColor Green
    } else {
        Write-Host "⚠ Registry restore failed (exit code $($p.ExitCode))" -ForegroundColor Yellow
    }
} else {
    # Manuelle Defaults
    $prof = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    Set-ItemProperty -Path $prof -Name "NetworkThrottlingIndex" -Value 10   -Force -EA SilentlyContinue
    Set-ItemProperty -Path $prof -Name "SystemResponsiveness"   -Value 20   -Force -EA SilentlyContinue
    Write-Host "✅ Registry reset to Windows defaults (no backup found)" -ForegroundColor Green
}

# ── 3. DNS zurücksetzen ────────────────────────────────────────
$adapters = Get-NetAdapter | Where-Object Status -eq 'Up'
foreach ($a in $adapters) {
    Set-DnsClientServerAddress -InterfaceAlias $a.Name -ResetServerAddresses -EA SilentlyContinue
}
Clear-DnsClientCache -EA SilentlyContinue
Write-Host "✅ DNS reset to automatic (DHCP)" -ForegroundColor Green

# ── 4. MTU auf 1500 zurücksetzen ──────────────────────────────
foreach ($a in $adapters) {
    netsh interface ipv4 set subinterface "$($a.Name)" mtu=1500 store=persistent 2>$null
}
Write-Host "✅ MTU reset to 1500" -ForegroundColor Green

# ── 5. Balanced Power Plan wiederherstellen ────────────────────
powercfg -setactive SCHEME_BALANCED 2>$null
Write-Host "✅ Power scheme reset to Balanced" -ForegroundColor Green

# ── 6. Runtime-Dateien löschen (optional) ─────────────────────
$runtimeFiles = @(
    "netninja_config.json",
    "netninja_heatmap.json",
    "netninja_sessions.json",
    "netninja_registry_backup.reg",
    "netninja_network_backup.json"
)
$deleteData = Read-Host "`nDelete NetNinja data files (config, history, logs)? [y/N]"
if ($deleteData -match '^[yY]') {
    foreach ($f in $runtimeFiles) {
        $fp = Join-Path $scriptDir $f
        if (Test-Path $fp) { Remove-Item $fp -Force }
    }
    Get-ChildItem $scriptDir -Filter "netninja_log*.txt" | Remove-Item -Force
    Get-ChildItem $scriptDir -Filter "stats_*.csv"        | Remove-Item -Force
    Write-Host "✅ Data files removed" -ForegroundColor Green
}

Write-Host "`nNetNinja uninstalled successfully." -ForegroundColor Cyan
