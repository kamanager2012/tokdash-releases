$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PyzPath = Join-Path $ScriptDir "cognitally.pyz"

if (Get-Command py -ErrorAction SilentlyContinue) {
    & py -3 "$PyzPath" @args
    exit $LASTEXITCODE
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    & python "$PyzPath" @args
    exit $LASTEXITCODE
} elseif (Get-Command python3 -ErrorAction SilentlyContinue) {
    & python3 "$PyzPath" @args
    exit $LASTEXITCODE
} else {
    Write-Error "Error: Python 3 was not found in PATH. Please install Python 3."
    exit 1
}
