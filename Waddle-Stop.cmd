@echo off
setlocal EnableExtensions
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-launcher.ps1" -Action stop
set "WADDLE_EXIT=%ERRORLEVEL%"
if "%WADDLE_EXIT%"=="0" exit /b 0

echo.
echo ============================================================
echo WADDLE STOP FAILED - the window will stay open.
echo Log: %~dp0.work\logs\launcher\stop-last.log
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_EXIT%
