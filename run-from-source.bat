@echo off
chcp 65001 >nul
title CleanTool
cd /d "%~dp0"
echo Starting CleanTool from source...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0src\CleanTool.ps1"
if errorlevel 1 (
    echo.
    echo Failed to start. Right-click this file and choose "Run as administrator".
    pause
)