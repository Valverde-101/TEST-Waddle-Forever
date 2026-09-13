@echo off
setlocal EnableExtensions
pushd "%~dp0" >nul
if errorlevel 1 (
  echo WADDLE SYNC FAILED - cannot enter repository path.
  if not "%WADDLE_NONINTERACTIVE%"=="1" pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-source-sync.ps1" -Trigger manual -RequireRemote -RequireCore -InstallHooks
set "WADDLE_EXIT=%ERRORLEVEL%"
popd >nul

if "%WADDLE_EXIT%"=="0" (
  echo.
  echo ============================================================
  echo WADDLE SOURCE SYNC COMPLETE
  echo AndroidBuild Core verified the managed Git provider and branch state.
  echo Local source is aligned safely with the tracked GitHub branch,
  echo or local commits/changes were preserved without overwriting them.
  echo Repository Git safety hooks are enabled for manual commits/branch switches.
  echo State: %~dp0.work\state\source-sync.json
  echo ============================================================
  if not "%WADDLE_NONINTERACTIVE%"=="1" pause
  exit /b 0
)

echo.
echo ============================================================
echo WADDLE SOURCE SYNC BLOCKED
echo No local files were deleted or overwritten.
echo Check: %~dp0.work\logs\source-sync\source-sync-last.log
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_EXIT%
