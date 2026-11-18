# Cognitally (TokDash) Windows Native PowerShell Installer
# Usage:
#   Local:     powershell -ExecutionPolicy Bypass -File .\install.ps1
#   Remote:    irm https://raw.githubusercontent.com/kamanager2012/tokdash-releases/v0.1.2/install.ps1 | iex
#   Uninstall: powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall

[CmdletBinding()]
param(
    [string]$InstallDir = $(Join-Path $env:LOCALAPPDATA "Programs\cognitally"),
    [string]$Version = $(if ($env:COGNITALLY_VERSION) { $env:COGNITALLY_VERSION } else { "v0.1.2" }),
    [switch]$NoPathUpdate,
    [switch]$SkipDoctor,
    [switch]$Local,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"
$ExplicitVersion = $PSBoundParameters.ContainsKey("Version") -or [bool]$env:COGNITALLY_VERSION
$Version = $Version.Trim()

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
    $out = & $PyExe @PyPrefix -c "import hashlib, pathlib, sys; print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())" "$Path"
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

function Assert-ArtifactSha256 {
    param(
        [string]$PyExe,
        [string[]]$PyPrefix,
        [string]$ArtifactName,
        [string]$FilePath,
        [string]$SumsPath,
        [string]$EnvOverride
    )
    if (-not (Test-Path $FilePath)) {
        throw "Missing staged artifact $ArtifactName (fail-closed; existing installation unchanged)."
    }
    $ExpectedSha = if ($EnvOverride) { $EnvOverride.Trim().ToLowerInvariant() } else { Get-ExpectedSha256 -SumsPath $SumsPath -ArtifactName $ArtifactName }
    if (-not $ExpectedSha -or ($ExpectedSha -notmatch "^[0-9a-f]{64}$")) {
        throw "Missing or invalid SHA-256 expected checksum for $ArtifactName (fail-closed; existing installation unchanged)."
    }
    $ActualSha = Get-FileSha256 -PyExe $PyExe -PyPrefix $PyPrefix -Path $FilePath
    if ($ActualSha -ne $ExpectedSha) {
        throw "SHA-256 mismatch for $ArtifactName. Expected $ExpectedSha, got $ActualSha (existing installation unchanged)."
    }
    Write-Host "    SHA-256 verified ($ArtifactName): $ActualSha" -ForegroundColor Green
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

# 2. Setup target install directory & isolated staging/backup transaction directories
Write-Host "==> Target directory: $InstallDir" -ForegroundColor Yellow
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$TagSuffix = [guid]::NewGuid().ToString("N")
$StageDir = Join-Path $InstallDir ".stage.$TagSuffix"
$BackupDir = Join-Path $InstallDir ".backup.$TagSuffix"
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

$PyzStage = Join-Path $StageDir "cognitally.pyz"
$CmdStage = Join-Path $StageDir "cognitally.cmd"
$Ps1Stage = Join-Path $StageDir "cognitally.ps1"
$TokdashCmdStage = Join-Path $StageDir "tokdash.cmd"
$TokdashPs1Stage = Join-Path $StageDir "tokdash.ps1"
$SumsStage = Join-Path $StageDir "SHA256SUMS"

try {
    # 3. Locate local artifacts or download strictly from pinned tag (never silently fallback to latest)
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
        $CandPs1 = Join-Path $Dir "cognitally.ps1"
        if ((Test-Path $CandPyz) -and (Test-Path $CandCmd) -and (Test-Path $CandPs1)) {
            $LocalBaseDir = $Dir
            break
        }
    }

    $SumsPathForCheck = $null

    if ($Local -or ($LocalBaseDir -and -not $ExplicitVersion)) {
        if (-not $LocalBaseDir) {
            throw "Local mode requested (-Local), but cognitally.pyz / .cmd / .ps1 were not found next to install.ps1."
        }
        Write-Host "==> Staging local repository artifacts ($LocalBaseDir)..." -ForegroundColor Yellow
        Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.pyz") -Destination $PyzStage -Force
        Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.cmd") -Destination $CmdStage -Force
        Copy-Item -Path (Join-Path $LocalBaseDir "cognitally.ps1") -Destination $Ps1Stage -Force
        $LocalSums = Join-Path $LocalBaseDir "SHA256SUMS"
        if (Test-Path $LocalSums) {
            $SumsPathForCheck = $LocalSums
        }
    } else {
        $TagBase = "https://github.com/kamanager2012/tokdash-releases/releases/download/$Version"
        $LatestBase = "https://github.com/kamanager2012/tokdash-releases/releases/latest/download"
        $RawBase = "https://raw.githubusercontent.com/kamanager2012/tokdash-releases/$Version"

        if ($Version -eq "latest") {
            Write-Host "==> Downloading release package (latest) from GitHub Releases..." -ForegroundColor Yellow
            $DownloadCandidates = @($LatestBase)
        } else {
            Write-Host "==> Downloading pinned release package ($Version) from GitHub (no latest fallback)..." -ForegroundColor Yellow
            $DownloadCandidates = @($TagBase, $RawBase)
        }

        $ActiveBase = $null
        foreach ($CandBase in $DownloadCandidates) {
            try {
                Invoke-WebRequest -Uri "$CandBase/cognitally.pyz" -OutFile $PyzStage -UseBasicParsing
                $ActiveBase = $CandBase
                break
            } catch {
                continue
            }
        }
        if (-not $ActiveBase) {
            throw "Failed to download cognitally.pyz for version '$Version' (existing installation unchanged)."
        }

        $SiblingBases = if ($Version -eq "latest") { @($ActiveBase) } else { @($ActiveBase, $RawBase) }
        foreach ($ArtifactSpec in @(
            @{ Name = "cognitally.cmd"; Dest = $CmdStage },
            @{ Name = "cognitally.ps1"; Dest = $Ps1Stage },
            @{ Name = "SHA256SUMS"; Dest = $SumsStage }
        )) {
            $Fetched = $false
            foreach ($BaseUrl in $SiblingBases) {
                try {
                    Invoke-WebRequest -Uri "$BaseUrl/$($ArtifactSpec.Name)" -OutFile $ArtifactSpec.Dest -UseBasicParsing
                    $Fetched = $true
                    break
                } catch {
                    continue
                }
            }
            if (-not $Fetched -and -not ($ArtifactSpec.Name -eq "SHA256SUMS" -and $env:COGNITALLY_EXPECTED_SHA256 -and $env:COGNITALLY_EXPECTED_CMD_SHA256 -and $env:COGNITALLY_EXPECTED_PS1_SHA256)) {
                throw "Failed to download $($ArtifactSpec.Name) for version '$Version' (fail-closed; existing installation unchanged)."
            }
        }
        if (Test-Path $SumsStage) {
            $SumsPathForCheck = $SumsStage
        }
    }

    # 4. Verify Zipapp archive integrity, embedded BUILD_MANIFEST.json version, and ALL launcher SHA-256 digests
    $ManifestCheckScript = @'
import json, sys, zipfile
path, tag = sys.argv[1], sys.argv[2]
if not zipfile.is_zipfile(path):
    sys.stderr.write("Invalid Zipapp archive.\n")
    sys.exit(1)
with zipfile.ZipFile(path, "r") as zf:
    if "BUILD_MANIFEST.json" not in zf.namelist():
        sys.stderr.write("Missing BUILD_MANIFEST.json in archive.\n")
        sys.exit(2)
    manifest = json.loads(zf.read("BUILD_MANIFEST.json").decode("utf-8"))
actual_ver = str(manifest.get("version") or "").strip()
if tag != "latest" and actual_ver != tag.lstrip("v"):
    sys.stderr.write(f"Version mismatch: expected {tag.lstrip('v')}, got {actual_ver}\n")
    sys.exit(3)
'@
    $ManifestCheckScript | & $PyExe @PyPrefix - "$PyzStage" "$Version"
    if ($LASTEXITCODE -ne 0) {
        throw "Downloaded cognitally.pyz failed Zipapp or BUILD_MANIFEST.json version check for '$Version' (existing installation unchanged)."
    }

    Assert-ArtifactSha256 -PyExe $PyExe -PyPrefix $PyPrefix -ArtifactName "cognitally.pyz" -FilePath $PyzStage -SumsPath $SumsPathForCheck -EnvOverride $env:COGNITALLY_EXPECTED_SHA256
    Assert-ArtifactSha256 -PyExe $PyExe -PyPrefix $PyPrefix -ArtifactName "cognitally.cmd" -FilePath $CmdStage -SumsPath $SumsPathForCheck -EnvOverride $env:COGNITALLY_EXPECTED_CMD_SHA256
    Assert-ArtifactSha256 -PyExe $PyExe -PyPrefix $PyPrefix -ArtifactName "cognitally.ps1" -FilePath $Ps1Stage -SumsPath $SumsPathForCheck -EnvOverride $env:COGNITALLY_EXPECTED_PS1_SHA256

    # Stage backward-compatible tokdash shims inside $StageDir prior to transactional promotion
    $TokdashCmdContent = "@echo off`r`ncall `"%~dp0cognitally.cmd`" %*`r`n"
    Set-Content -Path $TokdashCmdStage -Value $TokdashCmdContent -Encoding ASCII

    $TokdashPs1Content = "`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path`r`n& (Join-Path `$ScriptDir `"cognitally.ps1`") @args`r`nexit `$LASTEXITCODE`r`n"
    Set-Content -Path $TokdashPs1Stage -Value $TokdashPs1Content -Encoding UTF8

    # 5. Transactional promotion (Backup -> Swap -> Full Rollback on any failure)
    $ManagedFiles = @("cognitally.pyz", "cognitally.cmd", "cognitally.ps1", "tokdash.cmd", "tokdash.ps1")
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    try {
        foreach ($Name in $ManagedFiles) {
            $DestFile = Join-Path $InstallDir $Name
            if (Test-Path $DestFile) {
                Copy-Item -Path $DestFile -Destination (Join-Path $BackupDir $Name) -Force
            }
        }
        $Idx = 0
        foreach ($Name in $ManagedFiles) {
            $StageFile = Join-Path $StageDir $Name
            $DestFile = Join-Path $InstallDir $Name
            Move-Item -Path $StageFile -Destination $DestFile -Force
            $Idx++
            if ($Idx -eq 1 -and $env:COGNITALLY_TEST_ABORT_DURING_PROMOTE -eq "1") {
                throw "Simulated mid-promotion fault after cognitally.pyz"
            }
        }
    } catch {
        foreach ($Name in $ManagedFiles) {
            $DestFile = Join-Path $InstallDir $Name
            $BakFile = Join-Path $BackupDir $Name
            if (Test-Path $BakFile) {
                Copy-Item -Path $BakFile -Destination $DestFile -Force -ErrorAction SilentlyContinue
            } elseif (Test-Path $DestFile) {
                Remove-Item -Path $DestFile -Force -ErrorAction SilentlyContinue
            }
        }
        throw "Installation promotion failed and rolled back cleanly: $_"
    }

    Write-Host "    Installed cognitally.pyz and cmd/ps1 shims to $InstallDir" -ForegroundColor Green
} finally {
    foreach ($TmpDir in @($StageDir, $BackupDir)) {
        if ($TmpDir -and (Test-Path $TmpDir)) {
            Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
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
