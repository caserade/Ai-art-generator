# Mobile Game Maker

Standalone Android **Mobile Game Maker** built with **Flutter + Flame**.

Create, design, scan art, parse level sketches with OpenAI Vision, tune physics from gameplay descriptions, and play 2D platformers on-device with dual virtual/physical controls.

## Modules

| Folder | Responsibility |
|--------|----------------|
| `lib/engine` | Flame game loop, tile maps, player physics |
| `lib/ai_vision` | OpenAI GPT-4o Vision/map & physics clients + offline presets |
| `lib/controllers` | Dual control engine, HID remap, haptics |
| `lib/storage` | SQLite (Isar-style API) + WebP compressor + art scanner |
| `lib/ui` | Studio screens & control overlay |

## Features

1. **Dual Control Engine** — virtual joysticks, D-Pad, A/B/X/Y with haptics; auto-map Xbox / DualSense / 8BitDo via `gamepads`; remapping UI.
2. **Art Scanner** — camera/gallery → local background isolation → 4-frame sprite sheet (Idle/Walk/Jump) → WebP @ 64/128 → auto hitboxes.
3. **Map Parser** — sketch → OpenAI Vision JSON tile grid (`0–4`) → playable `GameTileMapComponent` (offline preset fallback).
4. **Physics Understanding** — text/notes → `gravity_y`, `move_speed`, `jump_velocity`, `acceleration`, `friction` applied live to Flame player.

## Setup

```bash
flutter pub get
flutter test
flutter run   # Android device/emulator, or Chrome for UI smoke
```

Open **Settings** and paste your OpenAI API key for Vision/physics. Without a key, offline presets still work.

## Architecture notes

- AI calls are async with loading overlays and offline fallbacks.
- Cache folders are pruned on launch and from Settings.
- Target asset format is WebP to keep installs lean (&lt;100MB class).
