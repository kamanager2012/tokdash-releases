# Cognitally (TokDash) Windows Native PowerShell Installer
# Usage:
#   Local:  powershell -ExecutionPolicy Bypass -File .\install.ps1
#   Remote: irm https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main/install.ps1 | iex

[CmdletBinding()]
param(
    [string]$InstallDir = $(Join-Path $env:LOCALAPPDATA "Programs\cognitally"),
    [switch]$NoPathUpdate,
    [switch]$SkipDoctor
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " 🚀 Cognitally (TokDash) Windows Native Installer" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# 1. Check Python 3 environment
Write-Host "==> Checking Python environment..." -ForegroundColor Yellow
$PythonCmd = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $PythonCmd = "py -3"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $PythonCmd = "python"
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    $PythonCmd = "python3"
}

if (-not $PythonCmd) {
    Write-Error "Error: Python 3 was not found. Please install Python 3 (>=3.8) from https://python.org or the Microsoft Store."
    exit 1
}
Write-Host "    Found Python launcher: $PythonCmd" -ForegroundColor Green

# 2. Setup target install directory
Write-Host "==> Target directory: $InstallDir" -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$PyzDest = Join-Path $InstallDir "cognitally.pyz"
$CmdDest = Join-Path $InstallDir "cognitally.cmd"
$Ps1Dest = Join-Path $InstallDir "cognitally.ps1"
$TokdashCmdDest = Join-Path $InstallDir "tokdash.cmd"

# 3. Deploy or Download distribution artifacts
$ScriptRoot = $PSScriptRoot
$LocalPyz = if ($ScriptRoot) { Join-Path $ScriptRoot "dist\cognitally.pyz" } else { $null }
$LocalCmd = if ($ScriptRoot) { Join-Path $ScriptRoot "dist\cognitally.cmd" } else { $null }
$LocalPs1 = if ($ScriptRoot) { Join-Path $ScriptRoot "dist\cognitally.ps1" } else { $null }

if ($LocalPyz -and (Test-Path $LocalPyz) -and $LocalCmd -and (Test-Path $LocalCmd)) {
    Write-Host "==> Installing from local repository artifacts..." -ForegroundColor Yellow
    Copy-Item -Path $LocalPyz -Destination $PyzDest -Force
    Copy-Item -Path $LocalCmd -Destination $CmdDest -Force
    if ($LocalPs1 -and (Test-Path $LocalPs1)) {
        Copy-Item -Path $LocalPs1 -Destination $Ps1Dest -Force
    }
} else {
    Write-Host "==> Downloading latest release package from GitHub Releases..." -ForegroundColor Yellow
    $ReleaseBase = "https://github.com/kamanager2012/tokdash-releases/releases/latest/download"
    $RawBase = "https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main"

    try {
        Invoke-WebRequest -Uri "$ReleaseBase/cognitally.pyz" -OutFile $PyzDest -UseBasicParsing
    } catch {
        Invoke-WebRequest -Uri "$RawBase/cognitally.pyz" -OutFile $PyzDest -UseBasicParsing
    }

    try {
        Invoke-WebRequest -Uri "$RawBase/cognitally.cmd" -OutFile $CmdDest -UseBasicParsing
    } catch {
        Invoke-WebRequest -Uri "$ReleaseBase/cognitally.cmd" -OutFile $CmdDest -UseBasicParsing
    }

    try {
        Invoke-WebRequest -Uri "$RawBase/cognitally.ps1" -OutFile $Ps1Dest -UseBasicParsing
    } catch {
        # Optional helper
    }
}

# Create tokdash.cmd alias shim for backward compatibility
$TokdashCmdContent = "@echo off`r`ncall `"%~dp0cognitally.cmd`" %*`r`n"
Set-Content -Path $TokdashCmdDest -Value $TokdashCmdContent -Encoding ASCII

Write-Host "    Installed cognitally.pyz and cmd/ps1 shims to $InstallDir" -ForegroundColor Green

# 4. PATH Registration
if (-not $NoPathUpdate) {
    Write-Host "==> Checking User PATH environment variable..." -ForegroundColor Yellow
    $UserPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    $Paths = if ($UserPath) { $UserPath -split ";" | Where-Object { $_ -ne "" } } else { @() }
    $NormalizedInstallDir = $InstallDir.TrimEnd('\')

    $AlreadyInPath = $false
    foreach ($p in $Paths) {
        if ($p.TrimEnd('\').Equals($NormalizedInstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
            $AlreadyInPath = $true
            break
        }
    }

    if (-not $AlreadyInPath) {
        $NewUserPath = if ($UserPath) { "$UserPath;$InstallDir" } else { $InstallDir }
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, [EnvironmentVariableTarget]::User)
        $env:Path = "$env:Path;$InstallDir"
        Write-Host "    Added $InstallDir to User PATH." -ForegroundColor Green
    } else {
        Write-Host "    $InstallDir is already in User PATH." -ForegroundColor Cyan
    }
}

# 5. Doctor verification
if (-not $SkipDoctor) {
    Write-Host "==> Verifying installation with 'cognitally.cmd --doctor'..." -ForegroundColor Yellow
    & $CmdDest --doctor
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "✅ Cognitally Windows Installation Complete!" -ForegroundColor Green
Write-Host "   - Command Line: cognitally (or tokdash)" -ForegroundColor White
Write-Host "   - Health Check: cognitally --doctor" -ForegroundColor White
Write-Host "   - Statusline:   cognitally --statusline" -ForegroundColor White
Write-Host "   - MCP Server:   cognitally --mcp" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan
