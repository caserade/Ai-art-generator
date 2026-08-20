# Install Game Maker on your Android phone

Native Flutter Android app with **Kaiju**, your always-on companion.

## Download & install

1. Get the APK:
   - **Most phones (recommended):** `GameMaker-android-arm64.apk` (~23MB)
   - **Universal:** `GameMaker-android-release.apk` (~40MB)
2. On your phone: Settings → allow **Install unknown apps** for Files / Chrome
3. Open the APK → **Install** → launch **Game Maker**

Kaiju opens automatically on first launch (floating companion button bottom-right).

Package: `com.gamemaker.mobile_game_maker`  
Min Android: **7.0 (API 24)** · Version **1.1.0+3**

## USB install

```bash
adb install -r GameMaker-android-arm64.apk
# or
flutter install --release
```

## Build yourself

```bash
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
