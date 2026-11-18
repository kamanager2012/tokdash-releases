@echo off
setlocal
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "SCRIPT_DIR=%~dp0"
set "PYZ_PATH=%SCRIPT_DIR%cognitally.pyz"

if defined COGNITALLY_PYTHON (
    if exist "%COGNITALLY_PYTHON%" (
        "%COGNITALLY_PYTHON%" "%PYZ_PATH%" %*
        exit /b %ERRORLEVEL%
    )
    %COGNITALLY_PYTHON% "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

py -3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >nul 2>nul
if %ERRORLEVEL% equ 0 (
    py -3 "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

python -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" >nul 2>nul
if %ERRORLEVEL% equ 0 (
    python3 "%PYZ_PATH%" %*
    exit /b %ERRORLEVEL%
)

echo Error: Python 3 (^>=3.8) was not found in PATH. Please install Python 3 or set COGNITALLY_PYTHON. >&2
exit /b 1
