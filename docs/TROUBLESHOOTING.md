# Troubleshooting

---

## NetNinja won't start / closes immediately

**Cause:** Execution policy blocks unsigned scripts.

**Fix:**
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
```

---

## "Access denied" or no optimizations applied

**Cause:** Not running as Administrator.

**Fix:** Right-click `NetNinja.ps1` → **Run with PowerShell as Administrator**, or use the desktop shortcut created by `Install.ps1`.

---

## Ping always shows 0 or timeout

**Causes & fixes:**
1. **Wrong IP/port** — check `ServerAddress` and `ServerPort` in config
2. **Firewall blocking** — allow outbound TCP on the target port
3. **Server offline** — verify server is reachable with `Test-NetConnection your.ip -Port 5121`

---

## Auto-detect never finds the server

NetNinja scans active TCP connections of the game process. Make sure:
- The game is running and **logged into the server** (not at character select)
- The process name in config (`ProcessName`) matches the actual `.exe` name
- Use **Get-Process** in PowerShell to find the exact name

---

## High CPU usage

**Cause:** Very low `PingIntervalMin` (< 500ms) or many multi-targets.

**Fix:** Increase `PingIntervalMin` to `1000` (1 second) in config, or disable Multi-Target Mode.

---

## DNS change not working

**Cause:** Network adapter selected manually but adapter was renamed/changed.

**Fix:** In the tray menu → **Select Adapter** → choose the correct adapter or set to **AUTO**.

---

## Graph not rendering

**Cause:** `graphPanel` not yet initialized (HUD hidden).

**Fix:** Show the HUD first (`Ctrl+Alt+P`), then open the graph.

---

## Registry backup not created

**Cause:** Backup already exists (NetNinja skips if backup is present).

**Fix:** Delete `netninja_registry_backup.reg` in the app folder to force a fresh backup.

---

## Rules Engine not firing

Check:
1. Rule is **Enabled** (green in the list)
2. Condition thresholds match your actual ping/loss values
3. Action cooldown hasn't expired — check the **Fire Log** in the Rules Engine window
4. For webhook actions: URL is valid and the service is reachable

---

## Overlay (Ctrl+Alt+O) not transparent / not click-through

**Cause:** Some games run in exclusive fullscreen mode which prevents overlays.

**Fix:** Switch the game to **Borderless Window** mode.

---

## Getting more help

Open an issue on GitHub with:
- Your Windows version (`winver`)
- PowerShell version (`$PSVersionTable.PSVersion`)
- The last 50 lines of `netninja_log_YYYYMMDD.txt`
