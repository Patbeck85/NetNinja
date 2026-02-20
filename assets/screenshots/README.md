# Placeholder Images — Temporary until real screenshots are ready

Diese Datei erklärt die Platzhalter-Bilder im `assets/screenshots/` Ordner.

## Was sind Platzhalter?

Die 8 `.png`-Dateien sind **temporäre Platzhalter** mit Text-Overlays:
- `main_hud.png` → "Main HUD — 800×600"
- `rules_engine.png` → "Rules Engine — 700×620"
- etc.

Sie zeigen die **korrekte Dateigröße** und **Position** im README.

## Wie ersetze ich sie?

1. **Screenshots machen** (siehe `docs/SCREENSHOTS.md`)
2. **Dateien überschreiben** mit echten Screenshots
3. **Gleiche Dateinamen beibehalten**:
   ```
   main_hud.png → main_hud.png (echtes Bild)
   ```
4. **Commit + Push**:
   ```bash
   git add assets/screenshots/*.png
   git commit -m "Add real screenshots"
   git push
   ```

GitHub zeigt dann automatisch die echten Bilder im README!

## Warum Platzhalter?

- **README funktioniert sofort** (keine kaputten Bild-Links)
- **Zeigt Layout-Preview** für Contributors
- **Easy to replace** — einfach Dateien überschreiben
