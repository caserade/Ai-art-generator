# Run Game Maker natively on Windows PC
#
# Prerequisites: Flutter + Visual Studio (Desktop development with C++)
#
#   .\scripts\run_on_pc.ps1
#   .\scripts\run_on_pc.ps1 -Release

param(
  [switch]$Release,
  [string]$OpenAiKey = $env:OPENAI_API_KEY
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

flutter pub get

$define = @()
if ($OpenAiKey) {
  $define += "--dart-define=OPENAI_API_KEY=$OpenAiKey"
}

if ($Release) {
  flutter build windows --release @define
  $exe = Join-Path $Root "build\windows\x64\runner\Release\mobile_game_maker.exe"
  if (Test-Path $exe) {
    Write-Host "Launching $exe"
    Start-Process $exe
  } else {
    throw "Windows release exe not found at $exe"
  }
} else {
  flutter run -d windows @define
}
