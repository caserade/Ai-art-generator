@echo off
REM Double-click friendly: set up Flutter Windows deps and run Game Maker on PC.
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_and_run_pc.ps1" %*
if errorlevel 1 pause
