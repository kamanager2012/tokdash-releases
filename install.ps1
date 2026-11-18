# Cognitally (TokDash) Windows Native PowerShell Installer
# Usage:
#   Local:     powershell -ExecutionPolicy Bypass -File .\install.ps1
#   Remote:    irm https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main/install.ps1 | iex
#   Uninstall: powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall

[CmdletBinding()]
param(
    [string]$InstallDir = $(Join-Path $env:LOCALAPPDATA "Programs\cognitally"),
    [switch]$NoPathUpdate,
    [switch]$SkipDoctor,
    [switch]$Local,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

$PyzDest = Join-Path $InstallDir "cognitally.pyz"
$CmdDest = Join-Path $InstallDir "cognitally.cmd"
$Ps1Dest = Join-Path $InstallDir "cognitally.ps1"
$TokdashCmdDest = Join-Path $InstallDir "tokdash.cmd"
$TokdashPs1Dest = Join-Path $InstallDir "tokdash.ps1"

if ($Uninstall) {
    Write-Host "==> Uninstalling Cognitally / TokDash from $InstallDir..." -ForegroundColor Cyan
    $Removed = 0
    foreach ($Target in @($PyzDest, $CmdDest, $Ps1Dest, $TokdashCmdDest, $TokdashPs1Dest)) {
        if (Test-Path $Target) {
            Remove-Item -Path $Target -Force
            Write-Host "    Removed: $Target" -ForegroundColor Green
            $Removed++
        }
    }
    if ($Removed -eq 0) {
        Write-Host "    No installed files found in $InstallDir." -ForegroundColor Yellow
    } else {
        Write-Host "✅ Cognitally uninstalled." -ForegroundColor Green
    }
    exit 0
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host " 🚀 Cognitally (TokDash) Windows Native Installer" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

function Resolve-PythonLauncher {
    $Candidates = @()
    if ($env:COGNITALLY_PYTHON) {
        $parts = $env:COGNITALLY_PYTHON -split "\s+"
        $exe = $parts[0]
        $prefix = if ($parts.Length -gt 1) { $parts[1..($parts.Length - 1)] } else { @() }
        $Candidates += ,@($exe, $prefix, $env:COGNITALLY_PYTHON)
    }
    $Candidates += ,@("py", @("-3"), "py -3")
    $Candidates += ,@("python", @(), "python")
    $Candidates += ,@("python3", @(), "python3")

    foreach ($Cand in $Candidates) {
        $Exe = $Cand[0]
        $Prefix = $Cand[1]
        $Label = $Cand[2]
        if (-not (Test-Path $Exe) -and -not (Get-Command $Exe -ErrorAction SilentlyContinue)) {
            continue
        }
        try {
            $verOut = & $Exe @Prefix --version 2>$null
            if ($LASTEXITCODE -ne 0) { continue }
            & $Exe @Prefix -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" *> $null
            if ($LASTEXITCODE -eq 0) {
                return @{
                    Exe = $Exe
                    Prefix = $Prefix
                    Label = $Label
                    Version = ($verOut | Select-Object -First 1)
                }
            }
        } catch {
            continue
        }
    }
    return $null
}

# 1. Check real Python 3 (>=3.8) environment (filtering out Windows Store stubs)
Write-Host "==> Checking Python runtime (>= 3.8)..." -ForegroundColor Yellow
$PythonInfo = Resolve-PythonLauncher
if (-not $PythonInfo) {
    Write-Error "Error: Python 3 (>=3.8) was not found (Windows Store alias stubs are ignored). Install Python 3 from https://python.org or set COGNITALLY_PYTHON."
    exit 1
}
Write-Host "    Found Python launcher: $($PythonInfo.Label) ($($PythonInfo.Version))" -ForegroundColor Green

# 2. Setup target install directory
Write-Host "==> Target directory: $InstallDir" -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# 3. Locate local artifacts or download from GitHub Releases
$ScriptRoot = $PSScriptRoot
$LocalCandidates = @()
if ($ScriptRoot) {
    $LocalCandidates += $ScriptRoot
    $LocalCandidates += (Join-Path $ScriptRoot "dist")
}

$LocalBaseDir = $null
foreach ($Dir in $LocalCandidates) {
    $CandPyz = Join-Path $Dir "cognitally.pyz"
    $CandCmd = Join-Path $Dir "cognitally.cmd"
    if ((Test-Path $CandPyz) -and (Test-Path $CandCmd)) {
        $LocalBaseDir = $Dir
        break
    }
}

$PyzTemp = "$PyzDest.tmp"
$UsedLocal = $false

if ($LocalBaseDir -and ($Local -or (Test-Path (Join-Path $LocalBaseDir "cognitally.pyz")))) {
    Write-Host "==> Installing from local repository artifacts ($LocalBaseDir)..." -ForegroundColor Yellow
    Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.pyz") -Destination $PyzTemp -Force
    Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.cmd") -Destination $CmdDest -Force
    $LocalPs1 = Join-Path $LocalBaseDir "cognitally.ps1"
    if (Test-Path $LocalPs1) {
        Copy-Item -Path $LocalPs1 -Destination $Ps1Dest -Force
    }
    $UsedLocal = $true
} else {
    Write-Host "==> Downloading latest release package from GitHub Releases..." -ForegroundColor Yellow
    $ReleaseBase = "https://github.com/kamanager2012/tokdash-releases/releases/latest/download"
    $RawBase = "https://raw.githubusercontent.com/kamanager2012/tokdash-releases/main"

    try {
        Invoke-WebRequest -Uri "$ReleaseBase/cognitally.pyz" -OutFile $PyzTemp -UseBasicParsing
    } catch {
        Invoke-WebRequest -Uri "$RawBase/cognitally.pyz" -OutFile $PyzTemp -UseBasicParsing
    }

    try {
        Invoke-WebRequest -Uri "$ReleaseBase/cognitally.cmd" -OutFile $CmdDest -UseBasicParsing
    } catch {
        Invoke-WebRequest -Uri "$RawBase/cognitally.cmd" -OutFile $CmdDest -UseBasicParsing
    }

    try {
        Invoke-WebRequest -Uri "$ReleaseBase/cognitally.ps1" -OutFile $Ps1Dest -UseBasicParsing
    } catch {
        try {
            Invoke-WebRequest -Uri "$RawBase/cognitally.ps1" -OutFile $Ps1Dest -UseBasicParsing
        } catch {
            # Optional PowerShell shim
        }
    }
}

# 4. Verify Zipapp archive integrity & optional SHA-256
$PyExe = $PythonInfo.Exe
$PyPrefix = $PythonInfo.Prefix
& $PyExe @PyPrefix -c "import sys, zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)" "$PyzTemp"
if ($LASTEXITCODE -ne 0) {
    Remove-Item -Path $PyzTemp -Force -ErrorAction SilentlyContinue
    Write-Error "Error: Downloaded cognitally.pyz is not a valid Python Zipapp archive."
    exit 1
}

$ExpectedSha = $env:COGNITALLY_EXPECTED_SHA256
if (-not $ExpectedSha -and $UsedLocal -and $LocalBaseDir) {
    $SumsPath = Join-Path $LocalBaseDir "SHA256SUMS"
    if (Test-Path $SumsPath) {
        $MatchLine = Get-Content $SumsPath | Where-Object { $_ -match "\s+cognitally\.pyz$" } | Select-Object -First 1
        if ($MatchLine) {
            $ExpectedSha = ($MatchLine -split "\s+")[0]
        }
    }
}

if ($ExpectedSha) {
    $ActualSha = (& $PyExe @PyPrefix -c "import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], 'rb').read()).hexdigest())" "$PyzTemp").Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -Path $PyzTemp -Force -ErrorAction SilentlyContinue
        Write-Error "Error: Failed to compute SHA-256 checksum for cognitally.pyz."
        exit 1
    }
    if ($ActualSha -ne $ExpectedSha.ToLowerInvariant()) {
        Remove-Item -Path $PyzTemp -Force -ErrorAction SilentlyContinue
        Write-Error "Error: SHA-256 mismatch for cognitally.pyz. Expected $ExpectedSha, got $ActualSha"
        exit 1
    }
    Write-Host "    SHA-256 verified: $ActualSha" -ForegroundColor Green
}

Move-Item -Path $PyzTemp -Destination $PyzDest -Force

# Create tokdash.cmd & tokdash.ps1 alias shims for backward compatibility
$TokdashCmdContent = "@echo off`r`ncall `"%~dp0cognitally.cmd`" %*`r`n"
Set-Content -Path $TokdashCmdDest -Value $TokdashCmdContent -Encoding ASCII

$TokdashPs1Content = "`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path`r`n& (Join-Path `$ScriptDir `"cognitally.ps1`") @args`r`nexit `$LASTEXITCODE`r`n"
Set-Content -Path $TokdashPs1Dest -Value $TokdashPs1Content -Encoding UTF8

Write-Host "    Installed cognitally.pyz and cmd/ps1 shims to $InstallDir" -ForegroundColor Green

# 5. PATH Registration
if (-not $NoPathUpdate) {
    Write-Host "==> Checking User PATH environment variable..." -ForegroundColor Yellow
    $UserPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
    $Paths = if ($UserPath) { $UserPath -split ";" | Where-Object { $_ -ne "" } } else { @() }
    $NormalizedInstallDir = $InstallDir.TrimEnd("\")

    $AlreadyInPath = $false
    foreach ($p in $Paths) {
        if ($p.TrimEnd("\").Equals($NormalizedInstallDir, [System.StringComparison]::OrdinalIgnoreCase)) {
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

# 6. Doctor verification
if (-not $SkipDoctor) {
    Write-Host "==> Verifying installation with cognitally.cmd --doctor..." -ForegroundColor Yellow
    & $CmdDest --doctor
}

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "✅ Cognitally Windows Installation Complete!" -ForegroundColor Green
Write-Host "   - Command Line: cognitally (or tokdash)" -ForegroundColor White
Write-Host "   - Help:         cognitally --help" -ForegroundColor White
Write-Host "   - Health Check: cognitally --doctor" -ForegroundColor White
Write-Host "   - Statusline:   cognitally --statusline" -ForegroundColor White
Write-Host "   - MCP Server:   cognitally --mcp" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan
