@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-launcher.ps1" -Action setup
set "WADDLE_EXIT=%ERRORLEVEL%"
if not "%WADDLE_EXIT%"=="0" goto :failed

echo.
echo ============================================================
echo WADDLE SETUP COMPLETE
echo Dependencies, package index, Electron and Flash were validated.
echo Next: run Waddle-Start.cmd
echo Log: %~dp0.work\logs\launcher\setup-last.log
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b 0

:failed
echo.
echo ============================================================
echo WADDLE SETUP FAILED - the window will stay open.
echo Log: %~dp0.work\logs\launcher\setup-last.log
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_EXIT%
