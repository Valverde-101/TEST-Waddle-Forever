@echo off
setlocal
set "WADDLE_REPO=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%WADDLE_REPO%.github\scripts\waddle-diagnostics.ps1" -RepoRoot "%WADDLE_REPO%" %*
set "WADDLE_EXIT=%ERRORLEVEL%"
exit /b %WADDLE_EXIT%
