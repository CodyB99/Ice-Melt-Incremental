$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Ice Melt serves on 34873, not the Rojo default of 34872, because another project on
# this machine already holds 34872. The port lives in default.project.json.
#
# In the Rojo Studio plugin: Settings -> Port -> 34873, then Connect.
# Connecting this place to 34872 would sync a different project's source into it.

Write-Host "Serving Ice Melt Incremental on localhost:34873"
Write-Host "Set the Rojo plugin port to 34873 before pressing Connect."

rojo serve default.project.json
