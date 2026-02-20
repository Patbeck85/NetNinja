# Changelog

All notable changes to NetNinja are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [5.0.0] — 2026-02-16

### Added
- **Rules Engine** — 9 action types triggered by ping/loss thresholds (webhook, sound, failover, etc.)
- **Multi-Target Ping** — up to 8 simultaneous targets in HUD graph with color-coded lines
- **Auto-Diagnosis** — detects buffer bloat, ISP congestion, WiFi interference, routing changes
- **Discord Webhooks** — real-time alerts to Discord / Slack / Teams / Generic endpoints
- **Mini-HUD** — draggable always-on-top compact overlay
- **Session History** — persistent history of last 50 sessions with CSV export
- **Ping Heatmap** — latency by day of week / hour, persisted across sessions
- **GeoIP** — server location with world map visualization
- **A/B Benchmark** — before/after ping comparison with improvement percentage
- **Failover System** — automatic server failover on connection loss with configurable threshold
- **Discord Rich Presence** — show connection stats in Discord status
- **Show-AlertSettings** — full sound/notification profile editor
- **Show-WebhookSettings** — webhook configuration with live test
- `AvgMs` tracking per multi-target

### Fixed
- **CRITICAL** `Add-PingTarget`: `$Host` parameter shadowed PowerShell built-in — renamed to `$TargetHost`
- **CRITICAL** `Invoke-MultiPing`: Async closure captured loop variable by reference — all tasks shared the same `$t`
- **CRITICAL** `Invoke-MultiPing`: `Task[int]::Run` not supported in PS 5.1 — changed to `Task::Run([Action])`
- **MEMORY** TcpClient never disposed on timeout path — added `finally` blocks
- **MEMORY** WebClient not disposed on exception in `Get-GeoIP`, `Send-WebhookAlert`, `Export-GraphPNG`
- **MEMORY** Font objects created on every form open — all fonts now use cached `$script:Fonts.*`
- **BUG** `Evaluate-PingRules`: race condition — rules list copied before iteration
- **BUG** `Invoke-FailoverCheck`: `failoverConsecLoss` not reset on success
- **BUG** `Show-MiniHUD`: drag offset was `$null` instead of `[Point]::Empty`
- **BUG** `Get-GeoIP`: HTTP → HTTPS; private IP guard added
- **BUG** `Invoke-AutoDiagnosis`: jitter calculated as max-min — now uses mean absolute deviation
- **BUG** `Show-StatsDashboard`: StdDev recalculated average unnecessarily
- **BUG** `Restore-NetworkSettings`: only reset DNS, never restored actual saved servers
- **BUG** `Optimize-RAM`: `FreePhysicalMemory` reported in KB, displayed as GB (off by 1024x)
- **BUG** `Show-ConfigEditor`: validation logic (`-notmatch '^\d'`) always evaluated true for strings
- **BUG** `Add-FailoverTarget`: `$Host` parameter conflicted with PS built-in
- **PERF** `Play-AlertSound`: `Start-Sleep` in UI thread — moved to `Task::Run`
- **PERF** `Write-Log`: `Out-File -Append` not atomic — replaced with `StreamWriter`
- **PERF** `Write-Log`: log rotation checked on every write — throttled to once per 60s
- **PERF** `Save-CurrentSession`: `+=` on array was O(n) — replaced with `List<T>`
- **UI** All forms now have Escape key handlers
- **UI** `Show-TracerouteGUI`: process not killed on form close; Cancel button added; color-coded hops
- **UI** `Switch-Profile`: FPS activation `MessageBox` blocked ping timer — replaced with `BalloonTip`
- **SECURITY** `Get-GeoIP`: HTTP → HTTPS

### Changed
- Log rotation: keeps last 5 files (was unlimited)
- Log encoding: UTF-8 without BOM
- `Show-LogViewer`: tail 500 → 1000 lines
- `Show-RulesEngine`: fire log max 50 → 100 entries
- All registry writes backed up before first modification

---

## [4.9.0] — Initial Release

- Core ping monitoring with real-time graph
- 4 profiles: MMO, Competitive, Analysis, Silent
- Network optimization manager (19 tweaks)
- DNS switcher (Cloudflare / Google / Reset)
- MTU optimizer
- Adapter selector
- Config save/load (JSON)
- Dark/Light theme
- System tray integration
- Hotkeys: Ctrl+Alt+P/R/M/S/O
- Auto-elevation to Administrator
- 103 game process definitions for auto-detection
