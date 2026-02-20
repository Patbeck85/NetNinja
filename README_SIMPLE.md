# 🥷 NetNinja v5.0
**Network Latency Monitor & Optimizer for Windows — PowerShell 5.1+**

> Real-time ping monitoring, network optimization, and game server auto-detection — all in a single portable `.ps1` file.

---

## ✨ Features

| Category | Details |
|---|---|
| **Live Monitoring** | Real-time ping graph, packet loss, jitter, spike detection |
| **Game Auto-Detect** | 103 games (MMO, FPS, Battle Royale, MOBA, Survival) |
| **Profiles** | MMO · Competitive · Analysis · Silent |
| **Network Tweaks** | 19 base + 10 competitive-specific registry/TCP optimizations |
| **Overlay Mode** | Click-through fullscreen overlay (Ctrl+Alt+O) |
| **Multi-Target Ping** | Up to 8 simultaneous targets in HUD graph |
| **Rules Engine** | Trigger actions on ping/loss thresholds (9 action types) |
| **MTU Optimizer** | Automatic optimal MTU detection per profile |
| **A/B Benchmark** | Before/after comparison with statistics |
| **Auto-Diagnosis** | Buffer bloat, ISP congestion, WiFi interference detection |
| **Webhooks** | Discord / Slack / Teams / Generic alerts |
| **Session History** | Last 50 sessions, CSV export, HTML reports |
| **Failover** | Automatic server failover on connection loss |
| **GeoIP** | Server location lookup with world map |
| **Heatmap** | Ping heatmap by day/hour (persistent) |
| **Mini-HUD** | Always-on-top compact overlay |
| **Discord RPC** | Rich Presence integration |
| **DNS Switcher** | One-click Cloudflare / Google / Custom DNS |
| **Adaptive Rate** | 1s–5s ping interval based on stability |
| **Dark/Light Theme** | Central color palette, persisted |

---

## 🚀 Quick Start

### Requirements
- Windows 10 / 11
- PowerShell 5.1 or newer (pre-installed on Windows 10+)
- Administrator rights (auto-elevates on launch)

### Run
```powershell
# Option 1: Right-click → Run with PowerShell (as Administrator)

# Option 2: PowerShell terminal
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass
.\src\NetNinja.ps1
```

### First Launch
1. NetNinja auto-detects your game server via active TCP connections
2. Or enter your server IP/port manually in the HUD
3. Select a profile (MMO / Competitive / Analysis / Silent)
4. Optionally apply network optimizations from the Optimization Manager

---

## ⌨️ Hotkeys

| Shortcut | Action |
|---|---|
| `Ctrl+Alt+P` | Toggle HUD show/hide |
| `Ctrl+Alt+O` | Toggle Overlay mode (fullscreen click-through) |
| `Ctrl+Alt+R` | Reset statistics |
| `Ctrl+Alt+M` | Open MTU Optimizer |
| `Ctrl+Alt+S` | Save config |
| `Ctrl+Alt+H` | Export HTML report |

---

## 📁 Project Structure

```
NetNinja/
├── src/
│   └── NetNinja.ps1          # Main application (single-file)
├── config/
│   └── default_config.json   # Default configuration template
├── scripts/
│   ├── Install.ps1           # Optional: create desktop shortcut
│   └── Uninstall.ps1         # Restore all registry changes
├── docs/
│   ├── CONFIGURATION.md      # All config options explained
│   ├── PROFILES.md           # Profile system documentation
│   └── TROUBLESHOOTING.md    # Common issues & fixes
├── tests/
│   └── Test-Functions.ps1    # Unit tests for core functions
├── assets/
│   ├── icons/                # App icons
│   └── screenshots/          # UI screenshots
├── .github/
│   └── ISSUE_TEMPLATE/
│       ├── bug_report.md
│       └── feature_request.md
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

---

## ⚙️ Configuration

NetNinja saves its config to `netninja_config.json` in the same directory. You can pre-configure it via `config/default_config.json`.

Key settings:

```json
{
  "ServerAddress": "your.server.ip",
  "ServerPort": 5121,
  "AlertHighPing": 150,
  "AlertCriticalPing": 300,
  "AdaptiveRate": true,
  "SpikeThreshold": 50
}
```

See [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) for all options.

---

## 🛡️ Permissions & Safety

NetNinja requests Administrator rights to:
- Apply TCP/registry optimizations
- Change DNS settings
- Restart network adapters

All registry changes are **backed up automatically** before any modification. Use **Restore Network Settings** or **Restore Registry** in the tray menu to revert everything.

---

## 📜 Changelog

See [`CHANGELOG.md`](CHANGELOG.md).

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'Add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

Please read the [contributing guidelines](docs/CONTRIBUTING.md) first.

---

## 📄 License

MIT License — see [`LICENSE`](LICENSE) for details.

---

## ⚠️ Disclaimer

Network optimizations modify Windows registry and TCP settings. While all changes are backed up and reversible, use at your own risk. NetNinja is not affiliated with any game publisher or ISP.
