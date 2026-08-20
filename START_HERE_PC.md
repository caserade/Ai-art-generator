# START HERE — Game Maker on your PC (then phone)

This repo is a **complete Flutter app**. On Windows you run it as a native `.exe`; then install the same project on your phone with one USB script.

## 1) PC (native)

### Prerequisites (once)

1. [Flutter SDK](https://docs.flutter.dev/get-started/install/windows) (stable)
2. [Visual Studio 2022](https://visualstudio.microsoft.com/) with workload **Desktop development with C++**
3. Git

### Run

From the repo root in PowerShell:

```powershell
.\scripts\setup_and_run_pc.ps1
```

Or double-click `scripts\setup_and_run_pc.bat`.

| Goal | Command |
|------|---------|
| Dev window (hot reload) | `.\scripts\setup_and_run_pc.ps1` |
| Release `.exe` | `.\scripts\setup_and_run_pc.ps1 -Release` |
| Setup only | `.\scripts\setup_and_run_pc.ps1 -SkipRun` |
| Also build phone APK | `.\scripts\setup_and_run_pc.ps1 -BuildPhoneApk` |
| Seed OpenAI key | `$env:OPENAI_API_KEY="sk-..."; .\scripts\setup_and_run_pc.ps1` |

**PC play controls:** `WASD` / arrows to move · `Space` / `W` to jump · `J/K/L/I` (or `Z/X/C/V`) for A/B/X/Y · USB gamepad works too. On-screen pads are hidden on desktop (toggle from the play HUD).

Release binary path:

`build\windows\x64\runner\Release\mobile_game_maker.exe`

## 2) Port to phone (same PC)

1. Enable **Developer options → USB debugging** on the phone
2. Plug in USB (File Transfer / MTP)
3. Either use the APK already in `dist\GameMaker-android-arm64.apk`, or rebuild:

```powershell
.\scripts\setup_and_run_pc.ps1 -SkipRun -BuildPhoneApk
.\scripts\pc_to_phone.bat
```

Details: [`INSTALL_PC_PHONE.md`](INSTALL_PC_PHONE.md)

## 3) What you get

- Flame 2D platformer editor + play
- Free Brain (\$0) + optional OpenAI Vision / MCP tools
- Kaiju companion coach
- Art scanner, map parser, physics tuner
- Dual controls (keyboard on PC, touch + HID on phone)

More: [`INSTALL_PC.md`](INSTALL_PC.md) · [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md) · [`README.md`](README.md)
