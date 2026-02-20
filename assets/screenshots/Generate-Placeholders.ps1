#Requires -Version 5.1
<#
.SYNOPSIS
    Creates placeholder images for screenshots (temporary until real ones are ready).
.DESCRIPTION
    Generates 8 placeholder PNGs with text overlays showing expected dimensions.
    Requires .NET Framework (included in Windows).
#>

Add-Type -AssemblyName System.Drawing

$screenshots = @(
    @{Name="main_hud.png";              Width=800;  Height=600;  Text="Main HUD`nReal-time ping graph"},
    @{Name="rules_engine.png";          Width=700;  Height=620;  Text="Rules Engine`nAutomated actions"},
    @{Name="multi_target.png";          Width=620;  Height=540;  Text="Multi-Target Ping`nMonitor up to 8 targets"},
    @{Name="optimization_manager.png";  Width=600;  Height=840;  Text="Optimization Manager`n19+ network tweaks"},
    @{Name="stats_dashboard.png";       Width=640;  Height=720;  Text="Statistics Dashboard`nSession analytics"},
    @{Name="mini_hud.png";              Width=250;  Height=100;  Text="Mini-HUD`nCompact overlay"},
    @{Name="heatmap.png";               Width=900;  Height=540;  Text="Network Heatmap`nPing patterns by day/hour"},
    @{Name="overlay_mode.png";          Width=1920; Height=1080; Text="Overlay Mode`nClick-through fullscreen"}
)

foreach ($img in $screenshots) {
    Write-Host "Creating $($img.Name) ($($img.Width)×$($img.Height))..." -ForegroundColor Cyan
    
    $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    
    # Hintergrund: Dunkles Grau
    $bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(26, 26, 30))
    $g.FillRectangle($bgBrush, 0, 0, $img.Width, $img.Height)
    $bgBrush.Dispose()
    
    # Anti-Aliasing
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    
    # Text 1: "NetNinja v5.0"
    $font1 = New-Object System.Drawing.Font("Segoe UI", 36, [System.Drawing.FontStyle]::Bold)
    $brush1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 150, 215))
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    
    $y1 = [int]($img.Height * 0.35)
    $rect1 = New-Object System.Drawing.RectangleF(0, $y1 - 40, $img.Width, 80)
    $g.DrawString("NetNinja v5.0", $font1, $brush1, $rect1, $sf)
    $font1.Dispose()
    $brush1.Dispose()
    
    # Text 2: Screenshot-Name
    $font2 = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Regular)
    $brush2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 200, 220))
    $y2 = [int]($img.Height * 0.5)
    $rect2 = New-Object System.Drawing.RectangleF(0, $y2, $img.Width, 100)
    $g.DrawString($img.Text, $font2, $brush2, $rect2, $sf)
    $font2.Dispose()
    $brush2.Dispose()
    
    # Text 3: Dimensionen
    $font3 = New-Object System.Drawing.Font("Consolas", 14, [System.Drawing.FontStyle]::Regular)
    $brush3 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(96, 96, 120))
    $y3 = [int]($img.Height * 0.7)
    $rect3 = New-Object System.Drawing.RectangleF(0, $y3, $img.Width, 40)
    $g.DrawString("$($img.Width)×$($img.Height) — Placeholder", $font3, $brush3, $rect3, $sf)
    $font3.Dispose()
    $brush3.Dispose()
    
    $sf.Dispose()
    
    # Rahmen
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(42, 42, 50), 4)
    $g.DrawRectangle($pen, 0, 0, $img.Width - 1, $img.Height - 1)
    $pen.Dispose()
    
    $g.Dispose()
    
    # Speichern
    $bmp.Save($img.Name, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

Write-Host "`n✅ Alle 8 Platzhalter erstellt!" -ForegroundColor Green
Write-Host "   Ersetze sie mit echten Screenshots (siehe ..\docs\SCREENSHOTS.md)" -ForegroundColor Yellow
