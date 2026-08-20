# One-click PC setup → run Game Maker natively on Windows
#
# First time on a fresh clone:
#   .\scripts\setup_and_run_pc.ps1
#
# Options:
#   .\scripts\setup_and_run_pc.ps1 -Release          # build + launch .exe
#   .\scripts\setup_and_run_pc.ps1 -SkipRun          # only install deps / enable windows
#   .\scripts\setup_and_run_pc.ps1 -BuildPhoneApk    # also refresh dist APK for USB install
#   .\scripts\setup_and_run_pc.ps1 -OpenAiKey sk-...

param(
  [switch]$Release,
  [switch]$SkipRun,
  [switch]$BuildPhoneApk,
  [string]$OpenAiKey = $env:OPENAI_API_KEY
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Require-Command([string]$Name, [string]$Hint) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Missing '$Name'. $Hint"
  }
}

Write-Host "==> Game Maker — PC native bootstrap" -ForegroundColor Cyan
Write-Host "    Root: $Root"

Require-Command "flutter" "Install Flutter: https://docs.flutter.dev/get-started/install/windows"
Require-Command "git" "Install Git for Windows."

Write-Host "==> flutter doctor (summary)" -ForegroundColor Cyan
flutter doctor -v | Select-String -Pattern "Flutter|Windows|Chrome|Android|Visual Studio|connected" | ForEach-Object { $_.Line }

Write-Host "==> Enable Windows desktop" -ForegroundColor Cyan
flutter config --enable-windows-desktop | Out-Null

Write-Host "==> flutter pub get" -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

$define = @()
if ($OpenAiKey) {
  $define += "--dart-define=OPENAI_API_KEY=$OpenAiKey"
  Write-Host "==> OpenAI key will be seeded into Settings" -ForegroundColor DarkGray
} else {
  Write-Host "==> No OPENAI_API_KEY — Free Brain works offline" -ForegroundColor DarkGray
}

if ($BuildPhoneApk) {
  Write-Host "==> Building phone APK (arm64) → dist\" -ForegroundColor Cyan
  Require-Command "flutter" ""
  flutter build apk --release --target-platform=android-arm64 @define
  if ($LASTEXITCODE -ne 0) { throw "APK build failed" }
  New-Item -ItemType Directory -Force -Path (Join-Path $Root "dist") | Out-Null
  Copy-Item -Force `
    (Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk") `
    (Join-Path $Root "dist\GameMaker-android-arm64.apk")
  Write-Host "    APK ready: dist\GameMaker-android-arm64.apk"
  Write-Host "    Plug phone in USB (File Transfer) then run: .\scripts\pc_to_phone.bat"
}

if ($SkipRun) {
  Write-Host "==> SkipRun set — setup complete. Next: .\scripts\run_on_pc.ps1" -ForegroundColor Green
  exit 0
}

if ($Release) {
  Write-Host "==> Building Windows release" -ForegroundColor Cyan
  flutter build windows --release @define
  if ($LASTEXITCODE -ne 0) { throw "Windows build failed" }
  $exe = Join-Path $Root "build\windows\x64\runner\Release\mobile_game_maker.exe"
  if (-not (Test-Path $exe)) { throw "Missing exe: $exe" }
  Write-Host "==> Launching $exe" -ForegroundColor Green
  Start-Process $exe
} else {
  Write-Host "==> Running on Windows (debug hot-reload)" -ForegroundColor Cyan
  Write-Host "    Play with WASD + Space. Toggle on-screen pads from the play HUD."
  flutter run -d windows @define
}
