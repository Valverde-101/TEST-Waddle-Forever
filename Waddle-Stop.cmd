@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-stop.ps1"
set "WADDLE_EXIT=%ERRORLEVEL%"
if "%WADDLE_EXIT%"=="0" exit /b 0

echo.
echo ============================================================
echo WADDLE STOP FAILED - the window will stay open.
echo State: %~dp0.work\state\waddle-client.json
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_EXIT%
