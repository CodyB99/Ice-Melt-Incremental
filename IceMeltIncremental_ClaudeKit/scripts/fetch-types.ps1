$ErrorActionPreference = "Stop"

# Downloads the Roblox global type definitions used by `scripts/analyze.ps1`.
# Output is a generated artifact and is gitignored; re-run after a Roblox API change.

$root = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $root "tools"
$target = Join-Path $toolsDir "globalTypes.d.luau"
$source = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"

if (-not (Test-Path $toolsDir)) {
    New-Item -ItemType Directory -Path $toolsDir | Out-Null
}

Write-Host "Downloading $source"
Invoke-WebRequest -Uri $source -OutFile $target -UseBasicParsing

$size = (Get-Item $target).Length
Write-Host "Wrote $target ($size bytes)"
