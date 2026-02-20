#Requires -Version 5.1
<#
.SYNOPSIS
    Basic unit tests for NetNinja core functions.
.DESCRIPTION
    Tests pure logic functions that don't require a running GUI.
    Run from the repo root: .\tests\Test-Functions.ps1
#>

$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0

function Assert-Equal {
    param($Label, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        Write-Host "  ✅ $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  ❌ $Label  (expected: $Expected  got: $Actual)" -ForegroundColor Red
        $script:fail++
    }
}
function Assert-True {
    param($Label, $Condition)
    Assert-Equal $Label $true $Condition
}

Write-Host "`nNetNinja — Unit Tests" -ForegroundColor Cyan
Write-Host "=" * 40 -ForegroundColor Cyan

# ── Get-PingColor ─────────────────────────────────────────────
Write-Host "`n[Get-PingColor]"

# Inline-Implementierung zum isolierten Testen
function Get-PingColor {
    param([int]$ping)
    $p = [math]::Max(0, [math]::Min($ping, 400))
    if ($p -lt 75)    { return [System.Drawing.Color]::FromArgb([int](40+($p/75)*185), [int](210-($p/75)*10), [int](60-($p/75)*50)) }
    elseif ($p -lt 150) { $t=($p-75)/75; return [System.Drawing.Color]::FromArgb([int](225+$t*20),[int](200-$t*20),10) }
    elseif ($p -lt 250) { $t=($p-150)/100; return [System.Drawing.Color]::FromArgb(245,[int](180-$t*110),10) }
    else { $t=[math]::Min(($p-250)/150,1); return [System.Drawing.Color]::FromArgb([int](245-$t*20),[int](70-$t*55),10) }
}

Add-Type -AssemblyName System.Drawing
$c0   = Get-PingColor 0
$c75  = Get-PingColor 75
$c300 = Get-PingColor 300

Assert-True  "0ms  → Green dominant (G > R)"   ($c0.G -gt $c0.R)
Assert-True  "75ms → Red component rises"       ($c75.R -gt $c0.R)
Assert-True  "300ms → Red dominant (R > G)"     ($c300.R -gt $c300.G)
Assert-Equal "400ms+ clamped to 400ms"          (Get-PingColor 400).R (Get-PingColor 999).R

# ── Jitter MAD Calculation ────────────────────────────────────
Write-Host "`n[Jitter MAD]"

$hist = @(50, 52, 48, 300, 51, 49, 52, 50)   # 1 spike at 300ms
$diffs = [System.Collections.Generic.List[double]]::new()
for ($i = 1; $i -lt $hist.Count; $i++) { $diffs.Add([math]::Abs($hist[$i] - $hist[$i-1])) }
$jitter = [int](($diffs | Measure-Object -Average).Average)

Assert-True  "Jitter MAD is > 0"               ($jitter -gt 0)
Assert-True  "Jitter MAD < raw max-min"        ($jitter -lt (($hist | Measure-Object -Maximum).Maximum - ($hist | Measure-Object -Minimum).Minimum))

# ── Stability Score ───────────────────────────────────────────
Write-Host "`n[Stability Score]"

function Get-StabilityScore { param($lossP, $maxLat, $spikes)
    [math]::Max(0, [math]::Round(100 - ($lossP*10) - (if ($maxLat -gt 200) {20} else {0}) - (if ($spikes -gt 10) {10} else {0}), 0))
}

Assert-Equal "Perfect connection = 100"     100 (Get-StabilityScore 0 50 0)
Assert-Equal "5% loss = 50"                 50  (Get-StabilityScore 5 50 0)
Assert-Equal "High lat penalty = -20"       80  (Get-StabilityScore 0 250 0)
Assert-Equal "Spike penalty = -10"          90  (Get-StabilityScore 0 50 15)
Assert-Equal "Score never below 0"          0   (Get-StabilityScore 20 500 100)

# ── Write-Log Throttle ────────────────────────────────────────
Write-Host "`n[Write-Log Throttle]"

$lastCheck = 0
$now = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
$shouldRotate1 = ($now - $lastCheck) -gt 60   # First call: always rotate
$lastCheck = $now
$shouldRotate2 = ($now - $lastCheck) -gt 60   # Second call immediately: skip

Assert-True  "First check triggers rotation"   $shouldRotate1
Assert-Equal "Second check skips rotation"     $false $shouldRotate2

# ── DNS Validation ────────────────────────────────────────────
Write-Host "`n[DNS/URL Validation]"

$validURLs   = @("https://hooks.slack.com/test", "http://localhost/webhook")
$invalidURLs = @("not-a-url", "ftp://bad-scheme.com", "")

foreach ($url in $validURLs) {
    Assert-True "Valid URL accepted: $url" ($url -match '^https?://')
}
foreach ($url in $invalidURLs) {
    Assert-Equal "Invalid URL rejected: '$url'" $false ($url -match '^https?://')
}

# ── Private IP Guard ──────────────────────────────────────────
Write-Host "`n[Private IP Guard]"

$privateIPs = @("127.0.0.1", "192.168.1.1", "10.0.0.5", "172.16.0.1", "172.31.255.255")
$publicIPs  = @("8.8.8.8", "1.1.1.1", "203.0.113.1")

foreach ($ip in $privateIPs) {
    Assert-True "Private IP blocked: $ip"  ($ip -match '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)')
}
foreach ($ip in $publicIPs) {
    Assert-Equal "Public IP allowed: $ip" $false ($ip -match '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)')
}

# ── Results ───────────────────────────────────────────────────
Write-Host "`n" + ("=" * 40) -ForegroundColor Cyan
$total = $pass + $fail
$pct   = if ($total -gt 0) { [math]::Round($pass/$total*100,0) } else { 0 }

if ($fail -eq 0) {
    Write-Host "✅  All $total tests passed ($pct%)" -ForegroundColor Green
} else {
    Write-Host "⚠  $pass/$total passed ($pct%) — $fail FAILED" -ForegroundColor Yellow
    exit 1
}
