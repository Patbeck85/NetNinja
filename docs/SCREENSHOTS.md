# Screenshot Guide für NetNinja

Diese Anleitung zeigt dir **genau**, welche Screenshots du machen musst und wie.

---

## 📸 Benötigte Screenshots (8 Stück)

### 1. **main_hud.png** — Haupt-HUD mit Graph
**Was zeigen:**
- HUD-Fenster mit aktivem Ping-Graph (idealerweise mit Daten)
- Graph sollte grüne Linie zeigen (guter Ping)
- Alle UI-Elemente sichtbar: Pause-Button, Stats, Timeframe-Buttons

**Schritte:**
1. NetNinja starten
2. Warten bis Graph Daten hat (~30 Sekunden)
3. `Win + Shift + S` drücken
4. Gesamtes HUD-Fenster markieren
5. Speichern als: `main_hud.png`

**Empfohlene Größe:** 800×600 Pixel

---

### 2. **rules_engine.png** — Rules Engine mit Regeln
**Was zeigen:**
- Rules Engine Fenster offen
- Mindestens 2-3 aktive Regeln in der Liste
- Fire Log mit Events (falls vorhanden)

**Schritte:**
1. Tray-Icon → **Rules Engine** öffnen
2. Falls noch keine Regeln da: 1-2 Beispiel-Regeln erstellen:
   - "High Ping Alert" → Ping > 150ms → Play sound
   - "Packet Loss" → Loss > 2% → Send notification
3. Screenshot vom Fenster
4. Speichern als: `rules_engine.png`

**Empfohlene Größe:** 700×620 Pixel

---

### 3. **multi_target.png** — Multi-Target Manager
**Was zeigen:**
- Multi-Target Manager mit 3-4 Targets
- Verschiedene Status (Active, Timeout, etc.)
- Verschiedene Farben sichtbar

**Schritte:**
1. Tray-Icon → **Multi-Target Ping Manager**
2. Falls leer: "Load Presets" klicken (fügt 4 Targets hinzu)
3. Screenshot
4. Speichern als: `multi_target.png`

**Empfohlene Größe:** 620×540 Pixel

---

### 4. **optimization_manager.png** — Optimization Manager
**Was zeigen:**
- Optimization Manager Fenster
- Alle Kategorien sichtbar (Basis, Advanced, Competitive, etc.)
- Mindestens eine Kategorie aufgeklappt

**Schritte:**
1. Tray-Icon → **Optimization Manager**
2. Klicke auf "Basic Optimizations" um die Checkbox-Liste zu zeigen
3. Screenshot
4. Speichern als: `optimization_manager.png`

**Empfohlene Größe:** 600×840 Pixel

---

### 5. **stats_dashboard.png** — Statistics Dashboard
**Was zeigen:**
- Stats Dashboard mit echten Daten
- Session-Dauer, Avg Ping, Packet Loss, Stability Score

**Schritte:**
1. NetNinja mindestens 2 Minuten laufen lassen
2. Tray-Icon → **Statistics Dashboard**
3. Screenshot
4. Speichern als: `stats_dashboard.png`

**Empfohlene Größe:** 640×720 Pixel

---

### 6. **mini_hud.png** — Mini-HUD Overlay
**Was zeigen:**
- Mini-HUD Overlay (kompaktes Ping-Display)
- Auf dunklem Hintergrund (Desktop oder Spiel)

**Schritte:**
1. Tray-Icon → **Show Mini-HUD**
2. Screenshot vom Mini-HUD + etwas Hintergrund
3. Speichern als: `mini_hud.png`

**Empfohlene Größe:** 250×100 Pixel (klein!)

---

### 7. **heatmap.png** — Ping Heatmap
**Was zeigen:**
- Heatmap-Fenster mit Daten (idealerweise mehrere Tage)
- Farbige Zellen (grün = gut, rot = schlecht)

**Schritte:**
1. Tray-Icon → **Network Heatmap**
2. Falls leer: App über mehrere Stunden laufen lassen
3. Screenshot
4. Speichern als: `heatmap.png`

**Empfohlene Größe:** 900×540 Pixel

---

### 8. **overlay_mode.png** — Overlay Mode (Click-Through)
**Was zeigen:**
- NetNinja im Overlay-Modus über einem Spiel/Desktop
- Zeigt Transparenz und Click-Through

**Schritte:**
1. Vollbild-Anwendung oder Spiel öffnen
2. `Ctrl + Alt + O` drücken (Toggle Overlay)
3. Screenshot vom Gesamtbild (Spiel + Overlay)
4. Speichern als: `overlay_mode.png`

**Empfohlene Größe:** 1920×1080 Pixel (Fullscreen)

---

## 💾 Speicherort

Alle Screenshots kommen nach:
```
NetNinja/assets/screenshots/
├── main_hud.png
├── rules_engine.png
├── multi_target.png
├── optimization_manager.png
├── stats_dashboard.png
├── mini_hud.png
├── heatmap.png
└── overlay_mode.png
```

---

## 🖼️ Bildoptimierung (Optional)

Komprimiere die PNGs um Dateigröße zu reduzieren:
- Online: https://tinypng.com/
- Windows: Irfanview mit "Save for Web"
- Command Line: `pngquant --quality=80-95 *.png`

Ziel: Unter 200 KB pro Bild

---

## ✅ Checkliste

- [ ] `main_hud.png` — Haupt-HUD mit Graph
- [ ] `rules_engine.png` — Rules Engine
- [ ] `multi_target.png` — Multi-Target Manager
- [ ] `optimization_manager.png` — Optimization Manager
- [ ] `stats_dashboard.png` — Statistics Dashboard
- [ ] `mini_hud.png` — Mini-HUD
- [ ] `heatmap.png` — Ping Heatmap
- [ ] `overlay_mode.png` — Overlay Mode

Sobald du alle hast → weiter mit `README_FINAL.md`!
