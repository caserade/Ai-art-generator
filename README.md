# Mobile Game Maker

Standalone Android **Mobile Game Maker** built with **Flutter + Flame**.

Create, design, scan art, parse level sketches with OpenAI Vision, tune physics from gameplay descriptions, and play 2D platformers on-device with dual virtual/physical controls.

## AI Brain

| Mode | Behavior |
|------|----------|
| **Free Brain** | On-device designer — games, maps, physics via MCP tools with **\$0 API cost** |
| **OpenAI MCP** | GPT-4o function-calling loop over the same MCP tools + Vision maps |
| **Hybrid** | Free Brain always on; OpenAI when an API key is set |

MCP tools: `design_game`, `generate_level`, `tune_physics`, `suggest_art_pipeline`, `explain_mechanics`.

## Modules

| Folder | Responsibility |
|--------|----------------|
| `lib/engine` | Flame game loop, tile maps, player physics |
| `lib/ai_vision` | Free Brain, OpenAI MCP client, Vision/map & physics |
| `lib/controllers` | Dual control engine, HID remap, haptics |
| `lib/storage` | SQLite + WebP compressor + art scanner |
| `lib/ui` | Studio screens & control overlay |

## Features

1. **AI Brain** — chat to design whole games; Free Brain works offline; OpenAI MCP optional.
2. **Dual Control Engine** — virtual joysticks / D-Pad / A·B·X·Y with haptics; Xbox / DualSense / 8BitDo via `gamepads`.
3. **Art Scanner** — camera/gallery → background isolation → 4-frame WebP sprite + hitboxes.
4. **Map Parser** — sketch → OpenAI Vision tile grid (`0–4`) → Flame map (offline fallback).
5. **Physics Understanding** — text → gravity/speed/jump/accel/friction applied live.

## Setup

```bash
flutter pub get
flutter test
flutter run                 # device / emulator
flutter build apk --release # native phone APK
```

See [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md) to sideload onto your phone.

Open **Settings** to pick Free / Hybrid / OpenAI and optionally paste an API key.
