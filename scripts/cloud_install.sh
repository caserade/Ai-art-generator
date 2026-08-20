#!/usr/bin/env bash
# Idempotent Cloud Agent install for Mobile Game Maker (Flutter).
# Dependency refresh only — do not put long-running servers or tests here.
set -euo pipefail

export PATH="${HOME}/flutter/bin:${PATH}"
export ANDROID_HOME="${ANDROID_HOME:-${HOME}/Android/Sdk}"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"
export PATH="${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter missing — expected at ~/flutter from environment snapshot"
  exit 1
fi

cd "$(dirname "$0")/.."
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get
echo "install complete"
