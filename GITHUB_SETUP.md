# GitHub Setup — Schritt für Schritt

Diese Anleitung zeigt dir, wie du NetNinja auf GitHub veröffentlichst.

---

## 📋 Voraussetzungen

1. **GitHub-Account** erstellen (falls noch nicht vorhanden):
   - Gehe zu https://github.com/signup
   - E-Mail, Passwort, Username wählen

2. **Git installieren**:
   - Download: https://git-scm.com/download/win
   - Installation: Alle Standardeinstellungen OK → "Next" durchklicken
   - **Wichtig:** Bei "Adjusting your PATH environment" → "Git from the command line and also from 3rd-party software" wählen

3. **Git konfigurieren** (einmalig):
   ```bash
   git config --global user.name "Dein Name"
   git config --global user.email "deine@email.com"
   ```
   *(Nutze die E-Mail-Adresse von deinem GitHub-Account)*

---

## 🚀 Methode 1: Via GitHub Desktop (EINFACH)

### Schritt 1: GitHub Desktop installieren
- Download: https://desktop.github.com/
- Installieren und mit deinem GitHub-Account anmelden

### Schritt 2: ZIP entpacken
- Entpacke `NetNinja-v5.0-github.zip` z.B. nach `C:\Users\DeinName\Documents\NetNinja`

### Schritt 3: Repository erstellen
1. In GitHub Desktop: **File → Add Local Repository**
2. Wähle den `NetNinja`-Ordner
3. Es erscheint: "This directory does not appear to be a Git repository"
4. Klicke **"create a repository"**
5. Name: `NetNinja`
6. Description: `Network Latency Monitor & Optimizer for Windows`
7. ✅ Keep this code private (oder public — deine Wahl)
8. **Create Repository**

### Schritt 4: Ersten Commit erstellen
1. In der linken Sidebar siehst du alle Dateien (sollten bereits alle ✅ sein)
2. Unten links bei "Summary": `Initial release v5.0`
3. (Optional) Description: `Complete rewrite with 49 bug fixes`
4. **Commit to main**

### Schritt 5: Auf GitHub veröffentlichen
1. Klicke oben **"Publish repository"**
2. ✅ Keep this code private (oder ❌ für public)
3. **Publish repository**
4. Fertig! 🎉

Dein Repository ist jetzt online unter:
`https://github.com/DeinUsername/NetNinja`

---

## 🔧 Methode 2: Via Command Line (FORTGESCHRITTEN)

### Schritt 1: ZIP entpacken
```bash
cd C:\Users\DeinName\Documents
unzip NetNinja-v5.0-github.zip
cd NetNinja
```

### Schritt 2: Git Repository initialisieren
```bash
git init
git add .
git commit -m "Initial release v5.0"
```

### Schritt 3: Auf GitHub ein leeres Repository erstellen
1. Gehe zu https://github.com/new
2. Repository name: `NetNinja`
3. Description: `Network Latency Monitor & Optimizer for Windows`
4. ✅ Public (oder Private)
5. ❌ **NICHT** "Add a README file" anklicken (du hast schon eins!)
6. ❌ **NICHT** .gitignore oder Lizenz hinzufügen (ebenfalls schon vorhanden)
7. **Create repository**

### Schritt 4: Lokales Repo mit GitHub verbinden
GitHub zeigt dir jetzt ein paar Befehle. Kopiere die unter **"…or push an existing repository from the command line"**:

```bash
git remote add origin https://github.com/DeinUsername/NetNinja.git
git branch -M main
git push -u origin main
```

**Falls Passwort-Abfrage:**
- GitHub erlaubt keine Passwörter mehr → du brauchst einen **Personal Access Token**
- Gehe zu: https://github.com/settings/tokens
- **Generate new token (classic)**
- Scopes: ✅ `repo` (Full control of private repositories)
- Token kopieren → als Passwort eingeben

### Schritt 5: Fertig!
Dein Repo ist jetzt online: `https://github.com/DeinUsername/NetNinja`

---

## 📸 Screenshots hinzufügen (empfohlen!)

Screenshots machen dein Projekt viel attraktiver. So fügst du sie hinzu:

### 1. Screenshots erstellen
- Starte NetNinja
- Drücke `Win + Shift + S` (Windows Snipping Tool)
- Erstelle Screenshots von:
  - Haupt-HUD mit Graph
  - Rules Engine
  - Optimization Manager
  - Multi-Target Manager
  - Mini-HUD
  - Stats Dashboard

### 2. Screenshots speichern
```
NetNinja/assets/screenshots/
├── main_hud.png
├── rules_engine.png
├── optimization_manager.png
├── multi_target.png
├── mini_hud.png
└── stats_dashboard.png
```

### 3. README.md erweitern
Am Anfang nach der ersten Überschrift einfügen:

```markdown
## 📸 Screenshots

### Main HUD
![Main HUD](assets/screenshots/main_hud.png)

### Rules Engine
![Rules Engine](assets/screenshots/rules_engine.png)

### Multi-Target Ping
![Multi-Target](assets/screenshots/multi_target.png)
```

### 4. Commit & Push
```bash
git add assets/screenshots/*.png
git add README.md
git commit -m "Add screenshots"
git push
```

---

## 🏷️ Release erstellen (Version v5.0)

Ein Release macht es einfach, die `.ps1`-Datei direkt herunterzuladen:

### Via GitHub Web
1. Gehe zu deinem Repository
2. Rechts: **Releases** → **Create a new release**
3. **Choose a tag:** `v5.0.0` → **Create new tag**
4. **Release title:** `NetNinja v5.0 — Stability & Features`
5. **Description:**
   ```markdown
   ## What's New in v5.0
   - Rules Engine with 9 action types
   - Multi-Target Ping (up to 8 targets)
   - Auto-Diagnosis (buffer bloat, ISP congestion, WiFi interference)
   - Discord/Slack/Teams webhooks
   - Session History (last 50 sessions)
   - 49 bug fixes (see CHANGELOG.md)
   
   ## Download
   Just download `NetNinja.ps1` and run it (requires PowerShell 5.1+ and Admin rights).
   ```
6. **Attach binaries:**
   - Klicke **"Attach binaries by dropping them here"**
   - Ziehe `NETNINJA_v5.0.ps1` rein (aus dem outputs-Ordner)
   - Benenne um in: `NetNinja.ps1` (Dateiname im Upload-Bereich)
7. **Publish release**

Jetzt können Leute direkt die `.ps1` downloaden von:
`https://github.com/DeinUsername/NetNinja/releases/latest`

---

## 🔄 Änderungen pushen (später)

Nach Änderungen am Code:

### Via GitHub Desktop
1. Dateien speichern
2. GitHub Desktop zeigt Änderungen automatisch
3. Commit-Message schreiben → **Commit to main**
4. **Push origin** (oben rechts)

### Via Command Line
```bash
git add .
git commit -m "Fix: Memory leak in TcpClient disposal"
git push
```

---

## 📚 Weitere Ressourcen

- **GitHub Docs:** https://docs.github.com/en/get-started
- **Git Basics:** https://git-scm.com/book/en/v2/Getting-Started-Git-Basics
- **Markdown Guide:** https://www.markdownguide.org/basic-syntax/

---

## ❓ Häufige Probleme

### "fatal: not a git repository"
→ Du bist im falschen Ordner. `cd` in den NetNinja-Ordner.

### "Permission denied (publickey)"
→ Nutze HTTPS statt SSH: `git remote set-url origin https://github.com/...`

### "Updates were rejected because the remote contains work"
→ Jemand hat direkt auf GitHub editiert:
```bash
git pull --rebase
git push
```

### Merge-Konflikt
→ GitHub Desktop zeigt an, welche Dateien betroffen sind. Öffne sie in einem Editor, such nach `<<<<<<<` und lösche die Marker manuell.

---

**Fertig!** 🎉 Dein Projekt ist jetzt auf GitHub und für alle sichtbar (oder privat, je nach Einstellung).
