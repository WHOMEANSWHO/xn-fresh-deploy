@echo off
setlocal
title Xn Fresh Deploy
cd /d "%~dp0"
set "XN_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if not exist "%~dp0Xn-Setup.ps1" (
    echo Xn-Setup.ps1 is missing. Keep every release file in the same folder.
    pause
    exit /b 1
)

if not exist "%XN_POWERSHELL%" (
    echo Windows PowerShell could not be found on this PC.
    pause
    exit /b 1
)

start "" "%XN_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Xn-Setup.ps1"
if errorlevel 1 (
    echo.
    echo Xn Fresh Deploy could not start. Check that the folder was fully extracted and is writable.
    pause
    exit /b 1
)

exit /b 0
