#Requires -Version 5.1
<#
.SYNOPSIS
    Creates a desktop shortcut for NetNinja that runs as Administrator.
.DESCRIPTION
    Run this script once after cloning the repository.
    It creates a shortcut on your Desktop that launches NetNinja
    with Administrator privileges automatically.
.EXAMPLE
    .\scripts\Install.ps1
#>

$scriptDir  = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$targetPs1  = Join-Path $scriptDir "src\NetNinja.ps1"
$shortcutPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "NetNinja.lnk"

if (-not (Test-Path $targetPs1)) {
    Write-Error "NetNinja.ps1 not found at: $targetPs1"
    exit 1
}

$wsh    = New-Object -ComObject WScript.Shell
$link   = $wsh.CreateShortcut($shortcutPath)
$link.TargetPath       = "powershell.exe"
$link.Arguments        = "-NoProfile -ExecutionPolicy Bypass -File `"$targetPs1`""
$link.WorkingDirectory = Split-Path $targetPs1
$link.Description      = "NetNinja — Network Latency Monitor & Optimizer"
$link.WindowStyle      = 1
$link.Save()

# Make it run as Administrator
$bytes = [System.IO.File]::ReadAllBytes($shortcutPath)
$bytes[0x15] = $bytes[0x15] -bor 0x20   # Set Run as Administrator flag
[System.IO.File]::WriteAllBytes($shortcutPath, $bytes)

Write-Host "✅ Shortcut created: $shortcutPath" -ForegroundColor Green
Write-Host "   Double-click to launch NetNinja as Administrator." -ForegroundColor Cyan
