#!/usr/bin/env bash
# PC → Phone USB install (Linux/macOS)
# Usage: ./scripts/pc_to_phone.sh [--rebuild] [--universal] [--launch]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REBUILD=0
UNIVERSAL=0
LAUNCH=0
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=1 ;;
    --universal) UNIVERSAL=1 ;;
    --launch) LAUNCH=1 ;;
  esac
done

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found. Install Android platform-tools."
  exit 1
fi

echo "=== Connected devices ==="
adb devices -l
if ! adb devices | grep -qE $'\tdevice$'; then
  echo "No phone in 'device' mode. Enable USB debugging and accept the prompt."
  exit 1
fi

APK_ARM64="$ROOT/dist/GameMaker-android-arm64.apk"
APK_UNI="$ROOT/dist/GameMaker-android-release.apk"

if [[ "$REBUILD" -eq 1 ]]; then
  flutter pub get
  if [[ "$UNIVERSAL" -eq 1 ]]; then
    flutter build apk --release
    mkdir -p "$ROOT/dist"
    cp -f build/app/outputs/flutter-apk/app-release.apk "$APK_UNI"
  else
    flutter build apk --release --split-per-abi --target-platform android-arm64
    mkdir -p "$ROOT/dist"
    cp -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$APK_ARM64"
  fi
fi

APK="$APK_ARM64"
[[ "$UNIVERSAL" -eq 1 ]] && APK="$APK_UNI"
if [[ ! -f "$APK" ]]; then
  if [[ -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk ]]; then
    mkdir -p "$ROOT/dist"
    cp -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$APK_ARM64"
    APK="$APK_ARM64"
  else
    echo "APK missing. Run with --rebuild"
    exit 1
  fi
fi

echo "Installing $APK"
adb install -r "$APK"
echo "Installed Game Maker + Kaiju."
if [[ "$LAUNCH" -eq 1 ]]; then
  adb shell am start -n com.gamemaker.mobile_game_maker/.MainActivity || true
fi
