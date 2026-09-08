@echo off
setlocal EnableExtensions
pushd "%~dp0" >nul
if errorlevel 1 (
  echo WADDLE START FAILED - cannot enter repository path.
  if not "%WADDLE_NONINTERACTIVE%"=="1" pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-play.ps1"
set "WADDLE_EXIT=%ERRORLEVEL%"
popd >nul
if "%WADDLE_EXIT%"=="0" exit /b 0

echo.
echo ============================================================
echo WADDLE START FAILED - the window will stay open.
echo Runtime diagnostics: %~dp0.work\logs\runtime
echo State: %~dp0.work\state\waddle-client.json
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_EXIT%
