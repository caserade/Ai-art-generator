# Mobile Game Maker

Standalone **PC + Phone Game Maker** built with **Flutter + Flame**.

Create, design, scan art, parse level sketches with OpenAI Vision, tune physics, and play 2D platformers on **Windows/Linux PC** first, then install the same build on **Android**.

## Start here (PC)

→ **[`START_HERE_PC.md`](START_HERE_PC.md)** — one script sets up Flutter Windows, runs the native app, and can build the phone APK.

```powershell
.\scripts\setup_and_run_pc.ps1
```

## AI Brain

| Mode | Behavior |
|------|----------|
| **Free Brain** | On-device designer — games, maps, physics via MCP tools with **\$0 API cost** |
| **OpenAI MCP** | GPT-4o function-calling loop over the same MCP tools + Vision maps |
| **Hybrid** | Free Brain always on; OpenAI when an API key is set |

MCP tools: `design_game`, `generate_level`, `tune_physics`, `suggest_art_pipeline`, `explain_mechanics`.

## Platforms

| Target | Guide |
|--------|--------|
| **Windows PC (native)** | [`START_HERE_PC.md`](START_HERE_PC.md) / [`INSTALL_PC.md`](INSTALL_PC.md) |
| **PC → phone (USB)** | [`INSTALL_PC_PHONE.md`](INSTALL_PC_PHONE.md) — `scripts\pc_to_phone.bat` |
| **Android phone** | [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md) — APK sideload |

## Modules

| Folder | Responsibility |
|--------|----------------|
| `lib/engine` | Flame game loop, tile maps, player physics |
| `lib/ai_vision` | Free Brain, OpenAI MCP client, Vision/map & physics |
| `lib/controllers` | Dual control engine (keyboard / touch / HID), remap |
| `lib/platform` | Desktop window bootstrap |
| `lib/storage` | SQLite + WebP compressor + art scanner |
| `lib/ui` | Studio screens & control overlay |

## Features

1. **Native PC window** — 1280×800 Game Maker desktop app; WASD + Space to play.
2. **AI Brain** — chat to design whole games; Free Brain works offline; OpenAI optional.
3. **Dual Control Engine** — keyboard on PC; virtual joysticks / D-Pad / A·B·X·Y on phone; Xbox / DualSense / 8BitDo via `gamepads`.
4. **Art Scanner** — camera/gallery → background isolation → 4-frame WebP sprite + hitboxes.
5. **Map Parser** — sketch → OpenAI Vision tile grid → Flame map (offline fallback).
6. **Physics Understanding** — text → gravity/speed/jump/accel/friction applied live.
7. **Kaiju companion** — context tips + chat → design/play.

## Setup

```powershell
.\scripts\setup_and_run_pc.ps1              # PC native
.\scripts\setup_and_run_pc.ps1 -BuildPhoneApk
.\scripts\pc_to_phone.bat                   # USB install to phone
```

```bash
flutter pub get
flutter test
flutter run -d windows          # PC
flutter run                     # phone / emulator
flutter build apk --release     # Android APK
```

Open **Settings** to pick Free / Hybrid / OpenAI and optionally paste an API key.
