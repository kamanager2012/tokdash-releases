@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PYZ_PATH=%SCRIPT_DIR%cognitally.pyz"

where py >nul 2>nul
if %ERRORLEVEL% equ 0 (
    py -3 "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

where python >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

where python3 >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python3 "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

echo Error: Python 3 was not found in PATH. Please install Python 3. >&2
exit /b 1
