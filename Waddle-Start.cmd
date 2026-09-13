@echo off
setlocal EnableExtensions
pushd "%~dp0" >nul
if errorlevel 1 (
  echo WADDLE START FAILED - cannot enter repository path.
  if not "%WADDLE_NONINTERACTIVE%"=="1" pause
  exit /b 1
)

rem Install repository-scoped Git safety hooks. No global Git configuration is changed.
git -c "safe.directory=%CD%" config --local core.hooksPath .githooks >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-source-sync.ps1" -Trigger start
set "WADDLE_SYNC_EXIT=%ERRORLEVEL%"
if not "%WADDLE_SYNC_EXIT%"=="0" (
  popd >nul
  echo.
  echo ============================================================
  echo WADDLE START BLOCKED - source synchronization needs attention.
  echo No local files were deleted or overwritten.
  echo Sync log: %~dp0.work\logs\source-sync\source-sync-last.log
  echo Run Waddle-Sync.cmd after resolving any real local changes.
  echo ============================================================
  if not "%WADDLE_NONINTERACTIVE%"=="1" pause
  exit /b %WADDLE_SYNC_EXIT%
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
