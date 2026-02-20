@echo off
REM ============================================================
REM NetNinja — Git Setup Wizard
REM Führt dich durch das erste Git-Setup
REM ============================================================

echo.
echo  ===================================================
echo   NetNinja — GitHub Setup Wizard
echo  ===================================================
echo.

REM ── Git installiert? ────────────────────────────────────────
where git >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [!] Git ist nicht installiert.
    echo.
    echo     Download: https://git-scm.com/download/win
    echo     Installiere Git und starte dieses Script erneut.
    echo.
    pause
    exit /b 1
)

echo [OK] Git gefunden: 
git --version
echo.

REM ── Git konfiguriert? ──────────────────────────────────────
git config --global user.name >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo [!] Git ist noch nicht konfiguriert.
    echo.
    set /p GIT_NAME="Dein Name (z.B. Max Mustermann): "
    set /p GIT_EMAIL="Deine E-Mail (z.B. max@example.com): "
    git config --global user.name "!GIT_NAME!"
    git config --global user.email "!GIT_EMAIL!"
    echo.
    echo [OK] Git konfiguriert.
    echo.
)

REM ── Bereits ein Git-Repo? ──────────────────────────────────
if exist ".git" (
    echo [!] Dieses Verzeichnis ist bereits ein Git-Repository.
    echo.
    echo     Falls du neu starten willst, loesche den .git Ordner manuell.
    echo.
    pause
    exit /b 0
)

REM ── Git Repository initialisieren ──────────────────────────
echo [*] Initialisiere Git-Repository...
git init
git add .
git commit -m "Initial release v5.0"
echo.
echo [OK] Lokales Repository erstellt!
echo.

REM ── GitHub-URL abfragen ────────────────────────────────────
echo ============================================================
echo  NAECHSTER SCHRITT:
echo ============================================================
echo.
echo  1. Gehe zu https://github.com/new
echo  2. Repository Name: NetNinja
echo  3. Public oder Private waehlen
echo  4. KEINE README, .gitignore oder Lizenz hinzufuegen!
echo  5. "Create repository" klicken
echo.
echo  6. GitHub zeigt dir jetzt eine URL wie:
echo     https://github.com/DeinUsername/NetNinja.git
echo.

set /p GITHUB_URL="Gib die Repository-URL ein: "

if "%GITHUB_URL%"=="" (
    echo.
    echo [!] Keine URL eingegeben. Abbruch.
    echo.
    echo     Fuehre manuell aus:
    echo     git remote add origin https://github.com/DeinUsername/NetNinja.git
    echo     git branch -M main
    echo     git push -u origin main
    echo.
    pause
    exit /b 1
)

REM ── Remote hinzufuegen und pushen ──────────────────────────
echo.
echo [*] Verbinde mit GitHub: %GITHUB_URL%
git remote add origin %GITHUB_URL%
git branch -M main

echo.
echo [*] Pushe Code nach GitHub...
echo     (Du wirst evtl. nach Username + Token gefragt)
echo.

git push -u origin main

if %ERRORLEVEL% EQU 0 (
    echo.
    echo  ===================================================
    echo   ERFOLGREICH!
    echo  ===================================================
    echo.
    echo   Dein Repository ist jetzt online!
    echo.
    echo   Naechste Schritte:
    echo   - Screenshots hinzufuegen (siehe GITHUB_SETUP.md)
    echo   - Release erstellen mit NetNinja.ps1 als Download
    echo.
) else (
    echo.
    echo [!] Push fehlgeschlagen.
    echo.
    echo     Moegliche Gruende:
    echo     - Falscher Username/Token
    echo     - Repo existiert nicht auf GitHub
    echo     - Keine Internetverbindung
    echo.
    echo     Versuche es manuell:
    echo     git push -u origin main
    echo.
)

pause
