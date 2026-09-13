@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Install repository-scoped Git safety hooks. No global Git configuration is changed.
git -c "safe.directory=%CD%" config --local core.hooksPath .githooks >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-source-sync.ps1" -Trigger setup
set "WADDLE_SYNC_EXIT=%ERRORLEVEL%"
if not "%WADDLE_SYNC_EXIT%"=="0" goto :syncfailed

powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-launcher.ps1" -Action setup
set "WADDLE_EXIT=%ERRORLEVEL%"
if not "%WADDLE_EXIT%"=="0" goto :failed

echo.
echo ============================================================
echo WADDLE SETUP COMPLETE
echo Source was synchronized safely before Setup.
echo Dependencies, package index, Electron and Flash were validated.
echo Next: run Waddle-Start.cmd
echo Log: %~dp0.work\logs\launcher\setup-last.log
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b 0

:syncfailed
echo.
echo ============================================================
echo WADDLE SETUP BLOCKED - source synchronization needs attention.
echo No local files were deleted or overwritten.
echo Sync log: %~dp0.work\logs\source-sync\source-sync-last.log
echo Run Waddle-Sync.cmd after resolving any real local changes.
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_SYNC_EXIT%

:failed
echo.
echo ============================================================
echo WADDLE SETUP FAILED - the window will stay open.
echo Log: %~dp0.work\logs\launcher\setup-last.log
echo ============================================================
if not "%WADDLE_NONINTERACTIVE%"=="1" pause
exit /b %WADDLE_EXIT%
