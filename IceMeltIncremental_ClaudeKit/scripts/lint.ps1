$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Uses the committed roblox.yml standard library, so this runs offline.
# Regenerate it with `selene generate-roblox-std` only when the Roblox API changes.
selene src
if ($LASTEXITCODE -ne 0) {
    throw "selene reported problems (exit $LASTEXITCODE)"
}

Write-Host "selene clean"
