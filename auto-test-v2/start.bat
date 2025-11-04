@echo off
chcp 65001 >nul
title Auto-Test V2 Client Launcher

echo ╔════════════════════════════════════════╗
echo ║   Auto-Test V2 Desktop Client          ║
echo ╚════════════════════════════════════════╝
echo.
echo Starting GUI Client...
echo.

cd /d "%~dp0"
python gui_client.py

if %errorlevel% neq 0 (
    echo.
    echo ❌ Launch Failed!
    echo.
    echo Possible reasons:
    echo   1. Python is not installed or not in PATH
    echo   2. Missing required dependencies
    echo.
    echo Please run: pip install -r requirements.txt
    echo.
    pause
)
