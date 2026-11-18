# Cognitally (TokDash) Windows Native PowerShell Installer
# Usage:
#   Local:     powershell -ExecutionPolicy Bypass -File .\install.ps1
#   Remote:    irm https://raw.githubusercontent.com/kamanager2012/tokdash-releases/v0.1.1/install.ps1 | iex
#   Uninstall: powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall

[CmdletBinding()]
param(
    [string]$InstallDir = $(Join-Path $env:LOCALAPPDATA "Programs\cognitally"),
    [string]$Version = $(if ($env:COGNITALLY_VERSION) { $env:COGNITALLY_VERSION } else { "v0.1.1" }),
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
Write-Host " 🚀 Cognitally (TokDash) Windows Native Installer ($Version)" -ForegroundColor Cyan
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

function Get-FileSha256 {
    param([string]$PyExe, [string[]]$PyPrefix, [string]$Path)
    $out = & $PyExe @PyPrefix -c "import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], rb).read()).hexdigest())" "$Path"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to compute SHA-256 checksum for $Path"
    }
    return ($out | Select-Object -First 1).Trim().ToLowerInvariant()
}

function Get-ExpectedSha256 {
    param([string]$SumsPath, [string]$ArtifactName)
    if (-not $SumsPath -or -not (Test-Path $SumsPath)) {
        return $null
    }
    $Escaped = [regex]::Escape($ArtifactName)
    $MatchLine = Get-Content $SumsPath | Where-Object { $_ -match "^[0-9a-fA-F]{64}\s+$Escaped$" } | Select-Object -First 1
    if ($MatchLine) {
        return (($MatchLine -split "\s+")[0]).ToLowerInvariant()
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

$PyExe = $PythonInfo.Exe
$PyPrefix = $PythonInfo.Prefix

# 2. Setup target install directory & isolated staging temp paths
Write-Host "==> Target directory: $InstallDir" -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$TagSuffix = [guid]::NewGuid().ToString("N")
$PyzTemp = "$PyzDest.tmp.$TagSuffix"
$CmdTemp = "$CmdDest.tmp.$TagSuffix"
$Ps1Temp = "$Ps1Dest.tmp.$TagSuffix"
$SumsTemp = Join-Path $InstallDir "SHA256SUMS.tmp.$TagSuffix"

try {
    # 3. Locate local artifacts or download from GitHub Releases into staging files
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

    $UsedLocal = $false
    $HasPs1 = $false
    $SumsPathForCheck = $null

    if ($LocalBaseDir -and ($Local -or (Test-Path (Join-Path $LocalBaseDir "cognitally.pyz")))) {
        Write-Host "==> Staging local repository artifacts ($LocalBaseDir)..." -ForegroundColor Yellow
        Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.pyz") -Destination $PyzTemp -Force
        Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.cmd") -Destination $CmdTemp -Force
        $LocalPs1 = Join-Path $LocalBaseDir "cognitally.ps1"
        if (Test-Path $LocalPs1) {
            Copy-Item -Path $LocalPs1 -Destination $Ps1Temp -Force
            $HasPs1 = $true
        }
        $LocalSums = Join-Path $LocalBaseDir "SHA256SUMS"
        if (Test-Path $LocalSums) {
            $SumsPathForCheck = $LocalSums
        }
        $UsedLocal = $true
    } else {
        Write-Host "==> Downloading release package ($Version) from GitHub Releases..." -ForegroundColor Yellow
        $TagBase = "https://github.com/kamanager2012/tokdash-releases/releases/download/$Version"
        $LatestBase = "https://github.com/kamanager2012/tokdash-releases/releases/latest/download"
        $RawBase = "https://raw.githubusercontent.com/kamanager2012/tokdash-releases/$Version"

        $ActiveBase = $null
        foreach ($CandBase in @($TagBase, $LatestBase, $RawBase)) {
            try {
                Invoke-WebRequest -Uri "$CandBase/cognitally.pyz" -OutFile $PyzTemp -UseBasicParsing
                $ActiveBase = $CandBase
                break
            } catch {
                continue
            }
        }
        if (-not $ActiveBase) {
            throw "Failed to download cognitally.pyz from GitHub Releases (existing installation unchanged)."
        }

        try {
            Invoke-WebRequest -Uri "$ActiveBase/cognitally.cmd" -OutFile $CmdTemp -UseBasicParsing
        } catch {
            Invoke-WebRequest -Uri "$RawBase/cognitally.cmd" -OutFile $CmdTemp -UseBasicParsing
        }

        try {
            Invoke-WebRequest -Uri "$ActiveBase/cognitally.ps1" -OutFile $Ps1Temp -UseBasicParsing
            $HasPs1 = $true
        } catch {
            try {
                Invoke-WebRequest -Uri "$RawBase/cognitally.ps1" -OutFile $Ps1Temp -UseBasicParsing
                $HasPs1 = $true
            } catch {
                $HasPs1 = $false
            }
        }

        if (-not $env:COGNITALLY_EXPECTED_SHA256) {
            $SumsFetched = $false
            foreach ($SumsBase in @($ActiveBase, $RawBase)) {
                try {
                    Invoke-WebRequest -Uri "$SumsBase/SHA256SUMS" -OutFile $SumsTemp -UseBasicParsing
                    $SumsFetched = $true
                    break
                } catch {
                    continue
                }
            }
            if ($SumsFetched -and (Test-Path $SumsTemp)) {
                $SumsPathForCheck = $SumsTemp
            }
        }
    }

    # 4. Verify Zipapp archive integrity & MANDATORY SHA-256 checksum (Fail-Closed)
    & $PyExe @PyPrefix -c "import sys, zipfile; sys.exit(0 if zipfile.is_zipfile(sys.argv[1]) else 1)" "$PyzTemp"
    if ($LASTEXITCODE -ne 0) {
        throw "Downloaded cognitally.pyz is not a valid Python Zipapp archive (existing installation unchanged)."
    }

    $ExpectedPyzSha = if ($env:COGNITALLY_EXPECTED_SHA256) { $env:COGNITALLY_EXPECTED_SHA256.Trim().ToLowerInvariant() } else { Get-ExpectedSha256 -SumsPath $SumsPathForCheck -ArtifactName "cognitally.pyz" }
    if (-not $ExpectedPyzSha -or ($ExpectedPyzSha -notmatch "^[0-9a-f]{64}$")) {
        throw "Missing or invalid SHA-256 expected checksum for cognitally.pyz (fail-closed; existing installation unchanged)."
    }

    $ActualPyzSha = Get-FileSha256 -PyExe $PyExe -PyPrefix $PyPrefix -Path $PyzTemp
    if ($ActualPyzSha -ne $ExpectedPyzSha) {
        throw "SHA-256 mismatch for cognitally.pyz. Expected $ExpectedPyzSha, got $ActualPyzSha (existing installation unchanged)."
    }
    Write-Host "    SHA-256 verified (cognitally.pyz): $ActualPyzSha" -ForegroundColor Green

    if (-not $env:COGNITALLY_EXPECTED_SHA256 -and $SumsPathForCheck) {
        $ExpectedCmdSha = Get-ExpectedSha256 -SumsPath $SumsPathForCheck -ArtifactName "cognitally.cmd"
        if ($ExpectedCmdSha) {
            $ActualCmdSha = Get-FileSha256 -PyExe $PyExe -PyPrefix $PyPrefix -Path $CmdTemp
            if ($ActualCmdSha -ne $ExpectedCmdSha) {
                throw "SHA-256 mismatch for cognitally.cmd. Expected $ExpectedCmdSha, got $ActualCmdSha"
            }
        }
        if ($HasPs1) {
            $ExpectedPs1Sha = Get-ExpectedSha256 -SumsPath $SumsPathForCheck -ArtifactName "cognitally.ps1"
            if ($ExpectedPs1Sha) {
                $ActualPs1Sha = Get-FileSha256 -PyExe $PyExe -PyPrefix $PyPrefix -Path $Ps1Temp
                if ($ActualPs1Sha -ne $ExpectedPs1Sha) {
                    throw "SHA-256 mismatch for cognitally.ps1. Expected $ExpectedPs1Sha, got $ActualPs1Sha"
                }
            }
        }
    }

    # 5. Atomic promotion only after all verification gates pass
    Move-Item -Path $PyzTemp -Destination $PyzDest -Force
    Move-Item -Path $CmdTemp -Destination $CmdDest -Force
    if ($HasPs1 -and (Test-Path $Ps1Temp)) {
        Move-Item -Path $Ps1Temp -Destination $Ps1Dest -Force
    }

    # Create tokdash.cmd & tokdash.ps1 alias shims for backward compatibility
    $TokdashCmdContent = "@echo off`r`ncall `"%~dp0cognitally.cmd`" %*`r`n"
    Set-Content -Path $TokdashCmdDest -Value $TokdashCmdContent -Encoding ASCII

    $TokdashPs1Content = "`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path`r`n& (Join-Path `$ScriptDir `"cognitally.ps1`") @args`r`nexit `$LASTEXITCODE`r`n"
    Set-Content -Path $TokdashPs1Dest -Value $TokdashPs1Content -Encoding UTF8

    Write-Host "    Installed cognitally.pyz and cmd/ps1 shims to $InstallDir" -ForegroundColor Green
} finally {
    foreach ($TmpItem in @($PyzTemp, $CmdTemp, $Ps1Temp, $SumsTemp)) {
        if ($TmpItem -and (Test-Path $TmpItem)) {
            Remove-Item -Path $TmpItem -Force -ErrorAction SilentlyContinue
        }
    }
}

# 6. PATH Registration
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

# 7. Doctor verification
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
