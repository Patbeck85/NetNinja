# Configuration Reference

NetNinja saves its configuration to `netninja_config.json` in the same directory as `NetNinja.ps1`. The file is created automatically on first launch and updated whenever you click **Save** or change a setting.

---

## All Options

| Key | Type | Default | Description |
|---|---|---|---|
| `ServerAddress` | string | `"127.0.0.1"` | Target server IP or hostname |
| `ServerPort` | int | `5121` | Target port for TCP latency measurement |
| `ProcessName` | string | `"ragnarok"` | Game process for auto-detection |
| `AlertHighPing` | int | `150` | Ping threshold (ms) for High alert |
| `AlertCriticalPing` | int | `300` | Ping threshold (ms) for Critical alert |
| `SpikeThreshold` | int | `50` | Delta (ms) above rolling average to count as spike |
| `AdaptiveRate` | bool | `true` | Automatically adjust ping interval based on stability |
| `PingIntervalMin` | int | `1000` | Minimum ping interval in ms (when unstable) |
| `PingIntervalMax` | int | `5000` | Maximum ping interval in ms (when stable) |
| `AdaptiveStableMaxPing` | int | `80` | Max avg ping (ms) to be considered "stable" |
| `AdaptiveStableJitter` | int | `15` | Max jitter (ms) to be considered "stable" |
| `AdaptiveStableWindow` | int | `10` | Number of consecutive stable pings before slowing down |
| `CurrentProfile` | string | `"MMO"` | Active profile: `MMO` / `FPS` / `Analysis` / `Silent` |
| `SelectedAdapter` | string\|null | `null` | Network adapter name, `null` = auto (first Up) |
| `DarkMode` | bool | `true` | UI theme: `true` = dark, `false` = light |
| `AudioAlertEnabled` | bool | `true` | Enable system sound alerts |
| `HUDOpacity` | float | `0.96` | HUD window opacity (0.1 – 1.0) |
| `HUDTopMost` | bool | `true` | Keep HUD window always on top |
| `HUDLocation` | object | `{X:20,Y:20}` | HUD window position on screen |

---

## Profiles

Profiles bundle a set of defaults. Switching a profile applies its settings instantly.

| Profile | Use Case | Ping Rate | Alerts | Optimizations |
|---|---|---|---|---|
| `MMO` | WoW, FFXIV, Ragnarok, BDO | 2s | High + Loss | Base tweaks |
| `FPS` | CS2, Valorant, Apex | 1s | All | Full competitive |
| `Analysis` | Diagnostics, ISP issues | 1s | All + detailed log | None |
| `Silent` | Background monitoring | 5s | None | None |

---

## Manual Edit

You can edit `netninja_config.json` with any text editor while NetNinja is **not running**. Changes take effect on next launch, or use **Config Editor** in the tray menu to edit live.

---

## Reset to Defaults

In the tray menu: **Config Editor → Reset Defaults**, or delete `netninja_config.json` and restart.
