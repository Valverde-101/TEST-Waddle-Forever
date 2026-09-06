@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".github\scripts\waddle-bootstrap.ps1"
exit /b %ERRORLEVEL%
