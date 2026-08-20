@echo off
REM Double-click or run from cmd: scripts\pc_to_phone.bat
REM Optional: scripts\pc_to_phone.bat -Rebuild -Launch
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pc_to_phone.ps1" %*
