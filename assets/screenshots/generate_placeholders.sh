#!/bin/bash
# Erstellt Platzhalter-Bilder für Screenshots (benötigt ImageMagick)

# Prüfe ob convert (ImageMagick) installiert ist
if ! command -v convert &> /dev/null; then
    echo "ImageMagick nicht gefunden. Installiere mit:"
    echo "  Ubuntu/Debian: sudo apt-get install imagemagick"
    echo "  macOS: brew install imagemagick"
    echo "  Windows: https://imagemagick.org/script/download.php"
    exit 1
fi

# Screenshot-Definitionen: Name, Breite, Höhe, Text
declare -a screenshots=(
    "main_hud.png|800|600|Main HUD\nReal-time ping graph"
    "rules_engine.png|700|620|Rules Engine\nAutomated actions"
    "multi_target.png|620|540|Multi-Target\nMonitor 8 targets"
    "optimization_manager.png|600|840|Optimization Manager\n19+ network tweaks"
    "stats_dashboard.png|640|720|Statistics Dashboard\nSession analytics"
    "mini_hud.png|250|100|Mini-HUD\nCompact overlay"
    "heatmap.png|900|540|Network Heatmap\nPing patterns"
    "overlay_mode.png|1920|1080|Overlay Mode\nClick-through"
)

for item in "${screenshots[@]}"; do
    IFS='|' read -r name width height text <<< "$item"
    
    echo "Creating $name (${width}×${height})"
    
    convert -size ${width}x${height} \
        xc:'#1a1a1e' \
        -gravity center \
        -pointsize 48 -fill '#0096d7' -annotate +0-40 "NetNinja v5.0" \
        -pointsize 32 -fill '#c8c8dc' -annotate +0+20 "$text" \
        -pointsize 18 -fill '#606078' -annotate +0+80 "${width}×${height} — Placeholder" \
        -bordercolor '#2a2a32' -border 2 \
        "$name"
done

echo ""
echo "✅ Alle 8 Platzhalter erstellt!"
echo "   Ersetze sie mit echten Screenshots (siehe ../docs/SCREENSHOTS.md)"
