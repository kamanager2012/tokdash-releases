$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyzPath = Join-Path $ScriptDir "cognitally.pyz"

function Test-PythonCandidate {
    param([string]$Exe, [string[]]$PrefixArgs)
    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) {
        return $false
    }
    try {
        & $Exe @PrefixArgs -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

if ($env:COGNITALLY_PYTHON) {
    if (Test-Path $env:COGNITALLY_PYTHON) {
        & $env:COGNITALLY_PYTHON "$PyzPath" @args
        exit $LASTEXITCODE
    }
    $parts = $env:COGNITALLY_PYTHON -split "\s+"
    $exe = $parts[0]
    $extra = if ($parts.Length -gt 1) { $parts[1..($parts.Length - 1)] } else { @() }
    & $exe @extra "$PyzPath" @args
    exit $LASTEXITCODE
}

if (Test-PythonCandidate -Exe "py" -PrefixArgs @("-3")) {
    & py -3 "$PyzPath" @args
    exit $LASTEXITCODE
} elseif (Test-PythonCandidate -Exe "python" -PrefixArgs @()) {
    & python "$PyzPath" @args
    exit $LASTEXITCODE
} elseif (Test-PythonCandidate -Exe "python3" -PrefixArgs @()) {
    & python3 "$PyzPath" @args
    exit $LASTEXITCODE
} else {
    Write-Error "Error: Python 3 (>=3.8) was not found in PATH. Please install Python 3 or set COGNITALLY_PYTHON."
    exit 1
}
