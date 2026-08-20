# PC → Phone USB install (Windows)
#
# Prerequisites (one-time on your PC):
# 1. Phone plugged in via USB
# 2. Phone: Developer options → USB debugging ON
# 3. Accept "Allow USB debugging" prompt on phone
# 4. Install Android platform-tools (adb) OR Flutter SDK
#
# Usage (from repo root in PowerShell):
#   .\scripts\pc_to_phone.ps1
#   .\scripts\pc_to_phone.ps1 -Rebuild
#   .\scripts\pc_to_phone.ps1 -Universal

param(
  [switch]$Rebuild,
  [switch]$Universal,
  [switch]$Launch
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Find-Adb {
  $candidates = @(
    (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
    "C:\Android\platform-tools\adb.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }
  if ($candidates.Count -eq 0) {
    throw "adb not found. Install Android platform-tools or Flutter, then reopen PowerShell."
  }
  return $candidates[0]
}

$Adb = Find-Adb
Write-Host "Using adb: $Adb"

Write-Host "`n=== Connected devices ==="
& $Adb devices -l
$devices = & $Adb devices | Select-String -Pattern "`tdevice$" 
if (-not $devices) {
  Write-Host @"

No phone detected in 'device' mode.
Checklist:
  - USB cable data-capable (not charge-only)
  - USB debugging enabled
  - Unlock phone and tap Allow for this computer
  - Try: adb kill-server; adb start-server; adb devices

"@
  exit 1
}

$ApkArm64 = Join-Path $Root "dist\GameMaker-android-arm64.apk"
$ApkUni = Join-Path $Root "dist\GameMaker-android-release.apk"
$BuildArm64 = Join-Path $Root "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
$BuildUni = Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk"

if ($Rebuild) {
  Write-Host "`nBuilding release APK..."
  flutter pub get
  if ($Universal) {
    flutter build apk --release
  } else {
    flutter build apk --release --split-per-abi --target-platform android-arm64
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $Root "dist") | Out-Null
  if (Test-Path $BuildArm64) { Copy-Item $BuildArm64 $ApkArm64 -Force }
  if (Test-Path $BuildUni) { Copy-Item $BuildUni $ApkUni -Force }
}

$Apk = if ($Universal) { $ApkUni } else { $ApkArm64 }
if (-not (Test-Path $Apk)) {
  if (Test-Path $BuildArm64) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "dist") | Out-Null
    Copy-Item $BuildArm64 $ApkArm64 -Force
    $Apk = $ApkArm64
  } elseif (Test-Path $BuildUni) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "dist") | Out-Null
    Copy-Item $BuildUni $ApkUni -Force
    $Apk = $ApkUni
  } else {
    throw "APK not found. Run with -Rebuild or place APK in dist\"
  }
}

Write-Host "`nInstalling: $Apk"
& $Adb install -r $Apk
if ($LASTEXITCODE -ne 0) {
  Write-Host "Install failed. If you see signatures conflict, uninstall old build first:"
  Write-Host "  adb uninstall com.gamemaker.mobile_game_maker"
  Write-Host "  adb uninstall com.gamemaker.mobile_game_maker.debug"
  exit $LASTEXITCODE
}

Write-Host "`nInstalled Game Maker + Kaiju on your phone."
if ($Launch) {
  & $Adb shell am start -n com.gamemaker.mobile_game_maker/.MainActivity
}
Write-Host "Done. Look for Kaiju (companion) on first launch."
