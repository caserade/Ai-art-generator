# Run Game Maker on your PC

Native Flutter desktop targets are enabled for **Windows** and **Linux**.

**New to this repo?** Start with [`START_HERE_PC.md`](START_HERE_PC.md).

## Windows (recommended)

### One script

```powershell
.\scripts\setup_and_run_pc.ps1
```

Double-click: `scripts\setup_and_run_pc.bat`

| Flag | Effect |
|------|--------|
| `-Release` | Build + launch `mobile_game_maker.exe` |
| `-SkipRun` | Install deps / enable Windows only |
| `-BuildPhoneApk` | Also refresh `dist\GameMaker-android-arm64.apk` |
| `-OpenAiKey sk-...` | Seed OpenAI into app Settings |

### Manual

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows) + [Visual Studio 2022](https://visualstudio.microsoft.com/) with **Desktop development with C++**
2. Pull this branch and run:

```powershell
git pull origin cursor/mobile-game-maker-3d76
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
```

Release `.exe`:

```powershell
flutter build windows --release
# → build\windows\x64\runner\Release\mobile_game_maker.exe
```

Optional OpenAI:

```powershell
flutter run -d windows --dart-define=OPENAI_API_KEY=sk-your-key
```

Free Brain works with no key.

### PC play controls

| Input | Action |
|-------|--------|
| `A` `D` / ← → | Move |
| `W` / ↑ / `Space` / `J` `Z` | Jump |
| `S` / ↓ | Duck / down |
| `K` `X` / `L` `C` / `I` `V` | B / X / Y |
| USB gamepad | Same as phone HID |
| HUD gamepad icon | Toggle on-screen virtual pads (hidden by default on desktop) |

Window opens at **1280×800** (min 960×640), titled **Game Maker — Kaiju**.

## Linux desktop

```bash
flutter pub get
flutter run -d linux
flutter build linux --release
```

## Phone from this PC

See [`INSTALL_PC_PHONE.md`](INSTALL_PC_PHONE.md) — plug USB and run `scripts\pc_to_phone.bat`.

## OpenAI MCP in Cursor (PC)

1. Cursor Desktop → **Settings → MCP → Composio → Connect**
2. Optionally set `OPENAI_API_KEY` in Cloud secrets / shell env
3. App Settings: Free / Hybrid / OpenAI
