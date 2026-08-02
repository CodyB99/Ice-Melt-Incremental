$ErrorActionPreference = "Stop"

# Strict Luau typecheck of src/ using luau-lsp.
# Needs a Rojo sourcemap so `script.Parent.X` and `WaitForChild("X")` resolve to real
# instances, and the Roblox global type definitions from scripts/fetch-types.ps1.

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$defs = Join-Path $root "tools/globalTypes.d.luau"
if (-not (Test-Path $defs)) {
    Write-Host "Roblox type definitions missing. Running scripts/fetch-types.ps1 first."
    & (Join-Path $PSScriptRoot "fetch-types.ps1")
}

rojo sourcemap default.project.json -o sourcemap.json
if (-not $?) { throw "rojo sourcemap failed" }

luau-lsp analyze --sourcemap=sourcemap.json --defs=$defs --settings=.luau-analyze.json --ignore="**/_Index/**" src
if ($LASTEXITCODE -ne 0) {
    throw "luau-lsp analyze reported problems (exit $LASTEXITCODE)"
}

Write-Host "luau-lsp analyze clean"
