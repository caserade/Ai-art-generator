# Install Game Maker on your Android phone

This repo builds a **native Android app** (Flutter → APK), not a website wrapper.

## Quick install (APK)

1. Build (on a machine with Flutter + Android SDK):

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

2. Copy the APK to your phone:

`build/app/outputs/flutter-apk/app-release.apk`

3. On your phone:
   - Settings → allow **Install unknown apps** for Files / Chrome
   - Open the APK → **Install**
   - Launch **Game Maker**

Package id: `com.gamemaker.mobile_game_maker`  
Min Android: **7.0 (API 24)** · Target: **API 35**

## USB install (developer mode)

```bash
flutter devices
flutter install --release
# or
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## App bundle (Play Store later)

```bash
flutter build appbundle --release
```

Replace the debug signing config in `android/app/build.gradle.kts` with your upload keystore before publishing.
