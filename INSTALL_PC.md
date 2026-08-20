# Run Game Maker on your PC

Native Flutter desktop targets are enabled for **Windows** and **Linux**.

## Windows (your PC)

1. Install [Flutter](https://docs.flutter.dev/get-started/install/windows) + [Visual Studio 2022](https://visualstudio.microsoft.com/) with **Desktop development with C++**
2. Clone / pull this branch:

```bash
git pull origin cursor/mobile-game-maker-3d76
cd Ai-art-generator   # or your local folder
flutter pub get
flutter run -d windows
```

Release `.exe` build:

```bash
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\mobile_game_maker.exe`

Optional OpenAI cloud brain:

```bash
flutter run -d windows --dart-define=OPENAI_API_KEY=sk-your-key
```

Free Brain works with no key.

## Linux desktop

```bash
flutter pub get
flutter run -d linux
flutter build linux --release
```

## Android phone (APK)

See [`INSTALL_ANDROID.md`](INSTALL_ANDROID.md). Prefer `GameMaker-android-arm64.apk` for modern phones.

## OpenAI MCP in Cursor (PC)

1. Cursor Desktop → **Settings → MCP → Composio → Connect**
2. Optionally connect OpenAI / add `OPENAI_API_KEY` in Cloud secrets
3. Reply in the agent chat that Composio is connected

Then the agent can use OpenAI MCP tools; the app itself already has Free Brain + optional OpenAI key in **Settings**.
