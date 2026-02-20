# Contributing to NetNinja

Thanks for your interest in improving NetNinja! 🥷

---

## 🐛 Reporting Bugs

Use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md). Include:
- Windows & PowerShell version
- Steps to reproduce
- Last 30 lines of `netninja_log_YYYYMMDD.txt`

---

## 💡 Suggesting Features

Use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md). Explain:
- What problem it solves
- Who would benefit
- How it should work

---

## 🔧 Submitting Code

### Setup
1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YourUsername/NetNinja.git
   cd NetNinja
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feature/my-feature
   ```

### Making Changes
- **Single file architecture:** All code goes in `src/NetNinja.ps1`
- **PowerShell 5.1 compatibility:** No `pwsh`-only features
- **Error handling:** Wrap risky operations in `try/catch`, use `finally` for disposal
- **Memory management:**
  - Always dispose `TcpClient`, `WebClient`, `Process`, `Font`, `Bitmap`
  - Reuse cached objects (`$script:Fonts.*`, `$script:gfxCache.*`)
  - Use `[System.Collections.Generic.List[T]]` instead of `+=` on arrays
- **UI best practices:**
  - Add `KeyPreview = $true` and Escape key handlers to all forms
  - Use `$script:C.*` color palette for theming
  - Add tooltips for non-obvious controls
- **Logging:** Use `Write-Log` with severity: `INFO`, `WARNING`, `ERROR`, `SUCCESS`

### Testing
Run the unit tests:
```powershell
.\tests\Test-Functions.ps1
```

Add new tests for any pure logic functions.

### Code Style
- **Indentation:** 4 spaces (no tabs)
- **Line length:** Try to keep under 120 characters
- **Naming:**
  - Functions: `Verb-Noun` (e.g. `Show-StatsDashboard`)
  - Variables: `$camelCase` for locals, `$script:camelCase` for script-scope
  - Constants: `$UPPER_CASE` (e.g. `$CONFIG`)
- **Comments:**
  - Use `# ── Section ───────────────` for major sections
  - Inline comments for non-obvious logic
  - No commented-out code in commits

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: Add webhook cooldown per severity level
fix: Memory leak in TcpClient disposal
docs: Update CONFIGURATION.md with new fields
style: Reformat Get-PingColor with consistent spacing
refactor: Extract DNS validation to separate function
test: Add unit tests for jitter calculation
```

### Pull Request
1. Push your branch:
   ```bash
   git push origin feature/my-feature
   ```
2. Open a Pull Request on GitHub
3. Title: Short summary (e.g. "Add webhook cooldown per severity")
4. Description:
   - What changed
   - Why it's needed
   - How to test it
5. Link to related issues if applicable

---

## 📁 Project Structure

```
NetNinja/
├── src/
│   └── NetNinja.ps1          ← All code (single file)
├── config/
│   └── default_config.json   ← Config template
├── scripts/
│   ├── Install.ps1           ← Installer
│   ├── Uninstall.ps1         ← Uninstaller
│   └── Setup-Git.bat         ← Git setup wizard
├── docs/
│   ├── CONFIGURATION.md      ← Config reference
│   ├── TROUBLESHOOTING.md    ← Common issues
│   ├── CONTRIBUTING.md       ← This file
│   └── GITHUB_SETUP.md       ← GitHub upload guide
├── tests/
│   └── Test-Functions.ps1    ← Unit tests
└── assets/
    ├── icons/                ← App icons
    └── screenshots/          ← UI screenshots
```

---

## 🔍 Code Review Checklist

Before submitting:
- [ ] Tested on Windows 10 and/or 11
- [ ] PowerShell 5.1 compatible (no `pwsh`-only syntax)
- [ ] All resources disposed (no memory leaks)
- [ ] Error handling added (`try/catch/finally`)
- [ ] Unit tests pass
- [ ] Comments added for complex logic
- [ ] No commented-out code
- [ ] Follows code style guidelines
- [ ] Commit messages are clear and descriptive

---

## ❓ Questions?

Open a [Discussion](https://github.com/YourUsername/NetNinja/discussions) or ping in the PR.
